require 'digest/md5'
ENV["JAVA_HOME"] ||= "/usr/lib/jvm/java-7-openjdk" 
module OpenTox

  module Algorithm 
    class Descriptor 
      include OpenTox

      JAVA_DIR = File.join(File.dirname(__FILE__),"..","java")
      CDK_JAR = Dir[File.join(JAVA_DIR,"cdk-*jar")].last
      JOELIB_JAR = File.join(JAVA_DIR,"joelib2.jar")
      LOG4J_JAR = File.join(JAVA_DIR,"log4j.jar")
      JMOL_JAR = File.join(JAVA_DIR,"Jmol.jar")

      obexclude = ["cansmi","cansmiNS","formula","InChI","InChIKey","s","smarts","title"]
      OBDESCRIPTORS = Hash[OpenBabel::OBDescriptor.list_as_string("descriptors").split("\n").collect do |d|
        name,description = d.split(/\s+/,2)
        ["Openbabel."+name,description] unless obexclude.include? name
      end.compact.sort{|a,b| a[0] <=> b[0]}]

      CDKDESCRIPTORS = Hash[YAML.load(`java -classpath #{CDK_JAR}:#{JAVA_DIR}  CdkDescriptorInfo`).collect { |d| ["Cdk."+d[:java_class].split('.').last.sub(/Descriptor/,''), d[:description]] }.sort{|a,b| a[0] <=> b[0]}]

      # exclude Hashcode (not a physchem property) and GlobalTopologicalChargeIndex (Joelib bug)
      joelibexclude = ["MoleculeHashcode","GlobalTopologicalChargeIndex"]
      # strip Joelib messages from stdout
      JOELIBDESCRIPTORS = Hash[YAML.load(`java -classpath #{JOELIB_JAR}:#{LOG4J_JAR}:#{JAVA_DIR}  JoelibDescriptorInfo | sed '0,/---/d'`).collect do |d|
        name = d[:java_class].sub(/^joelib2.feature.types./,'')
        # impossible to obtain meaningful descriptions from JOELIb, see java/JoelibDescriptors.java
        ["Joelib."+name, "no description available"] unless joelibexclude.include? name
      end.compact.sort{|a,b| a[0] <=> b[0]}] 

      DESCRIPTORS = OBDESCRIPTORS.merge(CDKDESCRIPTORS.merge(JOELIBDESCRIPTORS))
      require_relative "unique_descriptors.rb"

      def self.description descriptor
        lib = descriptor.split('.').first
        case lib
        when "Openbabel"
          OBDESCRIPTORS[descriptor]
        when "Cdk"
          name = descriptor.split('.')[0..-2].join('.')
          CDKDESCRIPTORS[name]
        when "Joelib"
          JOELIBDESCRIPTORS[descriptor]
        when "lookup"
          "Read feature values from a dataset"
        end
      end

      def self.smarts_match compounds, smarts, count=false
        obconversion = OpenBabel::OBConversion.new
        obmol = OpenBabel::OBMol.new
        obconversion.set_in_format('inchi')
        smarts_pattern = OpenBabel::OBSmartsPattern.new
        fingerprint = {}
        compounds = [compounds] unless compounds.is_a? Array
        smarts = [smarts] unless smarts.is_a? Array
        compounds.each do |compound|
          obconversion.read_string(obmol,compound.inchi)
          fingerprint[compound] = {}
          smarts.each do |smart|
            smarts_pattern.init(smart)
            if smarts_pattern.match(obmol)
              count ? value = smarts_pattern.get_map_list.to_a.size : value = 1
            else
              value = 0 
            end
            fingerprint[compound][smart] = value
          end
        end
        fingerprint
      end

      def self.smarts_count compounds, smarts
        smarts_match compounds,smarts,true
      end

      def self.physchem compounds, descriptors
        des = {}
        descriptors.each do |d|
          lib, descriptor = d.split(".",2)
          lib = lib.downcase.to_sym
          des[lib] ||= []
          des[lib] << descriptor
        end
        result = {}
        des.each do |lib,d|
          send(lib, compounds, d).each do |compound,values|
            result[compound] ||= {}
            result[compound].merge! values
          end 
        end
        result
      end

      def self.openbabel compounds, descriptors
        obdescriptors = descriptors.collect{|d| OpenBabel::OBDescriptor.find_type d}
        obmol = OpenBabel::OBMol.new
        obconversion = OpenBabel::OBConversion.new
        obconversion.set_in_format 'inchi'
        fingerprint = {}
        compounds.each do |compound|
          obconversion.read_string obmol, compound.inchi
          fingerprint[compound] = {}
          obdescriptors.each_with_index do |descriptor,i|
            fingerprint[compound]["Openbabel."+descriptors[i]] = fix_value(descriptor.predict(obmol))
          end
        end
        fingerprint
      end

      def self.cdk compounds, descriptors
        sdf = sdf_3d compounds
        # use java system call (rjb blocks within tasks)
        # use Tempfiles to avoid "Argument list too long" error 
        `java -classpath #{CDK_JAR}:#{JAVA_DIR}  CdkDescriptors #{sdf} #{descriptors.join(" ")}`
        fingerprint = {}
        YAML.load_file(sdf+"cdk.yaml").each_with_index do |calculation,i|
          $logger.error "Descriptor calculation failed for compound #{compounds[i].uri}." if calculation.empty?
          descriptors.each do |descriptor|
            fingerprint[compounds[i]] = calculation
          end
        end
        FileUtils.rm sdf+"cdk.yaml"
        fingerprint
      end

      def self.joelib compounds, descriptors
        # use java system call (rjb blocks within tasks)
        # use Tempfiles to avoid "Argument list too long" error 
        sdf = sdf_3d compounds
        `java -classpath #{JOELIB_JAR}:#{JMOL_JAR}:#{LOG4J_JAR}:#{JAVA_DIR}  JoelibDescriptors  #{sdf} #{descriptors.join(' ')}`
        fingerprint = {}
        YAML.load_file(sdf+"joelib.yaml").each_with_index do |calculation,i|
          $logger.error "Descriptor calculation failed for compound #{compounds[i].uri}." if calculation.empty?
          descriptors.each do |descriptor|
            fingerprint[compounds[i]] = calculation
          end
        end
        FileUtils.rm sdf+"joelib.yaml"
        fingerprint
      end

      def self.lookup compounds, features, dataset
        fingerprint = []
        compounds.each do |compound|
          fingerprint << []
          features.each do |feature|
          end
        end
      end

      def self.sdf_3d compounds
        obconversion = OpenBabel::OBConversion.new
        obmol = OpenBabel::OBMol.new
        obconversion.set_in_format 'inchi' 
        obconversion.set_out_format 'sdf'
        digest = Digest::MD5.hexdigest compounds.inspect
        sdf_file = "/tmp/#{digest}.sdf"
        unless File.exists? sdf_file # do not recreate existing 3d sdfs
          sdf = File.open sdf_file,"w+"
          # create 3d sdf file (faster in Openbabel than in CDK)
          compounds.each do |compound|
            obconversion.read_string obmol, compound.inchi
            sdf_2d = obconversion.write_string(obmol)  
            OpenBabel::OBOp.find_type("Gen3D").do(obmol) 
            sdf_3d = obconversion.write_string(obmol)  
            if sdf_3d.match(/.nan/)
              warning = "3D generation failed for compound #{compound.uri}, trying to calculate descriptors from 2D structure."
              $logger.warn warning
              # TODO
              #@feature_dataset[RDF::OT.Warnings] ? @feature_dataset[RDF::OT.Warnings] << warning : @feature_dataset[RDF::OT.Warnings] = warning
              sdf.puts sdf_2d
            else
              sdf.puts sdf_3d
            end
          end
          sdf.close
        end
        sdf_file
      end

      def self.fix_value val
        val = val.first if val.is_a? Array and val.size == 1
        if val.numeric?
          val = Float(val)
          val = nil if val.nan? or val.infinite?
        else
          val = nil if val == "NaN"
        end
        val
      end
      private_class_method :sdf_3d, :fix_value
    end
  end
end
