require 'digest/md5'
ENV["JAVA_HOME"] ||= "/usr/lib/jvm/java-7-openjdk" 
BABEL_3D_CACHE_DIR = File.join(File.dirname(__FILE__),"..",'/babel_3d_cache')
# TODO store 3D structures in mongodb
# TODO store descriptors in mongodb

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

      cdk_desc = YAML.load(`java -classpath #{CDK_JAR}:#{JAVA_DIR}  CdkDescriptorInfo`)
      CDKDESCRIPTORS = Hash[cdk_desc.collect { |d| ["Cdk."+d[:java_class].split('.').last.sub(/Descriptor/,''), d[:description]] }.sort{|a,b| a[0] <=> b[0]}]
      CDKDESCRIPTOR_VALUES = cdk_desc.collect { |d| prefix="Cdk."+d[:java_class].split('.').last.sub(/Descriptor/,''); d[:names].collect{ |name| prefix+"."+name } }.flatten

      # exclude Hashcode (not a physchem property) and GlobalTopologicalChargeIndex (Joelib bug)
      joelibexclude = ["MoleculeHashcode","GlobalTopologicalChargeIndex"]
      # strip Joelib messages from stdout
      JOELIBDESCRIPTORS = Hash[YAML.load(`java -classpath #{JOELIB_JAR}:#{LOG4J_JAR}:#{JAVA_DIR}  JoelibDescriptorInfo | sed '0,/---/d'`).collect do |d|
        name = d[:java_class].sub(/^joelib2.feature.types./,'')
        # impossible to obtain meaningful descriptions from JOELIb, see java/JoelibDescriptors.java
        ["Joelib."+name, "no description available"] unless joelibexclude.include? name
      end.compact.sort{|a,b| a[0] <=> b[0]}] 

      DESCRIPTORS = OBDESCRIPTORS.merge(CDKDESCRIPTORS.merge(JOELIBDESCRIPTORS))
      DESCRIPTOR_VALUES = OBDESCRIPTORS.keys + CDKDESCRIPTOR_VALUES + JOELIBDESCRIPTORS.keys

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
        bad_request_error "Compounds for smarts_match are empty" unless compounds
        bad_request_error "Smarts for smarts_match are empty" unless smarts
        compounds = parse compounds
        obconversion = OpenBabel::OBConversion.new
        obmol = OpenBabel::OBMol.new
        obconversion.set_in_format('inchi')
        smarts_pattern = OpenBabel::OBSmartsPattern.new
        smarts = [smarts] unless smarts.is_a? Array
        fingerprint = Array.new(compounds.size){Array.new(smarts.size,false)}
        compounds.each_with_index do |compound,c|
          obconversion.read_string(obmol,compound.inchi)
          smarts.each_with_index do |smart,s|
            smarts_pattern.init(smart)
            if smarts_pattern.match(obmol)
              count ? value = smarts_pattern.get_map_list.to_a.size : value = 1
            else
              value = 0 
            end
            fingerprint[c][s] = value
          end
        end
        fingerprint
      end

      def self.smarts_count compounds, smarts
        smarts_match compounds,smarts,true
      end

      def self.physchem compounds, descriptors=UNIQUEDESCRIPTORS
        compounds = parse compounds
        dataset = OpenTox::CalculatedDataset.new
        dataset.compounds = compounds
        des = {}
        descriptors.each do |d|
          lib, descriptor = d.split(".",2)
          lib = lib.downcase.to_sym
          des[lib] ||= []
          des[lib] << descriptor
        end
        result = {}
        features = []
        data_entries = Array.new(compounds.size){Array.new(des.size)}
        n = 0
        des.each do |lib,descriptors|
          features += descriptors.collect do |d|
            OpenTox::Feature.find_or_create_by(
              :title => "#{lib}.#{d}",
              :creator => __FILE__
            )
          end
          r = send(lib, compounds, descriptors)
          #p r
          r.each_with_index do |values,i|
            data_entries[i][n] = values
          end
          n += 1
        end
        #dataset.features = features
        #dataset.data_entries = data_entries
        #dataset
        data_entries
      end

      def self.openbabel compounds, descriptors
        compounds = parse compounds
        $logger.debug "compute #{descriptors.size} openbabel descriptors for #{compounds.size} compounds"
        obdescriptors = descriptors.collect{|d| OpenBabel::OBDescriptor.find_type d}
        obmol = OpenBabel::OBMol.new
        obconversion = OpenBabel::OBConversion.new
        obconversion.set_in_format 'inchi'
        fingerprint = Array.new(compounds.size){Array.new(obdescriptors.size)}
        compounds.each_with_index do |compound,c|
          obconversion.read_string obmol, compound.inchi
          obdescriptors.each_with_index do |descriptor,d|
            fingerprint[c][d] = fix_value(descriptor.predict(obmol))
          end
        end
        fingerprint
      end

      def self.cdk compounds, descriptors
        compounds = parse compounds
        $logger.debug "compute #{descriptors.size} cdk descriptors for #{compounds.size} compounds"
        sdf = sdf_3d compounds
        # use java system call (rjb blocks within tasks)
        # use Tempfiles to avoid "Argument list too long" error 
        run_cmd "java -classpath #{CDK_JAR}:#{JAVA_DIR}  CdkDescriptors #{sdf} #{descriptors.join(" ")}"
        fingerprint = {}
        YAML.load_file(sdf+"cdk.yaml").each_with_index do |calculation,i|
          $logger.error "Descriptor calculation failed for compound #{compounds[i].inchi}." if calculation.empty?
          descriptors.each do |descriptor|
            fingerprint[compounds[i]] = calculation
          end
        end
        FileUtils.rm sdf+"cdk.yaml"
        fingerprint
      end

      def self.joelib compounds, descriptors
        compounds = parse compounds
        $logger.debug "compute #{descriptors.size} joelib descriptors for #{compounds.size} compounds"
        # use java system call (rjb blocks within tasks)
        # use Tempfiles to avoid "Argument list too long" error 
        sdf = sdf_3d compounds
        run_cmd "java -classpath #{JOELIB_JAR}:#{JMOL_JAR}:#{LOG4J_JAR}:#{JAVA_DIR}  JoelibDescriptors  #{sdf} #{descriptors.join(' ')}"
        fingerprint = {}
        YAML.load_file(sdf+"joelib.yaml").each_with_index do |calculation,i|
          $logger.error "Descriptor calculation failed for compound #{compounds[i].inchi}." if calculation.empty?
          descriptors.each do |descriptor|
            fingerprint[compounds[i]] = calculation
          end
        end
        FileUtils.rm sdf+"joelib.yaml"
        fingerprint
      end

      def self.lookup compounds, features, dataset
        compounds = parse compounds
        fingerprint = []
        compounds.each do |compound|
          fingerprint << []
          features.each do |feature|
          end
        end
      end

      def self.run_cmd cmd
        cmd = "#{cmd} 2>&1"
        $logger.debug "running external cmd: '#{cmd}'"
        p = IO.popen(cmd) do |io|
          while line = io.gets
            $logger.debug "> #{line.chomp}"
          end
          io.close
          raise "external cmd failed '#{cmd}' (see log file for error msg)" unless $?.to_i == 0
        end
      end

      def self.sdf_3d compounds
        compounds = parse compounds
        obconversion = OpenBabel::OBConversion.new
        obmol = OpenBabel::OBMol.new
        obconversion.set_in_format 'inchi' 
        obconversion.set_out_format 'sdf'

        digest = Digest::MD5.hexdigest compounds.collect{|c| c.inchi}.inspect
        sdf_file = "/tmp/#{digest}.sdf"
        if File.exists? sdf_file # do not recreate existing 3d sdfs
          $logger.debug "re-using cached 3d structures from #{sdf_file}"
        else
          tmp_file = Tempfile.new('sdf')
          # create 3d sdf file (faster in Openbabel than in CDK)
          # MG: moreover, CDK 3d generation is faulty
          # MG: WARNING: Openbabel 3d generation is not deterministic
          # MG: WARNING: Openbabel 3D generation does not work for mixtures
          c = 0
          compounds.each do |compound|
            c += 1
            cmp_file = File.join(BABEL_3D_CACHE_DIR,Digest::MD5.hexdigest(compound.inchi)+".sdf")
            cmp_sdf = nil
            if File.exists? cmp_file
              $logger.debug "read cached 3d structure for compound #{c}/#{compounds.size}"
              cmp_sdf = File.read(cmp_file)
            else
              $logger.debug "compute 3d structure for compound #{c}/#{compounds.size}"
              obconversion.read_string obmol, compound.inchi
              sdf_2d = obconversion.write_string(obmol)  
              error = nil
              if compound.inchi.include?(";") # component includes multiple compounds (; in inchi, . in smiles)
                error = "OpenBabel 3D generation failes for multi-compound #{compound.inchi}, trying to calculate descriptors from 2D structure."
              else
                OpenBabel::OBOp.find_type("Gen3D").do(obmol) 
                sdf_3d = obconversion.write_string(obmol)  
                error = "3D generation failed for compound #{compound.inchi}, trying to calculate descriptors from 2D structure." if sdf_3d.match(/.nan/)
              end
              if error
                $logger.warn error
                # TODO
                # @feature_dataset[RDF::OT.Warnings] ? @feature_dataset[RDF::OT.Warnings] << error : @feature_dataset[RDF::OT.Warnings] = error
                cmp_sdf = sdf_2d
              else
                cmp_sdf = sdf_3d
                File.open(cmp_file,"w") do |f|
                  f.write(cmp_sdf)
                end
              end
            end
            tmp_file.write cmp_sdf
          end
          tmp_file.close
          File.rename(tmp_file, sdf_file)
        end
        sdf_file
      end

      def self.parse compounds
        case compounds.class.to_s
        when "OpenTox::Compound"
          compounds = [compounds]
        when "Array"
          compounds
        when "OpenTox::Dataset"
          compounds = compounds.compounds
        else
          bad_request_error "Cannot calculate descriptors for #{compounds.class} objects."
        end
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
      private_class_method :sdf_3d, :fix_value, :parse, :run_cmd
    end
  end
end
