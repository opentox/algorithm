=begin
* Name: fminer.rb
* Description: Fminer library 
* Author: Andreas Maunz <andreas@maunz.de>
* Date: 10/2012
=end

module OpenTox
  class Algorithm

    # Fminer algorithms (https://github.com/amaunz/fminer2)
    class Fminer < Algorithm
      attr_accessor :prediction_feature, :training_dataset, :minfreq, :compounds, :db_class_sizes, :all_activities, :smi

      def initialize(uri, subjectid=nil)
        super(uri, subjectid)
      end


      # Check parameters of a fminer call
      # Sets training dataset, prediction feature, and minfreq instance variables
      # @param[Hash] parameters of the REST call
      # @param[Integer] per-mil value for min frequency
      
      def check_params(params,per_mil)
        bad_request_error "Please submit a dataset_uri." unless params[:dataset_uri] and  !params[:dataset_uri].nil?
        @training_dataset = OpenTox::Dataset.new "#{params[:dataset_uri]}", @subjectid 
        unless params[:prediction_feature] # try to read prediction_feature from dataset
          resource_not_found_error "Please provide a prediction_feature parameter" unless @training_dataset.features.size == 1
          params[:prediction_feature] = @training_dataset.features.first.uri
        end
        @prediction_feature = OpenTox::Feature.find params[:prediction_feature], @subjectid 
        resource_not_found_error "No feature '#{params[:prediction_feature]}' in dataset '#{params[:dataset_uri]}'" unless 
          @training_dataset.find_feature_uri( params[:prediction_feature] ) 
        unless params[:min_frequency].nil? 
          # check for percentage
          if params[:min_frequency].include? "pc"
            per_mil=params[:min_frequency].gsub(/pc/,"")
            if per_mil.numeric?
              per_mil = per_mil.to_i * 10
            else
              bad_request=true
            end
          # check for per-mil
          elsif params[:min_frequency].include? "pm"
            per_mil=params[:min_frequency].gsub(/pm/,"")
            if per_mil.numeric?
              per_mil = per_mil.to_i
            else
              bad_request=true
            end
          # set minfreq directly
          else
            if params[:min_frequency].numeric?
              @minfreq=params[:min_frequency].to_i
              $logger.debug "min_frequency #{@minfreq}"
            else
              bad_request=true
            end
          end
          bad_request_error "Minimum frequency must be integer [n], or a percentage [n]pc, or a per-mil [n]pm , with n greater 0" if bad_request
        end
        if @minfreq.nil?
          @minfreq=OpenTox::Algorithm.min_frequency(@training_dataset,@prediction_feature,per_mil)
          $logger.debug "min_frequency #{@minfreq} (input was #{per_mil} per-mil)"
        end
      end

      # Effect calculation
      # Determine class bias
      # @param [Array] 2-Array of per-class occurrences
      # @param [Array] number of database instances per class
      # @return [Integer] Class index of preferred class

      def self.effect(occurrences, db_instances)
        max=0
        max_value=0
        nr_o = occurrences.sum_size
        nr_db = db_instances.to_scale.sum
  
        occurrences.each_with_index { |o,i| # fminer outputs occurrences sorted reverse by activity.
          actual = o.size.to_f/nr_o
          expected = db_instances[i].to_f/nr_db
          if actual > expected
            if ((actual - expected) / actual) > max_value
             max_value = (actual - expected) / actual # 'Schleppzeiger'
              max = i
            end
          end
        }
        max
      end


      # Add data to fminer
      # If fminer_instance is nil, actually only administrative data is filled in
      # Sets all_activities, compounds, and smi instance variables
      # @param[Object] Fminer instance
      # @param[Hash] Maps dependent variable values to Integers
      
      def add_fminer_data(fminer_instance, value_map)
        id=1
        @training_dataset.compounds.each do |compound|
          compound_activities = @training_dataset.values(compound, @prediction_feature)
          begin
            if @prediction_feature.feature_type == "classification"
              compound_activities = compound_activities.to_scale.mode
            else
              compound_activities = compound_activities.to_scale.median
            end
          rescue
            compound_activities = nil
          end

          if compound_activities.nil?
            $logger.warn "No activity for '#{compound.uri}' and feature '#{@prediction_feature.uri}'"
          else
            if @prediction_feature.feature_type == "classification"
              activity= value_map.invert[compound_activities].to_i # activities are mapped to 1..n
              bad_request_error "activity could not be mapped, is #{compound_activities} (#{compound_activities.class}), available: #{value_map.values} (#{value_map.values.collect{|k| k.class}})" if activity<1
              @db_class_sizes[activity-1].nil? ? @db_class_sizes[activity-1]=1 : @db_class_sizes[activity-1]+=1 # AM effect
            elsif @prediction_feature.feature_type == "regression"
              activity= compound_activities.to_f 
            end
            fminer_instance.AddCompound(compound.smiles,id) if fminer_instance
            fminer_instance.AddActivity(activity, id) if fminer_instance 
            @all_activities[id]=activity # DV: insert global information
            @compounds[id] = compound
            @smi[id] = compound.smiles
            id += 1
          end
        end
      end


      # Calculate metadata for fminer features
      # Used by all fminer services except BBRC
      # @param [String] SMARTS string
      # @param [Integer] single index into for @smi or @compounds instance variable
      # @param [Array] Array of Arrays of indices of hits
      # @param [Object] Fminer instance (may be nil, if p_value is not nil)
      # @param [String] URI of feature dataset to be produced
      # @param [Hash]  Maps dependent variable values to Integers
      # @param [Float] p-value for the SMARTS (may be nil, if Fminer instance is not nil)
      # @return [Array] 2-Array with metadata,parameters

      def calc_metadata(smarts, ids, counts, fminer_instance, feature_dataset_uri, value_map, params, p_value=nil)
        # Either p_value or fminer instance to calculate it
        return nil if (p_value.nil? and fminer_instance.nil?) 
        return nil if (p_value and fminer_instance) 
        # get activities of feature occurrences; see http://goo.gl/c68t8
        non_zero_ids = ids.collect { |idx| idx if counts[ids.index(idx)] > 0 }
        feat_hash = Hash[*(all_activities.select { |k,v| non_zero_ids.include?(k) }.flatten)] 
        if p_value.nil? and fminer_instance.GetRegression()
          p_value = fminer_instance.KSTest(all_activities.values, feat_hash.values).to_f
          effect = (p_value > 0) ? "activating" : "deactivating"
        else
          p_value = fminer_instance.ChisqTest(all_activities.values, feat_hash.values).to_f unless p_value
          g=Array.new
          value_map.each { |y,act| g[y-1]=Array.new }
          feat_hash.each  { |x,y|   g[y-1].push(x)   }
          max = OpenTox::Algorithm::Fminer.effect(g, db_class_sizes)
          effect = max+1
        end

        metadata = {
          RDF.type => [RDF::OT.Feature, RDF::OT.Substructure, RDF::OT.NumericFeature],
          RDF::OT.smarts => smarts.dup,
          RDF::OT.pValue => p_value.abs.round(5),
          RDF::OT.effect => effect
        }
        parameters = [
          { RDF::DC.title => "dataset_uri", RDF::OT.paramValue => params[:dataset_uri] },
          { RDF::DC.title => "prediction_feature", RDF::OT.paramValue => params[:prediction_feature] }
        ]
        metadata[RDF::OT.hasSource]=feature_dataset_uri if feature_dataset_uri 
        [ metadata, parameters ]
      end
    end

  end

end

