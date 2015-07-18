ENV['FMINER_SMARTS'] = 'true'
ENV['FMINER_NO_AROMATIC'] = 'true'
ENV['FMINER_PVALUES'] = 'true'
ENV['FMINER_SILENT'] = 'true'
ENV['FMINER_NR_HITS'] = 'true'

module OpenTox
  module Algorithm
    class Fminer
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
      def self.bbrc params
        
        @fminer=OpenTox::Algorithm::Fminer.new
        @fminer.check_params(params,5)
      
        #task = OpenTox::Task.run("Mining BBRC features", __FILE__ ) do |task|

          time = Time.now

          @bbrc = Bbrc::Bbrc.new
          @bbrc.Reset
          if @fminer.prediction_feature.feature_type == "regression"
            @bbrc.SetRegression(true) # AM: DO NOT MOVE DOWN! Must happen before the other Set... operations!
          else
            bad_request_error "No accept values for "\
                              "dataset '#{@fminer.training_dataset.uri}' and "\
                              "feature '#{@fminer.prediction_feature.uri}'" unless 
                               @fminer.prediction_feature.accept_values
            value_map=@fminer.prediction_feature.value_map
          end
          @bbrc.SetMinfreq(@fminer.minfreq)
          @bbrc.SetType(1) if params[:feature_type] == "paths"
          @bbrc.SetBackbone(false) if params[:backbone] == "false"
          @bbrc.SetChisqSig(params[:min_chisq_significance].to_f) if params[:min_chisq_significance]
          @bbrc.SetConsoleOut(false)

          feature_dataset = OpenTox::Dataset.new
          feature_dataset.title = "BBRC representatives"
          feature_dataset.creator = __FILE__
          feature_dataset.parameters = [
              { "title" => "dataset_id", "paramValue" => params[:dataset].id },
              { "title" => "prediction_feature", "paramValue" => params[:prediction_feature].id },
              { "title" => "min_frequency", "paramValue" => @fminer.minfreq },
              { "title" => "nr_hits", "paramValue" => (params[:nr_hits] == "true" ? "true" : "false") },
              { "title" => "backbone", "paramValue" => (params[:backbone] == "false" ? "false" : "true") }
          ] 

          @fminer.compounds = []
          @fminer.db_class_sizes = Array.new # AM: effect
          @fminer.all_activities = Hash.new # DV: for effect calculation in regression part
          @fminer.smi = [] # AM LAST: needed for matching the patterns back
    
          # Add data to fminer
          @fminer.add_fminer_data(@bbrc, value_map)
          g_median=@fminer.all_activities.values.to_scale.median

          #task.progress 10
          step_width = 80 / @bbrc.GetNoRootNodes().to_f
          features_smarts = Set.new
          features = Array.new

          puts "Setup: #{Time.now-time}"
          time = Time.now
          ftime = 0
    
          # run @bbrc
          
          # prepare to receive results as hash { c => [ [f,v], ... ] }
          fminer_results = {}

          (0 .. @bbrc.GetNoRootNodes()-1).each do |j|
            results = @bbrc.MineRoot(j)
            #task.progress 10+step_width*(j+1)
            results.each do |result|
              f = YAML.load(result)[0]
              smarts = f[0]
              p_value = f[1]
    
              if (!@bbrc.GetRegression)
                id_arrs = f[2..-1].flatten
                max = OpenTox::Algorithm::Fminer.effect(f[2..-1].reverse, @fminer.db_class_sizes) # f needs reversal for bbrc
                effect = max+1
              else #regression part
                id_arrs = f[2]
                # DV: effect calculation
                f_arr=Array.new
                f[2].each do |id|
                  id=id.keys[0] # extract id from hit count hash
                  f_arr.push(@fminer.all_activities[id])
                end
                f_median=f_arr.to_scale.median
                if g_median >= f_median
                  effect = 'activating'
                else
                  effect = 'deactivating'
                end
              end
    
              ft = Time.now
              unless features_smarts.include? smarts
                features_smarts << smarts
                feature = OpenTox::Feature.find_or_create_by({
                  "title" => smarts.dup,
                  "numeric" => true,
                  "substructure" => true,
                  "smarts" => smarts.dup,
                  "pValue" => p_value.to_f.abs.round(5),
                  "effect" => effect
                })
                features << feature
              end
              ftime += Time.now - ft

              id_arrs.each { |id_count_hash|
                id=id_count_hash.keys[0].to_i
                count=id_count_hash.values[0].to_i
                fminer_results[@fminer.compounds[id]] || fminer_results[@fminer.compounds[id]] = {}
                if params[:nr_hits] == "true"
                  fminer_results[@fminer.compounds[id]][feature] = count
                else
                  fminer_results[@fminer.compounds[id]][feature] = 1
                end
              }
    
            end # end of
          end   # feature parsing


          puts "Fminer: #{Time.now-time} (find/create Features: #{ftime})"
          time = Time.now
          puts JSON.pretty_generate(fminer_results)

          fminer_compounds = @fminer.training_dataset.compounds
          prediction_feature_idx = @fminer.training_dataset.features.index @fminer.prediction_feature
          prediction_feature_all_acts = fminer_compounds.each_with_index.collect { |c,idx| 
            @fminer.training_dataset.data_entries[idx][prediction_feature_idx] 
          }
          fminer_noact_compounds = fminer_compounds - @fminer.compounds

          feature_dataset.features = features
          feature_dataset.features = [ @fminer.prediction_feature ] + feature_dataset.features if params[:get_target] == "true"
          feature_dataset.compounds = fminer_compounds
          fminer_compounds.each_with_index { |c,idx|
            # TODO: reenable option
            #if (params[:get_target] == "true")
              #row = row + [ prediction_feature_all_acts[idx] ]
            #end
            features.each { |f|
              v = fminer_results[c][f.uri] if fminer_results[c] 
              unless fminer_noact_compounds.include? c
                v = 0 if v.nil?
              end
              feature_dataset.add_data_entry c, f, v.to_i
            }
          }

          puts "Prepare save: #{Time.now-time}"
          time = Time.now
          feature_dataset.save

          puts "Save: #{Time.now-time}"
          feature_dataset

    
        end
      #end
    end
  end
end
    


