# dataset.rb
# Dataset library
# Author: Andreas Maunz

module OpenTox

  class Dataset

    # Find database activities and calculate a consens
    # @param [Hash] uri Compound URI, Feature URI
    # @return [Object] activity Database activity, or nil
    def database_activity(params)
      f=Feature.find(params[:prediction_feature_uri],params[:subjectid])
      db_act = find_data_entry(params[:compound_uri], params[:prediction_feature_uri])
      if db_act
        if f.feature_type == "classification"
          db_act = db_act.to_scale.mode.dup
        else
          db_act = db_act.to_scale.median
        end
        $logger.debug "Database activity for '#{params[:compound_uri]}': '#{db_act}'"
        db_act
      else
        nil
      end

    end

  end

end


