module OpenTox

  module Descriptor 
    include OpenTox

    def initialize uri, subjectid
      super uri, subjectid
      @parameters = [ 
        { RDF::DC.description => "Dataset URI", 
          RDF::OT.paramScope => "optional", 
          RDF::DC.title => "dataset_uri" } ,
        { RDF::DC.description => "Compound URI", 
          RDF::OT.paramScope => "optional", 
          RDF::DC.title => "compound_uri" } 
      ]
      tokens = uri.split %r{/}
      @metadata = {
        RDF::DC.title => "#{tokens[-2].capitalize} #{tokens[-1]}",
        RDF.type => [RDF::OT.Algorithm, RDF::OTA.DescriptorCalculation],
      }
    end

    def fix_value val
      if val.numeric?
        val = Float(val)
        val = nil if val.nan? or val.infinite?
      else
        val = nil if val == "NaN"
      end
      val
    end

    class Openbabel
      include Descriptor

      def initialize uri, subjectid=nil
        descriptor = OpenBabel::OBDescriptor.find_type(uri.split("/").last)
        bad_request_error "Unknown descriptor #{uri}. See #{File.join $algorithm[:uri], "descriptor"} for a list of supported descriptors.", uri unless descriptor
        super uri, subjectid
        @metadata[RDF::DC.description] = descriptor.description.split("\n").first
        @obmol = OpenBabel::OBMol.new
        @obconversion = OpenBabel::OBConversion.new
        @obconversion.set_in_format 'inchi'
      end

      def self.all
        puts OpenBabel::OBDescriptor.list_as_string("descriptors")
        OpenBabel::OBDescriptor.list_as_string("descriptors").split("\n").collect do |d|
          title = d.split(/\s+/).first
          puts title
          unless title =~ /cansmi|formula|InChI|smarts|title/ or title == "s"
            File.join $algorithm[:uri], "descriptor/openbabel" ,title
          end
        end.compact.sort{|a,b| a.upcase <=> b.upcase}
      end

      # TODO: add to feature dataset
      # find feature
      # generic method for all libs
      def calculate params
        if params[:compound_uri]
          compounds = [ Compound.new(params[:compound_uri], @subjectid) ]
        elsif params[:dataset_uri]
          compounds = Dataset.new(params[:dataset_uri], @subjectid).compounds
        end
        compounds.collect do |compound|
          @obconversion.read_string @obmol, compound.inchi
          params[:descriptor_uris].each do |descriptor_uri|
            method = descriptor_uri.split('/').last
            calculator = OpenBabel::OBDescriptor.find_type method
            value = fix_value calculator.predict(@obmol)
            feature = OpenTox::Feature.find_or_create({
                RDF::DC.title => "OpenBabel "+method,
                RDF.type => [RDF::OT.Feature, RDF::OT.NumericFeature],
                RDF::DC.description => calculator.description,
              }, @subjectid)
            [compound, feature, value]
          end
        end
      end
    end

    class Smarts

      def self.fingerprint compounds, smarts, count=false
        if compounds.is_a? OpenTox::Compound
          compounds = [compounds]
        elsif compounds.is_a? OpenTox::Dataset
          # TODO: create and return dataset
          compounds = compounds.compounds
        else
          bad_request_error "Cannot match smarts on #{compounds.class} objects."
        end
        smarts = [smarts] unless smarts.is_a? Array
        obconversion = OpenBabel::OBConversion.new
        obmol = OpenBabel::OBMol.new
        obconversion.set_in_format('inchi')
        smarts_pattern = OpenBabel::OBSmartsPattern.new
        matches = []
        compounds.each do |compound|
          obconversion.read_string(obmol,compound.inchi)
          matches << []
          smarts.each do |smart|
            smarts_pattern.init(smart)
            if smarts_pattern.match(obmol)
              count ? value = smarts_pattern.get_map_list.to_a.size : value = 1
            else
              value = 0 
            end
            matches.last << value
          end
        end
        matches
      end

      def self.smarts_count compounds, smarts
        smarts_fingerprint compounds,smarts,true
      end
    end
  end

end
