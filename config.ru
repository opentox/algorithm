SERVICE="algorithm"
require 'bundler'
Bundler.require
require './application.rb'
map "/algorithm" do
  run OpenTox::Application
end
