module OpenTox

  module Algorithm 

    def self.run algorithm, arg1, arg2 #parameters
      klass,method = algorithm.split('.')
      Object.const_get(klass).send(method, arg1,arg2)
    end

  end
end

