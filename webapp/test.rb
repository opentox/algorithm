#for testing the error handling

module OpenTox
  class Application < Service
    
    post '/test/wait_for_error_in_task/?' do
      task = OpenTox::Task.create($task[:uri],@subjectid,{ RDF::DC.description => "wait_for_error_in_task"}) do |task|
        sleep 1
        uri = OpenTox::Dataset.new(File.join($dataset[:uri],'test/error_in_task')).post
      end
      response['Content-Type'] = 'text/uri-list'
      halt 202,task.uri.to_s+"\n"  
    end

  end
end
