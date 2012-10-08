# lazar.rb
# Lazar service
# Author: Andreas Maunz


$lazar_params = [ 
  "training_dataset_uri", 
  "prediction_feature_uri", 
  "feature_dataset_uri",
  "feature_generation_uri", 
  "feature_calculation_algorithm", 
  "similarity_algorithm",
  "min_sim", 
  "prediction_algorithm", 
  "propositionalized", 
  "pc_type", 
  "pc_lib", 
  "min_train_performance" 
]
$lazar_feature_generation_default = File.join($algorithm[:uri],"fminer","bbrc")
$lazar_feature_calculation_default = "match" 
$lazar_similarity_default = "tanimoto"
$lazar_min_sim_default = 0.3
$lazar_prediction_algorithm_default = "weighted_majority_vote"
$lazar_min_train_performance_default = 0.1


module OpenTox
  class Application < Service

    
    # Get representation of lazar algorithm
    # @return [String] Representation
    get '/lazar/?' do
      algorithm = OpenTox::Algorithm.new(url_for('/lazar',:full))
      algorithm.metadata = {
        DC.title => 'lazar',
        DC.creator => 'helma@in-silico.ch, andreas@maunz.de',
        RDF.Type => [OT.Algorithm]
      }
      algorithm.parameters = [
        { DC.description => "Dataset URI", OT.paramScope => "mandatory", DC.title => "dataset_uri" },
        { DC.description => "Feature URI for dependent variable", OT.paramScope => "optional", DC.title => "prediction_feature" },
        { DC.description => "Feature generation service URI", OT.paramScope => "optional", DC.title => "feature_generation_uri" },
        { DC.description => "Feature dataset URI", OT.paramScope => "optional", DC.title => "feature_dataset_uri" },
        { DC.description => "Further parameters for the feature generation service", OT.paramScope => "optional" }
      ]
      format_output(algorithm)
    end


    # Create a lazar prediction model
    # @param [String] dataset_uri Training dataset URI
    # @param [optional,String] prediction_feature URI of the feature to be predicted
    # @param [optional,String] feature_generation_uri URI of the feature generation algorithm 
    # @param [optional,String] - further parameters for the feature generation service 
    # @return [text/uri-list] Task URI 
    post '/lazar/?' do 
      params[:subjectid] = @subjectid
      resource_not_found_error "No dataset_uri parameter." unless params[:dataset_uri]
      task = OpenTox::Task.create(
                                  $task[:uri],
                                  @subjectid,
                                  { RDF::DC.description => "Create lazar model",
                                    RDF::DC.creator => url_for('/lazar',:full)
                                  }
                                ) do |task|
        begin 
          lazar = OpenTox::Model.new(nil, @subjectid)
          lazar.parameters = lazar.check_params($lazar_params, params)
          lazar.metadata = { 
            DC.title => "lazar model", 
            OT.dependentVariables => lazar.find_parameter_value("prediction_feature_uri"),
            OT.trainingDataset => lazar.find_parameter_value("training_dataset_uri"),
            OT.featureDataset => lazar.find_parameter_value("feature_dataset_uri"),
            RDF.type => ( OpenTox::Feature.find(lazar.find_parameter_value("prediction_feature_uri")).feature_type == "classification" ? 
              [OT.Model, OTA.ClassificationLazySingleTarget] :
              [OT.Model, OTA.RegressionLazySingleTarget] 
            )
          }
          # task.progress 10
          $logger.debug lazar.uri
          lazar.put @subjectid
          lazar.uri
        rescue => e
          $logger.debug "#{e.class}: #{e.message}"
          $logger.debug "Backtrace:\n\t#{e.backtrace.join("\n\t")}"
        end
      end
      response['Content-Type'] = 'text/uri-list'
      service_unavailable_error "Service unavailable" if task.cancelled?
      halt 202,task.uri.to_s+"\n"
    end


    # Create a lazar prediction model
    # @param [String] compound_uri URI of compound to be predicted
    # @param [String] training_dataset_uri URI of training dataset
    # @param [String] prediction_feature_uri URI of prediction feature
    # @param [String] feature_dataset_uri URI of feature dataset
    # @param [String] feature_calculation_algorithm Name of feature calculation algorithm
    # @param [String] min_sim Numeric value for minimum similarity
    # @param [String] prediction_algorithm Name of prediction algorithm
    # @param [String] propositionalized Whether propositionalization should be used 
    # @param [optional,String] pc_type Physico-chemical descriptor type
    # @param [optional,String] pc_lib Physico-chemical descriptor library
    # @param [optional,String] Further parameters for the feature generation service 
    # @return [text/uri-list] Task URI 
    post '/lazar/predict/?' do 
      params[:subjectid] = @subjectid
      task = OpenTox::Task.create(
                                  $task[:uri],
                                  @subjectid,
                                  { RDF::DC.description => "Create lazar model",
                                    RDF::DC.creator => url_for('/lazar/predict',:full)
                                  }
                                ) do |task|
        begin 
          prediction_dataset = OpenTox::Dataset.new(nil, @subjectid)
          # Store model parameters
          model_params = $lazar_params.collect { |p|
            {DC.title => p.to_s, OT.paramValue => params[p].to_s} unless params[p].nil?
          }.compact
          prediction_dataset.parameters = model_params
          model_params_hash = model_params.inject({}) { |h,p| 
            h[p[DC.title]] = p[OT.paramValue]
            h
          }
          prediction_dataset.metadata = {
            DC.title => "Lazar prediction",
            DC.creator => @uri.to_s,
            OT.hasSource => @uri.to_s,
            OT.dependentVariables => model_params_hash["prediction_feature_uri"],
            OT.predictedVariables => model_params_hash["prediction_feature_uri"]
          }

          $logger.debug "Inited p dataset"
          
          training_dataset = OpenTox::Dataset.find(params[:training_dataset_uri], @subjectid)
          prediction_feature = OpenTox::Feature.find(params[:prediction_feature_uri],@subjectid)
          $logger.debug "Loaded t dataset"
          unless training_dataset.database_activity(prediction_dataset,params)
            query_compound = OpenTox::Compound.new(params[:compound_uri])
            feature_dataset = OpenTox::Dataset.find(params[:feature_dataset_uri], @subjectid) # This takes time
            $logger.debug "Loaded f dataset"
            if feature_dataset.features.size > 0
              # use send, not eval, for calling the method (good backtrace)
              compound_fingerprints = OpenTox::Algorithm::FeatureValues.send( params[:feature_calculation_algorithm], 
                { :compound => query_compound, :features => feature_dataset.features.collect{ |f| f[DC.title] } }
              )
              $logger.debug "Calced q fps"
            end

            model = OpenTox::Model.new(model_params_hash)
            if feature_dataset.find_parameter_value("nr_hits") and model.feature_calculation_algorithm =~ /match/
              if model.feature_calculation_algorithm == "match" && feature_dataset.find_parameter_value("nr_hits") == "true"
                model.feature_calculation_algorithm = "match_hits"
              end
              if model.feature_calculation_algorithm == "match_hits" && feature_dataset.find_parameter_value("nr_hits") == "false"
                model.feature_calculation_algorithm = "match"
              end
              $logger.warn "Feature calculation overridden to '#{model.feature_calculation_algorithm}' by feature dataset '#{feature_dataset.uri}'"
            end
            model.add_data(training_dataset, feature_dataset, prediction_feature, compound_fingerprints, @subjectid)
            $logger.debug "Filled m data"
            mtf = OpenTox::Algorithm::Transform::ModelTransformer.new(model)
            mtf.transform
            $logger.debug "Transformed m"
            prediction = OpenTox::Algorithm::Neighbors.send(model.prediction_algorithm,  { :props => mtf.props,
                                                          :acts => mtf.acts,
                                                          :sims => mtf.sims,
                                                          :value_map => training_dataset.value_map(prediction_feature),
                                                          :min_train_performance => model.min_train_performance
                                                        } )
            $logger.debug "Predicted q"
            prediction_value = prediction[:prediction].to_f
            confidence_value = prediction[:confidence].to_f
            prediction_value = training_dataset.value_map(prediction_feature)[prediction[:prediction].to_i] if prediction_feature.feature_type == "classification"

            confidence_feature = OpenTox::Feature.new(nil, @subjectid)
            confidence_feature.title = "Confidence"
            confidence_feature.metadata = {
              DC.title => "Confidence"
            }
            confidence_feature.put(@subjectid)

            prediction_dataset.features = [ prediction_feature, confidence_feature ]
            prediction_dataset << [ query_compound, prediction_value, confidence_value ]
            $logger.debug "'#{params[:compound_uri]}': prediction '#{prediction_value}', confidence '#{confidence_value}'"
           
          end
          prediction_dataset.put
          $logger.debug prediction_dataset.uri
          prediction_dataset.uri
        rescue => e
          $logger.debug "#{e.class}: #{e.message}"
          $logger.debug "Backtrace:\n\t#{e.backtrace.join("\n\t")}"
        end
      end
      response['Content-Type'] = 'text/uri-list'
      service_unavailable_error "Service unavailable" if task.cancelled?
      halt 202,task.uri.to_s+"\n"
    end


  end
end