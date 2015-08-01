module OpenTox

  module Algorithm 

    def self.run algorithm, object, parameters={}
      bad_request_error "Cannot run '#{algorithm}' algorithm. Please provide an OpenTox::Algorithm." unless algorithm =~ /^OpenTox::Algorithm/
      klass,method = algorithm.split('.')
      parameters.empty? ?  Object.const_get(klass).send(method,object) : Object.const_get(klass).send(method,object, parameters)
    end

  end
end

