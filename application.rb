require 'opentox-server'
require File.join(File.expand_path(File.dirname(__FILE__)), 'libfminer/libbbrc/bbrc') # include before openbabel
require File.join(File.expand_path(File.dirname(__FILE__)), 'libfminer/liblast/last') # 
require File.join(File.expand_path(File.dirname(__FILE__)), 'last-utils/lu.rb')

#require 'openbabel.rb'
#require 'fminer.rb'
#require 'lazar.rb'
#require 'feature_selection.rb'

module OpenTox
  class Application < Service
    helpers do
      def uri_list 
        uris = [ url_for('/lazar', :full), url_for('/fminer/bbrc', :full), url_for('/fminer/last', :full), url_for('/feature_selection/rfe', :full) ]
        uris.compact.sort.join("\n") + "\n"
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
