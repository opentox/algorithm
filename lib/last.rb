module OpenTox
  module Algorithm
    class Fminer

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
      def self.last params
    
        @fminer=OpenTox::Algorithm::Fminer.new
        @fminer.check_params(params,80)
      
        # TODO introduce task again
        #task = OpenTox::Task.run("Mining LAST features", uri('/fminer/last')) do |task|

          @last = Last::Last.new
          @last.Reset
          if @fminer.prediction_feature.feature_type == "regression"
            @last.SetRegression(true) # AM: DO NOT MOVE DOWN! Must happen before the other Set... operations!
          else
            bad_request_error "No accept values for "\
                            "dataset '#{fminer.training_dataset.id}' and "\
                            "feature '#{fminer.prediction_feature.id}'" unless 
                             @fminer.prediction_feature.accept_values
            value_map=@fminer.prediction_feature.value_map
          end
          @last.SetMinfreq(@fminer.minfreq)
          @last.SetType(1) if params[:feature_type] == "paths"
          @last.SetConsoleOut(false)
    
    
          feature_dataset = OpenTox::CalculatedDataset.new
          feature_dataset["title"] = "LAST representatives for #{@fminer.training_dataset.title}",
          feature_dataset.creator = __FILE__
          feature_dataset.parameters = [
              { "title" => "dataset_id", "paramValue" => params[:dataset].id },
              { "title" => "prediction_feature_id", "paramValue" => params[:prediction_feature].id },
              { "title" => "min_frequency", "paramValue" => @fminer.minfreq },
              { "title" => "nr_hits", "paramValue" => (params[:nr_hits] == "true" ? "true" : "false") }
          ]
          
          @fminer.compounds = []
          @fminer.db_class_sizes = Array.new # AM: effect
          @fminer.all_activities = Hash.new # DV: for effect calculation (class and regr)
          @fminer.smi = [] # needed for matching the patterns back
    
          # Add data to fminer
          @fminer.add_fminer_data(@last, value_map)
          #task.progress 10
          #step_width = 80 / @bbrc.GetNoRootNodes().to_f
          # run @last
          xml = ""
          (0 .. @last.GetNoRootNodes()-1).each do |j|
            results = @last.MineRoot(j)
            #task.progress 10+step_width*(j+1)
            results.each do |result|
              xml << result
            end
          end
    
          lu = LU.new                             # uses last-utils here
          dom=lu.read(xml)                        # parse GraphML
          smarts=lu.smarts_rb(dom,'nls')          # converts patterns to LAST-SMARTS using msa variant (see last-pm.maunz.de)
          params[:nr_hits] == "true" ? hit_count=true : hit_count=false
          matches, counts = lu.match_rb(@fminer.smi,smarts,hit_count,true)       # creates instantiations

          features = []
          # create table with correct size
          data_entries = Array.new(params[:dataset].compounds.size) {Array.new(matches.size,0)}
          matches.each do |smarts, ids|
            metadata = @fminer.calc_metadata(smarts, ids, counts[smarts], @last, nil, value_map, params)
            feature = OpenTox::Feature.find_or_create_by(metadata)
            features << feature
            ids.each_with_index do |id,idx| 
              compound_idx = params[:dataset].compounds.index @fminer.compounds[id] 
              feature_idx = features.index feature
              data_entries[compound_idx] ||= []
              data_entries[compound_idx][feature_idx] = counts[smarts][idx]
            end
          end
          feature_dataset.compounds = @fminer.training_dataset.compounds
          feature_dataset.features = features
          feature_dataset.data_entries = data_entries

=begin
          # TODO check if this code is necessary, I dont understand what it does
          fminer_compounds = @fminer.training_dataset.compounds
          prediction_feature_idx = @fminer.training_dataset.features.index @fminer.prediction_feature
          prediction_feature_all_acts = fminer_compounds.each_with_index.collect { |c,idx| 
            @fminer.training_dataset.data_entries[idx][prediction_feature_idx] 
          }
          fminer_noact_compounds = fminer_compounds - @fminer.compounds

          if (params[:get_target] == "true")
            feature_dataset.features = [ @fminer.prediction_feature ] + feature_dataset.features
          end
          fminer_compounds.each_with_index { |c,idx|
            # TODO: fix value insertion
            row = [ c ]
            if (params[:get_target] == "true")
              row = row + [ prediction_feature_all_acts[idx] ]
            end
            features.each { |f|
              row << (fminer_results[c] ? fminer_results[c][f] : nil)
            }
            row.collect! { |v| v ? v : 0 } unless fminer_noact_compounds.include? c
            feature_dataset << row
          }
=end
          
          feature_dataset.save
          feature_dataset

      #  end
      end

    end
  end
end

