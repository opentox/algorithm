=begin
* Name: lazar.rb
* Description: Lazar model representation
* Author: Andreas Maunz <andreas@maunz.de>, Christoph Helma
* Date: 10/2012
=end

module OpenTox

  module Model

    class Lazar 
      include OpenTox

      attr_accessor :prediction_dataset

      # Check parameters for plausibility
      # Prepare lazar object (includes graph mining)
      # @param[Array] lazar parameters as strings
      # @param[Hash] REST parameters, as input by user
      def self.create params
        
        lazar = OpenTox::Model::Lazar.new(File.join($model[:uri],SecureRandom.uuid), @subjectid)

        training_dataset = OpenTox::Dataset.new(params[:dataset_uri], @subjectid) 
        lazar.parameters << {RDF::DC.title => "training_dataset_uri", RDF::OT.paramValue => training_dataset.uri}

        if params[:prediction_feature]
          resource_not_found_error "No feature '#{params[:prediction_feature]}' in dataset '#{params[:dataset_uri]}'" unless training_dataset.find_feature_uri( params[:prediction_feature] )
        else # try to read prediction_feature from dataset
          resource_not_found_error "Please provide a prediction_feature parameter" unless training_dataset.features.size == 1
          params[:prediction_feature] = training_dataset.features.first.uri
        end
        lazar[RDF::OT.trainingDataset] = training_dataset.uri
        prediction_feature = OpenTox::Feature.new(params[:prediction_feature], @subjectid) 
        predicted_variable = OpenTox::Feature.find_or_create({RDF::DC.title => "#{prediction_feature.title} prediction", RDF.type => [RDF::OT.Feature, prediction_feature[RDF.type]]}, @subjectid)
        lazar[RDF::DC.title] = prediction_feature.title 
        lazar.parameters << {RDF::DC.title => "prediction_feature_uri", RDF::OT.paramValue => prediction_feature.uri}
        lazar[RDF::OT.dependentVariables] = prediction_feature.uri

        bad_request_error "Unknown prediction_algorithm #{params[:prediction_algorithm]}" if params[:prediction_algorithm] and !OpenTox::Algorithm::Neighbors.respond_to?(params[:prediction_algorithm])
        lazar.parameters << {RDF::DC.title => "prediction_algorithm", RDF::OT.paramValue => params[:prediction_algorithm]} if params[:prediction_algorithm]

        confidence_feature = OpenTox::Feature.find_or_create({RDF::DC.title => "predicted_confidence", RDF.type => [RDF::OT.Feature, RDF::OT.NumericFeature]}, @subjectid)
        lazar[RDF::OT.predictedVariables] = [ predicted_variable.uri, confidence_feature.uri ]
        case prediction_feature.feature_type
        when "classification"
          lazar.parameters << {RDF::DC.title => "prediction_algorithm", RDF::OT.paramValue => "weighted_majority_vote"} unless lazar.parameter_value "prediction_algorithm"
          lazar[RDF.type] = [RDF::OT.Model, RDF::OTA.ClassificationLazySingleTarget] 
        when "regression"
          lazar.parameters << {RDF::DC.title => "prediction_algorithm", RDF::OT.paramValue => "local_svm_regression"} unless lazar.parameter_value "prediction_algorithm"
          lazar[RDF.type] = [RDF::OT.Model, RDF::OTA.RegressionLazySingleTarget] 
        end
        lazar.parameter_value("prediction_algorithm") =~ /majority_vote/ ? lazar.parameters << {RDF::DC.title => "propositionalized", RDF::OT.paramValue => false} :  lazar.parameters << {RDF::DC.title => "propositionalized", RDF::OT.paramValue => true}

        lazar.parameters << {RDF::DC.title => "min_sim", RDF::OT.paramValue => params[:min_sim].to_f} if params[:min_sim] and params[:min_sim].numeric?
        lazar.parameters << {RDF::DC.title => "feature_generation_uri", RDF::OT.paramValue => params[:feature_generation_uri]}
        #lazar.parameters["nr_hits"] =  params[:nr_hits]
        case params["feature_generation_uri"]
        when /fminer/
          if (params[:nr_hits] == "true")
            lazar.parameters << {RDF::DC.title => "feature_calculation_algorithm", RDF::OT.paramValue => "smarts_count"}
          else
            lazar.parameters << {RDF::DC.title => "feature_calculation_algorithm", RDF::OT.paramValue => "smarts_match"}
          end
          lazar.parameters << {RDF::DC.title => "similarity_algorithm", RDF::OT.paramValue => "tanimoto"}
          lazar.parameters << {RDF::DC.title => "min_sim", RDF::OT.paramValue => 0.3} unless lazar.parameter_value("min_sim")
        when /descriptor/
          method = params["feature_generation_uri"].split(%r{/}).last.chomp
          lazar.parameters << {RDF::DC.title => "feature_calculation_algorithm", RDF::OT.paramValue => method}
          lazar.parameters << {RDF::DC.title => "similarity_algorithm", RDF::OT.paramValue => "cosine"}
          lazar.parameters << {RDF::DC.title => "min_sim", RDF::OT.paramValue => 0.7} unless lazar.parameter_value("min_sim")
        end

        bad_request_error "Parameter min_train_performance is not numeric." if params[:min_train_performance] and !params[:min_train_performance].numeric?
        lazar.parameters << {RDF::DC.title => "min_train_performance", RDF::OT.paramValue => params[:min_train_performance].to_f} if params[:min_train_performance] and params[:min_train_performance].numeric?
        lazar.parameters << {RDF::DC.title => "min_train_performance", RDF::OT.paramValue => 0.1} unless lazar.parameter_value("min_train_performance")

        if params[:feature_dataset_uri]
          bad_request_error "Feature dataset #{params[:feature_dataset_uri]} does not exist." unless URI.accessible? params[:feature_dataset_uri], @subjectid
          lazar.parameters << {RDF::DC.title => "feature_dataset_uri", RDF::OT.paramValue => params[:feature_dataset_uri]}
          lazar[RDF::OT.featureDataset] = params["feature_dataset_uri"]
        else
          # run feature generation algorithm
          feature_dataset_uri = OpenTox::Algorithm::Generic.new(params[:feature_generation_uri], @subjectid).run(params)
          lazar.parameters << {RDF::DC.title => "feature_dataset_uri", RDF::OT.paramValue => feature_dataset_uri}
          lazar[RDF::OT.featureDataset] = feature_dataset_uri
        end
        lazar.put
        lazar.uri
      end

      def predict(params)
        @prediction_dataset = OpenTox::Dataset.new(nil, @subjectid) 
        # set instance variables and prediction dataset parameters from parameters
        params.each {|k,v|
          self.class.class_eval { attr_accessor k.to_sym }
          instance_variable_set "@#{k}", v
          @prediction_dataset.parameters << {RDF::DC.title => k, RDF::OT.paramValue => v}
        }
        #["training_compounds", "fingerprints", "training_activities", "training_fingerprints", "query_fingerprint", "neighbors"].each {|k|
        ["training_compounds", "training_activities", "training_fingerprints", "query_fingerprint", "neighbors"].each {|k|
          self.class.class_eval { attr_accessor k.to_sym }
          instance_variable_set("@#{k}", [])
        }

        @prediction_feature = OpenTox::Feature.new @prediction_feature_uri, @subjectid
        @predicted_variable = OpenTox::Feature.new @predicted_variable_uri, @subjectid
        @predicted_confidence = OpenTox::Feature.new @predicted_confidence_uri, @subjectid
        @prediction_dataset.metadata = {
          RDF::DC.title => "Lazar prediction for #{@prediction_feature.title}",
          RDF::DC.creator => @model_uri,
          RDF::OT.hasSource => @model_uri,
          RDF::OT.dependentVariables => @prediction_feature_uri,
          RDF::OT.predictedVariables => [@predicted_variable_uri,@predicted_confidence_uri]
        }

        @training_dataset = OpenTox::Dataset.new(@training_dataset_uri,@subjectid)

        @feature_dataset = OpenTox::Dataset.new(@feature_dataset_uri, @subjectid)
        bad_request_error "No features found in feature dataset #{@feature_dataset.uri}." if @feature_dataset.features.empty?

        @similarity_feature = OpenTox::Feature.find_or_create({RDF::DC.title => "#{@similarity_algorithm.capitalize} similarity", RDF.type => [RDF::OT.Feature, RDF::OT.NumericFeature]}, @subjectid)
        
        @prediction_dataset.features = [ @predicted_variable, @predicted_confidence, @prediction_feature, @similarity_feature ]

        prediction_feature_pos = @training_dataset.features.collect{|f| f.uri}.index @prediction_feature.uri

        if @dataset_uri
          compounds = OpenTox::Dataset.new(@dataset_uri, @subjectid).compounds
        else
          compounds = [ OpenTox::Compound.new(@compound_uri, @subjectid) ]
        end

        @training_fingerprints = @feature_dataset.data_entries
        @training_compounds = @training_dataset.compounds

        query_fingerprints = OpenTox::Algorithm::Descriptor.send( @feature_calculation_algorithm, compounds, @feature_dataset.features.collect{ |f| f[RDF::DC.title] } )#.collect{|row| row.collect{|val| val ? val.to_f : 0.0 } }
        
        compounds.each do |compound|
            
          database_activities = @training_dataset.values(compound,@prediction_feature)
          if database_activities and !database_activities.empty?
            database_activities.each do |database_activity|
              @prediction_dataset.add_data_entry compound, @prediction_feature, database_activity
            end
            next
          else
            # AM: transform to cosine space
            @min_sim = (@min_sim.to_f*2.0-1.0).to_s if @similarity_algorithm =~ /cosine/
            @training_activities = @training_dataset.data_entries.collect{|entry|
              act = entry[prediction_feature_pos]
              @prediction_feature.feature_type=="classification" ? @prediction_feature.value_map.invert[act] : act
            }

            @query_fingerprint = @feature_dataset.features.collect { |f| 
              val = query_fingerprints[compound][f.title]
              bad_request_error "Can not parse value '#{val}' to numeric" if val and !val.numeric?
              val ? val.to_f : 0.0
            } # query structure

            mtf = OpenTox::Algorithm::Transform::ModelTransformer.new(self)
            mtf.transform
            
            prediction = OpenTox::Algorithm::Neighbors.send(@prediction_algorithm, 
                { :props => mtf.props,
                  :activities => mtf.activities,
                  :sims => mtf.sims,
                  :value_map => @prediction_feature.feature_type=="classification" ?  @prediction_feature.value_map : nil,
                  :min_train_performance => @min_train_performance
                  } )
           
            predicted_value = prediction[:prediction]#.to_f
            confidence_value = prediction[:confidence]#.to_f

            # AM: transform to original space
            confidence_value = ((confidence_value+1.0)/2.0).abs if @similarity_algorithm =~ /cosine/
            predicted_value = @prediction_feature.value_map[prediction[:prediction].to_i] if @prediction_feature.feature_type == "classification"
            
          end

          @prediction_dataset.add_data_entry compound, @predicted_variable, predicted_value
          @prediction_dataset.add_data_entry compound, @predicted_confidence, confidence_value
        
          if @compound_uri # add neighbors only for compound predictions
            @neighbors.each do |neighbor|
              puts "Neighbor"
              puts neighbor.inspect
              n =  neighbor[:compound]
              @prediction_feature.feature_type == "classification" ? a = @prediction_feature.value_map[neighbor[:activity]] : a = neighbor[:activity]
              @prediction_dataset.add_data_entry n, @prediction_feature, a
              @prediction_dataset.add_data_entry n, @similarity_feature, neighbor[:similarity]
              #@prediction_dataset << [ n, @prediction_feature.value_map[neighbor[:activity]], nil, nil, neighbor[:similarity] ]
            end
          end

        end # iteration over compounds
        puts prediction_dataset.to_turtle
        @prediction_dataset.put
        @prediction_dataset

      end

    end

  end

end

