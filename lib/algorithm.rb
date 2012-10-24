=begin
* Name: algorithm.rb
* Description: General algorithms
* Author: Andreas Maunz <andreas@maunz.de>
* Date: 10/2012
=end

module OpenTox
  class Algorithm

    # Minimum Frequency
    # @param [Integer] per-mil value
    # return [Integer] min-frequency
    def self.min_frequency(training_dataset,prediction_feature,per_mil)
      nr_labeled_cmpds=0
      training_dataset.build_feature_positions
      f_idx=training_dataset.feature_positions[prediction_feature.uri]
      training_dataset.compounds.each_with_index { |cmpd, c_idx|
        if ( training_dataset.data_entries[c_idx] )
             unless training_dataset.data_entries[c_idx][f_idx].nil?
               nr_labeled_cmpds += 1 
             end
        end
      }
      minfreq = per_mil * nr_labeled_cmpds.to_f / 1000.0 # AM sugg. 8-10 per mil for BBRC, 50 per mil for LAST
      minfreq = 2 unless minfreq > 2
      Integer (minfreq)
    end

  end
end
