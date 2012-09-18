# feature_values.rb
# Feature Value library
# Author: Andreas Maunz

module OpenTox
  class Algorithm

    class FeatureValues
      # Substructure matching
      # @param [Hash] keys: compound, features, values: OpenTox::Compound, Array of SMARTS strings
      # @return [Array] Array with matching Smarts
      def self.match(params)
        params[:compound].match(params[:features])
      end

      # Substructure matching with number of non-unique hits
      # @param [Hash] keys: compound, features, values: OpenTox::Compound, Array of SMARTS strings
      # @return [Hash] Hash with matching Smarts and number of hits 
      def self.match_hits(params)
        params[:compound].match_hits(params[:features])
      end
    end

  end
end
