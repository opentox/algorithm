ENV['FMINER_SMARTS'] = 'true'
ENV['FMINER_NO_AROMATIC'] = 'true'
ENV['FMINER_PVALUES'] = 'true'
ENV['FMINER_SILENT'] = 'true'
ENV['FMINER_NR_HITS'] = 'true'

@@bbrc = Bbrc::Bbrc.new 
@@last = Last::Last.new 

# Get list of fminer algorithms
#
# @return [text/uri-list] URIs of fminer algorithms
get '/fminer/?' do
  list = [ url_for('/fminer/bbrc', :full), url_for('/fminer/last', :full) ].join("\n") + "\n"
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
      { DC.description => "Maximum number of hops", OT.paramScope => "optional", DC.title => "hops" },
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

# Creates same features for dataset <dataset_uri> that have been created
# with fminer in dataset <feature_dataset_uri>
# accept params[:nr_hits] as used in other fminer methods 
post '/fminer/:method/match?' do 
  
  LOGGER.info "apply fminer match #{params.inspect}"
  
  raise OpenTox::BadRequestError.new "feature_dataset_uri not given" unless params[:feature_dataset_uri]
  raise OpenTox::BadRequestError.new "dataset_uri not given" unless params[:dataset_uri] 
  task = OpenTox::Task.create("Matching features", url_for('/fminer/match',:full)) do |task|
    f_dataset = OpenTox::Dataset.find params[:feature_dataset_uri],@subjectid
    c_dataset = OpenTox::Dataset.find params[:dataset_uri],@subjectid
    res_dataset = OpenTox::Dataset.create CONFIG[:services]["dataset"],@subjectid
    f_dataset.features.each do |f,m|
      res_dataset.add_feature(f,m)
    end

    if params[:nr_hits] == "true"
      step_width = 100 / c_dataset.compounds.size.to_f
      count = 0
      c_dataset.compounds.each do |c|
        res_dataset.add_compound(c)
        comp = OpenTox::Compound.new(c)
        f_dataset.features.each do |f,m|
          hits = comp.match_hits([m[OT.smarts]])
          res_dataset.add(c,f,hits[m[OT.smarts]]) if hits[m[OT.smarts]]          
        end
        count += 1
        task.progress step_width*count
      end
    else
      LOGGER.debug "match #{c_dataset.compounds.size} compounds with #{f_dataset.features.keys.size} features"
      step_width = 100 / f_dataset.features.size.to_f
      count = 0
        
      obconversion = OpenBabel::OBConversion.new
      obconversion.set_in_format('inchi')    
      smarts_pattern = OpenBabel::OBSmartsPattern.new
      
      obmols = {}
      c_dataset.compounds.each do |c|
        res_dataset.add_compound(c)
        inchi = OpenTox::Compound.new(c).inchi
        obmol = OpenBabel::OBMol.new
        obconversion.read_string(obmol,inchi)
        obmols[c] = obmol
      end
      
      f_dataset.features.each do |f,m|
        smarts_pattern.init(m[OT.smarts])
        c_dataset.compounds.each do |c|
          res_dataset.add(c,f,1) if smarts_pattern.match(obmols[c])
        end
        count += 1
        task.progress step_width*count if count%10==0
      end
    end
    res_dataset.save @subjectid
    LOGGER.info "fminer match result #{res_dataset.uri}"
    res_dataset.uri
  end
  return_task(task)
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
# @return [text/uri-list] Task URI
post '/fminer/bbrc/?' do 
  
  LOGGER.info "apply fminer bbrc #{params.inspect}"

  fminer=OpenTox::Algorithm::Fminer.new
  fminer.check_params(params,5,@subjectid)

  task = OpenTox::Task.create("Mining BBRC features", url_for('/fminer',:full)) do |task|
    @@bbrc.Reset
    if fminer.prediction_feature.feature_type == "regression"
      @@bbrc.SetRegression(true) # AM: DO NOT MOVE DOWN! Must happen before the other Set... operations!
    else
      raise "no accept values for dataset '"+fminer.training_dataset.uri.to_s+"' and feature '"+fminer.prediction_feature.uri.to_s+
        "'" unless fminer.training_dataset.accept_values(fminer.prediction_feature.uri)
      @training_classes = fminer.training_dataset.accept_values(fminer.prediction_feature.uri).sort
      @value_map=Hash.new
      @training_classes.each_with_index { |c,i| @value_map[i+1] = c }
    end
    @@bbrc.SetMinfreq(fminer.minfreq)
    @@bbrc.SetType(1) if params[:feature_type] == "paths"
    @@bbrc.SetBackbone(eval params[:backbone]) if params[:backbone] and ( params[:backbone] == "true" or params[:backbone] == "false" ) # convert string to boolean
    @@bbrc.SetChisqSig(params[:min_chisq_significance].to_f) if params[:min_chisq_significance]
    @@bbrc.SetConsoleOut(false)
    
    feature_dataset = OpenTox::Dataset.new(nil, @subjectid)
    feature_dataset.add_metadata({
      DC.title => "BBRC representatives for " + fminer.training_dataset.metadata[DC.title].to_s,
      DC.creator => url_for('/fminer/bbrc',:full),
      OT.hasSource => url_for('/fminer/bbrc', :full),
      OT.parameters => [
        { DC.title => "dataset_uri", OT.paramValue => params[:dataset_uri] },
        { DC.title => "prediction_feature", OT.paramValue => params[:prediction_feature] }
    ]
    })
    feature_dataset.save(@subjectid)

    fminer.compounds = []
    fminer.db_class_sizes = Array.new # AM: effect
    fminer.all_activities = Hash.new # DV: for effect calculation in regression part
    fminer.smi = [] # AM LAST: needed for matching the patterns back

    # Add data to fminer
    #fminer.add_fminer_data(@@bbrc, params, @value_map)
    fminer.add_fminer_data(@@bbrc, @value_map)

    g_array=fminer.all_activities.values # DV: calculation of global median for effect calculation
    g_median=g_array.to_scale.median

    raise "No compounds in dataset #{fminer.training_dataset.uri}" if fminer.compounds.size==0
    task.progress 10
    step_width = 80 / @@bbrc.GetNoRootNodes().to_f
    features = Set.new

    feature_count = {}
    
    # run @@bbrc
    (0 .. @@bbrc.GetNoRootNodes()-1).each do |j|
      results = @@bbrc.MineRoot(j)
      task.progress 10+step_width*(j+1)
      results.each do |result|
        f = YAML.load(result)[0]
        smarts = f[0]
        p_value = f[1]

        if (!@@bbrc.GetRegression) 
          id_arrs = f[2..-1].flatten
          max = OpenTox::Algorithm.effect(f[2..-1], fminer.db_class_sizes)
          effect = f[2..-1].size-max
        else #regression part
          id_arrs = f[2]
          # DV: effect calculation
          f_arr=Array.new
          f[2].each do |id|
            id=id.keys[0] # extract id from hit count hash
            f_arr.push(fminer.all_activities[id]) 
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
          #feature_dataset.add_feature_parameters feature_uri, feature_dataset.parameters
          
          feature_count[feature_uri] = 0 
          
        end
        id_arrs.each { |id_count_hash|
          id=id_count_hash.keys[0].to_i
          count=id_count_hash.values[0].to_i
          if params[:nr_hits] == "true"
            feature_dataset.add(fminer.compounds[id], feature_uri, count)
          else
            feature_dataset.add(fminer.compounds[id], feature_uri, 1)
            feature_count[feature_uri] = feature_count[feature_uri]+1
          end
        }

      end # end of 
    end   # feature parsing

    # AM: add feature values for non-present features
    # feature_dataset.complete_data_entries 
    
    if (params[:max_num_features] && feature_dataset.features.size>params[:max_num_features].to_i)
      LOGGER.debug "removing features, found: #{feature_dataset.features.size}, max-num: #{params[:max_num_features]}"
      
      feature_p_count = []
      feature_dataset.features.each do |f_uri,m|
        feature_p_count << [f_uri, m[OT.pValue], feature_count[f_uri]]
      end
      # sort by p-value, tie breaking by number of compounds that match this feature
      sorted = feature_p_count.sort do |a,b|
        if b[1] == a[1]
          b[2] <=> a[2]
        else
          b[1] <=> a[1]
        end
      end
      (params[:max_num_features].to_i..(sorted.size-1)).each do |i|
        feature_dataset.features.delete(sorted[i][0])
        feature_dataset.compounds.each do |c|
          feature_dataset.data_entries[c].delete(sorted[i][0])   
        end
      end
    end
    
    feature_dataset.save(@subjectid) 
    LOGGER.info "fminer bbrc result #{feature_dataset.uri}"
    feature_dataset.uri
  end
  response['Content-Type'] = 'text/uri-list'
  raise OpenTox::ServiceUnavailableError.newtask.uri+"\n" if task.status == "Cancelled"
  halt 202,task.uri.to_s+"\n"
end
#end

# Run last algorithm on a dataset
#
# @param [String] dataset_uri URI of the training dataset
# @param [String] prediction_feature URI of the prediction feature (i.e. dependent variable)
# @param [optional] parameters LAST parameters, accepted parameters are
#   - min_frequency freq  Minimum frequency (default 5)
#   - feature_type Feature type, can be 'paths' or 'trees' (default "trees")
#   - hops Maximum number of hops
#   - nr_hits Set to "true" to get hit count instead of presence
# @return [text/uri-list] Task URI
post '/fminer/last/?' do

  fminer=OpenTox::Algorithm::Fminer.new
  fminer.check_params(params,80,@subjectid)

  task = OpenTox::Task.create("Mining LAST features", url_for('/fminer',:full)) do |task|
    @@last.Reset
    if fminer.prediction_feature.feature_type == "regression"
      @@last.SetRegression(true) # AM: DO NOT MOVE DOWN! Must happen before the other Set... operations!
    else
      raise "no accept values for dataset '"+fminer.training_dataset.uri.to_s+"' and feature '"+fminer.prediction_feature.uri.to_s+
        "'" unless fminer.training_dataset.accept_values(fminer.prediction_feature.uri)
      @training_classes = fminer.training_dataset.accept_values(fminer.prediction_feature.uri).sort
      @value_map=Hash.new
      @training_classes.each_with_index { |c,i| @value_map[i+1] = c }
    end
    @@last.SetMinfreq(fminer.minfreq)
    @@last.SetType(1) if params[:feature_type] == "paths"
    @@last.SetMaxHops(params[:hops]) if params[:hops]
    @@last.SetConsoleOut(false)


    feature_dataset = OpenTox::Dataset.new(nil, @subjectid)
    feature_dataset.add_metadata({
      DC.title => "LAST representatives for " + fminer.training_dataset.metadata[DC.title].to_s,
      DC.creator => url_for('/fminer/last',:full),
      OT.hasSource => url_for('/fminer/last', :full),
      OT.parameters => [
        { DC.title => "dataset_uri", OT.paramValue => params[:dataset_uri] },
        { DC.title => "prediction_feature", OT.paramValue => params[:prediction_feature] }
    ]
    })
    feature_dataset.save(@subjectid)

    fminer.compounds = []
    fminer.db_class_sizes = Array.new # AM: effect
    fminer.all_activities = Hash.new # DV: for effect calculation (class and regr)
    fminer.smi = [] # AM LAST: needed for matching the patterns back

    # Add data to fminer
    #fminer.add_fminer_data(@@last, params, @value_map)
    fminer.add_fminer_data(@@last, @value_map)

    raise "No compounds in dataset #{fminer.training_dataset.uri}" if fminer.compounds.size==0

    # run @@last
    features = Set.new
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

    lu = LU.new                             # AM LAST: uses last-utils here
    dom=lu.read(xml)                        # AM LAST: parse GraphML 
    smarts=lu.smarts_rb(dom,'nls')          # AM LAST: converts patterns to LAST-SMARTS using msa variant (see last-pm.maunz.de)
    params[:nr_hits] == "true" ? hit_count=true: hit_count=false
    matches, counts = lu.match_rb(fminer.smi,smarts,hit_count)       # AM LAST: creates instantiations

    matches.each do |smarts, ids|
      feat_hash = Hash[*(fminer.all_activities.select { |k,v| ids.include?(k) }.flatten)] # AM LAST: get activities of feature occurrences; see http://www.softiesonrails.com/2007/9/18/ruby-201-weird-hash-syntax
      if @@last.GetRegression() 
        p_value = @@last.KSTest(fminer.all_activities.values, feat_hash.values).to_f # AM LAST: use internal function for test
        effect = (p_value > 0) ? "activating" : "deactivating"
      else
        p_value = @@last.ChisqTest(fminer.all_activities.values, feat_hash.values).to_f
        g=Array.new
        @value_map.each { |y,act| g[y-1]=Array.new }
        feat_hash.each  { |x,y|   g[y-1].push(x)   }
        max = OpenTox::Algorithm.effect(g, fminer.db_class_sizes)
        effect = g.size-max
      end
      feature_uri = File.join feature_dataset.uri,"feature","last", features.size.to_s
      unless features.include? smarts
        features << smarts
        metadata = {
          RDF.type => [OT.Feature, OT.Substructure],
          OT.hasSource => feature_dataset.uri,
          OT.smarts => smarts,
          OT.pValue => p_value.abs,
          OT.effect => effect,
          OT.parameters => [
            { DC.title => "dataset_uri", OT.paramValue => params[:dataset_uri] },
            { DC.title => "prediction_feature", OT.paramValue => params[:prediction_feature] }
        ]
        } 
        feature_dataset.add_feature feature_uri, metadata
      end
      if !hit_count
        ids.each { |id| feature_dataset.add(fminer.compounds[id], feature_uri, 1)}
      else
        ids.each_with_index { |id,i| feature_dataset.add(fminer.compounds[id], feature_uri, counts[smarts][i])} 
      end
    end

    # AM: add feature values for non-present features
    # feature_dataset.complete_data_entries 

    feature_dataset.save(@subjectid) 
    feature_dataset.uri
  end
  response['Content-Type'] = 'text/uri-list'
  raise OpenTox::ServiceUnavailableError.newtask.uri+"\n" if task.status == "Cancelled"
  halt 202,task.uri.to_s+"\n"
end
