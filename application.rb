# application.rb
# Loads sub-repositories, library code, and webapps.
# Author: Andreas Maunz

# Require sub-Repositories
require File.join(File.expand_path(File.dirname(__FILE__)), 'libfminer/libbbrc/bbrc') # include before openbabel
require File.join(File.expand_path(File.dirname(__FILE__)), 'libfminer/liblast/last') # 
require File.join(File.expand_path(File.dirname(__FILE__)), 'last-utils/lu.rb')

# Library Code
$logger.debug "Algorithm booting: #{$algorithm.collect{ |k,v| "#{k}: '#{v}'"} }"
Dir['./lib/algorithm/*.rb'].each { |f| require f } # Libs
Dir['./lib/*.rb'].each { |f| require f } # Libs
Dir['./webapp/*.rb'].each { |f| require f } # Webapps

# Entry point
module OpenTox
  class Application < Service
    get '/?' do
      list = [ to('/lazar', :full), 
               to('/fminer/bbrc', :full), 
               to('/fminer/bbrc/sample', :full), 
               to('/fminer/last', :full), 
               to('/fminer/bbrc/match', :full), 
               to('/fminer/last/match', :full), 
               to('/fs/rfe', :full), 
               to('/pc', :full) ].join("\n") + "\n"
      format_output (list)
    end
  end
end
