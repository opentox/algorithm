=begin
* Name: dataset.rb
* Description: Dataset algorithms
* Author: Andreas Maunz <andreas@maunz.de>
* Date: 10/2012
=end

module OpenTox
  class Dataset

    # Find database activities and calculate a consens
    # @param [Hash] uri Compound URI, Feature URI
    # @return [Object] activity Database activity, or nil
    def database_activity(params)
      f=Feature.new params[:prediction_feature_uri], @subjectid
      db_act = values(Compound.new(params[:compound_uri], @subjectid), f)
      if !db_act.empty?
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

