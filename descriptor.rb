# descriptors.rb
# Calculation of physico-chemical descriptors
# Author: Andreas Maunz, Christoph Helma
require 'openbabel'

module OpenTox

  class Application < Service

    ENV["JAVA_HOME"] ||= "/usr/lib/jvm/java-7-openjdk" 
    JAVA_DIR = File.join(File.dirname(__FILE__),"java")
    CDK_JAR = Dir[File.join(JAVA_DIR,"cdk-*jar")].last
    JOELIB_JAR = File.join(JAVA_DIR,"joelib2.jar")
    LOG4J_JAR = File.join(JAVA_DIR,"log4j.jar")
    JMOL_JAR = File.join(JAVA_DIR,"Jmol.jar")

    unless defined? DESCRIPTORS 

      # initialize descriptors and features at startup to avoid duplication
      descriptors = { :cdk => [], :openbabel => [], :joelib => [] } # use arrays to keep the sequence intact

      @@obmol = OpenBabel::OBMol.new
      @@obconversion = OpenBabel::OBConversion.new
      @@obconversion.set_in_format 'inchi'

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
      cdk_descriptors = YAML.load(`java -classpath #{CDK_JAR}:#{JAVA_DIR}  CdkDescriptorInfo`)
      cdk_descriptors.each do |descriptor|
        descriptor[:title] = "Cdk " + descriptor[:java_class].split('.').last.sub(/Descriptor/,'')
        descriptor[:features] = []
        descriptor[:names].each do |name|
          descriptor[:features] << OpenTox::Feature.find_or_create({
            RDF::DC.title => "#{descriptor[:title]} #{name}",
            RDF.type => [RDF::OT.Feature, RDF::OT.NumericFeature],
            RDF::DC.description => descriptor[:description]
          }, @subjectid)
        end
      end
      descriptors[:cdk] = cdk_descriptors
      
      # Joelib
      joelib_descriptors = YAML.load(`java -classpath #{JOELIB_JAR}:#{LOG4J_JAR}:#{JAVA_DIR}  JoelibDescriptorInfo | sed '0,/---/d'`) # strip Joelib messages at stdout
      joelib_descriptors.each do |descriptor|
        # exclude Hashcode (not a physchem property) and GlobalTopologicalChargeIndex (Joelib bug)
        next if descriptor[:java_class] == "joelib2.feature.types.MoleculeHashcode" or descriptor[:java_class] == "joelib2.feature.types.GlobalTopologicalChargeIndex"
        descriptor[:title] = "Joelib " + descriptor[:java_class].split('.').last
        descriptor[:feature] = OpenTox::Feature.find_or_create({
            RDF::DC.title => descriptor[:title],
            RDF.type => [RDF::OT.Feature, RDF::OT.NumericFeature],
            #RDF::DC.description => descriptor[:title], # impossible to obtain meaningful descriptions from JOELIb, see java/JoelibDescriptors.java
          }, @subjectid)
      end
      descriptors[:joelib] = joelib_descriptors.select{|d| d[:title]}

      DESCRIPTORS = descriptors

    end

    helpers do

      def openbabel compounds, descriptors
        compounds.each do |compound|
          @@obconversion.read_string @@obmol, compound.inchi
          descriptors.each do |descriptor|
            @feature_dataset.add_data_entry compound, descriptor[:feature], fix_value(descriptor[:calculator].predict(@@obmol))
          end
        end
      end

      def cdk compounds, descriptors
        sdf_3d compounds
        # rjb blocks within tasks
        # Avoid "Argument list too long" error by sending only short descriptor names
        #yaml = `export CDKDescriptors= ;echo "#{@sdf}" |java -classpath #{CDK_JAR}:#{JAVA_DIR}  CdkDescriptors #{descriptors.collect{|d| d[:title].split("\s").last}.join(" ")}`
        #yaml = `export CDKDescriptors='#{descriptors.collect{|d| d[:title].split("\s").last}.join(" ")}';echo "#{@sdf}" |java -classpath #{CDK_JAR}:#{JAVA_DIR}  CdkDescriptors `
        puts `java -classpath #{CDK_JAR}:#{JAVA_DIR}  CdkDescriptors #{@sdf_file.path} #{descriptors.collect{|d| d[:title].split("\s").last}.join(" ")}`
        #puts yaml
        YAML.load_file(@sdf_file.path+"cdk.yaml").each_with_index do |calculation,i|
          $logger.error "Descriptor calculation failed for compound #{compounds[i].uri}." if calculation.empty?
          calculation.each do |name,value|
            feature = DESCRIPTORS[:cdk].collect{|d| d[:features]}.flatten.select{|f| f[RDF::DC.title].split("\s").last == name.to_s}.first
            @feature_dataset.add_data_entry compounds[i], feature, fix_value(value)
          end
        end
      end

      def joelib compounds, descriptors
        sdf_3d compounds
        # rjb blocks within tasks
        #yaml = `echo "#{@sdf}" |java -classpath #{JOELIB_JAR}:#{JMOL_JAR}:#{LOG4J_JAR}:#{JAVA_DIR}  JoelibDescriptors #{descriptors.collect{|d| d[:java_class]}.join(" ")}|grep "^[- ]"`
        #puts "java -classpath #{JOELIB_JAR}:#{JMOL_JAR}:#{LOG4J_JAR}:#{JAVA_DIR}  JoelibDescriptors  #{@sdf_file.path} #{descriptors.collect{|d| d[:java_class]}.join(" ")}"
        puts `java -classpath #{JOELIB_JAR}:#{JMOL_JAR}:#{LOG4J_JAR}:#{JAVA_DIR}  JoelibDescriptors  #{@sdf_file.path} #{descriptors.collect{|d| d[:java_class]}.join(" ")}`
        #YAML.load(yaml).each_with_index do |calculation,i|
        YAML.load_file(@sdf_file.path+"joelib.yaml").each_with_index do |calculation,i|
          $logger.error "Descriptor calculation failed for compound #{compounds[i].uri}." if calculation.empty?
          calculation.each do |java_class,value|
            feature = DESCRIPTORS[:joelib].select{|d| d[:java_class] == java_class}.first[:feature]
            @feature_dataset.add_data_entry compounds[i], feature, fix_value(value)
          end
        end
      end

      def sdf_3d compounds
        #unless @sdf_file and File.exists? @sdf_file.path
        unless @sdf
          @sdf = ""
          @@obconversion.set_out_format 'sdf'
          # create 3d sdf file (faster in Openbabel than in CDK)
          compounds.each do |compound|
            @@obconversion.read_string @@obmol, compound.inchi
            sdf_2d = @@obconversion.write_string(@@obmol)  
            OpenBabel::OBOp.find_type("Gen3D").do(@@obmol) 
            sdf_3d = @@obconversion.write_string(@@obmol)  
            if sdf_3d.match(/.nan/)
              warning = "3D generation failed for compound #{compound.uri}, trying to calculate descriptors from 2D structure."
              $logger.warn warning
              @feature_dataset[RDF::OT.Warnings] ? @feature_dataset[RDF::OT.Warnings] << warning : @feature_dataset[RDF::OT.Warnings] = warning
              @sdf << sdf_2d
            else
              @sdf << sdf_3d
            end
          end
          @sdf_file = Tempfile.open("sdf")
          @sdf_file.puts @sdf
          @sdf_file.close
        end
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
      bad_request_error "Unknown descriptor #{@uri}. See #{uri('descriptor')} for a complete list of supported descriptors.", @uri if @descriptors.empty?
      @descriptor = @descriptors.first
    end

    after do
      #@sdf_file.unlink if @sdf_file and File.exists @sdf_file.path
      #TODO cleanup yamls
      @sdf_file = nil
    end

    # Get a list of descriptor calculation 
    # @return [text/uri-list] URIs
    get '/descriptor/?' do
      DESCRIPTORS.collect{|lib,d| d.collect{|n| uri("/descriptor/#{lib}/#{n[:title].split(" ").last}")}}.flatten.sort.join("\n")
    end

    get '/descriptor/:lib/?' do
      DESCRIPTORS[params[:lib].to_sym].collect{|n| uri("/descriptor/#{params[:lib].to_sym}/#{n[:title].split(" ").last}")}.sort.join("\n")
    end

    # Get representation of descriptor calculation
    # @return [String] Representation
    get '/descriptor/:lib/:descriptor/?' do
      @algorithm[RDF::DC.title] = @descriptor[:title]
      @algorithm[RDF::DC.description] = @descriptor[:description] if @descriptor[:description]
      format_output(@algorithm)
    end

    post '/descriptor/?' do
      task = OpenTox::Task.run "Calculating PC descriptors", @uri, @subjectid do |task|
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
        [:openbabel, :cdk, :joelib].each{ |lib| send lib, compounds, descriptors[lib] }
        @feature_dataset.put
        @feature_dataset.uri
      end
      response['Content-Type'] = 'text/uri-list'
      halt 202, task.uri
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

