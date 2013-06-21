module OpenTox
  class Application < Service
    
    # Get representation of lazar algorithm
    # @return [String] Representation
    get '/lazar/?' do
      algorithm = OpenTox::Algorithm.new(to('/lazar',:full))
      algorithm.metadata = {
        RDF::DC.title => 'lazar',
        RDF::DC.creator => 'helma@in-silico.ch, andreas@maunz.de',
        RDF.Type => [RDF::OT.Algorithm]
      }
      algorithm.parameters = [
        { RDF::DC.description => "Dataset URI", RDF::OT.paramScope => "mandatory", RDF::DC.title => "dataset_uri" },
        { RDF::DC.description => "Feature URI for dependent variable", RDF::OT.paramScope => "optional", RDF::DC.title => "prediction_feature" },
        { RDF::DC.description => "Feature generation service URI", RDF::OT.paramScope => "optional", RDF::DC.title => "feature_generation_uri" },
        { RDF::DC.description => "Feature dataset URI", RDF::OT.paramScope => "optional", RDF::DC.title => "feature_dataset_uri" },
        { RDF::DC.description => "Further parameters for the feature generation service", RDF::OT.paramScope => "optional" }
      ]
      #format_output(algorithm)
      render algorithm
    end


    # Create a lazar prediction model
    # @param [String] dataset_uri Training dataset URI
    # @param [optional,String] prediction_feature URI of the feature to be predicted
    # @param [optional,String] feature_generation_uri URI of the feature generation algorithm 
    # @param [optional,String] - further parameters for the feature generation service 
    # @return [text/uri-list] Task URI 
    post '/lazar/?' do 
      bad_request_error "Please provide a dataset_uri parameter." unless params[:dataset_uri]
      #resource_not_found_error "Dataset '#{params[:dataset_uri]}' not found." unless URI.accessible? params[:dataset_uri], @subjectid # wrong URI class
      bad_request_error "Please provide a feature_generation_uri parameter." unless params[:feature_generation_uri]
      task = OpenTox::Task.run("Create lazar model", uri('/lazar'), @subjectid) do |task|
        #lazar = OpenTox::Model::Lazar.new(nil, @subjectid)
        lazar = OpenTox::Model::Lazar.new(File.join($model[:uri],SecureRandom.uuid), @subjectid)
        lazar.create(params)
        #lazar.put
        #lazar.uri
      end
      response['Content-Type'] = 'text/uri-list'
      halt 202,task.uri
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
      # pass parameters instead of model_uri, because model service is blocked by incoming call

      puts "LAZAR"
      puts params.inspect
      task = OpenTox::Task.run("Apply lazar model",uri('/lazar/predict'), @subjectid) do |task|

        lazar = OpenTox::LazarPrediction.new params
        puts lazar.inspect
        lazar.prediction_dataset.uri

      end
      response['Content-Type'] = 'text/uri-list'
      halt 202,task.uri
    end


  end
end
