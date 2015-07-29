=begin
* Name: similarity.rb
* Description: Similarity algorithms
* Author: Andreas Maunz <andreas@maunz.de
* Date: 10/2012
=end

module OpenTox
  module Algorithm

    class Similarity

      # Tanimoto similarity
      # @param [Array] a fingerprints of first compound
      # @param [Array] b fingerprints of second compound
      # @return [Float] Tanimoto similarity
      def self.tanimoto(a,b)
        #a = fingerprints.first
        #b = fingerprints.last
        common_p_sum = 0.0
        all_p_sum = 0.0
        size = [ a.size, b.size ].min
        $logger.warn "fingerprints don't have equal size" if a.size != b.size
        (0...size).each { |idx|
          common_p_sum += [ a[idx].to_f, b[idx].to_f ].min
          all_p_sum += [ a[idx].to_f, b[idx].to_f ].max
        }
        (all_p_sum > 0.0) ? (common_p_sum/all_p_sum) : 0.0
      end


      # Cosine similarity
      # @param [Array] a fingerprints of first compound
      # @param [Array] b fingerprints of second compound
      # @return [Float] Cosine similarity, the cosine of angle enclosed between vectors a and b
      def self.cosine(a, b)
        val = 0.0
        if a.size>0 and b.size>0
          if a.size>12 && b.size>12
            a = a[0..11]
            b = b[0..11]
          end
          a_vec = a.to_gv
          b_vec = b.to_gv
          val = a_vec.dot(b_vec) / (a_vec.norm * b_vec.norm)
        end
        val
      end

    end

  end
end
