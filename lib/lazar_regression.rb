module OpenTox

  module Model

    class LazarRegression < Lazar

      # Create a lazar model from a training_dataset and a feature_dataset
      # @param [OpenTox::Dataset] training_dataset
      # @param [OpenTox::Dataset] feature_dataset
      # @return [OpenTox::Model::Lazar] Regression or classification model
      def self.create training_dataset#, feature_dataset

        #bad_request_error "No features found in feature dataset #{feature_dataset.id}." if feature_dataset.features.empty?
        bad_request_error "More than one prediction feature found in training_dataset #{training_dataset.id}" unless training_dataset.features.size == 1
        #bad_request_error "Training dataset compounds do not match feature dataset compounds. Please ensure that they are in the same order." unless training_dataset.compounds == feature_dataset.compounds

        prediction_feature = training_dataset.features.first
        prediction_feature.nominal ?  lazar = OpenTox::Model::LazarClassification.new : lazar = OpenTox::Model::LazarRegression.new
        #lazar.feature_dataset_id = feature_dataset.id
        lazar.training_dataset_id = training_dataset.id
        lazar.prediction_feature_id = prediction_feature.id
        lazar.title = prediction_feature.title 

        # log transform activities (create new dataset)
        # scale, normalize features, might not be necessary
        # http://stats.stackexchange.com/questions/19216/variables-are-often-adjusted-e-g-standardised-before-making-a-model-when-is
        # http://stats.stackexchange.com/questions/7112/when-and-how-to-use-standardized-explanatory-variables-in-linear-regression
        # zero-order correlation and the semi-partial correlation
        # seems to be necessary for svm
        #   http://stats.stackexchange.com/questions/77876/why-would-scaling-features-decrease-svm-performance?lq=1
        #   http://stackoverflow.com/questions/15436367/svm-scaling-input-values
        # use lasso or elastic net??
        # select relevant features
        #   remove features with a single value
        #   remove correlated features
        #   remove features not correlated with endpoint

        lazar.save
        lazar
      end

      def predict object

        t = Time.now
        at = Time.now

        training_dataset = OpenTox::Dataset.find(training_dataset_id)

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

        $logger.debug "Setup: #{Time.now-t}"
        t = Time.now

        $logger.debug "Query fingerprint calculation: #{Time.now-t}"
        t = Time.now

        predictions = []
        prediction_feature = OpenTox::Feature.find prediction_feature_id
        tt = 0
        pt = 0
        nt = 0
        st = 0
        nit = 0
        predictions = []
        compounds.each_with_index do |compound,c|
          t = Time.new
          neighbors = compound.neighbors 
          weighted_sum = 0
          sim_sum = 0
          neighbors.each do |row|
            n,sim = row
            i = training_dataset.compound_ids.index n.id
            if i
              act = training_dataset.data_entries[i].first
              if act
                weighted_sum += sim*Math.log10(act)
                sim_sum += sim
              end
            end
          end
          weighted_average = 10**(weighted_sum/sim_sum)
          p weighted_average
        end 
        $logger.debug "Transform time: #{tt}"
        $logger.debug "Neighbor search time: #{nt} (Similarity calculation: #{st}, Neighbor insert: #{nit})"
        $logger.debug "Prediction time: #{pt}"
        $logger.debug "Total prediction time: #{Time.now-at}"

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
            :creator =>  __FILE__,
            :prediction_feature_id => prediction_feature.id

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

      def training_dataset
        Dataset.find training_dataset_id
      end

      def prediction_feature
        Feature.find prediction_feature_id
      end
      
      def training_activities
        i = @training_dataset.feature_ids.index prediction_feature_id
        @training_dataset.data_entries.collect{|de| de[i]}
      end

    end


  end

end

