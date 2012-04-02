# pc.rb
# (P)hysico (C)hemical descriptor calculation
# Author: Andreas Maunz


# Get a list of OpenBabel algorithms
# @return [text/uri-list] URIs of OpenBabel algorithms
get '/pc' do
  algorithms = YAML::load_file File.join(ENV['HOME'], ".opentox", "config", "pc_descriptors.yaml")
  response['Content-Type'] = 'text/uri-list'
  list = (algorithms.keys << "AllDescriptors").join("\n") + "\n"
  case request.env['HTTP_ACCEPT']
  when /text\/html/
    content_type "text/html"
    OpenTox.text_to_html list
  else
    content_type 'text/uri-list'
    list
  end
end

# Get RDF/XML representation of OpenBabel algorithm
# @return [application/rdf+xml] OWL-DL representation of OpenBabel algorithm
get '/pc/:descriptor' do
  descriptors = YAML::load_file File.join(ENV['HOME'], ".opentox", "config", "pc_descriptors.yaml")
  alg_params = [ { DC.description => "Dataset URI", OT.paramScope => "mandatory", DC.title => "dataset_uri" } ]
      
  if params[:descriptor] != "AllDescriptors"
    descriptors = descriptors[params[:descriptor]]
  else
    alg_params << { DC.description => "Descriptor Category, one or more of '#{descriptors.collect { |id, info| info[:category] }.uniq.sort.join(",")}'", OT.paramScope => "optional", DC.title => "category" }
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
    algorithm.metadata[DC.description] << (", category: " + descriptors[:category]) unless descriptors[:id] == "AllDescriptors"
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

