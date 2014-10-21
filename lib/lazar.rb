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
        
        lazar = OpenTox::Model::Lazar.new(File.join($model[:uri],SecureRandom.uuid))

        training_dataset = OpenTox::Dataset.new(params[:dataset_uri]) 
        lazar.parameters << {RDF::DC.title => "training_dataset_uri", RDF::OT.paramValue => training_dataset.uri}

        if params[:prediction_feature]
          resource_not_found_error "No feature '#{params[:prediction_feature]}' in dataset '#{params[:dataset_uri]}'" unless training_dataset.find_feature_uri( params[:prediction_feature] )
        else # try to read prediction_feature from dataset
          resource_not_found_error "Please provide a prediction_feature parameter" unless training_dataset.features.size == 1
          params[:prediction_feature] = training_dataset.features.first.uri
        end
        lazar[RDF::OT.trainingDataset] = training_dataset.uri
        prediction_feature = OpenTox::Feature.new(params[:prediction_feature]) 
        predicted_variable = OpenTox::Feature.find_or_create({RDF::DC.title => "#{prediction_feature.title} prediction", RDF.type => [RDF::OT.Feature, prediction_feature[RDF.type]]})
        lazar[RDF::DC.title] = prediction_feature.title 
        lazar.parameters << {RDF::DC.title => "prediction_feature_uri", RDF::OT.paramValue => prediction_feature.uri}
        lazar[RDF::OT.dependentVariables] = prediction_feature.uri

        bad_request_error "Unknown prediction_algorithm #{params[:prediction_algorithm]}" if params[:prediction_algorithm] and !OpenTox::Algorithm::Neighbors.respond_to?(params[:prediction_algorithm])
        lazar.parameters << {RDF::DC.title => "prediction_algorithm", RDF::OT.paramValue => params[:prediction_algorithm]} if params[:prediction_algorithm]

        confidence_feature = OpenTox::Feature.find_or_create({RDF::DC.title => "predicted_confidence", RDF.type => [RDF::OT.Feature, RDF::OT.NumericFeature]})
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
        
        if params["feature_generation_uri"]=~/fminer/
          if (params[:nr_hits] == "true")
            lazar.parameters << {RDF::DC.title => "feature_calculation_algorithm", RDF::OT.paramValue => "smarts_count"}
          else
            lazar.parameters << {RDF::DC.title => "feature_calculation_algorithm", RDF::OT.paramValue => "smarts_match"}
          end
          lazar.parameters << {RDF::DC.title => "similarity_algorithm", RDF::OT.paramValue => "tanimoto"}
          lazar.parameters << {RDF::DC.title => "min_sim", RDF::OT.paramValue => 0.3} unless lazar.parameter_value("min_sim")
        elsif params["feature_generation_uri"]=~/descriptor/ or params["feature_generation_uri"]==nil
          if params["feature_generation_uri"]
            method = params["feature_generation_uri"].split(%r{/}).last.chomp
            lazar.parameters << {RDF::DC.title => "feature_calculation_algorithm", RDF::OT.paramValue => method}
          end
          # cosine similartiy is default (e.g. used when no fetature_generation_uri is given and a feature_dataset_uri is provided instead)
          lazar.parameters << {RDF::DC.title => "similarity_algorithm", RDF::OT.paramValue => "cosine"}
          lazar.parameters << {RDF::DC.title => "min_sim", RDF::OT.paramValue => 0.7} unless lazar.parameter_value("min_sim")
        else
          bad_request_error "unnkown feature generation method #{params["feature_generation_uri"]}"
        end

        bad_request_error "Parameter min_train_performance is not numeric." if params[:min_train_performance] and !params[:min_train_performance].numeric?
        lazar.parameters << {RDF::DC.title => "min_train_performance", RDF::OT.paramValue => params[:min_train_performance].to_f} if params[:min_train_performance] and params[:min_train_performance].numeric?
        lazar.parameters << {RDF::DC.title => "min_train_performance", RDF::OT.paramValue => 0.1} unless lazar.parameter_value("min_train_performance")

        if params[:feature_dataset_uri]
          bad_request_error "Feature dataset #{params[:feature_dataset_uri]} does not exist." unless URI.accessible? params[:feature_dataset_uri]
          lazar.parameters << {RDF::DC.title => "feature_dataset_uri", RDF::OT.paramValue => params[:feature_dataset_uri]}
          lazar[RDF::OT.featureDataset] = params["feature_dataset_uri"]
        else
          # run feature generation algorithm
          feature_dataset_uri = OpenTox::Algorithm::Generic.new(params[:feature_generation_uri]).run(params)
          lazar.parameters << {RDF::DC.title => "feature_dataset_uri", RDF::OT.paramValue => feature_dataset_uri}
          lazar[RDF::OT.featureDataset] = feature_dataset_uri
        end
        lazar.put
        lazar.uri
      end

      def predict(params)
        @prediction_dataset = OpenTox::Dataset.new
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

        @prediction_feature = OpenTox::Feature.new @prediction_feature_uri
        @predicted_variable = OpenTox::Feature.new @predicted_variable_uri
        @predicted_confidence = OpenTox::Feature.new @predicted_confidence_uri
        @prediction_dataset.metadata = {
          RDF::DC.title => "Lazar prediction for #{@prediction_feature.title}",
          RDF::DC.creator => @model_uri,
          RDF::OT.hasSource => @model_uri,
          RDF::OT.dependentVariables => @prediction_feature_uri,
          RDF::OT.predictedVariables => [@predicted_variable_uri,@predicted_confidence_uri]
        }

        @training_dataset = OpenTox::Dataset.new(@training_dataset_uri)

        @feature_dataset = OpenTox::Dataset.new(@feature_dataset_uri)
        bad_request_error "No features found in feature dataset #{@feature_dataset.uri}." if @feature_dataset.features.empty?

        @similarity_feature = OpenTox::Feature.find_or_create({RDF::DC.title => "#{@similarity_algorithm.capitalize} similarity", RDF.type => [RDF::OT.Feature, RDF::OT.NumericFeature]})
        
        @prediction_dataset.features = [ @predicted_variable, @predicted_confidence, @prediction_feature, @similarity_feature ]

        prediction_feature_pos = @training_dataset.features.collect{|f| f.uri}.index @prediction_feature.uri

        if @dataset_uri
          compounds = OpenTox::Dataset.new(@dataset_uri).compounds
        else
          compounds = [ OpenTox::Compound.new(@compound_uri) ]
        end

        # @training_fingerprints = @feature_dataset.data_entries
        # select training fingerprints from feature dataset (do NOT use entire feature dataset)
        feature_compound_uris = @feature_dataset.compounds.collect{|c| c.uri}
        @training_fingerprints = []
        @training_dataset.compounds.each do |c|
          idx = feature_compound_uris.index(c.uri)
          bad_request_error "training dataset compound not found in feature dataset" if idx==nil
          @training_fingerprints << @feature_dataset.data_entries[idx][0..-1]
        end
        # fill trailing missing values with nil
        @training_fingerprints = @training_fingerprints.collect do |values|
          values << nil while (values.size < @feature_dataset.features.size)
          values
        end
        @training_compounds = @training_dataset.compounds
        internal_server_error "sth went wrong #{@training_compounds.size} != #{@training_fingerprints.size}" if @training_compounds.size != @training_fingerprints.size

        feature_names = @feature_dataset.features.collect{ |f| f[RDF::DC.title] }
        query_fingerprints = {}
        # first lookup in feature dataset, than apply feature_generation_uri
        compounds.each do |c|
          idx = feature_compound_uris.index(c.uri) # just use first index, features should be equal for duplicates
          if idx!=nil
            fingerprint = {}
            @feature_dataset.features.each do |f|
              fingerprint[f[RDF::DC.title]] = @feature_dataset.data_entry_value(idx,f.uri)
            end
            query_fingerprints[c] = fingerprint
          end
        end
        # if lookup failed, try computing!
        if query_fingerprints.size!=compounds.size
          bad_request_error "no feature_generation_uri provided in model AND cannot lookup all test compounds in existing feature dataset" unless @feature_calculation_algorithm
          query_fingerprints = OpenTox::Algorithm::Descriptor.send( @feature_calculation_algorithm, compounds, feature_names )#.collect{|row| row.collect{|val| val ? val.to_f : 0.0 } }
        end

        # AM: transform to cosine space
        @min_sim = (@min_sim.to_f*2.0-1.0).to_s if @similarity_algorithm =~ /cosine/

        compounds.each_with_index do |compound,c_count|
          $logger.debug "predict compound #{c_count+1}/#{compounds.size} #{compound.uri}"

          database_activities = @training_dataset.values(compound,@prediction_feature)
          if database_activities and !database_activities.empty?
            database_activities.each do |database_activity|
              $logger.debug "do not predict compound, it occurs in dataset with activity #{database_activity}"
              @prediction_dataset << [compound, nil, nil, database_activity, nil]
            end
            next
          elsif @prediction_dataset.compound_indices(compound.uri)
            $logger.debug "compound already predicted (copy old prediction)"
            predicted_value = @prediction_dataset.data_entry_value(@prediction_dataset.compound_indices(compound.uri).first,@predicted_variable.uri)
            confidence_value = @prediction_dataset.data_entry_value(@prediction_dataset.compound_indices(compound.uri).first,@predicted_confidence.uri)
          else
            @training_activities = @training_dataset.data_entries.collect{|entry|
              act = entry[prediction_feature_pos] if entry
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
            $logger.debug "predicted value: #{predicted_value}, confidence: #{confidence_value}"
          end

          @prediction_dataset << [ compound, predicted_value, confidence_value, nil, nil ]

          if @compound_uri # add neighbors only for compound predictions
            @neighbors.each do |neighbor|
              n =  neighbor[:compound]
              @prediction_feature.feature_type == "classification" ? a = @prediction_feature.value_map[neighbor[:activity]] : a = neighbor[:activity]
              @prediction_dataset << [ n, nil, nil, a, neighbor[:similarity] ]
            end
          end

        end # iteration over compounds
        @prediction_dataset.put
        @prediction_dataset

      end

    end

  end

end

