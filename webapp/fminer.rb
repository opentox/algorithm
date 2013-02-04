=begin
* Name: fminer.rb
* Description: Subgraph descriptor calculation 
* Author: Andreas Maunz <andreas@maunz.de>
* Date: 10/2012
=end

ENV['FMINER_SMARTS'] = 'true'
ENV['FMINER_NO_AROMATIC'] = 'true'
ENV['FMINER_PVALUES'] = 'true'
ENV['FMINER_SILENT'] = 'true'
ENV['FMINER_NR_HITS'] = 'true'

@@bbrc = Bbrc::Bbrc.new
@@last = Last::Last.new


module OpenTox
  
  class Application < Service

    # Get list of fminer algorithms
    # @return [text/uri-list] URIs
    get '/fminer/?' do
      list = [ to('/fminer/bbrc', :full), 
               to('/fminer/bbrc/sample', :full), 
               to('/fminer/last', :full), 
               to('/fminer/bbrc/match', :full), 
               to('/fminer/last/match', :full) 
             ].join("\n") + "\n"
      format_output(list)
    end
    
    # Get representation of BBRC algorithm
    # @return [String] Representation
    get "/fminer/bbrc/?" do
      algorithm = OpenTox::Algorithm.new(to('/fminer/bbrc',:full))
      algorithm.metadata = {
        DC.title => 'Backbone Refinement Class Representatives',
        DC.creator => "andreas@maunz.de",
        RDF.type => [OT.Algorithm,OTA.PatternMiningSupervised]
      }
      algorithm.parameters = [
          { DC.description => "Dataset URI", OT.paramScope => "mandatory", DC.title => "dataset_uri" },
          { DC.description => "Feature URI for dependent variable", OT.paramScope => "optional", DC.title => "prediction_feature" },
          { DC.description => "Minimum frequency", OT.paramScope => "optional", DC.title => "min_frequency" },
          { DC.description => "Feature type, can be 'paths' or 'trees'", OT.paramScope => "optional", DC.title => "feature_type" },
          { DC.description => "BBRC classes, pass 'false' to switch off mining for BBRC representatives.", OT.paramScope => "optional", DC.title => "backbone" },
          { DC.description => "Significance threshold (between 0 and 1)", OT.paramScope => "optional", DC.title => "min_chisq_significance" },
          { DC.description => "Whether subgraphs should be weighted with their occurrence counts in the instances (frequency)", OT.paramScope => "optional", DC.title => "nr_hits" },
          { DC.description => "Set to 'true' to obtain target variables as a feature", OT.paramScope => "optional", DC.title => "get_target" }
      ]
      format_output(algorithm)
    end
    
    # Get representation of BBRC-sample algorithm
    # @return [String] Representation
    get "/fminer/bbrc/sample/?" do
      algorithm = OpenTox::Algorithm.new(to('/fminer/bbrc/sample',:full))
      algorithm.metadata = {
        DC.title => 'Backbone Refinement Class Representatives, obtained from samples of a dataset',
        DC.creator => "andreas@maunz.de",
        RDF.type => [OT.Algorithm,OTA.PatternMiningSupervised]
      }
      algorithm.parameters = [
          { DC.description => "Dataset URI", OT.paramScope => "mandatory", DC.title => "dataset_uri" },
          { DC.description => "Feature URI for dependent variable", OT.paramScope => "optional", DC.title => "prediction_feature" },
          { DC.description => "Number of bootstrap samples", OT.paramScope => "optional", DC.title => "num_boots" },
          { DC.description => "Minimum sampling support", OT.paramScope => "optional", DC.title => "min_sampling_support" },
          { DC.description => "Minimum frequency", OT.paramScope => "optional", DC.title => "min_frequency" },
          { DC.description => "Whether subgraphs should be weighted with their occurrence counts in the instances (frequency)", OT.paramScope => "optional", DC.title => "nr_hits" },
          { DC.description => "BBRC classes, pass 'false' to switch off mining for BBRC representatives.", OT.paramScope => "optional", DC.title => "backbone" },
          { DC.description => "Chisq estimation method, pass 'mean' to use simple mean estimate for chisq test.", OT.paramScope => "optional", DC.title => "method" }
      ]
      format_output(algorithm)
    end
    
    # Get representation of fminer LAST-PM algorithm
    # @return [String] Representation
    get "/fminer/last/?" do
      algorithm = OpenTox::Algorithm.new(to('/fminer/last',:full))
      algorithm.metadata = {
        DC.title => 'Latent Structure Pattern Mining descriptors',
        DC.creator => "andreas@maunz.de",
        RDF.type => [OT.Algorithm,OTA.PatternMiningSupervised]
      }
      algorithm.parameters = [
          { DC.description => "Dataset URI", OT.paramScope => "mandatory", DC.title => "dataset_uri" },
          { DC.description => "Feature URI for dependent variable", OT.paramScope => "optional", DC.title => "prediction_feature" },
          { DC.description => "Minimum frequency", OT.paramScope => "optional", DC.title => "min_frequency" },
          { DC.description => "Feature type, can be 'paths' or 'trees'", OT.paramScope => "optional", DC.title => "feature_type" },
          { DC.description => "Whether subgraphs should be weighted with their occurrence counts in the instances (frequency)", OT.paramScope => "optional", DC.title => "nr_hits" },
          { DC.description => "Set to 'true' to obtain target variables as a feature", OT.paramScope => "optional", DC.title => "get_target" }
      ]
      format_output(algorithm)
    end
    
    
    # Get representation of matching algorithm
    # @return [String] Representation
    get "/fminer/:method/match?" do
      algorithm = OpenTox::Algorithm.new(to("/fminer/#{params[:method]}/match",:full))
      algorithm.metadata = {
        DC.title => 'fminer feature matching',
        DC.creator => "mguetlein@gmail.com, andreas@maunz.de",
        RDF.type => [OT.Algorithm,OTA.PatternMiningSupervised]
      }
      algorithm.parameters = [
          { DC.description => "Dataset URI", OT.paramScope => "mandatory", DC.title => "dataset_uri" },
          { DC.description => "Feature Dataset URI", OT.paramScope => "mandatory", DC.title => "feature_dataset_uri" },
          { DC.description => "Feature URI for dependent variable", OT.paramScope => "optional", DC.title => "prediction_feature" }
      ]
      format_output(algorithm)
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
    #   - get_target Set to "true" to obtain target variable as feature
    # @return [text/uri-list] Task URI
    post '/fminer/bbrc/?' do
    

      @@fminer=OpenTox::Algorithm::Fminer.new(to('/fminer/bbrc',:full))
      @@fminer.check_params(params,5,@subjectid)
    
      task = OpenTox::Task.create( 
                                  $task[:uri], 
                                  @subjectid, 
                                  { RDF::DC.description => "Mining BBRC features", 
                                    RDF::DC.creator => to('/fminer/bbrc',:full) 
                                  } 
                                 ) do |task|


        @@bbrc.Reset
        if @@fminer.prediction_feature.feature_type == "regression"
          @@bbrc.SetRegression(true) # AM: DO NOT MOVE DOWN! Must happen before the other Set... operations!
        else
          bad_request_error "No accept values for "\
                            "dataset '#{@@fminer.training_dataset.uri}' and "\
                            "feature '#{@@fminer.prediction_feature.uri}'" unless 
                             @@fminer.prediction_feature.accept_values
          value_map=@@fminer.training_dataset.value_map(@@fminer.prediction_feature)
        end
        @@bbrc.SetMinfreq(@@fminer.minfreq)
        @@bbrc.SetType(1) if params[:feature_type] == "paths"
        @@bbrc.SetBackbone(false) if params[:backbone] == "false"
        @@bbrc.SetChisqSig(params[:min_chisq_significance].to_f) if params[:min_chisq_significance]
        @@bbrc.SetConsoleOut(false)

  
        feature_dataset = OpenTox::Dataset.new(nil, @subjectid)
        feature_dataset.metadata = {
          DC.title => "BBRC representatives",
          DC.creator => to('/fminer/bbrc',:full),
          OT.hasSource => to('/fminer/bbrc', :full),
        }
        feature_dataset.parameters = [
            { DC.title => "dataset_uri", OT.paramValue => params[:dataset_uri] },
            { DC.title => "prediction_feature", OT.paramValue => params[:prediction_feature] },
            { DC.title => "min_frequency", OT.paramValue => @@fminer.minfreq },
            { DC.title => "nr_hits", OT.paramValue => (params[:nr_hits] == "true" ? "true" : "false") },
            { DC.title => "backbone", OT.paramValue => (params[:backbone] == "false" ? "false" : "true") }
        ]
  
        @@fminer.compounds = []
        @@fminer.db_class_sizes = Array.new # AM: effect
        @@fminer.all_activities = Hash.new # DV: for effect calculation in regression part
        @@fminer.smi = [] # AM LAST: needed for matching the patterns back
  
        # Add data to fminer
        @@fminer.add_fminer_data(@@bbrc, value_map)
        g_median=@@fminer.all_activities.values.to_scale.median

        #task.progress 10
        step_width = 80 / @@bbrc.GetNoRootNodes().to_f
        features_smarts = Set.new
        features = Array.new
  
        # run @@bbrc
        
        # prepare to receive results as hash { c => [ [f,v], ... ] }
        fminer_results = {}

        (0 .. @@bbrc.GetNoRootNodes()-1).each do |j|
          results = @@bbrc.MineRoot(j)
          #task.progress 10+step_width*(j+1)
          results.each do |result|
            f = YAML.load(result)[0]
            smarts = f[0]
            p_value = f[1]
  
            if (!@@bbrc.GetRegression)
              id_arrs = f[2..-1].flatten
              max = OpenTox::Algorithm::Fminer.effect(f[2..-1].reverse, @@fminer.db_class_sizes) # f needs reversal for bbrc
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
  
            #feature_uri = File.join feature_dataset.uri,"feature","bbrc", features.size.to_s
            unless features_smarts.include? smarts
              features_smarts << smarts
              metadata = {
                OT.hasSource => to('/fminer/bbrc', :full),
                RDF.type => [OT.Feature, OT.Substructure, OT.NumericFeature],
                OT.smarts => smarts.dup,
                OT.pValue => p_value.to_f.abs.round(5),
                OT.effect => effect
              }
              feature = OpenTox::Feature.find_by_title(smarts.dup,metadata)
              features << feature
            end

            id_arrs.each { |id_count_hash|
              id=id_count_hash.keys[0].to_i
              count=id_count_hash.values[0].to_i
              fminer_results[@@fminer.compounds[id]] || fminer_results[@@fminer.compounds[id]] = {}
              if params[:nr_hits] == "true"
                fminer_results[@@fminer.compounds[id]][feature.uri] = count
              else
                fminer_results[@@fminer.compounds[id]][feature.uri] = 1
              end
            }
  
          end # end of
        end   # feature parsing

        fminer_compounds = @@fminer.training_dataset.compounds.collect.to_a
        @@fminer.training_dataset.build_feature_positions
        prediction_feature_idx = @@fminer.training_dataset.feature_positions[@@fminer.prediction_feature.uri]
        prediction_feature_all_acts = fminer_compounds.each_with_index.collect { |c,idx| 
          @@fminer.training_dataset.data_entries[idx][prediction_feature_idx] 
        }
        fminer_noact_compounds = fminer_compounds - @@fminer.compounds

        feature_dataset.features = features
        if (params[:get_target] == "true")
          feature_dataset.features = [ @@fminer.prediction_feature ] + feature_dataset.features
        end
        fminer_compounds.each_with_index { |c,idx|
          row = [ c ]
          if (params[:get_target] == "true")
            row = row + [ prediction_feature_all_acts[idx] ]
          end
          features.each { |f|
            row << (fminer_results[c] ? fminer_results[c][f.uri] : nil)
          }
          row.collect! { |v| v ? v : 0 } unless fminer_noact_compounds.include? c
          feature_dataset << row
        }
          
        $logger.debug "fminer found #{feature_dataset.features.size} features for #{feature_dataset.compounds.size} compounds"
        feature_dataset.put @subjectid
        $logger.debug feature_dataset.uri
        feature_dataset.uri

      end
      response['Content-Type'] = 'text/uri-list'
      service_unavailable_error "Service unavailable" if task.cancelled?
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
    #   - get_target Set to "true" to obtain target variable as feature
    # @return [text/uri-list] Task URI
    post '/fminer/last/?' do
    
      @@fminer=OpenTox::Algorithm::Fminer.new(to('/fminer/last',:full))
      @@fminer.check_params(params,80,@subjectid)
    
      task = OpenTox::Task.create( 
                                    $task[:uri], 
                                    @subjectid, 
                                    { RDF::DC.description => "Mining LAST features", 
                                      RDF::DC.creator => to('/fminer/last',:full) 
                                    } 
                                   ) do |task|

        @@last.Reset
        if @@fminer.prediction_feature.feature_type == "regression"
          @@last.SetRegression(true) # AM: DO NOT MOVE DOWN! Must happen before the other Set... operations!
        else
          bad_request_error "No accept values for "\
                          "dataset '#{fminer.training_dataset.uri}' and "\
                          "feature '#{fminer.prediction_feature.uri}'" unless 
                           @@fminer.prediction_feature.accept_values
          value_map=@@fminer.training_dataset.value_map(@@fminer.prediction_feature)
        end
        @@last.SetMinfreq(@@fminer.minfreq)
        @@last.SetType(1) if params[:feature_type] == "paths"
        @@last.SetConsoleOut(false)
  
  
        feature_dataset = OpenTox::Dataset.new(nil, @subjectid)
        feature_dataset.metadata = {
          DC.title => "LAST representatives for " + @@fminer.training_dataset.metadata[DC.title].to_s,
          DC.creator => to('/fminer/last',:full),
          OT.hasSource => to('/fminer/last', :full)
        }
        feature_dataset.parameters = [
            { DC.title => "dataset_uri", OT.paramValue => params[:dataset_uri] },
            { DC.title => "prediction_feature", OT.paramValue => params[:prediction_feature] },
            { DC.title => "min_frequency", OT.paramValue => @@fminer.minfreq },
            { DC.title => "nr_hits", OT.paramValue => (params[:nr_hits] == "true" ? "true" : "false") }
        ]
        
        @@fminer.compounds = []
        @@fminer.db_class_sizes = Array.new # AM: effect
        @@fminer.all_activities = Hash.new # DV: for effect calculation (class and regr)
        @@fminer.smi = [] # needed for matching the patterns back
  
        # Add data to fminer
        @@fminer.add_fminer_data(@@last, value_map)
        #task.progress 10
        step_width = 80 / @@bbrc.GetNoRootNodes().to_f
        # run @@last
        xml = ""
        (0 .. @@last.GetNoRootNodes()-1).each do |j|
          results = @@last.MineRoot(j)
          #task.progress 10+step_width*(j+1)
          results.each do |result|
            xml << result
          end
        end
  
        lu = LU.new                             # uses last-utils here
        dom=lu.read(xml)                        # parse GraphML
        smarts=lu.smarts_rb(dom,'nls')          # converts patterns to LAST-SMARTS using msa variant (see last-pm.maunz.de)
        params[:nr_hits] == "true" ? hit_count=true : hit_count=false
        matches, counts = lu.match_rb(@@fminer.smi,smarts,hit_count,true)       # creates instantiations

        features = []
        # prepare to receive results as hash { c => [ [f,v], ... ] }
        fminer_results = {}
        matches.each do |smarts, ids|
          metadata, parameters = @@fminer.calc_metadata(smarts, ids, counts[smarts], @@last, nil, value_map, params)
          feature = OpenTox::Feature.find_by_title(smarts.dup,metadata)
          features << feature
          ids.each_with_index { |id,idx| 
            fminer_results[@@fminer.compounds[id]] || fminer_results[@@fminer.compounds[id]] = {}
            fminer_results[@@fminer.compounds[id]][feature.uri] = counts[smarts][idx]
          }
        end

        fminer_compounds = @@fminer.training_dataset.compounds.collect.to_a
        @@fminer.training_dataset.build_feature_positions
        prediction_feature_idx = @@fminer.training_dataset.feature_positions[@@fminer.prediction_feature.uri]
        prediction_feature_all_acts = fminer_compounds.each_with_index.collect { |c,idx| 
          @@fminer.training_dataset.data_entries[idx][prediction_feature_idx] 
        }
        fminer_noact_compounds = fminer_compounds - @@fminer.compounds

        feature_dataset.features = features
        if (params[:get_target] == "true")
          feature_dataset.features = [ @@fminer.prediction_feature ] + feature_dataset.features
        end
        fminer_compounds.each_with_index { |c,idx|
          row = [ c ]
          if (params[:get_target] == "true")
            row = row + [ prediction_feature_all_acts[idx] ]
          end
          features.each { |f|
            row << (fminer_results[c] ? fminer_results[c][f.uri] : nil)
          }
          row.collect! { |v| v ? v : 0 } unless fminer_noact_compounds.include? c
          feature_dataset << row
        }
        feature_dataset.put @subjectid
        $logger.debug feature_dataset.uri
        feature_dataset.uri

      end
      response['Content-Type'] = 'text/uri-list'
      service_unavailable_error "Service unavailable" if task.cancelled?
      halt 202,task.uri.to_s+"\n"
    end

  end

end

