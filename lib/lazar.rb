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
      store_in collection: "models"

      field :title, type: String
      field :description, type: String
      #field :parameters, type: Array, default: []
      field :creator, type: String, default: __FILE__
      # datasets
      field :training_dataset_id, type: BSON::ObjectId
      field :feature_dataset_id, type: BSON::ObjectId
      # algorithms
      #field :feature_generation, type: String
      #field :feature_calculation_algorithm, type: String
      field :prediction_algorithm, type: String
      field :similarity_algorithm, type: String
      # prediction features
      field :prediction_feature_id, type: BSON::ObjectId
      field :predicted_value_id, type: BSON::ObjectId
      field :predicted_variables, type: Array
      # parameters
      field :nr_hits, type: Boolean
      field :min_sim, type: Float
      #field :propositionalized, type:Boolean
      field :min_train_performance, type: Float

      attr_accessor :prediction_dataset
      attr_accessor :training_dataset
      attr_accessor :feature_dataset
      attr_accessor :query_fingerprint
      attr_accessor :neighbors

      # Check parameters for plausibility
      # Prepare lazar object (includes graph mining)
      # @param[Array] lazar parameters as strings
      # @param[Hash] REST parameters, as input by user
      def self.create training_dataset, feature_dataset, prediction_feature=nil, nr_hits=false, params={}
        
        lazar = OpenTox::Model::Lazar.new

        bad_request_error "No features found in feature dataset #{feature_dataset.id}." if feature_dataset.features.empty?
        lazar.feature_dataset_id = feature_dataset.id
        @training_dataset = training_dataset
        bad_request_error "Training dataset compounds do not match feature dataset compounds. Please ensure that they are in the same order." unless @training_dataset.compounds == feature_dataset.compounds
        lazar.training_dataset_id = @training_dataset.id

        if prediction_feature
          resource_not_found_error "No feature '#{params[:prediction_feature]}' in dataset '#{@training_dataset.id}'" unless @training_dataset.features.include?( params[:prediction_feature] )
        else # try to read prediction_feature from dataset
          resource_not_found_error "Please provide a prediction_feature parameter" unless @training_dataset.features.size == 1
          prediction_feature = @training_dataset.features.first
        end

        lazar.prediction_feature_id = prediction_feature.id
        lazar.title = prediction_feature.title 

        if params and params[:prediction_algorithm]
          bad_request_error "Unknown prediction_algorithm #{params[:prediction_algorithm]}" unless OpenTox::Algorithm::Neighbors.respond_to?(params[:prediction_algorithm])
          lazar.prediction_algorithm = params[:prediction_algorithm]
        end

        unless lazar.prediction_algorithm # set defaults
          # TODO consider params
          if prediction_feature.nominal
            lazar.prediction_algorithm = "OpenTox::Algorithm::Classification.weighted_majority_vote"
            lazar.similarity_algorithm = "OpenTox::Algorithm::Similarity.tanimoto"
            lazar.min_sim = 0.3 unless lazar.min_sim
          elsif prediction_feature.numeric
            lazar.prediction_algorithm = "OpenTox::Algorithm::Regression.local_svm_regression" 
            lazar.similarity_algorithm = "OpenTox::Algorithm::Similarity.cosine"
            # cosine similartiy is default
            lazar.min_sim = 0.7 unless lazar.min_sim
          end
        end
        #lazar.prediction_algorithm =~ /majority_vote/ ? lazar.propositionalized = false :  lazar.propositionalized = true

        lazar.min_sim = params[:min_sim].to_f if params[:min_sim] and params[:min_sim].numeric?
        # TODO: get info from training_dataset
        lazar.nr_hits =  nr_hits
        #lazar.feature_generation = feature_dataset.training_algorithm
        #lazar.parameters << {"title" => "feature_generation_uri", "paramValue" => params[:feature_generation_uri]}

        bad_request_error "Parameter min_train_performance is not numeric." if params[:min_train_performance] and !params[:min_train_performance].numeric?
        lazar.min_train_performance = params[:min_train_performance].to_f if params[:min_train_performance] and params[:min_train_performance].numeric?
        lazar.min_train_performance = 0.1 unless lazar.min_train_performance

        lazar.save
        lazar
      end

      def predict object

        # tailored for performance
        # all consistency checks should be done during model creation

        time = Time.now

        # prepare prediction dataset
        prediction_dataset = LazarPrediction.new
        prediction_feature = OpenTox::Feature.find prediction_feature_id
        prediction_dataset.title = "Lazar prediction for #{prediction_feature.title}",
        prediction_dataset.creator = __FILE__,

        confidence_feature = OpenTox::Feature.find_or_create_by({
          "title" => "Prediction confidence",
          "numeric" => true
        })

        prediction_dataset.features = [ confidence_feature, prediction_feature ]

        @training_dataset = OpenTox::Dataset.find(training_dataset_id)
        @feature_dataset = OpenTox::Dataset.find(feature_dataset_id)

        compounds = []
        case object.class.to_s
        when "OpenTox::Compound"
          compounds = [object] 
        when "Array"
          compounds = object
        when "OpenTox::Dataset"
          compounds = object.compounds
        else 
          bad_request_error "Please provide a OpenTox::Compound an Array of OpenTox::Compounds or an OpenTox::Dataset as parameter."
        end

        $logger.debug "Setup: #{Time.now-time}"
        time = Time.now

        @query_fingerprint = Algorithm.run(feature_dataset.feature_calculation_algorithm, compounds, @feature_dataset.features.collect{|f| f.name} )

        $logger.debug "Fingerprint calculation: #{Time.now-time}"
        time = Time.now

        # AM: transform to cosine space
        min_sim = (min_sim.to_f*2.0-1.0).to_s if similarity_algorithm =~ /cosine/

        compounds.each_with_index do |compound,c|

          $logger.debug "predict compound #{c+1}/#{compounds.size} #{compound.inchi}"

          database_activities = @training_dataset.values(compound,prediction_feature)
          if database_activities and !database_activities.empty?
            database_activities.each do |database_activity|
              $logger.debug "do not predict compound, it occurs in dataset with activity #{database_activity}"
              prediction_dataset.compound_ids << compound.id
              prediction_dataset[c,0] = database_activity
              prediction_dataset[c,1] = nil
            end
            next
          else
            t = Time.new

            if prediction_algorithm =~ /Regression/
              mtf = OpenTox::Algorithm::Transform::ModelTransformer.new(self)
              mtf.transform
              training_fingerprints = mtf.n_prop
              training_activities = mtf.activities
              p training_activities
              query_fingerprint = mtf.q_prop
              neighbors = [[nil,nil,nil,query_fingerprint]]
            else
              training_fingerprints = @feature_dataset.data_entries
              # TODO fix for multi feature datasets
              training_activities = @training_dataset.data_entries[i].first
              query_fingerprint = @query_fingerprint[c]
              neighbors = []
            end
            $logger.debug "Transform: #{Time.now-t}"
            t = Time.new
            

            # find neighbors
            training_fingerprints.each_with_index do |fingerprint, i|

              sim = Algorithm.run(similarity_algorithm,fingerprint, query_fingerprint)
              if sim > self.min_sim
                if prediction_algorithm =~ /Regression/
                  neighbors << [@feature_dataset.compounds[i],sim,training_activities[i], fingerprint]
                else
                  neighbors << [@feature_dataset.compounds[i],sim,training_activities[i]] 
                end
              end
            end

            if prediction_algorithm =~ /Regression/
              prediction = Algorithm.run(prediction_algorithm, neighbors, :min_train_performance => self.min_train_performance)
            else
              prediction = Algorithm.run(prediction_algorithm, neighbors)
            end

            $logger.debug "Prediction time: #{Time.now-time}"
            time = Time.now

            p prediction
            # AM: transform to original space (TODO)
            confidence_value = ((confidence_value+1.0)/2.0).abs if prediction.first and similarity_algorithm =~ /cosine/


            $logger.debug "predicted value: #{prediction[0]}, confidence: #{prediction[1]}"
          end
          prediction_dataset.compound_ids << compound
          prediction_dataset[c,0] = prediction[0]
          prediction_dataset[c,1] = prediction[1]

        end 
        prediction_dataset

      end
      
      def training_activities
        # TODO select predicted variable
            #@training_activities = @training_dataset.data_entries.collect{|entry|
              #act = entry[prediction_feature_pos] if entry
              #@prediction_feature.feature_type=="classification" ? @prediction_feature.value_map.invert[act] : act
            #}
        @training_dataset.data_entries.flatten
      end

    end

  end

end

