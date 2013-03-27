=begin
* Name: lazar.rb
* Description: Lazar model representation
* Author: Andreas Maunz <andreas@maunz.de>, Christoph Helma
* Date: 10/2012
=end

module OpenTox

  class LazarPrediction < Model

    attr_accessor :prediction_dataset

    def initialize(params)
      @prediction_dataset = OpenTox::Dataset.new(nil, @subjectid) 
      # set instance variables and prediction dataset parameters from parameters
      params.each {|k,v|
        self.class.class_eval { attr_accessor k.to_sym }
        instance_variable_set "@#{k}", v
        puts "#{k} => #{v}"
        @prediction_dataset.parameters << {RDF::DC.title => k, RDF::OT.paramValue => v}
      }
      ["cmpds", "fps", "acts", "n_prop", "q_prop", "neighbors"].each {|k|
        self.class.class_eval { attr_accessor k.to_sym }
        instance_variable_set("@#{k}", [])
      }

      puts "Loading #{@prediction_feature_uri}"
      @prediction_feature = OpenTox::Feature.new(@prediction_feature_uri,@subjectid)
      @predicted_variable = OpenTox::Feature.new @predicted_variable_uri, @subjectid
      @predicted_confidence = OpenTox::Feature.new @predicted_confidence_uri, @subjectid
      puts @predicted_variable.inspect
      puts @predicted_confidence.inspect
      puts "Setting metadata"
      #@prediction_dataset.metadata = {
      @prediction_dataset.metadata = {
        RDF::DC.title => "Lazar prediction for #{@prediction_feature.title}",
        RDF::DC.creator => @model_uri,
        RDF::OT.hasSource => @model_uri,
        RDF::OT.dependentVariables => @prediction_feature_uri,
        RDF::OT.predictedVariables => [@predicted_variable_uri,@predicted_confidence_uri]
      }

      puts "Loading #{@training_dataset_uri}"
      @training_dataset = OpenTox::Dataset.new(@training_dataset_uri,@subjectid)

      puts "Loading #{@feature_dataset_uri}"
      @feature_dataset = OpenTox::Dataset.new(@feature_dataset_uri, @subjectid)
      bad_request_error "No features found in feature dataset #{@feature_dataset.uri}." if @feature_dataset.features.empty?

      @similarity_feature = OpenTox::Feature.find_or_create({RDF::DC.title => "#{@similarity_algorithm.capitalize} similarity", RDF.type => [RDF::OT.Feature, RDF::OT.NumericFeature]}, @subjectid)
      
      @prediction_dataset.features = [ @predicted_variable, @predicted_confidence, @prediction_feature, @similarity_feature ]

      prediction_feature_pos = @training_dataset.features.collect{|f| f.uri}.index @prediction_feature.uri

      if @dataset_uri
        puts "Loading #{@dataset_uri}"
        compounds = OpenTox::Dataset.new(@dataset_uri,@subjectid).compounds
      else
        compounds = [ OpenTox::Compound.new(@compound_uri,@subjectid) ]
      end
      compounds.each do |compound|
          
        puts compound.smiles
        database_activity = @training_dataset.database_activity(params)
        if database_activity
          @prediction_dataset.add_data_entry compound, @prediction_feature, database_activity
          next
        else
          #pc_type = @feature_dataset.parameters["pc_type"]
          #@model.pc_type = pc_type unless pc_type.nil?
          #lib = @feature_dataset.parameters["lib"]
          #@model.lib = lib unless lib.nil?

          # AM: transform to cosine space
          @min_sim = (@min_sim.to_f*2.0-1.0).to_s if @similarity_algorithm =~ /cosine/

          compound_params = { 
            :compound => compound, 
            :feature_dataset => @feature_dataset,
            # TODO: fix in algorithm/lib/algorithm/feature_values.rb
            #:pc_type => @model.pc_type,
            #:lib => @model.lib
          }
          compound_fingerprints = OpenTox::Algorithm::FeatureValues.send( @feature_calculation_algorithm, compound_params, @subjectid )
          @training_dataset.compounds.each_with_index { |cmpd, idx|
            act = @training_dataset.data_entries[idx][prediction_feature_pos]
            @acts << (@prediction_feature.feature_type=="classification" ? @prediction_feature.value_map.invert[act] : nil)
            @n_prop << @feature_dataset.data_entries[idx]#.collect.to_a
            @cmpds << cmpd.uri
          }

          @q_prop = @feature_dataset.features.collect { |f| 
            val = compound_fingerprints[f.title]
            bad_request_error "Can not parse value '#{val}' to numeric" if val and !val.numeric?
            val ? val.to_f : 0.0
          } # query structure

          mtf = OpenTox::Algorithm::Transform::ModelTransformer.new(self)
          mtf.transform
          
          prediction = OpenTox::Algorithm::Neighbors.send(@prediction_algorithm, 
              { :props => mtf.props,
                :acts => mtf.acts,
                :sims => mtf.sims,
                :value_map => @prediction_feature.feature_type=="classification" ?  @prediction_feature.value_map : nil,
                :min_train_performance => @min_train_performance
                } )
         
          puts prediction.inspect
          predicted_value = prediction[:prediction].to_f
          confidence_value = prediction[:confidence].to_f

          # AM: transform to original space
          confidence_value = ((confidence_value+1.0)/2.0).abs if @similarity_algorithm =~ /cosine/
          predicted_value = @prediction_feature.value_map[prediction[:prediction].to_i] if @prediction_feature.feature_type == "classification"
          
        end

        @prediction_dataset.add_data_entry compound, predicted_variable, predicted_value
        @prediction_dataset.add_data_entry compound, predicted_confidence, confidence_value
      
        if @compound_uri # add neighbors only for compound predictions
          @neighbors.each do |neighbor|
            n =  OpenTox::Compound.new(neighbor[:compound])
            @prediction_dataset.add_data_entry n, @prediction_feature, @prediction_feature.value_map[neighbor[:activity]]
            @prediction_dataset.add_data_entry n, @similarity_feature, neighbor[:similarity]
            #@prediction_dataset << [ n, @prediction_feature.value_map[neighbor[:activity]], nil, nil, neighbor[:similarity] ]
          end
        end

      end # iteration over compounds
      @prediction_dataset.put

    end

  end

  class Model

    # Check parameters for plausibility
    # Prepare lazar object (includes graph mining)
    # @param[Array] lazar parameters as strings
    # @param[Hash] REST parameters, as input by user
    def create_model(params)

      training_dataset = OpenTox::Dataset.new(params[:dataset_uri], @subjectid) 
      @parameters << {RDF::DC.title => "training_dataset_uri", RDF::OT.paramValue => training_dataset.uri}

      # TODO: This is inconsistent, it would be better to have prediction_feature_uri in the API
      if params[:prediction_feature]
        resource_not_found_error "No feature '#{params[:prediction_feature]}' in dataset '#{params[:dataset_uri]}'" unless training_dataset.find_feature_uri( params[:prediction_feature] )
      else # try to read prediction_feature from dataset
        resource_not_found_error "Please provide a prediction_feature parameter" unless training_dataset.features.size == 1
        params[:prediction_feature] = training_dataset.features.first.uri
      end
      self[RDF::OT.trainingDataset] = training_dataset.uri
      prediction_feature = OpenTox::Feature.new(params[:prediction_feature], @subjectid) 
      predicted_variable = OpenTox::Feature.find_or_create({RDF::DC.title => "#{prediction_feature.title} prediction", RDF.type => [RDF::OT.Feature, prediction_feature[RDF.type]]}, @subjectid)
      self[RDF::DC.title] = prediction_feature.title 
      @parameters << {RDF::DC.title => "prediction_feature_uri", RDF::OT.paramValue => prediction_feature.uri}
      self[RDF::OT.dependentVariables] = prediction_feature.uri

      bad_request_error "Unknown prediction_algorithm #{params[:prediction_algorithm]}" if params[:prediction_algorithm] and !OpenTox::Algorithm::Neighbors.respond_to?(params[:prediction_algorithm])
      @parameters << {RDF::DC.title => "prediction_algorithm", RDF::OT.paramValue => params[:prediction_algorithm]} if params[:prediction_algorithm]

      confidence_feature = OpenTox::Feature.find_or_create({RDF::DC.title => "predicted_confidence", RDF.type => [RDF::OT.Feature, RDF::OT.NumericFeature]}, @subjectid)
      self[RDF::OT.predictedVariables] = [ predicted_variable.uri, confidence_feature.uri ]
      case prediction_feature.feature_type
      when "classification"
        @parameters << {RDF::DC.title => "prediction_algorithm", RDF::OT.paramValue => "weighted_majority_vote"} unless parameter_value "prediction_algorithm"
        self[RDF.type] = [RDF::OT.Model, RDF::OTA.ClassificationLazySingleTarget] 
      when "regression"
        @parameters << {RDF::DC.title => "prediction_algorithm", RDF::OT.paramValue => "local_svm_regression"} unless parameter_value "prediction_algorithm"
        self[RDF.type] = [RDF::OT.Model, RDF::OTA.RegressionLazySingleTarget] 
      end
      parameter_value("prediction_algorithm") =~ /majority_vote/ ? @parameters << {RDF::DC.title => "propositionalized", RDF::OT.paramValue => false} :  @parameters << {RDF::DC.title => "propositionalized", RDF::OT.paramValue => true}

      @parameters << {RDF::DC.title => "min_sim", RDF::OT.paramValue => params[:min_sim].to_f} if params[:min_sim] and params[:min_sim].numeric?
      @parameters << {RDF::DC.title => "feature_generation_uri", RDF::OT.paramValue => params[:feature_generation_uri]}
      #@parameters["nr_hits"] =  params[:nr_hits]
      case params["feature_generation_uri"]
      when /fminer/
        if (params[:nr_hits] == "true")
          @parameters << {RDF::DC.title => "feature_calculation_algorithm", RDF::OT.paramValue => "match_hits"}
        else
          @parameters << {RDF::DC.title => "feature_calculation_algorithm", RDF::OT.paramValue => "match"}
        end
        @parameters << {RDF::DC.title => "similarity_algorithm", RDF::OT.paramValue => "tanimoto"}
        @parameters << {RDF::DC.title => "min_sim", RDF::OT.paramValue => 0.3} unless parameter_value("min_sim")
      when /descriptors/
        @parameters << {RDF::DC.title => "feature_calculation_algorithm", RDF::OT.paramValue => "lookup"}
        @parameters << {RDF::DC.title => "similarity_algorithm", RDF::OT.paramValue => "cosine"}
        @parameters << {RDF::DC.title => "min_sim", RDF::OT.paramValue => 0.7} unless parameter_value("min_sim")
      end

      #TODO: check if these parameters are necessary with new version
      #set_parameter("pc_type", params[:pc_type] if params[:pc_type]
      #set_parameter("lib", params[:lib] if params[:lib]

      bad_request_error "Parameter min_train_performance is not numeric." if params[:min_train_performance] and !params[:min_train_performance].numeric?
      @parameters << {RDF::DC.title => "min_train_performance", RDF::OT.paramValue => params[:min_train_performance].to_f} if params[:min_train_performance] and params[:min_train_performance].numeric?
      @parameters << {RDF::DC.title => "min_train_performance", RDF::OT.paramValue => 0.1} unless parameter_value("min_train_performance")

      if params[:feature_dataset_uri]
        bad_request_error "Feature dataset #{params[:feature_dataset_uri]} does not exist." unless URI.accessible? params[:feature_dataset_uri]
        @parameters << {RDF::DC.title => "feature_dataset_uri", RDF::OT.paramValue => params[:feature_dataset_uri]}
        self[RDF::OT.featureDataset] = params["feature_dataset_uri"]
      else
        # run feature generation algorithm
        feature_dataset_uri = OpenTox::Algorithm.new(params[:feature_generation_uri]).run(params)
        @parameters << {RDF::DC.title => "feature_dataset_uri", RDF::OT.paramValue => feature_dataset_uri}
        self[RDF::OT.featureDataset] = feature_dataset_uri
      end

    end

  end

end

