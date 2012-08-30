# Shims for translation to the new architecture (TM).
# Author: Andreas Maunz, 2012

module OpenTox

  # Shims for the feature class
  class Feature

    # Load a feature from URI
    # @param [String] Feature URI
    # @return [OpenTox::Feature] Feature object with the full data
    def self.find(uri, subjectid=nil)
      return nil unless uri
      f = OpenTox::Feature.new uri, subjectid
      f.get
      f
    end

    # Find out feature type
    # Classification takes precedence
    # @return [String] Feature type
    def feature_type
      bad_request_error "rdf type of feature '#{@uri}' not set" unless self[RDF.type]
      if self[RDF.type].include?(OT.NominalFeature)
        "classification"
      elsif [RDF.type].to_a.flatten.include?(OT.NumericFeature)
        "regression"
      else
        "unknown"
      end
    end

    # Get accept values
    # @param[String] Feature URI
    # @return[Array] Accept values
    def accept_values
      accept_values = self[OT.acceptValue]
      accept_values.sort if accept_values
      accept_values
    end

  end

end
