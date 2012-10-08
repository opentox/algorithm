# lazar.rb
# Lazar model library
# Author: Andreas Maunz

module OpenTox

  class Model

    def initialize(*args)
      if args.size == 2
        super(*args)# We have uri and subjectid
      end
      if args.size == 1
        prepare_prediction_model(args[0]) # We have a hash (prediction time)
      end
    end

    # Internal use only
    def prepare_prediction_model(params)
      params.each {|k,v|
        self.class.class_eval { attr_accessor k.to_sym }
        instance_variable_set(eval(":@"+k), v)
      }
      ["cmpds", "fps", "acts", "n_prop", "q_prop", "neighbors"].each {|k|
        self.class.class_eval { attr_accessor k.to_sym }
        instance_variable_set(eval(":@"+k), [])
      }
    end
    private :prepare_prediction_model

    # Fills model in with data for prediction
    # Avoids associative lookups, since canonization to InChI takes time
    # @param [OpenTox::Dataset] training dataset
    # @param [OpenTox::Dataset] feature dataset
    # @param [OpenTox::Feature] prediction feature
    # @param [Hash] compound fingerprints
    # @param [String] subjectid
    def add_data(training_dataset, feature_dataset, prediction_feature, compound_fingerprints, subjectid)
      training_dataset.build_feature_positions
      prediction_feature_pos = training_dataset.feature_positions[prediction_feature.uri]
      training_dataset.compounds.each_with_index { |cmpd, idx|
        act = training_dataset.data_entries[idx][prediction_feature_pos]
        @acts << training_dataset.value_map(prediction_feature).invert[act]
        row = feature_dataset.data_entries[idx].collect { |val| 
          bad_request_error "Can not parse value '#{val}' to numeric" unless val.numeric?
          val.to_f 
        }
        @n_prop << row
        @cmpds << cmpd.uri
      }
      @q_prop = feature_dataset.features.collect { |f| 
        val = compound_fingerprints[f.title]
        bad_request_error "Can not parse value '#{val}' to numeric" if val and !val.numeric?
        val ? val.to_f : 0.0
      } # query structure
    end

    # Check parameters for plausibility
    # Prepare lazar object (includes graph mining)
    # @param[Array] lazar parameters as strings
    # @param[Hash] REST parameters, as input by user

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

      if params[:feature_dataset_uri]
        feature_dataset_uri = params[:feature_dataset_uri]
      else
        feature_dataset_uri = OpenTox::Algorithm.new(feature_generation_uri).run(params)
      end

      # TODO: add override (e.g. lookup)
      feature_calculation_algorithm = $lazar_feature_calculation_default
      if (params[:nr_hits] == "true") && (feature_calculation_algorithm =~ /match/)
        feature_calculation_algorithm = "match_hits"
      end

      # TODO: add override (e.g. cosine)
      similarity_algorithm = $lazar_similarity_default
      
      min_sim = $lazar_min_sim_default
      if params[:min_sim] and params[:min_sim].numeric?
        min_sim = params[:min_sim].to_f 
      end

      prediction_algorithm = $lazar_prediction_algorithm_default
      if params[:prediction_algorithm] and OpenTox::Algorithm::Neighbors.respond_to? params[:prediction_algorithm]
        prediction_algorithm = "OpenTox::Algorithm::Neighbors.#{params[:prediction_algorithm]}" if params[:prediction_algorithm]
      end

      propositionalized = true
      if ((prediction_algorithm =~ /majority_vote/) > 0)
        propositionalized = false
      end

      if params[:pc_type]
        pc_type = params[:pc_type] 
      end

      if params[:lib]
        pc_lib = params[:lib]
      end

      min_train_performance = $lazar_min_train_performance_default
      if params[:min_train_performance] and params[:min_train_performance].numeric?
        min_train_performance = params[:min_train_performance].to_f 
      end

      lazar_params.collect { |p|
        { DC.title => p, OT.paramValue => eval(p) } unless eval(p).nil?
      }.compact
    end


  end

end
