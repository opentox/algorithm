module OpenTox
  module Algorithm
    
    class Classification

      # Classification with majority vote from neighbors weighted by similarity
      # @param [Hash] params Keys `:activities, :sims, :value_map` are required
      # @return [Numeric] A prediction value.
      def self.weighted_majority_vote(neighbors)

        return {:prediction => nil, :confidence => nil} if neighbors.empty?

        neighbor_contribution = 0.0
        confidence_sum = 0.0
        confidence = 0.0
        prediction = nil

        $logger.debug "Weighted Majority Vote Classification."

        values = neighbors.collect{|n| n[1]}.uniq
        neighbors.each do |neighbor|
          neighbor_weight = neighbor[2]
          activity = values.index(neighbor[1]) + 1 # map values to integers > 1
          neighbor_contribution += activity * neighbor_weight
          if values.size == 2 # AM: provide compat to binary classification: 1=>false 2=>true
            case activity
            when 1
              confidence_sum -= neighbor_weight
            when 2
              confidence_sum += neighbor_weight
            end
          else
            confidence_sum += neighbor_weight
          end
        end
        if values.size == 2 
          if confidence_sum >= 0.0
            prediction = values[1]
          elsif confidence_sum < 0.0
            prediction = values[0] 
          end
        else 
          prediction = (neighbor_contribution/confidence_sum).round  # AM: new multinomial prediction
        end 

        $logger.debug "Prediction: '" + prediction.to_s + "'." unless prediction.nil?
        confidence = (confidence_sum/neighbors.size).abs 
        $logger.debug "Confidence: '" + confidence.to_s + "'." unless prediction.nil?
        return {:prediction => prediction, :confidence => confidence.abs}
      end

    end

  end
end

