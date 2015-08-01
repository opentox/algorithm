module OpenTox

  module Model

    class Lazar 
      include OpenTox
      include Mongoid::Document
      include Mongoid::Timestamps
      store_in collection: "models"

      field :title, type: String
      field :endpoint, type: String
      field :creator, type: String, default: __FILE__
      # datasets
      field :training_dataset_id, type: BSON::ObjectId
      field :feature_dataset_id, type: BSON::ObjectId
      # algorithms
      field :feature_calculation_algorithm, type: String
      field :prediction_algorithm, type: String
      field :similarity_algorithm, type: String
      field :min_sim, type: Float
      # prediction feature
      field :prediction_feature_id, type: BSON::ObjectId

      attr_accessor :prediction_dataset
      attr_accessor :training_dataset
      attr_accessor :feature_dataset
      attr_accessor :query_fingerprint
      attr_accessor :neighbors

      # Create a lazar model from a training_dataset and a feature_dataset
      # @param [OpenTox::Dataset] training_dataset
      # @param [OpenTox::Dataset] feature_dataset
      # @return [OpenTox::Model::Lazar] Regression or classification model
      def self.create training_dataset, feature_dataset

        bad_request_error "No features found in feature dataset #{feature_dataset.id}." if feature_dataset.features.empty?
        bad_request_error "More than one prediction feature found in training_dataset #{training_dataset.id}" unless training_dataset.features.size == 1
        bad_request_error "Training dataset compounds do not match feature dataset compounds. Please ensure that they are in the same order." unless training_dataset.compounds == feature_dataset.compounds

        prediction_feature = training_dataset.features.first
        prediction_feature.nominal ?  lazar = OpenTox::Model::LazarClassification.new : lazar = OpenTox::Model::LazarRegression.new
        lazar.feature_dataset_id = feature_dataset.id
        lazar.training_dataset_id = training_dataset.id
        lazar.prediction_feature_id = prediction_feature.id
        lazar.title = prediction_feature.title 

        lazar.save
        lazar
      end

      def predict object

        time = Time.now

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

        @query_fingerprint = Algorithm.run(feature_calculation_algorithm, compounds, @feature_dataset.features.collect{|f| f.name} )

        $logger.debug "Query fingerprint calculation: #{Time.now-time}"

        predictions = []
        prediction_feature = OpenTox::Feature.find prediction_feature_id
        tt = 0
        pt = 0
        compounds.each_with_index do |compound,c|
          t = Time.new

          $logger.debug "predict compound #{c+1}/#{compounds.size} #{compound.inchi}"

          database_activities = @training_dataset.values(compound,prediction_feature)
          if database_activities and !database_activities.empty?
            database_activities = database_activities.first if database_activities.size == 1
            $logger.debug "Compound #{compound.inchi} occurs in training dataset with activity #{database_activities}"
            predictions << {:compound => compound, :value => database_activities, :confidence => "measured"}
            next
          else

            if prediction_algorithm =~ /Regression/
              mtf = OpenTox::Algorithm::Transform::ModelTransformer.new(self)
              mtf.transform
              training_fingerprints = mtf.n_prop
              query_fingerprint = mtf.q_prop
              neighbors = [[nil,nil,nil,query_fingerprint]]
            else
              training_fingerprints = @feature_dataset.data_entries
              query_fingerprint = @query_fingerprint[c]
              neighbors = []
            end
            tt += Time.now-t
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

            if neighbors.empty?
              predictions << {:compound => compound, :value => nil, :confidence => nil, :warning => "No neighbors with similarity > #{min_sim} in dataset #{training_dataset.id}"}
              #$logger.warn "No neighbors found for compound #{compound}."
              next
            end

            if prediction_algorithm =~ /Regression/
              prediction = Algorithm.run(prediction_algorithm, neighbors, :min_train_performance => self.min_train_performance)
            else
              prediction = Algorithm.run(prediction_algorithm, neighbors)
            end
            prediction[:compound] = compound
            prediction[:neighbors] = neighbors.sort{|a,b| b[1] <=> a[1]} # sort with ascending similarities


            # AM: transform to original space (TODO)
            confidence_value = ((confidence_value+1.0)/2.0).abs if prediction.first and similarity_algorithm =~ /cosine/


            $logger.debug "predicted value: #{prediction[:value]}, confidence: #{prediction[:confidence]}"
            predictions << prediction
            pt += Time.now-t
          end

        end 
        $logger.debug "Transform time: #{tt}"
        $logger.debug "Prediction time: #{pt}"

        # serialize result
        case object.class.to_s
        when "OpenTox::Compound"
          return predictions.first
        when "Array"
          return predictions
        when "OpenTox::Dataset"
          # prepare prediction dataset
          prediction_dataset = LazarPrediction.new(
            :title => "Lazar prediction for #{prediction_feature.title}",
            :creator =>  __FILE__
          )
          confidence_feature = OpenTox::NumericFeature.find_or_create_by( "title" => "Prediction confidence" )
          warning_feature = OpenTox::NominalFeature.find_or_create_by("title" => "Warnings")
          prediction_dataset.features = [ prediction_feature, confidence_feature, warning_feature ]
          prediction_dataset.compounds = compounds
          prediction_dataset.data_entries = predictions.collect{|p| [p[:value], p[:confidence],p[:warning]]}
          prediction_dataset.save_all
          return prediction_dataset
        end

      end
      
      def training_activities
        i = @training_dataset.feature_ids.index prediction_feature_id
        @training_dataset.data_entries.collect{|de| de[i]}
      end

    end

    class LazarRegression < Lazar
      field :min_train_performance, type: Float, default: 0.1
      def initialize
        super
        self.prediction_algorithm = "OpenTox::Algorithm::Regression.local_svm_regression" 
        self.similarity_algorithm = "OpenTox::Algorithm::Similarity.cosine"
        self.min_sim = 0.7 

        # AM: transform to cosine space
        min_sim = (min_sim.to_f*2.0-1.0).to_s if similarity_algorithm =~ /cosine/
      end
    end

    class LazarClassification < Lazar
      def initialize
        super
        self.prediction_algorithm = "OpenTox::Algorithm::Classification.weighted_majority_vote"
        self.similarity_algorithm = "OpenTox::Algorithm::Similarity.tanimoto"
        self.feature_calculation_algorithm = "OpenTox::Algorithm::Descriptor.smarts_match"
        self.min_sim = 0.3
      end
    end

  end

end

