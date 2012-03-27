require 'opentox-server'
require File.join(File.expand_path(File.dirname(__FILE__)), 'libfminer/libbbrc/bbrc') # include before openbabel
require File.join(File.expand_path(File.dirname(__FILE__)), 'libfminer/liblast/last') # 
require File.join(File.expand_path(File.dirname(__FILE__)), 'last-utils/lu.rb')

module OpenTox
  class Application < Service
    helpers do
      def uri_list 
        "Gesendet von localhost:8080, der die Ruby-Bindings von libbrc, liblast und openbabel erfolgreich geladen hat.\nUnd tschuess.\n"
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
