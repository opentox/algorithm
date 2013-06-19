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
Dir['./lib/*.rb'].each { |f| require f; also_reload f } # Libs
#Dir['./lib/descriptor.rb'].each { |f| require f; also_reload f } # Libs
Dir['./*.rb'].each { |f| require_relative f; also_reload f } # Webapps

# Entry point
module OpenTox
  class Application < Service
    get '/?' do
      list = [ to('/lazar', :full), 
               to('/fminer/bbrc', :full), 
               #to('/fminer/bbrc/sample', :full), 
               to('/fminer/last', :full), 
               #to('/fminer/bbrc/match', :full), 
               #to('/fminer/last/match', :full), 
               to('/feature-selection/recursive-feature-elimination', :full), 
               to('/descriptor') ].join("\n") + "\n"
      render list
    end
  end
end
