ENV['FMINER_SMARTS'] = 'true'
ENV['FMINER_NO_AROMATIC'] = 'true'
ENV['FMINER_PVALUES'] = 'true'
ENV['FMINER_SILENT'] = 'true'
ENV['FMINER_NR_HITS'] = 'true'

@@bbrc = Bbrc::Bbrc.new
@@last = Last::Last.new


def calc_metadata(smarts, ids, counts, fminer_instance, feature_dataset_uri, value_map, params, p_value=nil)
  # Either p_value or fminer instance to calculate it
  return nil if (p_value.nil? and fminer_instance.nil?) 
  return nil if (p_value and fminer_instance) 
  # get activities of feature occurrences; see http://goo.gl/c68t8
  non_zero_ids = ids.collect { |idx| idx if counts[ids.index(idx)] > 0 }
  feat_hash = Hash[*(@@fminer.all_activities.select { |k,v| non_zero_ids.include?(k) }.flatten)] 
  if p_value.nil? and fminer_instance.GetRegression()
    p_value = fminer_instance.KSTest(@@fminer.all_activities.values, feat_hash.values).to_f
    effect = (p_value > 0) ? "activating" : "deactivating"
  else
    p_value = fminer_instance.ChisqTest(@@fminer.all_activities.values, feat_hash.values).to_f unless p_value
    g=Array.new
    value_map.each { |y,act| g[y-1]=Array.new }
    feat_hash.each  { |x,y|   g[y-1].push(x)   }
    max = OpenTox::Algorithm.effect(g, @@fminer.db_class_sizes)
    effect = max+1
  end
  metadata = {
    RDF.type => [OT.Feature, OT.Substructure],
    OT.smarts => smarts,
    OT.pValue => p_value.abs,
    OT.effect => effect,
    OT.parameters => [
      { DC.title => "dataset_uri", OT.paramValue => params[:dataset_uri] },
      { DC.title => "prediction_feature", OT.paramValue => params[:prediction_feature] }
    ]
  }
  metadata[OT.hasSource]=feature_dataset_uri if feature_dataset_uri 
  metadata
end



# Get list of fminer algorithms
#
# @return [text/uri-list] URIs of fminer algorithms
get '/fminer/?' do
  list = [ url_for('/fminer/bbrc', :full), url_for('/fminer/bbrc/sample', :full), url_for('/fminer/last', :full), url_for('/fminer/bbrc/match', :full), url_for('/fminer/last/match', :full) ].join("\n") + "\n"
  case request.env['HTTP_ACCEPT']
  when /text\/html/
    content_type "text/html"
    OpenTox.text_to_html list
  else
    content_type 'text/uri-list'
    list
  end
end



# Get RDF/XML representation of fminer bbrc algorithm
# @return [application/rdf+xml] OWL-DL representation of fminer bbrc algorithm
get "/fminer/bbrc/?" do
  algorithm = OpenTox::Algorithm::Generic.new(url_for('/fminer/bbrc',:full))
  algorithm.metadata = {
    DC.title => 'fminer backbone refinement class representatives',
    DC.creator => "andreas@maunz.de, helma@in-silico.ch",
    DC.contributor => "vorgrimmlerdavid@gmx.de",
#    BO.instanceOf => "http://opentox.org/ontology/ist-algorithms.owl#fminer_bbrc",
    RDF.type => [OT.Algorithm,OTA.PatternMiningSupervised],
    OT.parameters => [
      { DC.description => "Dataset URI", OT.paramScope => "mandatory", DC.title => "dataset_uri" },
      { DC.description => "Feature URI for dependent variable", OT.paramScope => "mandatory", DC.title => "prediction_feature" },
      { DC.description => "Minimum frequency", OT.paramScope => "optional", DC.title => "min_frequency" },
      { DC.description => "Feature type, can be 'paths' or 'trees'", OT.paramScope => "optional", DC.title => "feature_type" },
      { DC.description => "BBRC classes, pass 'false' to switch off mining for BBRC representatives.", OT.paramScope => "optional", DC.title => "backbone" },
      { DC.description => "Significance threshold (between 0 and 1)", OT.paramScope => "optional", DC.title => "min_chisq_significance" },
      { DC.description => "Whether subgraphs should be weighted with their occurrence counts in the instances (frequency)", OT.paramScope => "optional", DC.title => "nr_hits" },
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

# Get RDF/XML representation of fminer bbrc algorithm
# @return [application/rdf+xml] OWL-DL representation of fminer bbrc algorithm
get "/fminer/bbrc/sample/?" do
  algorithm = OpenTox::Algorithm::Generic.new(url_for('/fminer/bbrc/sample',:full))
  algorithm.metadata = {
    DC.title => 'fminer backbone refinement class representatives, obtained from samples of a dataset',
    DC.creator => "andreas@maunz.de",
#    BO.instanceOf => "http://opentox.org/ontology/ist-algorithms.owl#fminer_bbrc",
    RDF.type => [OT.Algorithm,OTA.PatternMiningSupervised],
    OT.parameters => [
      { DC.description => "Dataset URI", OT.paramScope => "mandatory", DC.title => "dataset_uri" },
      { DC.description => "Feature URI for dependent variable", OT.paramScope => "mandatory", DC.title => "prediction_feature" },
      { DC.description => "Number of bootstrap samples", OT.paramScope => "optional", DC.title => "num_boots" },
      { DC.description => "Minimum sampling support", OT.paramScope => "optional", DC.title => "min_sampling_support" },
      { DC.description => "Minimum frequency", OT.paramScope => "optional", DC.title => "min_frequency" },
      { DC.description => "Whether subgraphs should be weighted with their occurrence counts in the instances (frequency)", OT.paramScope => "optional", DC.title => "nr_hits" },
      { DC.description => "BBRC classes, pass 'false' to switch off mining for BBRC representatives.", OT.paramScope => "optional", DC.title => "backbone" },
      { DC.description => "Chisq estimation method, pass 'mean' to use simple mean estimate for chisq test.", OT.paramScope => "optional", DC.title => "method" }
  ]
  }
  case request.env['HTTP_ACCEPT']
  when /text\/html/
    content_type "text/html"
    OpenTox.text_to_html algorithm.to_yaml
  when /yaml/
    content_type "application/x-yaml"
    algorithm.to_yaml
  else
    response['Content-Type'] = 'application/rdf+xml'
    algorithm.to_rdfxml
  end
end

# Get RDF/XML representation of fminer last algorithm
# @return [application/rdf+xml] OWL-DL representation of fminer last algorithm
get "/fminer/last/?" do
  algorithm = OpenTox::Algorithm::Generic.new(url_for('/fminer/last',:full))
  algorithm.metadata = {
    DC.title => 'fminer latent structure class representatives',
    DC.creator => "andreas@maunz.de, helma@in-silico.ch",
    DC.contributor => "vorgrimmlerdavid@gmx.de",
#    BO.instanceOf => "http://opentox.org/ontology/ist-algorithms.owl#fminer_last",
    RDF.type => [OT.Algorithm,OTA.PatternMiningSupervised],
    OT.parameters => [
      { DC.description => "Dataset URI", OT.paramScope => "mandatory", DC.title => "dataset_uri" },
      { DC.description => "Feature URI for dependent variable", OT.paramScope => "mandatory", DC.title => "prediction_feature" },
      { DC.description => "Minimum frequency", OT.paramScope => "optional", DC.title => "min_frequency" },
      { DC.description => "Feature type, can be 'paths' or 'trees'", OT.paramScope => "optional", DC.title => "feature_type" },
      { DC.description => "Whether subgraphs should be weighted with their occurrence counts in the instances (frequency)", OT.paramScope => "optional", DC.title => "nr_hits" },
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


# Get RDF/XML representation of fminer matching algorithm
# @param [String] dataset_uri URI of the dataset 
# @param [String] feature_dataset_uri URI of the feature dataset (i.e. dependent variable)
# @param [optional] parameters Accepted parameters are
# - prediction_feature URI of prediction feature to calculate p-values for
get "/fminer/:method/match?" do
  algorithm = OpenTox::Algorithm::Generic.new(url_for("/fminer/#{params[:method]}/match",:full))
  algorithm.metadata = {
    DC.title => 'fminer feature matching',
    DC.creator => "mguetlein@gmail.com, andreas@maunz.de",
    RDF.type => [OT.Algorithm,OTA.PatternMiningSupervised],
    OT.parameters => [
      { DC.description => "Dataset URI", OT.paramScope => "mandatory", DC.title => "dataset_uri" },
      { DC.description => "Feature Dataset URI", OT.paramScope => "mandatory", DC.title => "feature_dataset_uri" },
      { DC.description => "Feature URI for dependent variable", OT.paramScope => "optional", DC.title => "prediction_feature" }
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




# Run bbrc algorithm on dataset
#
# @param [String] dataset_uri URI of the training dataset
# @param [String] prediction_feature URI of the prediction feature (i.e. dependent variable)
# @param [optional] parameters BBRC parameters, accepted parameters are
#   - min_frequency  Minimum frequency (default 5)
#   - feature_type Feature type, can be 'paths' or 'trees' (default "trees")
#   - backbone BBRC classes, pass 'false' to switch off mining for BBRC representatives. (default "true")
#   - min_chisq_significance Significance threshold (between 0 and 1)
#   - nr_hits Set to "true" to get hit count instead of presence
#   - complete_entries Set to "true" to obtain data entries for each compound
# @return [text/uri-list] Task URI
post '/fminer/bbrc/?' do

  @@fminer=OpenTox::Algorithm::Fminer.new
  @@fminer.check_params(params,5,@subjectid)

  task = OpenTox::Task.create("Mining BBRC features", url_for('/fminer',:full)) do |task|
    @@bbrc.Reset
    if @@fminer.prediction_feature.feature_type == "regression"
      @@bbrc.SetRegression(true) # AM: DO NOT MOVE DOWN! Must happen before the other Set... operations!
    else
      raise "no accept values for dataset '"+@@fminer.training_dataset.uri.to_s+"' and feature '"+@@fminer.prediction_feature.uri.to_s+
        "'" unless @@fminer.training_dataset.accept_values(@@fminer.prediction_feature.uri)
      value_map=@@fminer.training_dataset.value_map(@@fminer.prediction_feature.uri)
    end
    @@bbrc.SetMinfreq(@@fminer.minfreq)
    @@bbrc.SetType(1) if params[:feature_type] == "paths"
    @@bbrc.SetBackbone(false) if params[:backbone] == "false"
    @@bbrc.SetChisqSig(params[:min_chisq_significance].to_f) if params[:min_chisq_significance]
    @@bbrc.SetConsoleOut(false)

    feature_dataset = OpenTox::Dataset.new(nil, @subjectid)
    feature_dataset.add_metadata({
      DC.title => "BBRC representatives for " + @@fminer.training_dataset.metadata[DC.title].to_s,
      DC.creator => url_for('/fminer/bbrc',:full),
      OT.hasSource => url_for('/fminer/bbrc', :full),
      OT.parameters => [
        { DC.title => "dataset_uri", OT.paramValue => params[:dataset_uri] },
        { DC.title => "prediction_feature", OT.paramValue => params[:prediction_feature] },
        { DC.title => "min_frequency", OT.paramValue => @@fminer.minfreq },
        { DC.title => "nr_hits", OT.paramValue => (params[:nr_hits] == "true" ? "true" : "false") },
        { DC.title => "backbone", OT.paramValue => (params[:backbone] == "false" ? "false" : "true") }

    ]
    })
    feature_dataset.save(@subjectid)

    @@fminer.compounds = []
    @@fminer.db_class_sizes = Array.new # AM: effect
    @@fminer.all_activities = Hash.new # DV: for effect calculation in regression part
    @@fminer.smi = [] # needed for matching the patterns back

    # Add data to fminer
    @@fminer.add_fminer_data(@@bbrc, value_map)

    g_array=@@fminer.all_activities.values # DV: calculation of global median for effect calculation
    g_median=g_array.to_scale.median

    raise "No compounds in dataset #{@@fminer.training_dataset.uri}" if @@fminer.compounds.size==0
    task.progress 10
    step_width = 80 / @@bbrc.GetNoRootNodes().to_f
    features = Set.new

    # run @@bbrc
    
    # prepare to receive results as hash { c => [ [f,v], ... ] }
    fminer_results = {}
     
    (0 .. @@bbrc.GetNoRootNodes()-1).each do |j|
      results = @@bbrc.MineRoot(j)
      task.progress 10+step_width*(j+1)
      results.each do |result|
        f = YAML.load(result)[0]
        smarts = f[0]
        p_value = f[1]

        if (!@@bbrc.GetRegression)
          id_arrs = f[2..-1].flatten
          max = OpenTox::Algorithm.effect(f[2..-1].reverse, @@fminer.db_class_sizes) # f needs reversal for bbrc
          effect = max+1
        else #regression part
          id_arrs = f[2]
          # DV: effect calculation
          f_arr=Array.new
          f[2].each do |id|
            id=id.keys[0] # extract id from hit count hash
            f_arr.push(@@fminer.all_activities[id])
          end
          f_median=f_arr.to_scale.median
          if g_median >= f_median
            effect = 'activating'
          else
            effect = 'deactivating'
          end
        end

        feature_uri = File.join feature_dataset.uri,"feature","bbrc", features.size.to_s
        unless features.include? smarts
          features << smarts
          metadata = {
            OT.hasSource => url_for('/fminer/bbrc', :full),
            RDF.type => [OT.Feature, OT.Substructure],
            OT.smarts => smarts,
            OT.pValue => p_value.to_f,
            OT.effect => effect,
            OT.parameters => [
              { DC.title => "dataset_uri", OT.paramValue => params[:dataset_uri] },
              { DC.title => "prediction_feature", OT.paramValue => params[:prediction_feature] }
          ]
          }
          feature_dataset.add_feature feature_uri, metadata
        end

        # re-format to one big hash id_arr
        id_arr = {}; id_arrs.each { |id_count_hash| id_arr[id_count_hash.keys[0]] = id_count_hash.values[0] }
        @@fminer.compounds.collect.each_with_index { |cmpd,id| # This collects all cmpds that have an activity
          val = id_arr[id] ? ( params[:nr_hits] == "true" ? id_arr[id].to_i : 1 ) : 0
          if (val != 0 or params[:complete_entries] == "true")
            fminer_results[cmpd] || fminer_results[cmpd] = {}
            fminer_results[cmpd][feature_uri] || fminer_results[cmpd][feature_uri] = []
            fminer_results[cmpd][feature_uri] << val 
          end
        }
        
      end # end of 
    end   # feature parsing

    which_row = @@fminer.training_dataset.compounds.inject({}) { |h,id| h[id]=0; h }
    @@fminer.training_dataset.compounds.each { |cmpd|
      feature_dataset.add_compound(cmpd) # *unconditionally* add compounds *in order*
      i = which_row[cmpd]
      fminer_results[cmpd] && fminer_results[cmpd].each { |feature, values|
        feature_dataset.add_data_entry( cmpd, feature, values[i] )
      }
      which_row[cmpd] += 1
    }
    # AM: add feature values for non-present features
    # feature_dataset.complete_data_entries

    feature_dataset.save(@subjectid)
    feature_dataset.uri
  end
  response['Content-Type'] = 'text/uri-list'
  raise OpenTox::ServiceUnavailableError.newtask.uri+"\n" if task.status == "Cancelled"
  halt 202,task.uri.to_s+"\n"
end
#end


# Run bbrc/sample algorithm on a dataset
#
# @param [String] dataset_uri URI of the training dataset
# @param [String] prediction_feature URI of the prediction feature (i.e. dependent variable)
# @param [optional] BBRC sample parameters, accepted are
#   - num_boots Number of bootstrap samples (default 150)
#   - min_sampling_support Minimum sampling support (default 30% of num_boots)
#   - min_frequency  Minimum frequency (default 10% of dataset size)
#   - nr_hits Whether subgraphs should be weighted with their occurrence counts in the instances (frequency)
#   - random_seed Random seed ensures same datasets in bootBbrc
#   - backbone BBRC classes, pass 'false' to switch off mining for BBRC representatives. (default "true")
#   - method Chisq estimation method, pass 'mean' to use simple mean estimate (default 'mle').
#   - cache Whether cache files should be used for the combination of dataset, min_frequency, backbone, random seed (default "false")
#
# @return [text/uri-list] Task URI
post '/fminer/bbrc/sample/?' do

  @@fminer=OpenTox::Algorithm::Fminer.new
  @@fminer.check_params(params,100,@subjectid) # AM: 100 per-mil (10%) as default minfreq

  # num_boots
  unless params[:num_boots]
    num_boots = 150
    LOGGER.debug "Set num_boots to default value #{num_boots}"
  else
    raise OpenTox::BadRequestError.new "num_boots is not numeric" unless OpenTox::Algorithm.numeric? params[:num_boots]
	  num_boots = params[:num_boots].to_i.ceil
  end

  # min_sampling_support
  unless params[:min_sampling_support]
    min_sampling_support = (num_boots * 0.3).ceil
    LOGGER.debug "Set min_sampling_support to default value #{min_sampling_support}"
  else
    raise OpenTox::BadRequestError.new "min_sampling_support is not numeric" unless OpenTox::Algorithm.numeric? params[:min_sampling_support]
	  min_sampling_support= params[:min_sampling_support].to_i.ceil
  end

  # random_seed
  unless params[:random_seed]
    random_seed = 1
    LOGGER.debug "Set random seed to default value #{random_seed}"
  else
    raise OpenTox::BadRequestError.new "random_seed is not numeric" unless OpenTox::Algorithm.numeric? params[:random_seed]
    random_seed= params[:random_seed].to_i.ceil
  end

  # backbone
  unless params[:backbone]
    backbone = "true"
    LOGGER.debug "Set backbone to default value #{backbone}"
  else
    raise OpenTox::BadRequestError.new "backbone is neither 'true' nor 'false'" unless (params[:backbone] == "true" or params[:backbone] == "false")
    backbone = params[:backbone]
  end

  # method
  unless params[:method]
    method="mle"
    LOGGER.debug "Set method to default value #{method}"
  else
    raise OpenTox::BadRequestError.new "method is neither 'mle' nor 'mean'" unless (params[:method] == "mle" or params[:method] == "mean")
    method = params[:method]
  end

  # cache
  cache=false
  if params[:cache] == "true"
    cache=true
    LOGGER.debug "Set cache to true"
  end


  task = OpenTox::Task.create("Mining BBRC sample features", url_for('/fminer',:full)) do |task|
    if @@fminer.prediction_feature.feature_type == "regression"
      raise OpenTox::BadRequestError.new "BBRC sampling is only for classification"
    else
      raise "no accept values for dataset '"+@@fminer.training_dataset.uri.to_s+"' and feature '"+@@fminer.prediction_feature.uri.to_s+
        "'" unless @@fminer.training_dataset.accept_values(@@fminer.prediction_feature.uri)
      value_map=@@fminer.training_dataset.value_map(@@fminer.prediction_feature.uri)
    end

    feature_dataset = OpenTox::Dataset.new(nil, @subjectid)
    feature_dataset.add_metadata({
      DC.title => "BBRC representatives for " + @@fminer.training_dataset.metadata[DC.title].to_s + "(bootstrapped)",
      DC.creator => url_for('/fminer/bbrc/sample',:full),
      OT.hasSource => url_for('/fminer/bbrc/sample', :full)
    })
    feature_dataset.save(@subjectid)

    # filled by add_fminer_data:
    @@fminer.compounds = [] # indexed by id, starting from 1 (not 0)
    @@fminer.db_class_sizes = Array.new # for effect calculation
    @@fminer.all_activities = Hash.new # for effect calculation, indexed by id, starting from 1 (not 0)
    @@fminer.smi = [] # needed for matching the patterns back, indexed by id, starting from 1 (not 0)
    @@fminer.add_fminer_data(nil, value_map) # To only fill in administrative data (no fminer priming) pass 'nil' as instance

    raise "No compounds in dataset #{@@fminer.training_dataset.uri}" if @@fminer.compounds.size==0


    # run bbrc-sample, obtain smarts and p-values
    features = Set.new
    task.progress 10
    @r = RinRuby.new(true,false) # global R instance leads to Socket errors after a large number of requests
    @r.assign "dataset.uri", params[:dataset_uri]
    @r.assign "prediction.feature.uri", @@fminer.prediction_feature.uri
    @r.assign "num.boots", num_boots
    @r.assign "min.frequency.per.sample", @@fminer.minfreq
    @r.assign "min.sampling.support", min_sampling_support
    @r.assign "random.seed", random_seed
    @r.assign "backbone", backbone
    @r.assign "bbrc.service", File.join(CONFIG[:services]["opentox-algorithm"], "fminer/bbrc")
    @r.assign "dataset.service", CONFIG[:services]["opentox-dataset"]
    @r.assign "method", method

    require 'digest/md5'
    smiles_array = @@fminer.smi.collect
    smiles_array.shift if smiles_array[0].nil?
    cachedId = Digest::MD5.hexdigest(
      smiles_array.sort.join+
      num_boots.to_s+
      @@fminer.minfreq.to_s+
      random_seed.to_s+
      backbone.to_s
    )
    @r.assign "cachedId", cachedId
    @r.eval "cachedId <- NULL" unless cache

    @r.eval "source(\"bbrc-sample/bbrc-sample.R\")"
    begin
      @r.eval "bootBbrc(dataset.uri, prediction.feature.uri, num.boots, min.frequency.per.sample, min.sampling.support, cachedId, bbrc.service, dataset.service, T, random.seed, as.logical(backbone), method)"
      smarts = (@r.pull "ans.patterns").collect! { |id| id.gsub(/\'/,"") } # remove extra quotes around smarts
      r_p_values = @r.pull "ans.p.values"
      smarts_p_values = {}; smarts.size.times { |i| smarts_p_values[ smarts[i] ] = r_p_values[i] }
      merge_time = @r.pull "merge.time"
      n_stripped_mss = @r.pull "n.stripped.mss"
      n_stripped_cst = @r.pull "n.stripped.cst"
    rescue Exception => e
      LOGGER.debug "#{e.class}: #{e.message}"
      LOGGER.debug "Backtrace:\n\t#{e.backtrace.join("\n\t")}"
    end
    @r.quit # free R

    # matching
    task.progress 90
    lu = LU.new
    params[:nr_hits] == "true" ? hit_count=true: hit_count=false
    matches, counts, used_compounds = lu.match_rb(@@fminer.smi,smarts,hit_count,true) # last arg: always create complete entries for sampling

    @@fminer.training_dataset.compounds.each { |cmpd| feature_dataset.add_compound(cmpd) }
    
    feature_dataset.add_metadata({
          OT.parameters => [
        { DC.title => "dataset_uri", OT.paramValue => params[:dataset_uri] },
        { DC.title => "prediction_feature", OT.paramValue => params[:prediction_feature] },
        { DC.title => "min_sampling_support", OT.paramValue => min_sampling_support },
        { DC.title => "num_boots", OT.paramValue => num_boots },
        { DC.title => "min_frequency_per_sample", OT.paramValue => @@fminer.minfreq },
        { DC.title => "nr_hits", OT.paramValue => hit_count.to_s },
        { DC.title => "merge_time", OT.paramValue => merge_time.to_s },
        { DC.title => "n_stripped_mss", OT.paramValue => n_stripped_mss.to_s },
        { DC.title => "n_stripped_cst", OT.paramValue => n_stripped_cst.to_s },
        { DC.title => "random_seed", OT.paramValue => random_seed.to_s },
        { DC.title => "backbone", OT.paramValue => backbone.to_s },
        { DC.title => "method", OT.paramValue => method.to_s }
          ]
    })

    matches.each do |smarts, ids|
      metadata = calc_metadata (smarts, ids, counts[smarts], nil, nil , value_map, params, smarts_p_values[smarts])
      feature_uri = File.join feature_dataset.uri,"feature","last", feature_dataset.features.size.to_s
      feature_dataset.add_feature feature_uri, metadata
      ids.each_with_index { |id,idx| feature_dataset.add_data_entry(@@fminer.compounds[id], feature_uri, counts[smarts][idx])}
    end

    feature_dataset.save(@subjectid)
    feature_dataset.uri
  end
  response['Content-Type'] = 'text/uri-list'
  raise OpenTox::ServiceUnavailableError.newtask.uri+"\n" if task.status == "Cancelled"
  halt 202,task.uri.to_s+"\n"
end

# Run last algorithm on a dataset
#
# @param [String] dataset_uri URI of the training dataset
# @param [String] prediction_feature URI of the prediction feature (i.e. dependent variable)
# @param [optional] parameters LAST parameters, accepted parameters are
#   - min_frequency freq  Minimum frequency (default 5)
#   - feature_type Feature type, can be 'paths' or 'trees' (default "trees")
#   - nr_hits Set to "true" to get hit count instead of presence
#   - complete_entries Set to "true" to obtain data entries for each compound
# @return [text/uri-list] Task URI
post '/fminer/last/?' do

  @@fminer=OpenTox::Algorithm::Fminer.new
  @@fminer.check_params(params,80,@subjectid)

  task = OpenTox::Task.create("Mining LAST features", url_for('/fminer',:full)) do |task|
    @@last.Reset
    if @@fminer.prediction_feature.feature_type == "regression"
      @@last.SetRegression(true) # AM: DO NOT MOVE DOWN! Must happen before the other Set... operations!
    else
      raise "no accept values for dataset '"+@@fminer.training_dataset.uri.to_s+"' and feature '"+@@fminer.prediction_feature.uri.to_s+
        "'" unless @@fminer.training_dataset.accept_values(@@fminer.prediction_feature.uri)
      value_map=@@fminer.training_dataset.value_map(@@fminer.prediction_feature.uri)
    end
    @@last.SetMinfreq(@@fminer.minfreq)
    @@last.SetType(1) if params[:feature_type] == "paths"
    @@last.SetConsoleOut(false)


    feature_dataset = OpenTox::Dataset.new(nil, @subjectid)
    feature_dataset.add_metadata({
      DC.title => "LAST representatives for " + @@fminer.training_dataset.metadata[DC.title].to_s,
      DC.creator => url_for('/fminer/last',:full),
      OT.hasSource => url_for('/fminer/last', :full),
      OT.parameters => [
        { DC.title => "dataset_uri", OT.paramValue => params[:dataset_uri] },
        { DC.title => "prediction_feature", OT.paramValue => params[:prediction_feature] },
        { DC.title => "min_frequency", OT.paramValue => @@fminer.minfreq },
        { DC.title => "nr_hits", OT.paramValue => (params[:nr_hits] == "true" ? "true" : "false") }
      ]
    })
    feature_dataset.save(@subjectid)

    @@fminer.compounds = []
    @@fminer.db_class_sizes = Array.new # AM: effect
    @@fminer.all_activities = Hash.new # DV: for effect calculation (class and regr)
    @@fminer.smi = [] # needed for matching the patterns back

    # Add data to fminer
    @@fminer.add_fminer_data(@@last, value_map)

    raise "No compounds in dataset #{@@fminer.training_dataset.uri}" if @@fminer.compounds.size==0

    # run @@last
    xml = ""
    task.progress 10
    step_width = 80 / @@last.GetNoRootNodes().to_f

    (0 .. @@last.GetNoRootNodes()-1).each do |j|
      results = @@last.MineRoot(j)
      task.progress 10+step_width*(j+1)
      results.each do |result|
        xml << result
      end
    end

    lu = LU.new                             # uses last-utils here
    dom=lu.read(xml)                        # parse GraphML
    smarts=lu.smarts_rb(dom,'nls')          # converts patterns to LAST-SMARTS using msa variant (see last-pm.maunz.de)
    params[:nr_hits] == "true" ? hit_count=true : hit_count=false
    params[:complete_entries] == "true" ? complete_entries=true : complete_entries=false
    matches, counts = lu.match_rb(@@fminer.smi,smarts,hit_count,complete_entries)       # creates instantiations

    @@fminer.training_dataset.compounds.each { |cmpd| feature_dataset.add_compound(cmpd)  }
    matches.each do |smarts, ids|
      metadata = calc_metadata (smarts, ids, counts[smarts], @@last, nil, value_map, params)
      feature_uri = File.join feature_dataset.uri,"feature","last", feature_dataset.features.size.to_s
      feature_dataset.add_feature feature_uri, metadata
      @@fminer.compounds.collect.each_with_index { |cmpd,id| # This collects all cmpds that have an activity
        count_idx = matches[smarts].index(id)
        feature_dataset.add_data_entry(cmpd, feature_uri, counts[smarts][count_idx]) if count_idx
      }
    end

    feature_dataset.save(@subjectid)
    feature_dataset.uri
  end
  response['Content-Type'] = 'text/uri-list'
  raise OpenTox::ServiceUnavailableError.newtask.uri+"\n" if task.status == "Cancelled"
  halt 202,task.uri.to_s+"\n"
end

# Matches features of a a feature dataset onto instances of another dataset. 
# The latter is referred to as 'training dataset', since p-values are computed,
# if user passes a prediction feature, or if the training dataset has only one feature.
# The result does not contain the prediction feature.
# @param [String] dataset_uri URI of the dataset 
# @param [String] feature_dataset_uri URI of the feature dataset (i.e. dependent variable)
# @param [String] prediction_feature URI of prediction feature to calculate p-values for
# @param [optional] 
#   - complete_entries Set to "true" to obtain data entries for each compound
# @return [text/uri-list] Task URI
post '/fminer/:method/match?' do
  raise OpenTox::BadRequestError.new "feature_dataset_uri not given" unless params[:feature_dataset_uri]
  raise OpenTox::BadRequestError.new "dataset_uri not given" unless params[:dataset_uri]

  @@fminer=OpenTox::Algorithm::Fminer.new
  @@fminer.training_dataset = OpenTox::Dataset.find "#{params[:dataset_uri]}",@subjectid
  unless params[:prediction_feature] # try to read prediction_feature from dataset
    @@fminer.prediction_feature = OpenTox::Feature.find(@@fminer.training_dataset.features.keys.first,@subjectid) if @@fminer.training_dataset.features.size == 1
  end
  @@fminer.prediction_feature = OpenTox::Feature.find(params[:prediction_feature],@subjectid) if params[:prediction_feature]

  raise OpenTox::NotFoundError.new "No feature #{@@fminer.prediction_feature.uri} in dataset #{params[:dataset_uri]}" unless @@fminer.training_dataset.features and @@fminer.training_dataset.features.include?(@@fminer.prediction_feature.uri)

  task = OpenTox::Task.create("Matching features", url_for('/fminer/match',:full)) do |task|

    if @@fminer.prediction_feature.feature_type == "classification"
      raise "no accept values for dataset '"+@@fminer.training_dataset.uri.to_s+"' and feature '"+@@fminer.prediction_feature.uri.to_s+
        "'" unless @@fminer.training_dataset.accept_values(@@fminer.prediction_feature.uri)
      value_map=@@fminer.training_dataset.value_map(@@fminer.prediction_feature.uri)
    end

    # filled by add_fminer_data:
    @@fminer.compounds = [] # indexed by id, starting from 1 (not 0)
    @@fminer.db_class_sizes = Array.new # for effect calculation
    @@fminer.all_activities = Hash.new # for effect calculation, indexed by id, starting from 1 (not 0)
    @@fminer.smi = [] # needed for matching the patterns back, indexed by id, starting from 1 (not 0)
    @@fminer.add_fminer_data(nil, value_map) # To only fill in administrative data (no fminer priming) pass 'nil' as instance
    raise "No compounds in dataset #{@@fminer.training_dataset.uri}" if @@fminer.compounds.size==0

    f_dataset = OpenTox::Dataset.find params[:feature_dataset_uri],@subjectid
    c_dataset = @@fminer.training_dataset
    feature_dataset = OpenTox::Dataset.create CONFIG[:services]["dataset"],@subjectid # Intialize result 
    
    # Run matching, put data entries in result. Features are recreated.
    smarts = f_dataset.features.collect { |f,m| m[OT.smarts] }
    params[:nr_hits] == "true" ? hit_count=true : hit_count=false
    params[:complete_entries] == "true" ? complete_entries=true : complete_entries=false
    matches, counts = LU.new.match_rb(@@fminer.smi, smarts, hit_count, complete_entries) if smarts.size>0

    @@fminer.training_dataset.compounds.each { |cmpd| feature_dataset.add_compound(cmpd)  }
    matches.each do |smarts, ids|
      metadata = calc_metadata (smarts, ids, counts[smarts], @@last, nil, value_map, params)
      feature_uri = File.join feature_dataset.uri,"feature",params[:method], feature_dataset.features.size.to_s
      feature_dataset.add_feature feature_uri, metadata
      @@fminer.compounds.collect.each_with_index { |cmpd,id| # This collects all cmpds that have an activity
        count_idx = matches[smarts].index(id)
        feature_dataset.add_data_entry(cmpd, feature_uri, counts[smarts][count_idx]) if count_idx
      }
    end

    feature_dataset.save @subjectid
    feature_dataset.uri
  end
  return_task(task)
end

