module OpenTox

  class Model

    
    def initialize(uri, subjectid=nil)
      super(uri, subjectid)
    end
  

    def check_params(lazar_params, params)
      unless training_dataset = OpenTox::Dataset.find(params[:dataset_uri], @subjectid) # AM: find is a shim
        resource_not_found_error "Dataset '#{params[:dataset_uri]}' not found." 
      end
      training_dataset_uri = training_dataset.uri

      unless params[:prediction_feature] # try to read prediction_feature from dataset
        resource_not_found_error "Please provide a prediction_feature parameter" unless training_dataset.features.size == 1
        params[:prediction_feature] = training_dataset.features.first.uri
      end

      unless training_dataset.find_feature( params[:prediction_feature] ) # AM: find_feature is a shim
        resource_not_found_error "No feature '#{params[:prediction_feature]}' in dataset '#{params[:dataset_uri]}'" 
      end
      prediction_feature = OpenTox::Feature.find(params[:prediction_feature], @subjectid) # AM: find is a shim
      prediction_feature_uri = prediction_feature.uri

      feature_generation_uri = $lazar_feature_generation_default
      if params[:feature_generation_uri]
        feature_generation_uri = params[:feature_generation_uri]
      end

      feature_calculation_algorithm = $lazar_feature_calculation_default
      
      min_sim = $lazar_min_sim_default
      if params[:min_sim] and params[:min_sim].numeric?
        min_sim = params[:min_sim].to_f 
      end

      prediction_algorithm = $lazar_prediction_algorithm_default
      if params[:prediction_algorithm] and OpenTox::Algorithm::Neighbors.respond_to? params[:prediction_algorithm]
        prediction_algorithm = "OpenTox::Algorithm::Neighbors.#{params[:prediction_algorithm]}" if params[:prediction_algorithm]
      end

      propositionalized = (prediction_algorithm=="Neighbors.weighted_majority_vote" ? false : true)

      pc_type = $lazar_pc_type_default
      if params[:pc_type]
        pc_type = params[:pc_type] 
      end

      pc_lib = $lazar_pc_lib_default
      if params[:lib]
        pc_lib = params[:lib]
      end

      min_train_performance = $lazar_min_train_performance_default
      if params[:min_train_performance] and params[:min_train_performance].numeric?
        min_train_performance = params[:min_train_performance].to_f 
      end

      lazar_params.collect { |p|
        { DC.title => p, OT.paramValue => eval(p) }
      }
    end

  end

end

