# algorithm.rb
# Algorithm library
# Author: Andreas Maunz

module OpenTox
  class Algorithm

    # Minimum Frequency
    # @param [Integer] per-mil value
    # return [Integer] min-frequency
    def self.min_frequency(training_dataset,per_mil)
      minfreq = per_mil * training_dataset.compounds.size.to_f / 1000.0 # AM sugg. 8-10 per mil for BBRC, 50 per mil for LAST
      minfreq = 2 unless minfreq > 2
      Integer (minfreq)
    end


    class Neighbors

      # Classification with majority vote from neighbors weighted by similarity
      # @param [Hash] params Keys `:acts, :sims, :value_map` are required
      # @return [Numeric] A prediction value.
      def self.weighted_majority_vote(params)

        neighbor_contribution = 0.0
        confidence_sum = 0.0
        confidence = 0.0
        prediction = nil

        $logger.debug "Weighted Majority Vote Classification."

        params[:acts].each_index do |idx|
          neighbor_weight = params[:sims][1][idx]
          neighbor_contribution += params[:acts][idx] * neighbor_weight
          if params[:value_map].size == 2 # AM: provide compat to binary classification: 1=>false 2=>true
            case params[:acts][idx]
            when 1
              confidence_sum -= neighbor_weight
            when 2
              confidence_sum += neighbor_weight
            end
          else
            confidence_sum += neighbor_weight
          end
        end
        if params[:value_map].size == 2 
          if confidence_sum >= 0.0
            prediction = 2 unless params[:acts].size==0
          elsif confidence_sum < 0.0
            prediction = 1 unless params[:acts].size==0
          end
        else 
          prediction = (neighbor_contribution/confidence_sum).round  unless params[:acts].size==0  # AM: new multinomial prediction
        end 

        $logger.debug "Prediction is: '" + prediction.to_s + "'." unless prediction.nil?
        confidence = (confidence_sum/params[:acts].size).abs if params[:acts].size > 0
        $logger.debug "Confidence is: '" + confidence.to_s + "'." unless prediction.nil?
        return {:prediction => prediction, :confidence => confidence.abs}
      end



      # Local support vector regression from neighbors 
      # @param [Hash] params Keys `:props, :acts, :sims, :min_train_performance` are required
      # @return [Numeric] A prediction value.
      def self.local_svm_regression(params)

        begin
          confidence = 0.0
          prediction = nil

          $logger.debug "Local SVM."
          if params[:acts].size>0
            if params[:props]
              n_prop = params[:props][0].collect
              q_prop = params[:props][1].collect
              props = [ n_prop, q_prop ]
            end
            acts = params[:acts].collect
            prediction = local_svm_prop( props, acts, params[:min_train_performance]) # params[:props].nil? signals non-prop setting
            prediction = nil if (!prediction.nil? && prediction.infinite?)
            $logger.debug "Prediction is: '" + prediction.to_s + "'."
            confidence = get_confidence({:sims => params[:sims][1], :acts => params[:acts]})
            confidence = 0.0 if prediction.nil?
          end
          {:prediction => prediction, :confidence => confidence}
        rescue Exception => e
          $logger.debug "#{e.class}: #{e.message}"
          $logger.debug "Backtrace:\n\t#{e.backtrace.join("\n\t")}"
        end

      end


      # Local support vector regression from neighbors 
      # @param [Hash] params Keys `:props, :acts, :sims, :min_train_performance` are required
      # @return [Numeric] A prediction value.
      def self.local_svm_classification(params)

        begin
          confidence = 0.0
          prediction = nil

          $logger.debug "Local SVM."
          if params[:acts].size>0
            if params[:props]
              n_prop = params[:props][0].collect
              q_prop = params[:props][1].collect
              props = [ n_prop, q_prop ]
            end
            acts = params[:acts].collect
            acts = acts.collect{|v| "Val" + v.to_s} # Convert to string for R to recognize classification
            prediction = local_svm_prop( props, acts, params[:min_train_performance]) # params[:props].nil? signals non-prop setting
            prediction = prediction.sub(/Val/,"") if prediction # Convert back to Float
            confidence = 0.0 if prediction.nil?
            $logger.debug "Prediction is: '" + prediction.to_s + "'."
            confidence = get_confidence({:sims => params[:sims][1], :acts => params[:acts]})
          end
          {:prediction => prediction, :confidence => confidence}
        rescue Exception => e
          $logger.debug "#{e.class}: #{e.message}"
          $logger.debug "Backtrace:\n\t#{e.backtrace.join("\n\t")}"
        end

      end



      # Local support vector prediction from neighbors. 
      # Uses propositionalized setting.
      # Not to be called directly (use local_svm_regression or local_svm_classification).
      # @param [Array] props, propositionalization of neighbors and query structure e.g. [ Array_for_q, two-nested-Arrays_for_n ]
      # @param [Array] acts, activities for neighbors.
      # @param [Float] min_train_performance, parameter to control censoring
      # @return [Numeric] A prediction value.
      def self.local_svm_prop(props, acts, min_train_performance)

        $logger.debug "Local SVM (Propositionalization / Kernlab Kernel)."
        n_prop = props[0] # is a matrix, i.e. two nested Arrays.
        q_prop = props[1] # is an Array.

        prediction = nil
        if Algorithm::zero_variance? acts
          prediction = acts[0]
        else
          #$logger.debug gram_matrix.to_yaml
          @r = RinRuby.new(true,false) # global R instance leads to Socket errors after a large number of requests
          @r.eval "suppressPackageStartupMessages(library('caret'))" # requires R packages "caret" and "kernlab"
          @r.eval "suppressPackageStartupMessages(library('doMC'))" # requires R packages "multicore"
          @r.eval "registerDoMC()" # switch on parallel processing
          @r.eval "set.seed(1)"
          begin

            # set data
            $logger.debug "Setting R data ..."
            @r.n_prop = n_prop.flatten
            @r.n_prop_x_size = n_prop.size
            @r.n_prop_y_size = n_prop[0].size
            @r.y = acts
            @r.q_prop = q_prop
            #@r.eval "y = matrix(y)"
            @r.eval "prop_matrix = matrix(n_prop, n_prop_x_size, n_prop_y_size, byrow=T)"
            @r.eval "q_prop = matrix(q_prop, 1, n_prop_y_size, byrow=T)"

            # prepare data
            $logger.debug "Preparing R data ..."
            @r.eval <<-EOR
              weights=NULL
              if (class(y) == 'character') { 
                y = factor(y)
                suppressPackageStartupMessages(library('class')) 
                #weights=unlist(as.list(prop.table(table(y))))
              }
            EOR

            @r.eval <<-EOR
              rem = nearZeroVar(prop_matrix)
              if (length(rem) > 0) {
                prop_matrix = prop_matrix[,-rem,drop=F]
                q_prop = q_prop[,-rem,drop=F]
              }
              rem = findCorrelation(cor(prop_matrix))
              if (length(rem) > 0) {
                prop_matrix = prop_matrix[,-rem,drop=F]
                q_prop = q_prop[,-rem,drop=F]
              }
            EOR

            # model + support vectors
            $logger.debug "Creating R SVM model ..."
            train_success = @r.eval <<-EOR
              # AM: TODO: evaluate class weight effect by altering:
              # AM: comment in 'weights' above run and class.weights=weights vs. class.weights=1-weights
              # AM: vs
              # AM: comment out 'weights' above (status quo), thereby disabling weights
              model = train(prop_matrix,y,
                             method="svmradial",
                             preProcess=c("center", "scale"),
                             class.weights=weights,
                             trControl=trainControl(method="LGOCV",number=10),
                             tuneLength=8
                           )
              perf = ifelse ( class(y)!='numeric', max(model$results$Accuracy), model$results[which.min(model$results$RMSE),]$Rsquared )
            EOR


            # prediction
            $logger.debug "Predicting ..."
            @r.eval "p = predict(model,q_prop)"
            @r.eval "if (class(y)!='numeric') p = as.character(p)"
            prediction = @r.p

            # censoring
            prediction = nil if ( @r.perf.nan? || @r.perf < min_train_performance )
            prediction = nil unless train_success
            $logger.debug "Performance: #{sprintf("%.2f", @r.perf)}"
          rescue Exception => e
            $logger.debug "#{e.class}: #{e.message}"
            $logger.debug "Backtrace:\n\t#{e.backtrace.join("\n\t")}"
          end
          @r.quit # free R
        end
        prediction
      end

    end 



    class Similarity

      # Tanimoto similarity
      # @param [Hash, Array] fingerprints of first compound
      # @param [Hash, Array] fingerprints of second compound
      # @return [Float] (Weighted) tanimoto similarity
      
      def self.tanimoto(fingerprints_a,fingerprints_b,weights=nil,params=nil)
        common_p_sum = 0.0
        all_p_sum = 0.0
        size = [ fingerprints_a.size, fingerprints_b.size ].min
        $logger.warn "fingerprints don't have equal size" if fingerprints_a.size != fingerprints_b.size
        (0...size).each { |idx|
          common_p_sum += [ fingerprints_a[idx], fingerprints_b[idx] ].min
          all_p_sum += [ fingerprints_a[idx], fingerprints_b[idx] ].max
        }
        (all_p_sum > 0.0) ? (common_p_sum/all_p_sum) : 0.0
      end



      # Cosine similarity
      # @param [Hash] properties_a key-value properties of first compound
      # @param [Hash] properties_b key-value properties of second compound
      # @return [Float] cosine of angle enclosed between vectors induced by keys present in both a and b
      def self.cosine(fingerprints_a,fingerprints_b,weights=nil)

        # fingerprints are hashes
        if fingerprints_a.class == Hash && fingerprints_b.class == Hash
          a = []; b = []
          common_features = fingerprints_a.keys & fingerprints_b.keys
          if common_features.size > 1
            common_features.each do |p|
              a << fingerprints_a[p]
              b << fingerprints_b[p]
            end
          end

        # fingerprints are arrays
        elsif fingerprints_a.class == Array && fingerprints_b.class == Array
          a = fingerprints_a
          b = fingerprints_b
        end

        (a.size > 0 && b.size > 0) ? self.cosine_num(a.to_gv, b.to_gv) : 0.0

      end

      # Cosine similarity
      # @param [GSL::Vector] a
      # @param [GSL::Vector] b
      # @return [Float] cosine of angle enclosed between a and b
      def self.cosine_num(a, b)
        if a.size>12 && b.size>12
          a = a[0..11]
          b = b[0..11]
        end
        a.dot(b) / (a.norm * b.norm)
      end

    end


    class FeatureValues
      # Substructure matching
      # @param [Hash] keys: compound, features, values: OpenTox::Compound, Array of SMARTS strings
      # @return [Array] Array with matching Smarts
      def self.match(params)
        params[:compound].match(params[:features])
      end

      # Substructure matching with number of non-unique hits
      # @param [Hash] keys: compound, features, values: OpenTox::Compound, Array of SMARTS strings
      # @return [Hash] Hash with matching Smarts and number of hits 
      def self.match_hits(params)
        params[:compound].match_hits(params[:features])
      end
    end

  end
end
