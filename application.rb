# application.rb
# Loads sub-repositories, library code, and webapps.
# Author: Andreas Maunz

# Require sub-Repositories
require File.join(File.expand_path(File.dirname(__FILE__)), 'libfminer/libbbrc/bbrc') # include before openbabel
require File.join(File.expand_path(File.dirname(__FILE__)), 'libfminer/liblast/last') # 
require File.join(File.expand_path(File.dirname(__FILE__)), 'last-utils/lu.rb')

# Library Code
$logger.debug "Algorithm booting: #{$algorithm.collect{ |k,v| "#{k}: '#{v}'"} }"
Dir['./lib/utils/shims/*.rb'].each { |f| require f } # Shims for legacy code
Dir['./lib/utils/*.rb'].each { |f| require f } # Utils for Libs
Dir['./lib/algorithm/*.rb'].each { |f| require f } # Libs
Dir['./lib/*.rb'].each { |f| require f } # Libs
Dir['./webapp/*.rb'].each { |f| require f } # Webapps

# Entry point
module OpenTox
  class Application < Service
    get '/?' do
      list = [ url_for('/lazar', :full), 
               url_for('/fminer/bbrc', :full), 
               url_for('/fminer/bbrc/sample', :full), 
               url_for('/fminer/last', :full), 
               url_for('/fminer/bbrc/match', :full), 
               url_for('/fminer/last/match', :full), 
               url_for('/fs/rfe', :full), 
               url_for('/pc', :full) ].join("\n") + "\n"
      format_output (list)
    end
  end
end
