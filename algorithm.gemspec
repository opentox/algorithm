# -*- encoding: utf-8 -*-
$:.push File.expand_path("../lib", __FILE__)

Gem::Specification.new do |s|
  s.name        = "opentox-algorithm"
  s.version     = File.read("./VERSION")
  s.authors     = ["Christoph Helma"]
  s.email       = ["helma@in-silico.ch"]
  s.homepage    = "http://github.com/opentox/algorithm"
  s.summary     = %q{OpenTox Algorithm Service}
  s.description = %q{OpenTox Algorithm Service}
  s.license     = 'GPL-3'

  s.rubyforge_project = "algorithm"

  s.files         = `git ls-files`.split("\n")
  s.required_ruby_version = '>= 1.9.2'

  # specify any dependencies here; for example:
  s.add_runtime_dependency "opentox-server"
  s.add_runtime_dependency "opentox-client"
  s.add_runtime_dependency 'rinruby'#, "~>2.0.2"
  s.add_runtime_dependency 'nokogiri'#, "~>1.4.4"
  s.add_runtime_dependency 'statsample'#, "~>1.1"
  s.add_runtime_dependency 'gsl'#, "~>1.14"
  s.add_runtime_dependency "openbabel"#, "~>2.3.1.5"
  s.post_install_message = "Please configure your service in ~/.opentox/config/algorithm.rb"
end
