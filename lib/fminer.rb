module OpenTox

  class Algorithm

    # Fminer algorithms (https://github.com/amaunz/fminer2)
    class Fminer < Algorithm
      def initialize(uri)
        super uri
      end
    end

    # Backbone Refinement Class mining (http://bbrc.maunz.de/)
    class BBRC < Fminer
      def initialize(uri)
        super uri
      end
    end

    # LAtent STructure Pattern Mining (http://last-pm.maunz.de)
    class LAST < Fminer
      def initialize(uri)
        super uri
      end
    end

  end

end

