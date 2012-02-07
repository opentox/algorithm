# Get list of feature_selection algorithms
#
# @return [text/uri-list] URIs of feature_selection algorithms
get '/feature_selection/?' do
  list = [ url_for('/feature_selection/rfe', :full) ].join("\n") + "\n"
  case request.env['HTTP_ACCEPT']
  when /text\/html/
    content_type "text/html"
    OpenTox.text_to_html list
  else
    content_type 'text/uri-list'
    list
  end
end

# Get RDF/XML representation of feature_selection rfe algorithm
# @return [application/rdf+xml] OWL-DL representation of feature_selection rfe algorithm
get "/feature_selection/rfe/?" do
  algorithm = OpenTox::Algorithm::Generic.new(url_for('/feature_selection/rfe',:full))
  algorithm.metadata = {
    DC.title => 'recursive feature elimination',
    DC.creator => "andreas@maunz.de, helma@in-silico.ch",
    DC.contributor => "vorgrimmlerdavid@gmx.de",
    BO.instanceOf => "http://opentox.org/ontology/ist-algorithms.owl#feature_selection_rfe",
    RDF.type => [OT.Algorithm,OTA.PatternMiningSupervised],
    OT.parameters => [
      { DC.description => "Dataset URI", OT.paramScope => "mandatory", DC.title => "dataset_uri" },
      { DC.description => "Feature Dataset URI", OT.paramScope => "mandatory", DC.title => "feature_dataset_uri" }
  ]
  }
  case request.env['HTTP_ACCEPT']
  when /text\/html/
    content_type "text/html"
    OpenTox.text_to_html algorithm.to_yaml
  when /application\/x-yaml/
    content_type "application/x-yaml"
    algorithm.to_yaml
  else
    response['Content-Type'] = 'application/rdf+xml'  
    algorithm.to_rdfxml
  end
end

# Run rfe algorithm on dataset
#
# @param [String] dataset_uri URI of the training dataset
# @param [String] feature_dataset_uri URI of the feature dataset
# @return [text/uri-list] Task URI
post '/feature_selection/rfe/?' do 

  raise OpenTox::NotFoundError.new "Please submit a dataset_uri." unless params[:dataset_uri]
  raise OpenTox::NotFoundError.new "Please submit a feature_dataset_uri." unless params[:feature_dataset_uri]

  ds_csv=OpenTox::RestClientWrapper.get( params[:dataset_uri], {:accept => "text/csv"} )
  tf_ds=Tempfile.open(['rfe_', '.csv'])
  tf_ds.puts(ds_csv)
  
  fds_csv=OpenTox::RestClientWrapper.get( params[:feature_dataset_uri], {:accept => "text/csv"})
  tf_fds=Tempfile.open(['rfe_', '.csv'])
  tf_fds.puts(fds_csv)

  task = OpenTox::Task.create("Recursive Feature Elimination", url_for('/feature_selection',:full)) do |task|
    rfe=OpenTox::Algorithm::FeatureSelection.rfe( { :ds_csv_file => tf_ds, :fds_csv_file => tf_fds } )
    r_result_uri=OpenTox::Dataset.create_from_csv(r_result_file).uri
    File.unlink(r_result_file)
    tf_ds.close!
    tf_fds.close! 
    r_result_uri
  end
  response['Content-Type'] = 'text/uri-list'
  raise OpenTox::ServiceUnavailableError.newtask.uri+"\n" if task.status == "Cancelled"
  halt 202,task.uri.to_s+"\n"
end

