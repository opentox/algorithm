require 'opentox-server'
require File.join(File.expand_path(File.dirname(__FILE__)), 'libfminer/libbbrc/bbrc') # include before openbabel
require File.join(File.expand_path(File.dirname(__FILE__)), 'libfminer/liblast/last') # 
require File.join(File.expand_path(File.dirname(__FILE__)), 'last-utils/lu.rb')

module OpenTox
  class Application < Service
    helpers do
      def uri_list 
        "I have loaded native extensions for libbrc, liblast and openbabel right now!.\n\n My load path is: #{$LOAD_PATH} \n\nI have loaded #{$LOADED_FEATURES.size} objects.\n"
      end 
    end

    get '/?' do
      case @accept
      when 'text/uri-list'
        response['Content-Type'] = 'text/uri-list'
        uri_list
      else
        response['Content-Type'] = 'application/rdf+xml'
        uri_list
      end
    end

  end
end
