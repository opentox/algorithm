# fs.rb
# Feature Selection
# Author: Andreas Maunz

module OpenTox
  class Application < Service

  # Get list of feature selection algorithms
  # @return [text/uri-list] URIs
  get '/algorithm/fs/?' do
    list = [ url_for('/algorithm/feature_selection/rfe', :full) ].join("\n") + "\n"
    format_output(list)
  end
  
  # Get representation of Recursive Feature Elimination algorithm
  # @return [String] Representation
  get "/algorithm/fs/rfe/?" do
    algorithm = OpenTox::Algorithm::Generic.new(url_for('/algorithm/feature_selection/rfe',:full))
    algorithm.metadata = {
      DC.title => 'Recursive Feature Elimination',
      DC.creator => "andreas@maunz.de",
      RDF.type => [OT.Algorithm,OTA.PatternMiningSupervised]
    }
    algorithm.parameters = [
        { DC.description => "Dataset URI", OT.paramScope => "mandatory", DC.title => "dataset_uri" },
        { DC.description => "Prediction Feature URI", OT.paramScope => "mandatory", DC.title => "prediction_feature" },
        { DC.description => "Feature Dataset URI", OT.paramScope => "mandatory", DC.title => "feature_dataset_uri" },
        { DC.description => "Delete Instances with missing values", OT.paramScope => "optional", DC.title => "del_missing" }
    ]
    format_output(algorithm)
  end
  
  # Run rfe algorithm on dataset
  # @param [String] dataset_uri URI of the training dataset
  # @param [String] prediction_feature URI
  # @param [String] feature_dataset_uri URI
  # @return [text/uri-list] Task URI
  post '/algorithm/fs/rfe/?' do 
  
    raise OpenTox::NotFoundError.new "Please submit a dataset_uri." unless params[:dataset_uri]
    raise OpenTox::NotFoundError.new "Please submit a prediction_feature." unless params[:prediction_feature]
    raise OpenTox::NotFoundError.new "Please submit a feature_dataset_uri." unless params[:feature_dataset_uri]
  
    ds_csv=OpenTox::RestClientWrapper.get( params[:dataset_uri], {:accept => "text/csv"} )
    ds=Tempfile.open(['rfe_', '.csv'])
    ds.puts(ds_csv)
    ds.flush()
  
    prediction_feature = params[:prediction_feature].split('/').last # get col name
    
    fds_features = OpenTox::Dataset.new(params[:feature_dataset_uri]).load_features
    fds_csv=OpenTox::RestClientWrapper.get( params[:feature_dataset_uri], {:accept => "text/csv"})
    fds=Tempfile.open(['rfe_', '.csv'])
    fds.puts(fds_csv)
    fds.flush()
  
    del_missing = params[:del_missing] == "true" ? true : false
  
    task = OpenTox::Task.create("Recursive Feature Elimination", url_for('/algorithm/feature_selection',:full)) do |task|
      r_result_file = OpenTox::Algorithm::FeatureSelection.rfe( { :ds_csv_file => ds.path, :prediction_feature => prediction_feature, :fds_csv_file => fds.path, :del_missing => del_missing } )
      
      
      # # # Upload dataset
      ds = OpenTox::Dataset.find ( 
        OpenTox::RestClientWrapper.post(
          File.join(CONFIG[:services]["opentox-dataset"]), File.open(r_result_file).read, {:content_type => "text/csv"}
        )
      ) 
      ds.features.each { |id,info| # rewrite features
        fds_features.each { |fid,finfo|
          if ( (fid.split('/').last == id.split('/').last) && (finfo[DC.title] == info[DC.title]) )
            ds.features[id] = finfo
            break
          end
        }
      }
      r_result_uri = ds.save
      begin
        ds.close!; fds.close! 
        File.unlink(r_result_file)
      rescue
      end
      r_result_uri
    end
    response['Content-Type'] = 'text/uri-list'
    raise OpenTox::ServiceUnavailableError.newtask.uri+"\n" if task.status == "Cancelled"
    halt 202,task.uri.to_s+"\n"
  end

  end
end
