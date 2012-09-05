# pc.rb
# (P)hysico (C)hemical descriptor calculation
# Author: Andreas Maunz

module OpenTox
  class Application < Service


  # Get a list of descriptor calculation algorithms
  # @return [text/uri-list] URIs
  get '/pc' do
    algorithms = YAML::load_file File.join(ENV['HOME'], ".opentox", "config", "pc_descriptors.yaml")
    list = (algorithms.keys.sort << "AllDescriptors").collect { |name| url_for("/pc/#{name}",:full) }.join("\n") + "\n"
    format_output(list)
  end
  
  # Get representation of Descriptor Calculation Algorithm
  # @return [String] Representation
  get '/pc/:descriptor' do
    descriptors = YAML::load_file File.join(ENV['HOME'], ".opentox", "config", "pc_descriptors.yaml")
    alg_params = [ 
      { DC.description => "Dataset URI", 
        OT.paramScope => "mandatory", 
        DC.title => "dataset_uri" } 
    ]
    if params[:descriptor] != "AllDescriptors"
      descriptors = descriptors[params[:descriptor]]
    else
      alg_params << { 
        DC.description => "Physico-chemical type, one or more of '#{descriptors.collect { |id, info| info[:pc_type] }.uniq.sort.join(",")}'", 
        OT.paramScope => "optional", DC.title => "pc_type" 
      }
      alg_params << { 
        DC.description => "Software Library, one or more of '#{descriptors.collect { |id, info| info[:lib] }.uniq.sort.join(",")}'", 
        OT.paramScope => "optional", DC.title => "lib" 
      }
      descriptors = {:id => "AllDescriptors", :name => "All PC descriptors" } # Comes from pc_descriptors.yaml for single descriptors
    end
  
    if descriptors 
      # Contents
      algorithm = OpenTox::Algorithm::Generic.new(url_for("/pc/#{params[:descriptor]}",:full))
      mmdata = {
        DC.title => params[:descriptor],
        DC.creator => "andreas@maunz.de",
        DC.description => descriptors[:name],
        RDF.type => [OTA.DescriptorCalculation],
      }
      mmdata[DC.description] << (", pc_type: " + descriptors[:pc_type]) unless descriptors[:id] == "AllDescriptors"
      mmdata[DC.description] << (", lib: " + descriptors[:lib])         unless descriptors[:id] == "AllDescriptors"
      algorithm.metadata=mmdata
      algorithm.parameters = alg_params
      format_output(algorithm)
    else
      raise OpenTox::NotFoundError.new "Unknown descriptor #{params[:descriptor]}."
    end
  end

  end
end
