module OpenTox

  class Validation
    include OpenTox
    include Mongoid::Document
    include Mongoid::Timestamps
    store_in collection: "validations"

    field :prediction_dataset_id, type: BSON::ObjectId
    field :test_dataset_id, type: BSON::ObjectId
    field :nr_instances, type: Integer
    field :nr_unpredicted, type: Integer
    field :accept_values, type: String
    field :confusion_matrix, type: Array
    field :weighted_confusion_matrix, type: Array
    field :predictions, type: Array

    # TODO classification und regression in subclasses
    def self.create model, training_set, test_set
      validation = self.class.new
      feature_dataset = Dataset.find model.feature_dataset_id
      if feature_dataset.is_a? FminerDataset
        features = Algorithm.run feature_dataset.training_algorithm, training_set, feature_dataset.training_parameters
      else
        # TODO search for descriptors
      end
      validation_model = Model::Lazar.create training_set, features
      test_set_without_activities = Dataset.new(:compound_ids => test_set.compound_ids) # just to be sure that activities cannot be used
      prediction_dataset = validation_model.predict test_set_without_activities
      accept_values = prediction_dataset.prediction_feature.accept_values
      confusion_matrix = Array.new(accept_values.size,0){Array.new(accept_values.size,0)}
      weighted_confusion_matrix = Array.new(accept_values.size,0){Array.new(accept_values.size,0)}
      predictions = []
      prediction_dataset.data_entries.each_with_index do |pe,i|
        if pe[0] and pe[1] and pe[1].numeric? 
          prediction = pe[0]
          # TODO prediction_feature, convention??
          # TODO generalize for multiple classes
          activity = test_set.data_entries[i].first
          confidence = prediction_dataset.data_entries[i][1]
          predictions << [prediction_dataset.compound_ids[i], activity, prediction, confidence]
          if prediction == activity
            if prediction == accept_values[0]
              confusion_matrix[0][0] += 1
              weighted_confusion_matrix[0][0] += confidence
            elsif prediction == accept_values[1]
              confusion_matrix[1][1] += 1
              weighted_confusion_matrix[1][1] += confidence
            end
          elsif prediction != activity
            if prediction == accept_values[0]
              confusion_matrix[0][1] += 1
              weighted_confusion_matrix[0][1] += confidence
            elsif prediction == accept_values[1]
              confusion_matrix[1][0] += 1
              weighted_confusion_matrix[1][0] += confidence
            end
          end
        end
      end
      validation = self.new(
        :prediction_dataset_id => prediction_dataset.id,
        :test_dataset_id => test_set.id,
        :nr_instances => test_set.compound_ids.size,
        :nr_unpredicted => prediction_dataset.data_entries.count{|de| de.first.nil?},
        :accept_values => accept_values,
        :confusion_matrix => confusion_matrix,
        :weighted_confusion_matrix => weighted_confusion_matrix,
        :predictions => predictions.sort{|a,b| b[3] <=> a[3]} # sort according to confidence
      )
      validation.save
      validation
    end

    def prediction_dataset
      Dataset.find prediction_dataset_id
    end

    def test_dataset
      Dataset.find test_dataset_id
    end

  end

  class CrossValidation
    include OpenTox
    include Mongoid::Document
    include Mongoid::Timestamps
    store_in collection: "crossvalidations"

    field :validation_ids, type: Array, default: []
    field :folds, type: Integer
    field :nr_instances, type: Integer
    field :nr_unpredicted, type: Integer
    field :accept_values, type: Array
    field :confusion_matrix, type: Array
    field :weighted_confusion_matrix, type: Array
    field :accuracy, type: Float
    field :weighted_accuracy, type: Float
    field :true_rate, type: Hash
    field :predictivity, type: Hash
    field :predictions, type: Array
    # TODO auc, f-measure (usability??)

    def self.create model, n=10
      validation_ids = []
      nr_instances = 0
      nr_unpredicted = 0
      accept_values = model.prediction_feature.accept_values
      confusion_matrix = Array.new(accept_values.size,0){Array.new(accept_values.size,0)}
      weighted_confusion_matrix = Array.new(accept_values.size,0){Array.new(accept_values.size,0)}
      true_rate = {}
      predictivity = {}
      predictions = []
      model.training_dataset.folds(n).each do |fold|
        validation = Validation.create(model, fold[0], fold[1])
        validation_ids << validation.id
        nr_instances += validation.nr_instances
        nr_unpredicted += validation.nr_unpredicted
        validation.confusion_matrix.each_with_index do |r,i|
          r.each_with_index do |c,j|
            confusion_matrix[i][j] += c
            weighted_confusion_matrix[i][j] += validation.weighted_confusion_matrix[i][j]
          end
        end
        predictions << validation.predictions
      end
      true_rate = {}
      predictivity = {}
      accept_values.each_with_index do |v,i|
        true_rate[v] = confusion_matrix[i][i]/confusion_matrix[i].reduce(:+).to_f
        predictivity[v] = confusion_matrix[i][i]/confusion_matrix.collect{|n| n[i]}.reduce(:+).to_f
      end
      confidence_sum = 0
      weighted_confusion_matrix.each do |r|
        r.each do |c|
          confidence_sum += c
        end
      end
      cv = CrossValidation.new(
        :folds => n,
        :validation_ids => validation_ids,
        :nr_instances => nr_instances,
        :nr_unpredicted => nr_unpredicted,
        :accept_values => accept_values,
        :confusion_matrix => confusion_matrix,
        :weighted_confusion_matrix => weighted_confusion_matrix,
        :accuracy => (confusion_matrix[0][0]+confusion_matrix[1][1])/(nr_instances-nr_unpredicted).to_f,
        :weighted_accuracy => (weighted_confusion_matrix[0][0]+weighted_confusion_matrix[1][1])/confidence_sum.to_f,
        :true_rate => true_rate,
        :predictivity => predictivity,
        :predictions => predictions.sort{|a,b| b[3] <=> a[3]} # sort according to confidence
      )
      cv.save
      cv
    end

    #Average area under roc  0.646
    #Area under roc  0.646
    #F measure carcinogen: 0.769, noncarcinogen: 0.348

  end

end
