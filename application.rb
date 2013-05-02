# application.rb
# Loads sub-repositories, library code, and webapps.
# Author: Andreas Maunz
require 'statsample'

# Require sub-Repositories
require_relative 'libfminer/libbbrc/bbrc' # include before openbabel
require_relative 'libfminer/liblast/last' # 
require_relative 'last-utils/lu.rb'

# Library Code
$logger.debug "Algorithm booting: #{$algorithm.collect{ |k,v| "#{k}: '#{v}'"} }"
Dir['./lib/algorithm/*.rb'].each { |f| require f; also_reload f } # Libs
Dir['./lib/*.rb'].each { |f| require f; also_reload f } # Libs
Dir['./webapp/*.rb'].each { |f| require f; also_reload f } # Webapps
require_relative "descriptor.rb"
also_reload "descriptor.rb"
#Dir['./webapp/pc-descriptors.rb'].each { |f| require f; also_reload f } # Webapps

# Entry point
module OpenTox
  class Application < Service
  
    # for service check
    head '/?' do
      #$logger.debug "Algorithm service is running."
    end
    
    get '/?' do
      list = [ to('/lazar', :full), 
               to('/fminer/bbrc', :full), 
               to('/fminer/bbrc/sample', :full), 
               to('/fminer/last', :full), 
               to('/fminer/bbrc/match', :full), 
               to('/fminer/last/match', :full), 
               to('/fs/rfe', :full), 
               to('/descriptor') ].join("\n") + "\n"
      format_output (list)
    end
  end
end
