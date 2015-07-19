=begin
* Name: lazar.rb
* Description: Lazar model representation
* Author: Andreas Maunz <andreas@maunz.de>, Christoph Helma
* Date: 10/2012
=end

module OpenTox

  module Model

    class Lazar 
      include OpenTox
      include Mongoid::Document
      include Mongoid::Timestamps
      store_in collection: "model"

      field :title, type: String
      field :description, type: String
      #field :parameters, type: Array, default: []
      field :creator, type: String, default: __FILE__
      # datasets
      field :training_dataset_id, type: BSON::ObjectId
      field :feature_dataset_id, type: BSON::ObjectId
      # algorithms
      field :feature_generation, type: String
      field :feature_calculation_algorithm, type: String
      field :prediction_algorithm, type: Symbol
      field :similarity_algorithm, type: Symbol
      # prediction features
      field :prediction_feature_id, type: BSON::ObjectId
      field :predicted_value_id, type: BSON::ObjectId
      field :predicted_variables, type: Array
      # parameters
      field :min_sim, type: Float
      field :propositionalized, type:Boolean
      field :min_train_performance, type: Float

      attr_accessor :prediction_dataset

      # Check parameters for plausibility
      # Prepare lazar object (includes graph mining)
      # @param[Array] lazar parameters as strings
      # @param[Hash] REST parameters, as input by user
      def self.create feature_dataset, prediction_feature=nil, params={}
        
        lazar = OpenTox::Model::Lazar.new

        bad_request_error "No features found in feature dataset #{feature_dataset.id}." if feature_dataset.features.empty?
        lazar.feature_dataset_id = feature_dataset.id
        training_dataset = OpenTox::Dataset.find(feature_dataset.parameters.select{|p| p["title"] == "dataset_id"}.first["paramValue"])
        bad_request_error "Training dataset compounds do not match feature dataset compounds. Please ensure that they are in the same order." unless training_dataset.compounds == feature_dataset.compounds
        lazar.training_dataset_id = training_dataset.id

        if prediction_feature
          resource_not_found_error "No feature '#{params[:prediction_feature]}' in dataset '#{training_dataset.id}'" unless training_dataset.features.include?( params[:prediction_feature] )
        else # try to read prediction_feature from dataset
          resource_not_found_error "Please provide a prediction_feature parameter" unless training_dataset.features.size == 1
          prediction_feature = training_dataset.features.first
        end

        lazar.prediction_feature_id = prediction_feature.id
        lazar.title = prediction_feature.title 

        if params and params[:prediction_algorithm]
          bad_request_error "Unknown prediction_algorithm #{params[:prediction_algorithm]}" unless OpenTox::Algorithm::Neighbors.respond_to?(params[:prediction_algorithm])
          lazar.prediction_algorithm = params[:prediction_algorithm]
        end

        confidence_feature = OpenTox::Feature.find_or_create_by({
          "title" => "Prediction confidence",
          "numeric" => true
        })
        
        unless lazar.prediction_algorithm
          lazar.prediction_algorithm = :weighted_majority_vote if prediction_feature.nominal
          lazar.prediction_algorithm = :local_svm_regression if prediction_feature.numeric
        end
        lazar.prediction_algorithm =~ /majority_vote/ ? lazar.propositionalized = false :  lazar.propositionalized = true

        lazar.min_sim = params[:min_sim].to_f if params[:min_sim] and params[:min_sim].numeric?
        lazar.nr_hits =  params[:nr_hits] if params[:nr_hits]
        lazar.feature_generation = feature_dataset.creator
        #lazar.parameters << {"title" => "feature_generation_uri", "paramValue" => params[:feature_generation_uri]}
        # TODO insert algorithm into feature dataset
        # TODO store algorithms in mongodb?
        if lazar.feature_generation =~ /fminer|bbrc|last/
          if (lazar[:nr_hits] == "true")
            lazar.feature_calculation_algorithm = "smarts_count"
          else
            lazar.feature_calculation_algorithm = "smarts_match"
          end
          lazar.similarity_algorithm = "tanimoto"
          lazar.min_sim = 0.3 unless lazar.min_sim
        elsif lazar.feature_generation =~/descriptor/ or lazar.feature_generation.nil?
          # cosine similartiy is default (e.g. used when no fetature_generation_uri is given and a feature_dataset_uri is provided instead)
          lazar.similarity_algorithm = "cosine"
          lazar.min_sim = 0.7 unless lazar.min_sim
        else
          bad_request_error "unkown feature generation method #{lazar.feature_generation}"
        end

        bad_request_error "Parameter min_train_performance is not numeric." if params[:min_train_performance] and !params[:min_train_performance].numeric?
        lazar.min_train_performance = params[:min_train_performance].to_f if params[:min_train_performance] and params[:min_train_performance].numeric?
        lazar.min_train_performance = 0.1 unless lazar.min_train_performance

=begin
        if params[:feature_dataset_uri]
          bad_request_error "Feature dataset #{params[:feature_dataset_uri]} does not exist." unless URI.accessible? params[:feature_dataset_uri]
          lazar.parameters << {"title" => "feature_dataset_uri", "paramValue" => params[:feature_dataset_uri]}
          lazar[RDF::OT.featureDataset] = params["feature_dataset_uri"]
        else
          # run feature generation algorithm
          feature_dataset_uri = OpenTox::Algorithm::Generic.new(params[:feature_generation_uri]).run(params)
          lazar.parameters << {"title" => "feature_dataset_uri", "paramValue" => feature_dataset_uri}
          lazar[RDF::OT.featureDataset] = feature_dataset_uri
        end
=end
        lazar.save
        lazar
      end

      def predict params

        # tailored for performance
        # all consistency checks should be done during model creation

        time = Time.now

        # prepare prediction dataset
        prediction_dataset = OpenTox::Dataset.new
        prediction_feature = OpenTox::Feature.find prediction_feature_id
        prediction_feature = OpenTox::Feature.find prediction_feature_id
        prediction_dataset.title = "Lazar prediction for #{prediction_feature.title}",
        prediction_dataset.creator = __FILE__,

        similarity_feature = OpenTox::Feature.find_or_create_by({
          "title" => "#{similarity_algorithm.capitalize} similarity",
          "numeric" => true
        })
       
        #prediction_dataset.features = [ predicted_confidence, prediction_feature, similarity_feature ]

        # TODO set instance variables and prediction dataset parameters from parameters (see development branch)


        training_dataset = OpenTox::Dataset.find(training_dataset_id)

        feature_dataset = OpenTox::Dataset.find(feature_dataset_id)

        if params[:compound]
          compounds = [ params[:compound]] 
        else
          compounds = params[:dataset].compounds
        end

        puts "Setup: #{Time.now-time}"
        time = Time.now

        # TODO: this seems to be very time consuming
        # uses > 11" on development machine
        # select training fingerprints from feature dataset (do NOT use entire feature dataset)
=begin
        @training_dataset.compounds.each do |c|
          idx = @feature_dataset.compounds.index(c)
          bad_request_error "training dataset compound not found in feature dataset" if idx==nil
          @training_fingerprints << @feature_dataset.data_entries[idx][0..-1]
        end
        # fill trailing missing values with nil
        @training_fingerprints = @training_fingerprints.collect do |values|
          values << nil while (values.size < @feature_dataset.features.size)
          values
        end
=end
        # replacement code (sequence has been preserved in bbrc and last
        # uses ~0.025" on development machine
        #@training_fingerprints = @feature_dataset.data_entries
        #@training_compounds = @training_dataset.compounds

        #feature_names = @feature_dataset.features.collect{ |f| f[:title] }

        puts "Fingerprint: #{Time.now-time}"
        time = Time.now
        query_fingerprint = OpenTox::Algorithm::Descriptor.send( feature_calculation_algorithm, compounds, feature_dataset.features.collect{|f| f["title"]} )

        puts "Fingerprint calculation: #{Time.now-time}"
        time = Time.now

        # AM: transform to cosine space
        min_sim = (min_sim.to_f*2.0-1.0).to_s if similarity_algorithm =~ /cosine/

        neighbors = []
        compounds.each_with_index do |compound,c|
          $logger.debug "predict compound #{c+1}/#{compounds.size} #{compound.inchi}"

          database_activities = training_dataset.values(compound,prediction_feature)
          if database_activities and !database_activities.empty?
            database_activities.each do |database_activity|
              $logger.debug "do not predict compound, it occurs in dataset with activity #{database_activity}"
              prediction_dataset << [compound, nil, nil, database_activity, nil]
            end
            next
          else
=begin
            @training_activities = @training_dataset.data_entries.collect{|entry|
              act = entry[prediction_feature_pos] if entry
              @prediction_feature.feature_type=="classification" ? @prediction_feature.value_map.invert[act] : act
            }
=end

            #@query_fingerprint = @feature_dataset.features.collect { |f| 
              #val = query_fingerprints[compound][f.title]
              #bad_request_error "Can not parse value '#{val}' to numeric" if val and !val.numeric?
              #val ? val.to_f : 0.0
            #} # query structure

            # TODO reintroduce for regression
            #mtf = OpenTox::Algorithm::Transform::ModelTransformer.new(self)
            #mtf.transform
            #

            feature_dataset.data_entries.each_with_index do |fingerprint, i|

              sim = OpenTox::Algorithm::Similarity.send(similarity_algorithm,fingerprint, query_fingerprint[c])
              # TODO fix for multi feature datasets
              neighbors << [feature_dataset.compounds[i],training_dataset.data_entries[i].first,sim] if sim > self.min_sim
            end
            similarity_sum = 0.0
            confidence_sum = 0.0
            prediction = nil
            activities = training_dataset.data_entries.flatten.uniq.sort
            neighbors.each do |n|
              similarity_sum += n.last
              if activities.index(n[1]) == 0
                confidence_sum += n.last
              elsif activities.index(n[1]) == 1
                confidence_sum -= n.last
              end
            end
             
            if confidence_sum > 0.0
              prediction = activities[0]
            else
              prediction = activities[1]
            end

            p prediction, confidence_sum/similarity_sum
  

            
=begin
            prediction = OpenTox::Algorithm::Neighbors.send(prediction_algorithm, 
                { :props => mtf.props,
                  :activities => mtf.activities,
                  :sims => mtf.sims,
                  :value_map => @prediction_feature.feature_type=="classification" ?  @prediction_feature.value_map : nil,
                  :min_train_performance => @min_train_performance
                  } )
           
            predicted_value = prediction[:prediction]#.to_f
            confidence_value = prediction[:confidence]#.to_f

            # AM: transform to original space
            confidence_value = ((confidence_value+1.0)/2.0).abs if @similarity_algorithm =~ /cosine/
            predicted_value = @prediction_feature.value_map[prediction[:prediction].to_i] if @prediction_feature.feature_type == "classification"
            $logger.debug "predicted value: #{predicted_value}, confidence: #{confidence_value}"
=end
          end

=begin
          @prediction_dataset << [ compound, predicted_value, confidence_value, nil, nil ]

          if @compound_uri # add neighbors only for compound predictions
            @neighbors.each do |neighbor|
              n =  neighbor[:compound]
              @prediction_feature.feature_type == "classification" ? a = @prediction_feature.value_map[neighbor[:activity]] : a = neighbor[:activity]
              @prediction_dataset << [ n, nil, nil, a, neighbor[:similarity] ]
            end
          end
=end

        end # iteration over compounds
        @prediction_dataset

      end

    end

  end

end

