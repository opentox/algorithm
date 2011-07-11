@@feature_generation_default = File.join(CONFIG[:services]["opentox-algorithm"],"fminer","bbrc")

# Get RDF/XML representation of the lazar algorithm
# @return [application/rdf+xml] OWL-DL representation of the lazar algorithm
get '/lazar/?' do
  algorithm = OpenTox::Algorithm::Generic.new(url_for('/lazar',:full))
  algorithm.metadata = {
    DC.title => 'lazar',
    DC.creator => "helma@in-silico.ch, andreas@maunz.de",
    DC.contributor => "vorgrimmlerdavid@gmx.de",
    OT.parameters => [
      { DC.description => "Dataset URI with the dependent variable", OT.paramScope => "mandatory", DC.title => "dataset_uri" },
      { DC.description => "Feature URI for dependent variable. Optional for datasets with only a single feature.", OT.paramScope => "optional", DC.title => "prediction_feature" },
      { DC.description => "URI of feature genration service. Default: #{@@feature_generation_default}", OT.paramScope => "optional", DC.title => "feature_generation_uri" },
      { DC.description => "URI of feature dataset. If this parameter is set no feature generation algorithm will be called", OT.paramScope => "optional", DC.title => "feature_dataset_uri" },
      { DC.description => "Further parameters for the feaature generation service", OT.paramScope => "optional" }
    ]
  }
  case request.env['HTTP_ACCEPT']
  when /text\/html/
    content_type "text/html"
    OpenTox.text_to_html algorithm.to_yaml
  when /application\/x-yaml/
    content_type "application/x-yaml"
    algorithm.to_yaml
  else
    response['Content-Type'] = 'application/rdf+xml'  
    algorithm.to_rdfxml
  end
end

# Create a lazar prediction model
# @param [String] dataset_uri Training dataset URI
# @param [optional,String] prediction_feature URI of the feature to be predicted
# @param [optional,String] feature_generation_uri URI of the feature generation algorithm 
# @param [optional,String] - further parameters for the feature generation service 
# @return [text/uri-list] Task URI 
post '/lazar/?' do 

  LOGGER.debug "building lazar model with params: "+params.inspect
  params[:subjectid] = @subjectid
  raise OpenTox::NotFoundError.new "No dataset_uri parameter." unless params[:dataset_uri]
	dataset_uri = params[:dataset_uri]

  task = OpenTox::Task.create("Create lazar model",url_for('/lazar',:full)) do |task|

    raise OpenTox::NotFoundError.new "Dataset #{dataset_uri} not found." unless training_activities = OpenTox::Dataset.new(dataset_uri)
    training_activities.load_all(@subjectid)

    prediction_feature = OpenTox::Feature.find(params[:prediction_feature],@subjectid)
    unless params[:prediction_feature] # try to read prediction_feature from dataset
    raise OpenTox::NotFoundError.new "#{training_activities.features.size} features in dataset #{dataset_uri}. Please provide a  prediction_feature parameter." unless training_activities.features.size == 1
      prediction_feature = OpenTox::Feature.find(training_activities.features.keys.first,@subjectid)
      params[:prediction_feature] = prediction_feature.uri # pass to feature mining service
    end
    
    feature_generation_uri = @@feature_generation_default unless feature_generation_uri = params[:feature_generation_uri]

    raise OpenTox::NotFoundError.new "No feature #{prediction_feature.uri} in dataset #{params[:dataset_uri]}. (features: "+
      training_activities.features.inspect+")" unless training_activities.features and training_activities.features.include?(prediction_feature.uri)

		lazar = OpenTox::Model::Lazar.new
    lazar.min_sim = params[:min_sim] if params[:min_sim] 


    if prediction_feature.feature_type == "classification"
      @training_classes = training_activities.accept_values(prediction_feature.uri).sort
      @training_classes.each_with_index { |c,i|
        lazar.value_map[i+1] = c # don't use '0': we must take the weighted mean later.
        params[:value_map] = lazar.value_map
      }
    elsif  prediction_feature.feature_type == "regression"
      lazar.prediction_algorithm = "Neighbors.local_svm_regression" 
    end
    task.progress 10

		if params[:feature_dataset_uri]
      feature_dataset_uri = params[:feature_dataset_uri]
      training_features = OpenTox::Dataset.new(feature_dataset_uri)
      case training_features.feature_type(@subjectid)
      when "classification"
        lazar.similarity_algorithm = "Similarity.tanimoto"
      when "regression"
        lazar.similarity_algorithm = "Similarity.euclid"
      end
    else # create features
      params[:feature_generation_uri] = feature_generation_uri
      if feature_generation_uri.match(/fminer/)
        lazar.feature_calculation_algorithm = "Substructure.match"
      else
        raise OpenTox::NotFoundError.new "External feature generation services not yet supported"
      end
      params[:subjectid] = @subjectid
      prediction_feature = OpenTox::Feature.find params[:prediction_feature], @subjectid
      if prediction_feature.feature_type == "regression" && feature_generation_uri.match(/fminer/) 
        params[:feature_type] = "paths"
      end
      feature_dataset_uri = OpenTox::Algorithm::Generic.new(feature_generation_uri).run(params, OpenTox::SubTask.new(task,10,70)).to_s
      training_features = OpenTox::Dataset.new(feature_dataset_uri)
    end

    training_features.load_all(@subjectid)
		raise OpenTox::NotFoundError.new "Dataset #{feature_dataset_uri} not found." if training_features.nil?

    # sorted features for index lookups

    lazar.features = training_features.features.sort if prediction_feature.feature_type == "regression" and lazar.feature_calculation_algorithm != "Substructure.match"

    training_features.data_entries.each do |compound,entry|
      lazar.fingerprints[compound] = [] unless lazar.fingerprints[compound]
      entry.keys.each do |feature|
        if lazar.feature_calculation_algorithm == "Substructure.match"
          if training_features.features[feature]
            smarts = training_features.features[feature][OT.smarts]
            lazar.fingerprints[compound] << smarts
            unless lazar.features.include? smarts
              lazar.features << smarts
              lazar.p_values[smarts] = training_features.features[feature][OT.pValue]
              lazar.effects[smarts] = training_features.features[feature][OT.effect]
            end
          end
        else
          case training_features.feature_type(@subjectid)
          when "classification"
            # fingerprints are sets
            if entry[feature].flatten.size == 1
              lazar.fingerprints[compound] << feature if entry[feature].flatten.first.to_s.match(TRUE_REGEXP)
              lazar.features << feature unless lazar.features.include? feature
            else
              LOGGER.warn "More than one entry (#{entry[feature].inspect}) for compound #{compound}, feature #{feature}"
            end
          when "regression"
            # fingerprints are arrays
            if entry[feature].flatten.size == 1
              lazar.fingerprints[compound][lazar.features.index(feature)] = entry[feature].flatten.first
            else
              LOGGER.warn "More than one entry (#{entry[feature].inspect}) for compound #{compound}, feature #{feature}"
            end
          end
        end
      end
    end
    task.progress 80

    # AM: allow prediction_algorithm override by user for classification AND regression
    lazar.prediction_algorithm = "Neighbors.#{params[:prediction_algorithm]}" unless params[:prediction_algorithm].nil?
    lazar.prop_kernel = true if (params[:local_svm_kernel] == "propositionalized" || params[:prediction_algorithm] == "local_mlr_prop")
    lazar.balanced = true if params[:balanced] == "true"

    training_activities.data_entries.each do |compound,entry| 
			lazar.activities[compound] = [] unless lazar.activities[compound]
      unless entry[prediction_feature.uri].empty?
        entry[prediction_feature.uri].each do |value|
          if prediction_feature.feature_type == "classification"
            lazar.activities[compound] << lazar.value_map.invert[value] # insert mapped values, not originals
          elsif prediction_feature.feature_type == "regression"
            #never use halt in tasks, do not raise exception when, print warning instead
            if value.to_f==0
              LOGGER.warn "0 values not allowed in training dataset. log10 is calculated internally. skipping compound"
            else
              lazar.activities[compound] << value.to_f
            end
          end
        end
      end
    end
    task.progress 90

    lazar.metadata[DC.title] = "lazar model for #{URI.decode(File.basename(prediction_feature.uri))}"
    lazar.metadata[OT.dependentVariables] = prediction_feature.uri
    lazar.metadata[OT.trainingDataset] = dataset_uri
		lazar.metadata[OT.featureDataset] = feature_dataset_uri
    case training_activities.feature_type(@subjectid)
    when "classification"
      lazar.metadata[RDF.type] = [OT.Model, OTA.ClassificationLazySingleTarget]
    when "regression"
      lazar.metadata[RDF.type] = [OT.Model, OTA.RegressionLazySingleTarget]
    end

    lazar.metadata[OT.parameters] = [
      {DC.title => "dataset_uri", OT.paramValue => dataset_uri},
      {DC.title => "prediction_feature", OT.paramValue => prediction_feature.uri},
      {DC.title => "feature_generation_uri", OT.paramValue => feature_generation_uri}
    ]
		
		model_uri = lazar.save(@subjectid)
		LOGGER.info model_uri + " created #{Time.now}"
    model_uri
	end
  response['Content-Type'] = 'text/uri-list' 
  raise OpenTox::ServiceUnavailableError.newtask.uri+"\n" if task.status == "Cancelled"
  halt 202,task.uri
end

