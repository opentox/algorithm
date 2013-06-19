# descriptors.rb
# Calculation of physico-chemical descriptors
# Author: Andreas Maunz, Christoph Helma
require 'openbabel'

module OpenTox

  class Application < Service

    before '/descriptor/:lib/:descriptor/?' do
      #if request.get?
        lib = @uri.split("/")[-2].capitalize
        klass = OpenTox::Descriptor.const_get params[:lib].capitalize
        @algorithm = klass.new @uri, @subjectid unless params[:lib] == "smarts"
=begin
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
          bad_request_error "Please provide a dataset_uri or compound_uri parameter", @uri
        end
      end
=end
    end

    # Get a list of descriptor calculation 
    # @return [text/uri-list] URIs
    get '/descriptor/?' do
      #uris = ["Openbabel","Cdk","Joelib"].collect do |lib|
      uris = ["Openbabel"].collect do |lib|
        klass = OpenTox::Descriptor.const_get lib
        klass.all 
      end.flatten
      render uris
    end

    get '/descriptor/:lib/?' do
      klass = OpenTox::Descriptor.const_get params[:lib].capitalize
      render klass.all
    end

    # Get representation of descriptor calculation
    # @return [String] Representation
    get '/descriptor/:lib/:descriptor/?' do
      render @algorithm
    end

    post '/descriptor/smarts/:method/?' do
      method = params[:method].to_sym
      bad_request_error "Please provide a compound_uri or dataset_uri parameter and a smarts parameter. The count parameter is optional and defaults to false." unless (params[:compound_uri] or params[:dataset_uri]) and params[:smarts]
      params[:count] ?  params[:count] = params[:count].to_boolean : params[:count] = false
      if params[:compound_uri]
        compounds = OpenTox::Compound.new params[:compound_uri]
        response['Content-Type'] = "application/json"
        OpenTox::Descriptor::Smarts.send(method, compounds, params[:smarts], params[:count]).to_json
      elsif params[:dataset_uri]
        compounds = OpenTox::Dataset.new params[:dataset_uri]
        # TODO: create and return dataset
      end
    end

    # use /descriptor with dataset_uri and descriptor_uri parameters for efficient calculation of multiple compounds/descriptors
    post '/descriptor/:lib/:descriptor/?' do
      bad_request_error "Please provide a compound_uri parameter", @uri unless params[:compound_uri]
      params[:descriptor_uris] = [@uri]
      @algorithm.calculate params
      #compounds = [ Compound.new(params[:compound_uri], @subjectid) ]
      #send params[:lib].to_sym, compounds, @descriptors
      #@feature_dataset.put
      #@feature_dataset.uri
    end
=begin
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


      # CDK
      cdk_descriptors = YAML.load(`java -classpath #{CDK_JAR}:#{JAVA_DIR}  CdkDescriptorInfo`)
      cdk_descriptors.each do |descriptor|
        title = descriptor[:java_class].split('.').last.sub(/Descriptor/,'')
        descriptor[:title] = "Cdk " + title
        descriptor[:uri] = File.join $algorithm[:uri], "descriptor/cdk" ,title
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
        title = descriptor[:java_class].split('.').last
        descriptor[:uri] = File.join $algorithm[:uri], "descriptor/joelib",title
        descriptor[:title] = "Joelib " + title
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

      def cdk compounds, descriptors
        sdf_3d compounds
        # use java system call (rjb blocks within tasks)
        # use Tempfiles to avoid "Argument list too long" error 
        puts `java -classpath #{CDK_JAR}:#{JAVA_DIR}  CdkDescriptors #{@sdf_file.path} #{descriptors.collect{|d| d[:title].split("\s").last}.join(" ")}`
        YAML.load_file(@sdf_file.path+"cdk.yaml").each_with_index do |calculation,i|
          $logger.error "Descriptor calculation failed for compound #{compounds[i].uri}." if calculation.empty?
          calculation.each do |name,value|
            feature = DESCRIPTORS[:cdk].collect{|d| d[:features]}.flatten.select{|f| f[RDF::DC.title].split("\s").last == name.to_s}.first
            @feature_dataset.add_data_entry compounds[i], feature, fix_value(value)
          end
        end
      end

      def joelib compounds, descriptors
        # use java system call (rjb blocks within tasks)
        # use Tempfiles to avoid "Argument list too long" error 
        sdf_3d compounds
        puts `java -classpath #{JOELIB_JAR}:#{JMOL_JAR}:#{LOG4J_JAR}:#{JAVA_DIR}  JoelibDescriptors  #{@sdf_file.path} #{descriptors.collect{|d| d[:java_class]}.join(" ")}`
        YAML.load_file(@sdf_file.path+"joelib.yaml").each_with_index do |calculation,i|
          $logger.error "Descriptor calculation failed for compound #{compounds[i].uri}." if calculation.empty?
          calculation.each do |java_class,value|
            feature = DESCRIPTORS[:joelib].select{|d| d[:java_class] == java_class}.first[:feature]
            @feature_dataset.add_data_entry compounds[i], feature, fix_value(value)
          end
        end
      end

      def sdf_3d compounds
        unless @sdf_file and File.exists? @sdf_file.path
          @sdf_file = Tempfile.open("sdf")
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
              @sdf_file.puts sdf_2d
            else
              @sdf_file.puts sdf_3d
            end
          end
          @sdf_file.close
        end
      end
    end

    before '/descriptor/:lib/:descriptor/?' do
      @descriptors = DESCRIPTORS[params[:lib].to_sym].select{|d| d[:title].split(" ").last == params[:descriptor]}
      bad_request_error "Unknown descriptor #{@uri}. See #{uri('descriptor')} for a complete list of supported descriptors.", @uri if @descriptors.empty?
      @descriptor = @descriptors.first
    end

    after do # Tempfile cleanup
      if @sdf_file and File.exists? @sdf_file.path
        FileUtils.rm Dir["#{@sdf_file.path}*.yaml"]
        @sdf_file.unlink
      end
      @sdf_file = nil
    end

    # Get representation of descriptor calculation
    # @return [String] Representation
    get '/descriptor/:lib/:descriptor/?' do
      render @algorithm
    end

    post '/descriptor/?' do
      task = OpenTox::Task.run "Calculating PC descriptors", @uri, @subjectid do |task|
        if params[:descriptor_uris]
          descriptors = {}
          params[:descriptor_uris].each do |descriptor_uri|
            lib = descriptor_uri.split('/')[-2]
            descriptors[lib.to_sym] ||= []
            descriptors[lib.to_sym] += DESCRIPTORS[lib.to_sym].select{|d| d[:uri] == descriptor_uri}
          end
        else
          descriptors = DESCRIPTORS
        end
        if params[:compound_uri]
          compounds = [ Compound.new(params[:compound_uri], @subjectid) ]
        elsif params[:dataset_uri]
          compounds = Dataset.new(params[:dataset_uri]).compounds
        end
        [:openbabel, :cdk, :joelib].each{ |lib| send lib, compounds, descriptors[lib] if descriptors[lib] }
        @feature_dataset.put
        @feature_dataset.uri
      end
      response['Content-Type'] = 'text/uri-list'
      halt 202, task.uri
    end
=end

  end

end

