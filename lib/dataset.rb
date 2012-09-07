# dataset.rb
# Dataset library
# Author: Andreas Maunz

module OpenTox

  class Dataset

    # Find database activities and store them in @prediction_dataset
    # @param [Hash] Compound URI, Feature URI
    # @return [Boolean] true if compound has databasse activities, false if not
    def database_activity(params)
      db_act = find_data_entry(params[:compound_uri], params[:feature_uri])
      if db_act
        f=Feature.find(params[:feature_uri],params[:subjectid])
        if f.feature_type="classification"
          db_act = value_map(f).invert[db_act]
        end
        prediction_dataset.features = [ f ]
        prediction_dataset << [ OpenTox::Compound.new(compound_uri), db_act ]
        prediction_dataset.put(params[:subjectid])
        $logger.debug "Database activity #{prediction_dataset.uri}"
        true
      else
        false
      end

    end

  end

end


