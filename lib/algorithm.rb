module OpenTox

  module Algorithm 

    def self.run algorithm, object, parameters={}
      klass,method = algorithm.split('.')
      parameters.empty? ?  Object.const_get(klass).send(method,object) : Object.const_get(klass).send(method,object, parameters)
    end

  end
end

