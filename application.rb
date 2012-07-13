# Java Klimbim
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


# fminer libs to be included before openbabel, otherwise strange SWIG overloading problems
require File.join(File.expand_path(File.dirname(__FILE__)), 'libfminer/libbbrc/bbrc') 
require File.join(File.expand_path(File.dirname(__FILE__)), 'libfminer/liblast/last')
require File.join(File.expand_path(File.dirname(__FILE__)), 'last-utils/lu.rb')

gem "opentox-ruby", "~> 4"
require 'opentox-ruby'
require 'rjb'
require 'rinruby'


# main
require 'fminer.rb'
require 'lazar.rb'
require 'fs.rb'
require 'pc.rb'

set :lock, true

before do
	LOGGER.debug "Request: " + request.path
end

# Get a list of available algorithms
#
# @return [text/uri-list] algorithm URIs
get '/?' do
	list = [ url_for('/lazar', :full), url_for('/fminer/bbrc', :full), url_for('/fminer/bbrc/sample', :full), url_for('/fminer/last', :full), url_for('/fminer/bbrc/match', :full), url_for('/fminer/last/match', :full), url_for('/feature_selection/rfe', :full), url_for('/pc', :full) ].join("\n") + "\n"
  case request.env['HTTP_ACCEPT']
  when /text\/html/
    content_type "text/html"
    OpenTox.text_to_html list,@subjectid
  else
    content_type 'text/uri-list'
    list
  end
end
