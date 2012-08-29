# Require sub-Repositories
require File.join(File.expand_path(File.dirname(__FILE__)), 'libfminer/libbbrc/bbrc') # include before openbabel
require File.join(File.expand_path(File.dirname(__FILE__)), 'libfminer/liblast/last') # 
require File.join(File.expand_path(File.dirname(__FILE__)), 'last-utils/lu.rb')

# Library Code (Backend Classes)
libs = ['fminer', 'generic', 'utils/diag', 'utils/java', 'utils/html', 'utils/workarounds']
libs.each { |lib| require "./lib/#{lib}.rb" }

# Service Components (Sinatra Routes)
services = ['fminer', 'fs', 'pc', 'sinatra'] 
services.each { |lib| require "./webapp/#{lib}.rb" }

module OpenTox
  class Application < Service

    # get implementation
    get '/algorithm/?' do
      list = [ url_for('/algorithm/lazar', :full), 
               url_for('/algorithm/fminer/bbrc', :full), 
               url_for('/algorithm/fminer/bbrc/sample', :full), 
               url_for('/algorithm/fminer/last', :full), 
               url_for('/algorithm/fminer/bbrc/match', :full), 
               url_for('/algorithm/fminer/last/match', :full), 
               url_for('/algorithm/fs/rfe', :full), 
               url_for('/algorithm/pc', :full) ].join("\n") + "\n"
      format_output (list)
    end

  end
end
