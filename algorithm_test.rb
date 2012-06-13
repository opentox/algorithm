require "rubygems"
require "sinatra"
before {
  request.env['HTTP_HOST']="local-ot/algorithm"
  request.env["REQUEST_URI"]=request.env["PATH_INFO"]
}

require "opentox-ruby"
ENV['RACK_ENV'] = 'test'
require 'application.rb'
require 'test/unit'
require 'rack/test'
LOGGER = Logger.new(STDOUT)
LOGGER.datetime_format = "%Y-%m-%d %H:%M:%S "
  
module Sinatra
  
  set :raise_errors, false
  set :show_exceptions, false

  module UrlForHelper
    BASE = "http://local-ot/algorithm"
    def url_for url_fragment, mode=:path_only
      case mode
      when :path_only
        raise "not impl"
      when :full
      end
      "#{BASE}#{url_fragment}"
    end
  end
end

class AlgorithmTest < Test::Unit::TestCase
  include Rack::Test::Methods
  
  def app
    Sinatra::Application
  end
  
  def test_prediction
    
    begin
      
      #dataset_uri = "http://apps.ideaconsult.net:8080/ambit2/dataset/603204?pagesize=100&page=0"
      #test_dataset_uri = "http://apps.ideaconsult.net:8080/ambit2/dataset/603204?pagesize=100&page=1"
      #feature_dataset_uri = "http://apps.ideaconsult.net:8080/ambit2/dataset/603204?pagesize=200&page=0"
      #prediction_feature = "http://apps.ideaconsult.net:8080/ambit2/feature/528321"
      
     # dataset_uri = "http://apps.ideaconsult.net:8080/ambit2/dataset/425254"
     # prediction_feature = "http://apps.ideaconsult.net:8080/ambit2/feature/528321"
      
      ##dataset_uri = "http://local-ot/dataset/1488"
      #prediction_feature = "http://local-ot/dataset/1315/feature/Rodent%20carcinogenicity"
      
      #kazius 250 no features
      dataset_uri = "http://local-ot/dataset/9264"
      prediction_feature = dataset_uri+"/feature/endpoint"
      feature_dataset_uri = "http://local-ot/dataset/91409"
      
      params = {:dataset_uri=>dataset_uri,
                :prediction_feature=>prediction_feature,
                :min_frequency=>7, :max_num_features=>300} #multi: 10=>4, 5=>>3000
      
      
#      params = {:dataset_uri=>dataset_uri,
#        :prediction_feature=>prediction_feature, :feature_dataset_uri=>feature_dataset_uri}
#      post "/lazar",params
      
      #post "/fminer/bbrc",params
      #uri = wait_for_task(last_response.body)
      #puts uri
      
      #puts OpenTox::RestClientWrapper.post(File.join(CONFIG[:services]["opentox-algorithm"],"fminer/bbrc"),params)
      
#      model = uri
#      puts "model #{model}"
#      params = {:dataset_uri=>test_dataset_uri}
#      puts OpenTox::RestClientWrapper.post(model,params)
      
      #puts "features: "+OpenTox::Dataset.find(uri).features.size.to_s
     
      feature_dataset_uri="http://opentox.informatik.uni-freiburg.de/dataset/3277"
      dataset_uri="http://opentox.informatik.uni-freiburg.de/dataset/1333"

      params = {:dataset_uri=>dataset_uri,
        :feature_dataset_uri=>feature_dataset_uri}
      #post "/fminer/bbrc/match",params
      #uri = wait_for_task(last_response.body)
      
      puts OpenTox::RestClientWrapper.post(File.join(CONFIG[:services]["opentox-algorithm"],"fminer/bbrc/match"),params)
      
#      puts uri
      
#      fminer = File.join(CONFIG[:services]["opentox-algorithm"],"fminer/bbrc")
#      OpenTox::RestClientWrapper.post(fminer,params)
      
#      params = {:dataset_uri=>"http://local-ot/dataset/1488",
#        :prediction_feature=>"http://local-ot/dataset/1315/feature/Rodent%20carcinogenicity",
#        :min_frequency=>50}
#      post "/lazar",params
#      uri = wait_for_task(last_response.body)
#      puts uri
      #puts "features: "+OpenTox::Dataset.find(uri).features.size.to_s
      
   #  fminer = File.join(CONFIG[:services]["opentox-algorithm"],"fminer/bbrc")
   #  OpenTox::RestClientWrapper.post(fminer,params)
     
   rescue => ex
     rep = OpenTox::ErrorReport.create(ex, "")
     puts rep.to_yaml
   end 
    
    #get "/lazar",nil,'HTTP_ACCEPT' => "application/rdf+xml"
    #get "/fminer",nil,'HTTP_ACCEPT' => "application/rdf+xml" 
    #OpenTox::Algorithm.Generic.find("http://localhost/algorithm/lazar")
    
  #  puts last_response.body
    
#    webservice = "http://ot.algorithm.de/lazar"
#    headers = {:dataset_uri=>"http://ot.dataset.de/2", 
#      :prediction_feature=>"http://localhost/toxmodel/feature%23Hamster%20Carcinogenicity%20(DSSTOX/CPDB)", 
#      :feature_generation_uri=>"http://ot.algorithm.de/fminer"}
#    
#    #puts OpenTox::RestClientWrapper.post(webservice,headers)
#    post webservice,headers
#    #puts 
#    uri = wait_for_task(last_response.body.to_s)
#    puts uri
#    puts OpenTox::RestClientWrapper.get(uri,:accept => 'application/rdf+xml')
#    #get uri
    
  end
  
      # see test_util.rb
  def wait_for_task(uri)
      if uri.task_uri?
        task = OpenTox::Task.find(uri)
        task.wait_for_completion
        raise "task failed: "+uri.to_s if task.error?
        uri = task.result_uri
      end
      return uri
    end
  
  
  
end