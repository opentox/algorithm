# pc.rb
# (P)hysico (C)hemical descriptor calculation
# Author: Andreas Maunz


# Get a list of descriptor calculation algorithms
# @return [text/uri-list] URIs of descriptor calculation algorithms
get '/pc' do
  algorithms = YAML::load_file File.join(ENV['HOME'], ".opentox", "config", "pc_descriptors.yaml")
  response['Content-Type'] = 'text/uri-list'
  list = (algorithms.keys.sort << "AllDescriptors").collect { |name| url_for("/pc/#{name}",:full) }.join("\n") + "\n"
  case request.env['HTTP_ACCEPT']
  when /text\/html/
    content_type "text/html"
    OpenTox.text_to_html list
  else
    content_type 'text/uri-list'
    list
  end
end

# Get representation of descriptor calculation algorithm
# @return [application/rdf+xml] OWL-DL representation of descriptor calculation algorithm
get '/pc/:descriptor' do
  descriptors = YAML::load_file File.join(ENV['HOME'], ".opentox", "config", "pc_descriptors.yaml")
  alg_params = [ { DC.description => "Dataset URI", OT.paramScope => "mandatory", DC.title => "dataset_uri" } ]
      
  if params[:descriptor] != "AllDescriptors"
    descriptors = descriptors[params[:descriptor]]
  else
    alg_params << { DC.description => "Physico-chemical type, one or more of '#{descriptors.collect { |id, info| info[:pc_type] }.uniq.sort.join(",")}'", OT.paramScope => "optional", DC.title => "pc_type" }
    alg_params << { DC.description => "Software Library, one or more of '#{descriptors.collect { |id, info| info[:lib] }.uniq.sort.join(",")}'", OT.paramScope => "optional", DC.title => "lib" }
    descriptors = {:id => "AllDescriptors", :name => "All PC descriptors" }
  end

  if descriptors 

    # Contents
    algorithm = OpenTox::Algorithm::Generic.new(url_for("/pc/#{params[:descriptor]}",:full))
    algorithm.metadata = {
      DC.title => params[:descriptor],
      DC.creator => "andreas@maunz.de",
      DC.description => descriptors[:name],
      RDF.type => [OTA.DescriptorCalculation],
    }
    algorithm.metadata[OT.parameters] = alg_params
    algorithm.metadata[DC.description] << (", pc_type: " + descriptors[:pc_type]) unless descriptors[:id] == "AllDescriptors"
    algorithm.metadata[DC.description] << (", lib: " + descriptors[:lib]) unless descriptors[:id] == "AllDescriptors"

    # Deliver
    case request.env['HTTP_ACCEPT']
    when /text\/html/
      content_type "text/html"
      OpenTox.text_to_html algorithm.to_yaml
    when /yaml/
      content_type "application/x-yaml"
      algorithm.to_yaml
    else
      response['Content-Type'] = 'application/rdf+xml'  
      algorithm.to_rdfxml
    end

  else
    raise OpenTox::NotFoundError.new "Unknown descriptor #{params[:descriptor]}."
  end
end

# Run pc descriptor calculation algorithm on dataset for a set of descriptors. Can be constrained to types and libraries.
# @param [String] dataset_uri URI of the training dataset
# @param optional [String] pc_type Physico-chemical descriptor type to generate, see TODO
# @param optional [String] lib Library to use, see TODO
# @return [text/uri-list] Task URI
post '/pc/AllDescriptors' do
  response['Content-Type'] = 'text/uri-list'
  raise OpenTox::NotFoundError.new "Parameter 'dataset_uri' missing." unless params[:dataset_uri]

  descriptors = YAML::load_file File.join(ENV['HOME'], ".opentox", "config", "pc_descriptors.yaml")
  params[:pc_type] = descriptors.collect { |id,info| info[:pc_type]}.uniq.sort.join(',')  unless params[:pc_type]

  task = OpenTox::Task.create("PC descriptor calculation for dataset ", @uri) do |task|
    Rjb.load(nil,["-Xmx64m"]) # start vm
    byteArray = Rjb::import('java.io.ByteArrayOutputStream'); printStream = Rjb::import('java.io.PrintStream'); 
    out = byteArray.new() ; Rjb::import('java.lang.System').out = printStream.new(out) # joelib is too verbose
    s = Rjb::import('JoelibFc') # import main class

    LOGGER.debug "Running PC with pc_type '#{params[:pc_type]}' and lib '#{params[:lib]}'"
    OpenTox::Algorithm.pc_descriptors( { :dataset_uri => params[:dataset_uri], :pc_type => params[:pc_type], :rjb => s, :add_uri => true, :task => task, :lib => params[:lib], :subjectid => @subjectid} )
  end
  raise OpenTox::ServiceUnavailableError.newtask.uri+"\n" if task.status == "Cancelled"
  halt 202,task.uri.to_s+"\n"
end

# Run pc descriptor calculation algorithm on dataset for a specific descriptor.
#
# @param [String] dataset_uri URI of the training dataset
# @return [text/uri-list] Task URI
post '/pc/:descriptor' do
  response['Content-Type'] = 'text/uri-list'
  raise OpenTox::NotFoundError.new "Parameter 'dataset_uri' missing." unless params[:dataset_uri]

  descriptors = YAML::load_file File.join(ENV['HOME'], ".opentox", "config", "pc_descriptors.yaml")
  params[:pc_type] = descriptors.collect { |id,info| info[:pc_type]}.uniq.sort.join(',')

  task = OpenTox::Task.create("PC descriptor calculation for dataset ", @uri) do |task|
    Rjb.load(nil,["-Xmx64m"]) # start vm
    byteArray = Rjb::import('java.io.ByteArrayOutputStream'); printStream = Rjb::import('java.io.PrintStream'); 
    out = byteArray.new() ; Rjb::import('java.lang.System').out = printStream.new(out) # joelib is too verbose
    s = Rjb::import('JoelibFc') # import main class
    OpenTox::Algorithm.pc_descriptors( { :dataset_uri => params[:dataset_uri], :pc_type => params[:pc_type], :descriptor => params[:descriptor], :rjb => s, :add_uri => false, :task => task, :subjectid => @subjectid} )
  end
  raise OpenTox::ServiceUnavailableError.newtask.uri+"\n" if task.status == "Cancelled"
  halt 202,task.uri.to_s+"\n"
end

