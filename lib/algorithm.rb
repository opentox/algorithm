# algorithm.rb
# Algorithm library
# Author: Andreas Maunz

module OpenTox
  class Algorithm

    # Minimum Frequency
    # @param [Integer] per-mil value
    # return [Integer] min-frequency
    def self.min_frequency(training_dataset,per_mil)
      minfreq = per_mil * training_dataset.compounds.size.to_f / 1000.0 # AM sugg. 8-10 per mil for BBRC, 50 per mil for LAST
      minfreq = 2 unless minfreq > 2
      Integer (minfreq)
    end

    class Neighbors
    end

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
