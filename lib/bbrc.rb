module OpenTox
  module Algorithm
    class Fminer
      #
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

        time = Time.now

        @bbrc = Bbrc::Bbrc.new
        @bbrc.Reset
        if @fminer.prediction_feature.feature_type == "regression"
          @bbrc.SetRegression(true) # AM: DO NOT MOVE DOWN! Must happen before the other Set... operations!
        else
          bad_request_error "No accept values for "\
                            "dataset '#{@fminer.training_dataset.id}' and "\
                            "feature '#{@fminer.prediction_feature.id}'" unless 
                             @fminer.prediction_feature.accept_values
          value_map=@fminer.prediction_feature.value_map
        end
        @bbrc.SetMinfreq(@fminer.minfreq)
        @bbrc.SetType(1) if params[:feature_type] == "paths"
        @bbrc.SetBackbone(false) if params[:backbone] == "false"
        @bbrc.SetChisqSig(params[:min_chisq_significance].to_f) if params[:min_chisq_significance]
        @bbrc.SetConsoleOut(false)

        feature_dataset = OpenTox::CalculatedDataset.new
        feature_dataset.title = "BBRC representatives"
        feature_dataset.creator = __FILE__
        feature_dataset.parameters = [
            { "title" => "dataset_id", "paramValue" => params[:dataset].id },
            { "title" => "prediction_feature_id", "paramValue" => params[:prediction_feature].id },
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
        #features_smarts = Set.new
        features = []
        data_entries = Array.new(params[:dataset].compounds.size) {[]}

        $logger.debug "Setup: #{Time.now-time}"
        time = Time.now
        ftime = 0
  
        # run @bbrc
        
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
            feature = OpenTox::Feature.find_or_create_by({
              "title" => smarts.dup,
              "numeric" => true,
              "substructure" => true,
              "smarts" => smarts.dup,
              "pValue" => p_value.to_f.abs.round(5),
              "effect" => effect,
              "parameters" => [
                { "title" => "dataset_id", "paramValue" => params[:dataset].id },
                { "title" => "prediction_feature_id", "paramValue" => params[:prediction_feature].id }
              ]
            })
            features << feature
            ftime += Time.now - ft

            id_arrs.each { |id_count_hash|
              id=id_count_hash.keys[0].to_i
              count=id_count_hash.values[0].to_i
              fminer_results[@fminer.compounds[id]] || fminer_results[@fminer.compounds[id]] = {}
              compound_idx = params[:dataset].compounds.index @fminer.compounds[id] 
              feature_idx = features.index feature
              data_entries[compound_idx] ||= []
              if params[:nr_hits] == "true"
                fminer_results[@fminer.compounds[id]][feature] = count
                data_entries[compound_idx][feature_idx] = count
              else
                fminer_results[@fminer.compounds[id]][feature] = 1
                data_entries[compound_idx][feature_idx] = 1
              end
            }
  
          end # end of
        end   # feature parsing

        $logger.debug "Fminer: #{Time.now-time} (find/create Features: #{ftime})"
        time = Time.now

        # convert nil entries to 0
        data_entries.collect! do |r| 
          if r.empty? 
            Array.new(features.size,0) 
          else
            r[features.size-1] = 0 if r.size < features.size # grow array to match feature size
            r.collect!{|c| c.nil? ? 0 : c} # remove nils
          end
        end

        feature_dataset.compounds = params[:dataset].compounds
        feature_dataset.features = features
        feature_dataset.data_entries = data_entries

        $logger.debug "Prepare save: #{Time.now-time}"
        time = Time.now
        #File.open("kazius.json","w+"){|f| f.puts feature_dataset.inspect}
        feature_dataset.save

        $logger.debug "Save: #{Time.now-time}"
        feature_dataset
  
      end
    end
  end
end
