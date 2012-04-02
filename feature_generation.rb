# Get list if pc descriptor calculation algorithms
#
# @return [text/uri-list] URIs of pc descriptor calculation algorithms
get '/pcdesc' do
algorithm = OpenTox::Algorithm::Generic.new(url_for('/pcdesc',:full))
  algorithm.metadata = {
    DC.title => 'Physico-chemical (PC) descriptor calculation',
    DC.creator => "andreas@maunz.de, vorgrimmlerdavid@gmx.de",
    RDF.type => [OT.Algorithm,OTA.DescriptorCalculation],
    OT.parameters => [
      { DC.description => "Dataset URI", OT.paramScope => "mandatory", DC.title => "dataset_uri" },
      { DC.description => "PC type", OT.paramScope => "mandatory", DC.title => "pc_type" },
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

# Run pc descriptor calculation algorithm on dataset
#
# @param [String] dataset_uri URI of the training dataset
# @param [String] feature_dataset_uri URI of the feature dataset
# @return [text/uri-list] Task URI
post '/pcdesc' do
  response['Content-Type'] = 'text/uri-list'
  raise OpenTox::NotFoundError.new "Please submit a dataset_uri." unless params[:dataset_uri]
  raise "No PC type given" unless params["pc_type"]

  task = OpenTox::Task.create("PC descriptor calculation for dataset ", @uri) do |task|
    types = params[:pc_type].split(",")
    if types.include?("joelib")
      Rjb.load(nil,["-Xmx64m"]) 
      s = Rjb::import('JoelibFc')
    end
    OpenTox::Algorithm.pc_descriptors( { :dataset_uri => params[:dataset_uri], :pc_type => params[:pc_type], :rjb => s, :task => task } )
  end
  raise OpenTox::ServiceUnavailableError.newtask.uri+"\n" if task.status == "Cancelled"
  halt 202,task.uri.to_s+"\n"
end

