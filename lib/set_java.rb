# Contains Java settings.
# Joelib runs on Java.
# Author: Andreas Maunz, 2012

ENV["JAVA_HOME"] = "/usr/lib/jvm/java-6-sun" unless ENV["JAVA_HOME"]
ENV["JOELIB2"] = File.join File.expand_path(File.dirname(__FILE__)),"java"
deps = []
deps << "#{ENV["JAVA_HOME"]}/lib/tools.jar"
deps << "#{ENV["JAVA_HOME"]}/lib/classes.jar"
deps << "#{ENV["JOELIB2"]}"
jars = Dir[ENV["JOELIB2"]+"/*.jar"].collect {|f| File.expand_path(f) }
deps = deps + jars
ENV["CLASSPATH"] = deps.join(":")
