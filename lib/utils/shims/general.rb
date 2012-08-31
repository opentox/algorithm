# Shims for translation to the new architecture (TM).
# Author: Andreas Maunz, 2012

# This avoids having to prefix everything with "RDF::" (e.g. "RDF::DC").
# So that we can use our old code mostly as is.
include RDF

module OpenTox

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
