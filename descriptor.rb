# descriptors.rb
# Calculation of physico-chemical descriptors
# Author: Andreas Maunz, Christoph Helma
require 'rjb'
require 'openbabel'

module OpenTox

  class Application < Service

    ENV["JAVA_HOME"] ||= "/usr/lib/jvm/java-7-openjdk" 
    java_dir = File.join(File.dirname(__FILE__),"java")
    jars = Dir[File.join(ENV["JAVA_HOME"],"lib","*.jar")]
    jars += Dir[File.join(java_dir,"*jar")]
    ENV["CLASSPATH"] = ([java_dir]+jars).join(":")
    jars.each { |jar| Rjb::load jar }

    StringReader ||= Rjb::import "java.io.StringReader"
    CDKMdlReader ||= Rjb::import "org.openscience.cdk.io.MDLReader"
    CDKMolecule ||= Rjb::import "org.openscience.cdk.Molecule"
    CDKDescriptorEngine ||= Rjb::import "org.openscience.cdk.qsar.DescriptorEngine"
    #AromaticityDetector = Rjb::import 'org.openscience.cdk.aromaticity.CDKHueckelAromaticityDetector'
    JOELIBHelper ||= Rjb::import 'joelib2.feature.FeatureHelper'
    JOELIBFactory ||= Rjb::import 'joelib2.feature.FeatureFactory'
    JOELIBSmilesParser ||= Rjb::import "joelib2.smiles.SMILESParser"
    JOELIBTypeHolder ||= Rjb::import "joelib2.io.BasicIOTypeHolder"
    JOELIBMolecule ||= Rjb::import "joelib2.molecule.BasicConformerMolecule"

    unless defined? DESCRIPTORS 

      # initialize descriptors and features at startup to avoid duplication
      descriptors = { :cdk => [], :openbabel => [], :joelib => [] } # use arrays to keep the sequence intact

      @@obmol = OpenBabel::OBMol.new
      @@obconversion = OpenBabel::OBConversion.new
      @@obconversion.set_in_format 'inchi'
      @@cdk_engine = CDKDescriptorEngine.new(CDKDescriptorEngine.MOLECULAR)

      # OpenBabel
      OpenBabel::OBDescriptor.list_as_string("descriptors").split("\n").each do |d|
        title,description = d.split(/\s+/,2)
        unless title =~ /cansmi|formula|InChI|smarts|title/ or title == "s"
          title = "OpenBabel "+title
          feature = OpenTox::Feature.find_or_create({
              RDF::DC.title => title,
              RDF.type => [RDF::OT.Feature, RDF::OT.NumericFeature],
              RDF::DC.description => description,
            }, @subjectid)
          descriptors[:openbabel] << {
            :title => title,
            :description => description,
            :calculator => OpenBabel::OBDescriptor.find_type(title.split(" ").last),
            :feature => feature
          }
        end
      end

      # CDK
      @@cdk_engine.getDescriptorClassNames.toArray.each do |d|
        cdk_class = d.toString
        title = "CDK "+cdk_class.split('.').last
        description = @@cdk_engine.getDictionaryDefinition(cdk_class).gsub(/\s+/,' ').strip + " (Class: " + @@cdk_engine.getDictionaryClass(cdk_class).join(", ") + ")"
        descriptor = {
          :title => title,
          :description => description,
          :calculator => Rjb::import(cdk_class).new,
          :features => []
        }
        # CDK Descriptors may return more than one value
        descriptor[:features] = descriptor[:calculator].getDescriptorNames.collect do |name|
          feature = OpenTox::Feature.find_or_create({
            RDF::DC.title => "#{title} #{name}",
            RDF.type => [RDF::OT.Feature, RDF::OT.NumericFeature],
            RDF::DC.description => description
          }, @subjectid)
        end
        descriptors[:cdk] << descriptor
      end

      # JOELIB
      factory = JOELIBFactory.instance
      JOELIBHelper.instance.getNativeFeatures.toArray.each do |f|
        joelib_class = f.toString
        unless joelib_class == "joelib2.feature.types.GlobalTopologicalChargeIndex"
          # CH: returns "joelib2.feature.types.atomlabel.AtomValence\n#{numeric value}"
          # unsure if numeric_value is GlobalTopologicalChargeIndex or AtomValence
          # excluded from descriptor list
          title = "JOELib "+joelib_class.split('.').last
          description = title # feature.getDescription.hasText returns false, feature.getDescription.getHtml returns unparsable content
          feature = OpenTox::Feature.find_or_create({
              RDF::DC.title => title,
              RDF.type => [RDF::OT.Feature, RDF::OT.NumericFeature],
              RDF::DC.description => description,
            }, @subjectid)
          descriptors[:joelib] << {
            :title => title,
            :description => description, 
            :calculator => Rjb::import(joelib_class).new,
            :feature => feature
          }
        end
      end
      DESCRIPTORS = descriptors

    end

    helpers do

      def openbabel compounds, descriptors
        compounds.each do |compound|
          @@obconversion.read_string @@obmol, compound.inchi
          descriptors.each do |descriptor|
            puts descriptor[:title]
            @feature_dataset.add_data_entry compound, descriptor[:feature], fix_value(descriptor[:calculator].predict(@@obmol))
          end
        end
      end

      def cdk compounds, descriptors
        @@obconversion.set_out_format 'sdf'
        compounds.each do |compound|
          @@obconversion.read_string @@obmol, compound.inchi
          sdf = @@obconversion.write_string(@@obmol)  
          OpenBabel::OBOp.find_type("Gen3D").do(@@obmol) 
          sdf_3D = @@obconversion.write_string(@@obmol)  
          if sdf_3D.match(/.nan/)
            warning = "3D generation failed for compound #{compound.uri} (using 2D structure)."
            $logger.warn warning
            @feature_dataset[RDF::OT.Warnings] ? @feature_dataset[RDF::OT.Warnings] << warning : @feature_dataset[RDF::OT.Warnings] = warning
          else
            sdf = sdf_3D
          end
          reader = CDKMdlReader.new(StringReader.new(sdf))
          cdk_compound = reader.read(CDKMolecule.new)
          #AromaticityDetector.detectAromaticity(cdk_compound)
          values = []
          descriptors.each do |descriptor|
            puts descriptor[:title]
            begin
            result = descriptor[:calculator].calculate cdk_compound
            result.getValue.toString.split(",").each_with_index do |value,i|
              @feature_dataset.add_data_entry compound, descriptor[:features][i], fix_value(value)
            end
            rescue
              $logger.error "#{descriptor[:title]} calculation failed with #{$!.message} for compound #{compound.uri}."
            end
          end
        end
      end

      def joelib compounds, descriptors
        @@obconversion.set_out_format 'smi'
        compounds.each do |compound|
          mol = JOELIBMolecule.new(JOELIBTypeHolder.instance.getIOType("SMILES"), JOELIBTypeHolder.instance.getIOType("SMILES"))
          @@obconversion.read_string @@obmol, compound.inchi
          JOELIBSmilesParser.smiles2molecule mol, @@obconversion.write_string(@@obmol).strip, "Smiles: #{@@obconversion.write_string(@@obmol).strip}"
          mol.addHydrogens
          descriptors.each do |descriptor|
            puts descriptor[:title]
            puts descriptor[:calculator].toString#java_methods.inspect
            puts descriptor[:calculator].calculate(mol).toString
            @feature_dataset.add_data_entry compound, descriptor[:feature], fix_value(descriptor[:calculator].calculate(mol).toString)
          end
        end
      end

      def fix_value val
        #unless val.numeric?
        if val.numeric?
          val = Float(val)
          val = nil if val.nan? or val.infinite?
        end
        val
      end
    end

    before '/descriptor/?*' do
      if request.get?
        @algorithm = OpenTox::Algorithm.new @uri
        @algorithm.parameters = [ 
          { RDF::DC.description => "Dataset URI", 
            RDF::OT.paramScope => "optional", 
            RDF::DC.title => "dataset_uri" } ,
          { RDF::DC.description => "Compound URI", 
            RDF::OT.paramScope => "optional", 
            RDF::DC.title => "compound_uri" } 
        ]
        @algorithm.metadata = {
          RDF.type => [RDF::OTA.DescriptorCalculation],
        }
      elsif request.post?
        @feature_dataset = Dataset.new nil, @subjectid
        @feature_dataset.metadata = {
          RDF::DC.title => "Physico-chemical descriptors",
          RDF::DC.creator => @uri,
          RDF::OT.hasSource => @uri,
        }
        if params[:compound_uri]
          @feature_dataset.parameters = [ { RDF::DC.title => "compound_uri", RDF::OT.paramValue => params[:compound_uri] }]
        elsif params[:dataset_uri]
          @feature_dataset.parameters = [ { RDF::DC.title => "dataset_uri", RDF::OT.paramValue => params[:dataset_uri] }]
        else
          bad_request_error "Please provide a dataset_uri or compound_uri paramaeter", @uri
        end
      end
    end

    before '/descriptor/:lib/:descriptor/?' do
      @descriptors = DESCRIPTORS[params[:lib].to_sym].select{|d| d[:title].split(" ").last == params[:descriptor]}
      bad_request_error "Unknown descriptor #{@uri}. See #{uri('descriptors')} for a complete list of supported descriptors.", @uri if @descriptors.empty?
      @descriptor = @descriptors.first
    end

    # Get a list of descriptor calculation 
    # @return [text/uri-list] URIs
    get '/descriptor/?' do
      DESCRIPTORS.collect{|lib,d| d.collect{|n| uri("/descriptors/#{lib}/#{n[:title].split(" ").last}")}}.flatten.sort.join("\n")
    end

    get '/descriptor/:lib/?' do
      DESCRIPTORS[params[:lib].to_sym].collect{|n| uri("/descriptors/#{params[:lib].to_sym}/#{n[:title].split(" ").last}")}.sort.join("\n")
    end

    # Get representation of descriptor calculation
    # @return [String] Representation
    get '/descriptor/:lib/:descriptor/?' do
      @algorithm[RDF::DC.title] = @descriptor[:title]
      @algorithm[RDF::DC.description] = @descriptor[:description]
      format_output(@algorithm)
    end

    post '/descriptor/?' do
      #task = OpenTox::Task.run "Calculating PC descriptors", @uri, @subjectid do |task|
        puts "Task created"
        if params[:descriptors]
          descriptors = {}
          params[:descriptors].each do |descriptor|
            #lib, title = descriptor.split('/')
            descriptors[lib.to_sym] ||= []
            descriptors[lib.to_sym] << DESCRIPTORS[lib.to_sym].select{|d| d[:title] == descriptor}
          end
        else
          descriptors = DESCRIPTORS
        end
        if params[:compound_uri]
          compounds = [ Compound.new(params[:compound_uri], @subjectid) ]
        elsif params[:dataset_uri]
          compounds = Dataset.new(params[:dataset_uri]).compounds
        end
        puts "Calculating"
        [:openbabel, :cdk, :joelib].each{ |lib| puts lib; send lib, compounds, descriptors[lib]; puts lib.to_s+" finished" }
        #[:joelib].each{ |lib| send lib, compounds, descriptors[lib]; puts lib.to_s+" finished" }
        puts "saving file"
        File.open("/home/ch/tmp.nt","w+"){|f| f.puts @feature_dataset.to_ntriples}
        puts "saving "+@feature_dataset.uri
        @feature_dataset.put
        puts "finished"
        @feature_dataset.uri
      #end
      #response['Content-Type'] = 'text/uri-list'
      #halt 202, task.uri
    end

    post '/descriptor/:lib/:descriptor/?' do
      if params[:compound_uri]
        compounds = [ Compound.new(params[:compound_uri], @subjectid) ]
        send params[:lib].to_sym, compounds, @descriptors
        @feature_dataset.put
        @feature_dataset.uri
      elsif params[:dataset_uri]
        task = OpenTox::Task.run "Calculating PC descriptors", @uri, @subjectid do |task|
          compounds = Dataset.new(params[:dataset_uri]).compounds
          send params[:lib].to_sym, compounds, @descriptors
          @feature_dataset.put
          @feature_dataset.uri
        end
        response['Content-Type'] = 'text/uri-list'
        halt 202, task.uri
      end
    end

  end

end

