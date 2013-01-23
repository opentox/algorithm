=begin
* Name: neighbors.rb
* Description: Prediction algorithms library
* Author: Andreas Maunz <andreas@maunz.de>
* Date: 10/2012
=end

module OpenTox
  class Algorithm
    
    class Neighbors

      # Get confidence.
      # @param[Hash] Required keys: :sims, :acts
      # @return[Float] Confidence
      def self.get_confidence(params)
        conf = params[:sims].inject{|sum,x| sum + x }
        confidence = conf/params[:sims].size
        #$logger.debug "Confidence: '" + confidence.to_s + "'."
        return confidence
      end

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

        #$logger.debug "Prediction: '" + prediction.to_s + "'." unless prediction.nil?
        confidence = (confidence_sum/params[:acts].size).abs if params[:acts].size > 0
        #$logger.debug "Confidence: '" + confidence.to_s + "'." unless prediction.nil?
        return {:prediction => prediction, :confidence => confidence.abs}
      end



      # Local support vector regression from neighbors 
      # @param [Hash] params Keys `:props, :acts, :sims, :min_train_performance` are required
      # @return [Numeric] A prediction value.
      def self.local_svm_regression(params)

        confidence = 0.0
        prediction = nil

        $logger.debug "Local SVM."
        if params[:acts].size>0
          if params[:props]
            n_prop = params[:props][0].collect.to_a
            q_prop = params[:props][1].collect.to_a
            props = [ n_prop, q_prop ]
          end
          acts = params[:acts].collect.to_a
          prediction = local_svm_prop( props, acts, params[:min_train_performance]) # params[:props].nil? signals non-prop setting
          prediction = nil if (!prediction.nil? && prediction.infinite?)
          #$logger.debug "Prediction: '" + prediction.to_s + "' ('#{prediction.class}')."
          confidence = get_confidence({:sims => params[:sims][1], :acts => params[:acts]})
          confidence = 0.0 if prediction.nil?
        end
        {:prediction => prediction, :confidence => confidence}

      end


      # Local support vector regression from neighbors 
      # @param [Hash] params Keys `:props, :acts, :sims, :min_train_performance` are required
      # @return [Numeric] A prediction value.
      def self.local_svm_classification(params)

        confidence = 0.0
        prediction = nil

        $logger.debug "Local SVM."
        if params[:acts].size>0
          if params[:props]
            n_prop = params[:props][0].collect.to_a
            q_prop = params[:props][1].collect.to_a
            props = [ n_prop, q_prop ]
          end
          acts = params[:acts].collect.to_a
          acts = acts.collect{|v| "Val" + v.to_s} # Convert to string for R to recognize classification
          prediction = local_svm_prop( props, acts, params[:min_train_performance]) # params[:props].nil? signals non-prop setting
          prediction = prediction.sub(/Val/,"") if prediction # Convert back
          confidence = 0.0 if prediction.nil?
          #$logger.debug "Prediction: '" + prediction.to_s + "' ('#{prediction.class}')."
          confidence = get_confidence({:sims => params[:sims][1], :acts => params[:acts]})
        end
        {:prediction => prediction, :confidence => confidence}

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
        if acts.uniq.size == 1
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
              if (!(class(y) == 'numeric')) { 
                y = factor(y)
                suppressPackageStartupMessages(library('class')) 
                weights=unlist(as.list(prop.table(table(y))))
                weights=(weights-1)^2
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
            @r.eval "predict(model,q_prop); p = predict(model,q_prop)" # kernlab bug: predict twice
            @r.eval "if (class(y)!='numeric') p = as.character(p)"
            prediction = @r.p

            # censoring
            prediction = nil if ( @r.perf.nan? || @r.perf < min_train_performance.to_f )
            prediction = nil if prediction =~ /NA/
            prediction = nil unless train_success
            $logger.debug "Performance: '#{sprintf("%.2f", @r.perf)}'"
          #rescue Exception => e
            #$logger.debug "#{e.class}: #{e.message}"
            #$logger.debug "Backtrace:\n\t#{e.backtrace.join("\n\t")}"
          ensure
            @r.quit # free R
          end
        end
        prediction
      end

    end 

  end
end
