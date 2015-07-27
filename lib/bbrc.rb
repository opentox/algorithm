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

        table_of_elements = [
"H", "He", "Li", "Be", "B", "C", "N", "O", "F", "Ne", "Na", "Mg", "Al", "Si", "P", "S", "Cl", "Ar", "K", "Ca", "Sc", "Ti", "V", "Cr", "Mn", "Fe", "Co", "Ni", "Cu", "Zn", "Ga", "Ge", "As", "Se", "Br", "Kr", "Rb", "Sr", "Y", "Zr", "Nb", "Mo", "Tc", "Ru", "Rh", "Pd", "Ag", "Cd", "In", "Sn", "Sb", "Te", "I", "Xe", "Cs", "Ba", "La", "Ce", "Pr", "Nd", "Pm", "Sm", "Eu", "Gd", "Tb", "Dy", "Ho", "Er", "Tm", "Yb", "Lu", "Hf", "Ta", "W", "Re", "Os", "Ir", "Pt", "Au", "Hg", "Tl", "Pb", "Bi", "Po", "At", "Rn", "Fr", "Ra", "Ac", "Th", "Pa", "U", "Np", "Pu", "Am", "Cm", "Bk", "Cf", "Es", "Fm", "Md", "No", "Lr", "Rf", "Db", "Sg", "Bh", "Hs", "Mt", "Ds", "Rg", "Cn", "Uut", "Fl", "Uup", "Lv", "Uus", "Uuo"]
        
        @fminer=OpenTox::Algorithm::Fminer.new
        @fminer.check_params(params,5)

        time = Time.now

        @bbrc = Bbrc::Bbrc.new
        @bbrc.Reset
        if @fminer.prediction_feature.numeric 
          @bbrc.SetRegression(true) # AM: DO NOT MOVE DOWN! Must happen before the other Set... operations!
        else
          bad_request_error "No accept values for "\
                            "dataset '#{@fminer.training_dataset.id}' and "\
                            "feature '#{@fminer.prediction_feature.id}'" unless @fminer.prediction_feature.accept_values
          value_map = @fminer.prediction_feature.accept_values.each_index.inject({}) { |h,idx| h[idx+1]=@fminer.prediction_feature.accept_values[idx]; h }
        end
        @bbrc.SetMinfreq(@fminer.minfreq)
        @bbrc.SetType(1) if params[:feature_type] == "paths"
        @bbrc.SetBackbone(false) if params[:backbone] == "false"
        @bbrc.SetChisqSig(params[:min_chisq_significance].to_f) if params[:min_chisq_significance]
        @bbrc.SetConsoleOut(false)

        feature_dataset = FminerDataset.new(
            :training_dataset_id => params[:dataset].id,
            :training_algorithm => "#{self.to_s}.bbrc",
            :training_feature_id => params[:prediction_feature].id ,
            :training_parameters => {
              :min_frequency => @fminer.minfreq,
              :nr_hits => (params[:nr_hits] == "true" ? "true" : "false"),
              :backbone => (params[:backbone] == "false" ? "false" : "true") 
            }

        )
        feature_dataset.compounds = params[:dataset].compounds

        @fminer.compounds = []
        @fminer.db_class_sizes = Array.new # AM: effect
        @fminer.all_activities = Hash.new # DV: for effect calculation in regression part
        @fminer.smi = [] # AM LAST: needed for matching the patterns back
  
        # Add data to fminer
        @fminer.add_fminer_data(@bbrc, value_map)
        g_median=@fminer.all_activities.values.to_scale.median

        #task.progress 10
        #step_width = 80 / @bbrc.GetNoRootNodes().to_f
        features = []
        feature_ids = []
        matches = {}

        $logger.debug "Setup: #{Time.now-time}"
        time = Time.now
        ftime = 0
        itime = 0
        rtime = 0
  
        # run @bbrc
        (0 .. @bbrc.GetNoRootNodes()-1).each do |j|
          results = @bbrc.MineRoot(j)
          results.each do |result|
            rt = Time.now
            f = YAML.load(result)[0]
            smarts = f.shift
            # convert fminer representation into a more human readable format
            smarts.gsub!(%r{\[#(\d+)&(\w)\]}) do
             element = table_of_elements[$1.to_i-1]
             $2 == "a" ? element.downcase : element
            end
            p_value = f.shift
  
=begin
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
=end
            rtime += Time.now - rt
  
            ft = Time.now
            feature = OpenTox::FminerSmarts.find_or_create_by({
              "smarts" => smarts,
              "pValue" => p_value.to_f.abs.round(5),
              #"effect" => effect,
              "dataset_id" => feature_dataset.id
            })
            feature_dataset.add_feature feature
            feature_ids << feature.id.to_s
            ftime += Time.now - ft

            it = Time.now
            f.first.each do |id_count_hash|
              id_count_hash.each do |id,count|
                matches[@fminer.compounds[id].id.to_s] = {feature.id.to_s => count}
              end
            end
            itime += Time.now - it
  
          end
        end

        $logger.debug "Fminer: #{Time.now-time} (read: #{rtime}, iterate: #{itime}, find/create Features: #{ftime})"
        time = Time.now

        n = 0
        feature_dataset.compound_ids.each do |cid|
          cid = cid.to_s
          feature_dataset.feature_ids.each_with_index do |fid,i|
            fid = fid.to_s
            unless matches[cid] and matches[cid][fid]# fminer returns only matches
              count = 0
            else
              count = matches[cid][fid]
            end
            feature_dataset.bulk << [cid,fid,count]
            n +=1
          end
        end

        $logger.debug "Prepare save: #{Time.now-time}"
        time = Time.now
        feature_dataset.bulk_write
        feature_dataset.save

        $logger.debug "Save: #{Time.now-time}"
        feature_dataset
  
      end
    end
  end
end
