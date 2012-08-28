module OpenTox

  class Algorithm

    # Generic algorithms
    class Generic < Algorithm
      def initialize(uri)
        super uri
      end
    end

    def metadata=(hsh) 
      hsh.each {|k,v|
        self[k]=v
      }
    end

  end
end
