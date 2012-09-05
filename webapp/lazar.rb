module OpenTox
  
  class Application < Service

    

    # Get representation of lazar algorithm
    # @return [String] Representation
    get '/lazar/?' do
      algorithm = OpenTox::Algorithm::Generic.new(url_for('/lazar',:full))
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
      @feature_generation_default = File.join($algorithm[:uri],"fminer","bbrc")
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
                 # AM: store in model as param
          unless training_dataset = OpenTox::Dataset.find(params[:dataset_uri], @subjectid) # AM: find is a shim
            resource_not_found_error "Dataset '#{params[:dataset_uri]}' not found." 
          end

          # Prediction feature
          unless params[:prediction_feature] # try to read prediction_feature from dataset
            resource_not_found_error "Please provide a prediction_feature parameter" unless training_dataset.features.size == 1
            params[:prediction_feature] = training_dataset.features.first.uri
          end
          # AM: store in model as param
          prediction_feature = OpenTox::Feature.find(params[:prediction_feature], @subjectid) # AM: find is a shim
          resource_not_found_error "No feature '#{params[:prediction_feature]}' in dataset '#{params[:dataset_uri]}'" unless
            training_dataset.find_feature( params[:prediction_feature] ) # AM: find_feature is a shim

          # Feature generation
          # AM: store in model as param
          feature_generation_uri = @feature_generation_default unless 
            ( (feature_generation_uri = params[:feature_generation_uri]) || (params[:feature_dataset_uri]) )

          lazar = OpenTox::Model.new(nil, @subjectid)
          if prediction_feature.feature_type == "regression"
            # AM: store in model as param
            feature_calculation_algorithm = "Substructure.match_hits" 
            prediction_algorithm = "Neighbors.local_svm_regression" 
          end



        rescue => e
          $logger.debug "#{e.class}: #{e.message}"
          $logger.debug "Backtrace:\n\t#{e.backtrace.join("\n\t")}"
        end

      end

    end

  end

end
