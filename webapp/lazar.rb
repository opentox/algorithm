=begin
* Name: lazar.rb
* Description: Lazar
* Author: Andreas Maunz <andreas@maunz.de>
* Date: 10/2012
=end

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
  "lib", 
  "min_train_performance" 
]
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

    def predicted_variable(prediction_feature)
      OpenTox::Feature.find_by_title("predicted_variable", {RDF.type => prediction_feature[RDF.type]})
    end
    
    def predicted_confidence
      OpenTox::Feature.find_by_title("predicted_confidence", {RDF.type => [RDF::OT.NumericFeature]})
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
          prediction_feature = OpenTox::Feature.find(lazar.find_parameter_value("prediction_feature_uri"))
          lazar.metadata = { 
            DC.title => "lazar model", 
            OT.dependentVariables => lazar.find_parameter_value("prediction_feature_uri"),
            OT.predictedVariables => [ predicted_variable(prediction_feature).uri, predicted_confidence.uri ],
            OT.trainingDataset => lazar.find_parameter_value("training_dataset_uri"),
            OT.featureDataset => lazar.find_parameter_value("feature_dataset_uri"),
            RDF.type => ( prediction_feature.feature_type == "classification" ? 
              [OT.Model, OTA.ClassificationLazySingleTarget] :
              [OT.Model, OTA.RegressionLazySingleTarget] 
            )
          }
          # task.progress 10
          lazar.put @subjectid
          $logger.debug lazar.uri
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


    # Make a lazar prediction -- not to be called directly
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
      if ( (params[:compound_uri] and params[:dataset_uri]) or 
           (!params[:compound_uri] and !params[:dataset_uri])
         )
        bad_request_error "Submit either compound uri or dataset uri"
      end

      task = OpenTox::Task.create(
        $task[:uri],
        @subjectid,
        { 
          RDF::DC.description => "Apply lazar model",
          RDF::DC.creator => url_for('/lazar/predict',:full)
        }
      ) do |task|

        begin 

          if params[:dataset_uri]
            compounds = OpenTox::Dataset.find(params[:dataset_uri]).compounds
          else
            compounds = [ OpenTox::Compound.new(params[:compound_uri]) ]
          end

          compounds.each { |query_compound|
            params[:compound_uri] = query_compound.uri # AM: store compound in params hash
            unless @prediction_dataset # AM: only once for dataset predictions
              @prediction_dataset = OpenTox::Dataset.new(nil, @subjectid) 

              @model_params_hash = $lazar_params.inject({}){ |h,p|
                h[p] = params[p].to_s unless params[p].nil?
                h
              }
              @model = OpenTox::Model.new(@model_params_hash)

              $logger.debug "Loading t dataset"
              @training_dataset = OpenTox::Dataset.find(params[:training_dataset_uri], @subjectid)
              @prediction_feature = OpenTox::Feature.find(params[:prediction_feature_uri],@subjectid)
              @predicted_variable = predicted_variable(@prediction_feature)
              @predicted_confidence = predicted_confidence
              @similarity_feature = OpenTox::Feature.find_by_title("similarity", {RDF.type => [RDF::OT.NumericFeature]})
              @prediction_dataset.features = [ @prediction_feature, @predicted_variable, @predicted_confidence, @similarity_feature ]
              
              @prediction_dataset.metadata = {
                DC.title => "Lazar prediction",
                DC.creator => @uri.to_s,
                OT.hasSource => @uri.to_s,
                OT.dependentVariables => @model_params_hash["prediction_feature_uri"],
                OT.predictedVariables => [@predicted_variable.uri,@predicted_confidence.uri]
              }
            end
            
            database_activity = @training_dataset.database_activity(params)
            if database_activity

              orig_value = database_activity.to_f
              predicted_value = orig_value
              confidence_value = 1.0

            else
              @model = OpenTox::Model.new(@model_params_hash)

              unless @feature_dataset
                $logger.debug "Loading f dataset"
                @feature_dataset = OpenTox::Dataset.find(params[:feature_dataset_uri], @subjectid)
              end

              case @feature_dataset.find_parameter_value("nr_hits")
                when "true" then @model.feature_calculation_algorithm = "match_hits"
                when "false" then @model.feature_calculation_algorithm = "match"
              end
              pc_type = @feature_dataset.find_parameter_value("pc_type")
              @model.pc_type = pc_type unless pc_type.nil?
              lib = @feature_dataset.find_parameter_value("lib")
              @model.lib = lib unless lib.nil?

              # AM: transform to cosine space
              @model.min_sim = (@model.min_sim.to_f*2.0-1.0).to_s if @model.similarity_algorithm =~ /cosine/

              if @feature_dataset.features.size > 0
                compound_params = { 
                  :compound => query_compound, 
                  :feature_dataset => @feature_dataset,
                  :pc_type => @model.pc_type,
                  :lib => @model.lib
                }
                # use send, not eval, for calling the method (good backtrace)
                $logger.debug "Calculating q fps"
                compound_fingerprints = OpenTox::Algorithm::FeatureValues.send( @model.feature_calculation_algorithm, compound_params, @subjectid )
              else
                bad_request_error "No features found"
              end

              @model.add_data(@training_dataset, @feature_dataset, @prediction_feature, compound_fingerprints, @subjectid)
              mtf = OpenTox::Algorithm::Transform::ModelTransformer.new(@model)
              mtf.transform
              $logger.debug "Predicting q"
              prediction = OpenTox::Algorithm::Neighbors.send(@model.prediction_algorithm, 
                { :props => mtf.props,
                  :acts => mtf.acts,
                  :sims => mtf.sims,
                  :value_map => @prediction_feature.feature_type=="classification" ?
                    @training_dataset.value_map(@prediction_feature) : nil,
                  :min_train_performance => @model.min_train_performance
                  } )
              orig_value = nil
              predicted_value = prediction[:prediction].to_f
              confidence_value = prediction[:confidence].to_f

              # AM: transform to original space
              confidence_value = ((confidence_value+1.0)/2.0).abs if @model.similarity_algorithm =~ /cosine/
              predicted_value = @training_dataset.value_map(@prediction_feature)[prediction[:prediction].to_i] if @prediction_feature.feature_type == "classification"

              $logger.debug "Prediction: '#{predicted_value}'"
              $logger.debug "Confidence: '#{confidence_value}'"
            end

            @prediction_dataset << [ 
              query_compound, 
              orig_value,
              predicted_value, 
              confidence_value, 
              nil
            ]
            @model.neighbors.each { |neighbor|
              @prediction_dataset << [ 
                OpenTox::Compound.new(neighbor[:compound]), 
                @training_dataset.value_map(@prediction_feature)[neighbor[:activity]],
                nil, 
                nil, 
                neighbor[:similarity] 
              ]
            }

          }

         @prediction_dataset.parameters = $lazar_params.collect { |p|
           {DC.title => p, OT.paramValue => @model.instance_variable_get("@#{p}")} unless  @model.instance_variable_get("@#{p}").nil?
         }

          @prediction_dataset.put
          $logger.debug @prediction_dataset.uri
          @prediction_dataset.uri

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
