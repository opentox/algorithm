# lazar.rb
# Lazar Model Factory
# Author: Andreas Maunz


$lazar_feature_generation_default = File.join($algorithm[:uri],"fminer","bbrc")
$lazar_feature_calculation_default = "Substructure.match_hits" 
$lazar_min_sim_default = 0.3
$lazar_prediction_algorithm_default = "OpenTox::Algorithm::Neighbors.weighted_majority_vote"
$lazar_min_train_performance_default = 0.1


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

         lazar_params = [ "training_dataset_uri", 
                           "prediction_feature_uri", 
                           "feature_dataset_uri",
                           "feature_generation_uri", 
                           "feature_calculation_algorithm", 
                           "min_sim", 
                           "prediction_algorithm", 
                           "propositionalized", 
                           "pc_type", 
                           "pc_lib", 
                           "min_train_performance" 
                         ] 

          lazar = OpenTox::Model.new(nil, @subjectid)
          lazar.parameters = lazar.check_params(lazar_params, params)
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

        rescue => e
          $logger.debug "#{e.class}: #{e.message}"
          $logger.debug "Backtrace:\n\t#{e.backtrace.join("\n\t")}"
        end

      end

      response['Content-Type'] = 'text/uri-list'
      service_unavailable_error "Service unavailable" if task.status == "Cancelled"
      halt 202,task.uri.to_s+"\n"

    end

  end

end
