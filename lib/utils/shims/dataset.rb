# Shims for translation to the new architecture (TM).
# Author: Andreas Maunz, 2012

module OpenTox

  # Shims for the Dataset Class
  class Dataset

    # Load a dataset from URI
    # @param [String] Dataset URI
    # @return [OpenTox::Dataset] Dataset object
    def self.find(uri, subjectid=nil)
      return nil unless uri
      ds = OpenTox::Dataset.new uri, subjectid
      ds.get
      ds
    end

    # Search a dataset for a given feature by URI
    # @param [String] Feature URI
    # @return [OpenTox::Feature] Feature object, or nil if not present
    def find_feature(uri)
      res = @features.collect { |f| f.uri == uri ? f : nil }.compact
      internal_server_error "Duplicate Feature '#{uri}' in dataset '#{@uri}'" if res.size > 1
      res.size > 0 ? res[0] : nil
    end

    # Create value map
    def value_map(feature)
      training_classes = feature.accept_values
      value_map={}
      training_classes.each_with_index { |c,i| value_map[i+1] = c }
      value_map
    end

  end


end
