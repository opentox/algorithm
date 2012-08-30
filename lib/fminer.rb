module OpenTox

  class Algorithm

    # Fminer algorithms (https://github.com/amaunz/fminer2)
    class Fminer < Algorithm
      attr_accessor :prediction_feature, :training_dataset, :minfreq, :compounds, :db_class_sizes, :all_activities, :smi

      def initialize(uri)
        super uri
      end

      def check_params(params,per_mil,subjectid=nil)
        bad_request_error "Please submit a dataset_uri." unless params[:dataset_uri] and  !params[:dataset_uri].nil?
        @training_dataset = OpenTox::Dataset.find "#{params[:dataset_uri]}", subjectid # AM: find is a shim
        #puts @training_dataset.features[0].class
        #puts @training_dataset.features[0].to_turtle
        #puts @training_dataset.features[0].metadata
        #puts @training_dataset.features[0].uri


        unless params[:prediction_feature] # try to read prediction_feature from dataset
          raise OpenTox::NotFoundError.new "Please provide a prediction_feature parameter" unless @training_dataset.features.size == 1
          prediction_feature = OpenTox::Feature.find(@training_dataset.features.first.uri,@subjectid)
          params[:prediction_feature] = prediction_feature.uri
        end
        @prediction_feature = OpenTox::Feature.find params[:prediction_feature], subjectid # AM: find is a shim

        resource_not_found_error "No feature '#{params[:prediction_feature]}' in dataset '#{params[:dataset_uri]}'" unless 
          @training_dataset.find_feature( params[:prediction_feature] ) # AM: find_feature is a shim

        unless params[:min_frequency].nil? 
          # check for percentage
          if params[:min_frequency].include? "pc"
            per_mil=params[:min_frequency].gsub(/pc/,"")
            if OpenTox::Algorithm.numeric? per_mil
              per_mil = per_mil.to_i * 10
            else
              bad_request=true
            end
          # check for per-mil
          elsif params[:min_frequency].include? "pm"
            per_mil=params[:min_frequency].gsub(/pm/,"")
            if OpenTox::Algorithm.numeric? per_mil
              per_mil = per_mil.to_i
            else
              bad_request=true
            end
          # set minfreq directly
          else
            if OpenTox::Algorithm.numeric? params[:min_frequency]
              @minfreq=params[:min_frequency].to_i
              $logger.debug "min_frequency #{@minfreq}"
            else
              bad_request=true
            end
          end
          raise OpenTox::BadRequestError.new "Minimum frequency must be integer [n], or a percentage [n]pc, or a per-mil [n]pm , with n greater 0" if bad_request
        end
        if @minfreq.nil?
          @minfreq=OpenTox::Algorithm.min_frequency(@training_dataset,per_mil)
          $logger.debug "min_frequency #{@minfreq} (input was #{per_mil} per-mil)"
        end
      end

    

    end

    # Backbone Refinement Class mining (http://bbrc.maunz.de/)
    class BBRC < Fminer
      def initialize(uri)
        super uri
      end
    end

    # LAtent STructure Pattern Mining (http://last-pm.maunz.de)
    class LAST < Fminer
      def initialize(uri)
        super uri
      end
    end

  end

end

