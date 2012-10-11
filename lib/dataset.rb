# dataset.rb
# Dataset library
# Author: Andreas Maunz

module OpenTox

  class Dataset

    # Find database activities and store them in @prediction_dataset
    # @param [Hash] Compound URI, Feature URI
    # @return [Boolean] true if compound has databasse activities, false if not
    def database_activity(prediction_dataset, params)
      f=Feature.find(params[:prediction_feature_uri],params[:subjectid])
      db_act = find_data_entry(params[:compound_uri], params[:prediction_feature_uri])
      if db_act
        if f.feature_type == "classification"
          db_act = db_act.to_scale.mode.dup
        else
          db_act = db_act.to_scale.median
        end
        prediction_dataset.features = [ f ]
        prediction_dataset << [ OpenTox::Compound.new(params[:compound_uri]), db_act ]
        $logger.debug "Database activity for '#{params[:compound_uri]}': '#{db_act}'"
        true
      else
        false
      end

    end

  end

end


