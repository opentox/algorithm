module OpenTox

  class Algorithm

    # Generic algorithms
    class Generic < Algorithm
      def initialize(uri)
        super uri
      end
    end

    # Help function to provide the metadata= functionality.
    # Downward compatible to opentox-ruby.
    # @param [Hash] Key-Value pairs with the metadata
    # @return self
    def metadata=(hsh) 
      hsh.each {|k,v|
        self[k]=v
      }
    end

  end
end
