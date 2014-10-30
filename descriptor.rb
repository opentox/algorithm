# descriptors.rb
# Calculation of physico-chemical descriptors
# Author: Andreas Maunz, Christoph Helma
require 'openbabel'

module OpenTox

  class Application < Service

    before '/descriptor/:method/?' do
      if request.get?
        @algorithm = OpenTox::Algorithm::Descriptor.new @uri
        @algorithm.parameters = [ {
          RDF::DC.description => "Dataset URI", 
          RDF::OT.paramScope => "optional", 
          RDF::DC.title => "dataset_uri"
        },{
          RDF::DC.description => "Compound URI", 
          RDF::OT.paramScope => "optional", 
          RDF::DC.title => "compound_uri"
        } ]
        @algorithm.metadata = {
          RDF.type => [RDF::OT.Algorithm, RDF::OTA.DescriptorCalculation],
        }
      end
    end

    get '/descriptor/?' do
      render [ uri('/descriptor/physchem'), uri('/descriptor/smarts_match'), uri('/descriptor/smarts_count'), uri('/descriptor/lookup')].sort
    end

    get '/descriptor/smarts_match/?' do
      @algorithm.parameters += [ {
        RDF::DC.description => "SMARTS strings", 
        RDF::OT.paramScope => "mandatory", 
        RDF::DC.title => "descriptors"
      } ]
      @algorithm.metadata[RDF::DC.title] = "SMARTS matcher"
      render @algorithm
    end

    get '/descriptor/smarts_count/?' do
      @algorithm.parameters += [ {
        RDF::DC.description => "Counts SMARTS matches", 
        RDF::OT.paramScope => "mandatory", 
        RDF::DC.title => "descriptors"
      } ]
      @algorithm.metadata[RDF::DC.title] = "SMARTS count"
      render @algorithm
    end

    get '/descriptor/physchem/?' do
      @algorithm.parameters += [ {
        RDF::DC.description => "Physical-chemical descriptors (see #{File.join @uri, 'list'} for a list of supported parameters)", 
        RDF::OT.paramScope => "mandatory", 
        RDF::DC.title => "descriptors"
      } ]
      @algorithm.metadata[RDF::DC.title] = "Physical-chemical descriptors"
      render @algorithm
    end

    get '/descriptor/physchem/list/?' do
      response['Content-Type'] = 'text/plain'
      OpenTox::Algorithm::Descriptor::DESCRIPTORS.collect{|k,v| "#{k}\t#{v}"}.join "\n"
    end

    get '/descriptor/physchem/list_values/?' do
      response['Content-Type'] = 'text/plain'
      OpenTox::Algorithm::Descriptor::DESCRIPTOR_VALUES.join "\n"
    end

    get '/descriptor/physchem/unique/?' do
      response['Content-Type'] = 'text/plain'
      OpenTox::Algorithm::Descriptor::UNIQUEDESCRIPTORS.collect{|d| "#{d}\t#{OpenTox::Algorithm::Descriptor::DESCRIPTORS[d]}"}.join "\n"
    end

    get '/descriptor/lookup/?' do
      @algorithm.parameters += [ {
        RDF::DC.description => "Read feature values from a dataset", 
        RDF::OT.paramScope => "mandatory", 
        RDF::DC.title => "feature_dataset_uri"
      } ]
      @algorithm.metadata[RDF::DC.title] = "Dataset lookup"
      render @algorithm
    end

    post '/descriptor/:method' do
      if params[:method] == "physchem"
        params[:descriptors] = OpenTox::Algorithm::Descriptor::UNIQUEDESCRIPTORS if !params[:descriptors] or params[:descriptors] == [""]
      else
        bad_request_error "Please provide 'descriptors' parameters.", @uri unless params[:descriptors]
      end
      if params[:compound_uri] # return json
        @compounds = [params[:compound_uri]].flatten.collect{|u| OpenTox::Compound.new u}
        result = OpenTox::Algorithm::Descriptor.send(params[:method].to_sym, @compounds, params[:descriptors])
        Hash[result.map {|compound, v| [compound.uri, v] }].to_json
      elsif params[:dataset_uri] # return dataset
        task = OpenTox::Task.run("Calculating #{params[:method]} descriptors for dataset #{params[:dataset_uri]}.", @uri) do |task|
          @compounds = OpenTox::Dataset.new(params[:dataset_uri]).compounds
          result = OpenTox::Algorithm::Descriptor.send(params[:method].to_sym, @compounds, params[:descriptors])
          internal_server_error "internal error: wrong num results" if (@compounds.size != result.size)

          dataset = OpenTox::Dataset.new
          dataset.metadata = {
            RDF::DC.title => "Physico-chemical descriptors",
            RDF::DC.creator => @uri,
            RDF::OT.hasSource => @uri,
          }
          dataset.parameters = [
            { RDF::DC.title => "dataset_uri", RDF::OT.paramValue => params[:dataset_uri] },
            { RDF::DC.title => "descriptors", RDF::OT.paramValue => params[:descriptors] },
          ]
          params[:method] == "smarts_match" ? feature_type = RDF::OT.NominalFeature : feature_type = RDF::OT.NumericFeature 

          #get descriptor names as returned from calculation (names may differ from params[:descriptors] because of CDK descriptors)
          descriptors = []
          result.each do |compound,values|
            values.each do |desc,val|
              descriptors << desc unless descriptors.include?(desc)
            end
          end
          #try to preserve descriptor order
          sorted_descriptors = []
          params[:descriptors].each do |d|
            sorted_descriptors << descriptors.delete(d) if descriptors.include?(d)
          end
          sorted_descriptors += descriptors
          
          sorted_descriptors.each do |name|
            dataset.features << OpenTox::Feature.find_or_create({
                RDF::DC.title => name,
                RDF.type => [RDF::OT.Feature, feature_type],
                RDF::DC.description => OpenTox::Algorithm::Descriptor.description(name)
              })
          end
          result.each do |compound,values|
            dataset << ([compound] + sorted_descriptors.collect{|name| values[name]})
          end
          dataset.put
          dataset.uri
        end
        response['Content-Type'] = 'text/uri-list'
        halt 202,task.uri
      else
        bad_request_error "Please provide a dataset_uri or compound_uri parameter", @uri
      end
    end

  end

end

