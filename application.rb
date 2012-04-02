ENV["JAVA_HOME"] = "/usr/lib/jvm/java-6-sun" unless ENV["JAVA_HOME"]
ENV["JOELIB2"] = File.join File.expand_path(File.dirname(__FILE__)),"java"
deps = []
deps << "#{ENV["JAVA_HOME"]}/lib/tools.jar"
deps << "#{ENV["JAVA_HOME"]}/lib/classes.jar"
deps << "#{ENV["JOELIB2"]}"
jars = Dir[ENV["JOELIB2"]+"/*.jar"].collect {|f| File.expand_path(f) }
deps = deps + jars
ENV["CLASSPATH"] = deps.join(":")


require 'rubygems'
# AM LAST: can include both libs, no problems
require File.join(File.expand_path(File.dirname(__FILE__)), 'libfminer/libbbrc/bbrc') # has to be included before openbabel, otherwise we have strange SWIG overloading problems
require File.join(File.expand_path(File.dirname(__FILE__)), 'libfminer/liblast/last') # has to be included before openbabel, otherwise we have strange SWIG overloading problems
require File.join(File.expand_path(File.dirname(__FILE__)), 'last-utils/lu.rb') # AM LAST
gem "opentox-ruby", "~> 3"
require 'opentox-ruby'

#require 'smarts.rb'
#require 'similarity.rb'
require 'openbabel.rb'
require 'fminer.rb'
require 'lazar.rb'
require 'feature_selection.rb'

set :lock, true

before do
	LOGGER.debug "Request: " + request.path
end

# Get a list of available algorithms
#
# @return [text/uri-list] algorithm URIs
get '/?' do
	list = [ url_for('/lazar', :full), url_for('/fminer/bbrc', :full), url_for('/fminer/last', :full), url_for('/feature_selection/rfe', :full) ].join("\n") + "\n"
  case request.env['HTTP_ACCEPT']
  when /text\/html/
    content_type "text/html"
    OpenTox.text_to_html list,@subjectid
  else
    content_type 'text/uri-list'
    list
  end
end
