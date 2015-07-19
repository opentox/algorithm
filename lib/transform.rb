=begin
* Name: transform.rb
* Description: Transformation algorithms
* Author: Andreas Maunz <andreas@maunz.de
* Date: 10/2012
=end

module OpenTox
  module Algorithm

    class Transform
    # Uses Statsample Library (http://ruby-statsample.rubyforge.org/) by C. Bustos
    
      # Auto-Scaler for GSL vectors.
      # Center on mean and divide by standard deviation.
      class AutoScale 
        attr_accessor :vs, :mean, :stdev

        # @param [GSL::Vector] values Values to transform using AutoScaling.
        def initialize values
          bad_request_error "Cannot transform, values empty." if values.size==0
          vs = values.clone
          @mean = vs.to_scale.mean
          @stdev = vs.to_scale.standard_deviation_population
          @stdev = 0.0 if @stdev.nan? 
          @vs = transform vs
        end

        # @param [GSL::Vector] values Values to transform.
        # @return [GSL::Vector] transformed values.
        def transform values
          bad_request_error "Cannot transform, values empty." if values.size==0
          autoscale values.clone
        end

        # @param [GSL::Vector] values Values to restore.
        # @return [GSL::Vector] transformed values.
        def restore values
          bad_request_error "Cannot transform, values empty." if values.size==0
          rv_ss = values.clone.to_scale * @stdev unless @stdev == 0.0
          (rv_ss + @mean).to_gsl
        end

        # @param [GSL::Vector] values to transform.
        # @return [GSL::Vector] transformed values.
        def autoscale values
          vs_ss = values.clone.to_scale - @mean
          @stdev == 0.0 ? vs_ss.to_gsl : ( vs_ss * ( 1 / @stdev) ).to_gsl
        end

      end


      # Principal Components Analysis.
      class PCA
        attr_accessor :data_matrix, :data_transformed_matrix, :eigenvector_matrix, :eigenvalue_sums, :autoscaler

        # Creates a transformed dataset as GSL::Matrix.
        #
        # @param [GSL::Matrix] data_matrix Data matrix.
        # @param [Float] compression Compression ratio from [0,1], default 0.05.
        # @return [GSL::Matrix] Data transformed matrix.
        def initialize data_matrix, compression=0.05, maxcols=(1.0/0.0)

          @data_matrix = data_matrix.clone
          @compression = compression.to_f
          @mean = Array.new
          @autoscaler = Array.new
          @cols = Array.new
          @maxcols = maxcols

          # Objective Feature Selection
          bad_request_error "Error! PCA needs at least two dimensions." if data_matrix.size2 < 2
          @data_matrix_selected = nil
          (0..@data_matrix.size2-1).each { |i|
            if !@data_matrix.col(i).to_a.zero_variance?
              if @data_matrix_selected.nil?
                @data_matrix_selected = GSL::Matrix.alloc(@data_matrix.size1, 1) 
                @data_matrix_selected.col(0)[0..@data_matrix.size1-1] = @data_matrix.col(i)
              else
                @data_matrix_selected = @data_matrix_selected.horzcat(GSL::Matrix.alloc(@data_matrix.col(i).to_a,@data_matrix.size1, 1))
              end
              @cols << i
            end             
          }
          bad_request_error "Error! PCA needs at least two dimensions." if (@data_matrix_selected.nil? || @data_matrix_selected.size2 < 2)

          # PCA uses internal centering on 0
          @data_matrix_scaled = GSL::Matrix.alloc(@data_matrix_selected.size1, @cols.size)
          (0..@cols.size-1).each { |i|
            as = OpenTox::Algorithm::Transform::AutoScale.new(@data_matrix_selected.col(i))
            @data_matrix_scaled.col(i)[0..@data_matrix.size1-1] = as.vs * as.stdev # re-adjust by stdev
            @mean << as.mean
            @autoscaler << as
          }

          # PCA
          data_matrix_hash = Hash.new
          (0..@cols.size-1).each { |i|
            column_view = @data_matrix_scaled.col(i)
            data_matrix_hash[i] = column_view.to_scale
          }
          dataset_hash = data_matrix_hash.to_dataset # see http://goo.gl/7XcW9
          cor_matrix=Statsample::Bivariate.correlation_matrix(dataset_hash)
          pca=Statsample::Factor::PCA.new(cor_matrix)

          # Select best eigenvectors
          pca.eigenvalues.each { |ev| bad_request_error "PCA failed!" unless !ev.nan? }
          @eigenvalue_sums = Array.new
          (0..@cols.size-1).each { |i|
            @eigenvalue_sums << pca.eigenvalues[0..i].inject{ |sum, ev| sum + ev }
          }
          eigenvectors_selected = Array.new
          pca.eigenvectors.each_with_index { |ev, i|
            if (@eigenvalue_sums[i] <= ((1.0-@compression)*@cols.size)) || (eigenvectors_selected.size == 0)
              eigenvectors_selected << ev.to_a unless @maxcols <= eigenvectors_selected.size
            end
          }
          @eigenvector_matrix = GSL::Matrix.alloc(eigenvectors_selected.flatten, eigenvectors_selected.size, @cols.size).transpose
          @data_transformed_matrix = (@eigenvector_matrix.transpose * @data_matrix_scaled.transpose).transpose

        end

        # Transforms data to feature space found by PCA.
        #
        # @param [GSL::Matrix] values Data matrix.
        # @return [GSL::Matrix] Transformed data matrix.
        def transform values
          vs = values.clone
          bad_request_error "Error! Too few columns for transformation." if vs.size2 < @cols.max
          data_matrix_scaled = GSL::Matrix.alloc(vs.size1, @cols.size)
          @cols.each_with_index { |i,j|
            data_matrix_scaled.col(j)[0..data_matrix_scaled.size1-1] = @autoscaler[j].transform(vs.col(i).to_a) * @autoscaler[j].stdev
          }
          (@eigenvector_matrix.transpose * data_matrix_scaled.transpose).transpose
        end

        # Restores data in the original feature space (possibly with compression loss).
        #
        # @return [GSL::Matrix] Data matrix.
        def restore
          data_matrix_restored = (@eigenvector_matrix * @data_transformed_matrix.transpose).transpose # reverse pca
          # reverse scaling
          (0..@cols.size-1).each { |i|
            data_matrix_restored.col(i)[0..data_matrix_restored.size1-1] += @mean[i]
          }
          data_matrix_restored
        end

      end


      # Singular Value Decomposition
      class SVD
        attr_accessor :data_matrix, :compression, :data_transformed_matrix, :uk, :vk, :eigk, :eigk_inv

        # Creates a transformed dataset as GSL::Matrix.
        #
        # @param [GSL::Matrix] data_matrix Data matrix
        # @param [Float] compression Compression ratio from [0,1], default 0.05
        # @return [GSL::Matrix] Data transformed matrix

        def initialize data_matrix, compression=0.05
          @data_matrix = data_matrix.clone
          @compression = compression

          # Compute the SV Decomposition X=USV
          # vt is *not* the transpose of V here, but V itself (see http://goo.gl/mm2xz)!
          u, vt, s = data_matrix.SV_decomp 
          
          # Determine cutoff index
          s2 = s.mul(s) ; s2_sum = s2.sum
          s2_run = 0
          k = s2.size - 1
          s2.to_a.reverse.each { |v| 
            s2_run += v
            frac = s2_run / s2_sum
            break if frac > compression
            k -= 1
          }
          k += 1 if k == 0 # avoid uni-dimensional (always cos sim of 1)
          
          # Take the k-rank approximation of the Matrix
          #   - Take first k columns of u
          #   - Take first k columns of vt
          #   - Take the first k eigenvalues
          @uk = u.submatrix(nil, (0..k)) # used to transform column format data
          @vk = vt.submatrix(nil, (0..k)) # used to transform row format data
          s = GSL::Matrix.diagonal(s)
          @eigk = s.submatrix((0..k), (0..k))
          @eigk_inv = @eigk.inv

          # Transform data
          @data_transformed_matrix = @uk # = u for all SVs
          # NOTE: @data_transformed_matrix is also equal to
          # @data_matrix * @vk * @eigk_inv

        end


        # Transforms data instance (1 row) to feature space found by SVD.
        #
        # @param [GSL::Matrix] values Data matrix (1 x m).
        # @return [GSL::Matrix] Transformed data matrix.
        def transform_instance values
          values * @vk * @eigk_inv
        end
        alias :transform :transform_instance # make this the default (see PCA interface)

        # Transforms data feature (1 column) to feature space found by SVD.
        #
        # @param [GSL::Matrix] values Data matrix (1 x n).
        # @return [GSL::Matrix] Transformed data matrix.
        def transform_feature values
          values * @uk * @eigk_inv
        end


        # Restores data in the original feature space (possibly with compression loss).
        #
        # @return [GSL::Matrix] Data matrix.
        def restore
          @data_transformed_matrix * @eigk * @vk.transpose  # reverse svd
        end


      end



      # Attaches transformations to an OpenTox::Model
      # Stores props, sims, performs similarity calculations
      class ModelTransformer
        attr_accessor :model, :similarity_algorithm, :activities, :sims

        # @params[OpenTox::Model] model Model to transform
        def initialize model
          @model = model
        end

        # Transforms the model
        def transform
          get_matrices # creates @n_prop, @q_prop, @activities from ordered fingerprints
          @ids = (0..((@n_prop.length)-1)).to_a # surviving compounds; become neighbors

          if (@model.similarity_algorithm =~ /cosine/)
            # truncate nil-columns and -rows
            $logger.debug "O: #{@n_prop.size}x#{@n_prop[0].size}; R: #{@q_prop.size}"
            while @q_prop.size>0
              idx = @q_prop.index(nil)
              break if idx.nil?
              @q_prop.slice!(idx)
              @n_prop.each { |r| r.slice!(idx) }
            end
            $logger.debug "Q: #{@n_prop.size}x#{@n_prop[0].size}; R: #{@q_prop.size}"
            remove_nils  # removes nil cells (for cosine); alters @n_props, @q_props, cuts down @ids to survivors
            $logger.debug "M: #{@n_prop.size}x#{@n_prop[0].size}; R: #{@q_prop.size}"

            # adjust rest
            #fingerprints_tmp = []; @ids.each { |idx| fingerprints_tmp << @fingerprints[idx] }; @fingerprints = fingerprints_tmp
            compounds_tmp = []; @ids.each { |idx| compounds_tmp << @compounds[idx] }; @compounds = compounds_tmp
            acts_tmp = []; @ids.each { |idx| acts_tmp << @activities[idx] }; @activities = acts_tmp

            # scale and svd
            nr_cases, nr_features = @n_prop.size, @n_prop[0].size
            gsl_n_prop = GSL::Matrix.alloc(@n_prop.flatten, nr_cases, nr_features); gsl_n_prop_orig = gsl_n_prop.clone # make backup
            gsl_q_prop = GSL::Matrix.alloc(@q_prop.flatten, 1, nr_features); gsl_q_prop_orig = gsl_q_prop.clone # make backup
            (0...nr_features).each { |i|
               autoscaler = OpenTox::Algorithm::Transform::AutoScale.new(gsl_n_prop.col(i))
               gsl_n_prop.col(i)[0..nr_cases-1] = autoscaler.vs
               gsl_q_prop.col(i)[0..0] = autoscaler.transform gsl_q_prop.col(i)
            }
            svd = OpenTox::Algorithm::Transform::SVD.new(gsl_n_prop, 0.0)
            @n_prop = svd.data_transformed_matrix.to_a
            @q_prop = svd.transform(gsl_q_prop).row(0).to_a
            $logger.debug "S: #{@n_prop.size}x#{@n_prop[0].size}; R: #{@q_prop.size}"
          else
            convert_nils # convert nil cells (for tanimoto); leave @n_props, @q_props, @ids untouched
          end

          # neighbor calculation
          @ids = [] # surviving compounds become neighbors
          @sims = [] # calculated by neighbor routine
          
          neighbors
          n_prop_tmp = []; @ids.each { |idx| n_prop_tmp << @n_prop[idx] }; @n_prop = n_prop_tmp # select neighbors from matrix
          acts_tmp = []; @ids.each { |idx| acts_tmp << @activities[idx] }; @activities = acts_tmp


          # Sims between neighbors, if necessary
          gram_matrix = []
          if !@model.propositionalized && !@model.prediction_algorithm == "weighted_majority_vote" # need gram matrix for SVM (n. prop.)
            @n_prop.each_index do |i|
              gram_matrix[i] = [] unless gram_matrix[i]
              @n_prop.each_index do |j|
                if (j>i)
                  sim = OpenTox::Algorithm::Similarity.send(@similarity_algorithm.to_sym, @n_prop[i], @n_prop[j])
                  gram_matrix[i][j] = sim
                  gram_matrix[j] = [] unless gram_matrix[j]
                  gram_matrix[j][i] = gram_matrix[i][j]
                end
              end
              gram_matrix[i][i] = 1.0
            end
          end

          # reclaim original data (if svd was performed)
          if svd
            @n_prop = gsl_n_prop_orig.to_a 
            n_prop_tmp = []; @ids.each { |idx| n_prop_tmp << @n_prop[idx] }; @n_prop = n_prop_tmp
            @q_prop = gsl_q_prop_orig.row(0).to_a
          end

          $logger.debug "F: #{@n_prop.size}x#{@n_prop[0].size}; R: #{@q_prop.size}" if (@n_prop && @n_prop[0] && @q_prop)
          $logger.debug "Sims: #{@sims.size}, Acts: #{@activities.size}"

          @sims = [ gram_matrix, @sims ] 

        end


          

        # Find neighbors and store them as object variable, access all compounds for that.
        def neighbors
          @model.neighbors = []
          @n_prop.each_with_index do |fp, idx| # AM: access all compounds
            add_neighbor fp, idx
          end
        end


        # Adds a neighbor to @neighbors if it passes the similarity threshold
        # @param[Array] training_props Propositionalized data for this neighbor
        # @param[Integer] Index of neighbor
        def add_neighbor(training_props, idx)
          unless @model.training_activities[idx].nil?
            sim = similarity(training_props)
            if sim > @model.min_sim.to_f
                @model.neighbors << {
                  :compound => @compounds[idx],
                  :similarity => sim,
                  :activity => activities[idx]
                }
                @sims << sim
                @ids << idx
            end
          end
        end


        # Removes nil entries from n_prop and q_prop.
        # Matrix is a nested two-dimensional array.
        # Removes iteratively rows or columns with the highest fraction of nil entries, until all nil entries are removed.
        # Tie break: columns take precedence.
        # Deficient input such as [[nil],[nil]] will not be completely reduced, as the algorithm terminates if any matrix dimension (x or y) is zero.
        # Enables the use of cosine similarity / SVD
        def remove_nils
         return @n_prop if (@n_prop.length == 0 || @n_prop[0].length == 0)
          col_nr_nils = (Matrix.rows(@n_prop)).column_vectors.collect{ |cv| (cv.to_a.count(nil) / cv.size.to_f) }
          row_nr_nils = (Matrix.rows(@n_prop)).row_vectors.collect{ |rv| (rv.to_a.count(nil) / rv.size.to_f) }
          m_cols = col_nr_nils.max
          m_rows = row_nr_nils.max
          idx_cols = col_nr_nils.index(m_cols)
          idx_rows = row_nr_nils.index(m_rows)
          while ((m_cols > 0) || (m_rows > 0)) do
            if m_cols >= m_rows
              @n_prop.each { |row| row.slice!(idx_cols) }
              @q_prop.slice!(idx_cols)
            else
              @n_prop.slice!(idx_rows)
              @ids.slice!(idx_rows)
            end
            break if (@n_prop.length == 0) || (@n_prop[0].length == 0)
            col_nr_nils = Matrix.rows(@n_prop).column_vectors.collect{ |cv| (cv.to_a.count(nil) / cv.size.to_f) }
            row_nr_nils = Matrix.rows(@n_prop).row_vectors.collect{ |rv| (rv.to_a.count(nil) / rv.size.to_f) }
            m_cols = col_nr_nils.max
            m_rows = row_nr_nils.max
            idx_cols= col_nr_nils.index(m_cols)
            idx_rows = row_nr_nils.index(m_rows)
          end
        end

        # Replaces nils by zeroes in n_prop and q_prop
        # Enables the use of Tanimoto similarities with arrays (rows of n_prop and q_prop)
        def convert_nils
          @n_prop.each { |row| row.collect! { |v| v.nil? ? 0 : v } }
          @q_prop.collect! { |v| v.nil? ? 0 : v }
        end


        # Executes model similarity_algorithm
        # @param[Array] A propositionalized data entry
        # @return[Float] Similarity to query structure
        def similarity(training_props)
          OpenTox::Algorithm::Similarity.send(@model.similarity_algorithm,training_props, @q_prop)
        end


        # Converts fingerprints to matrix, order of rows by fingerprints. nil values allowed.
        # Same for compound fingerprints.
        def get_matrices
          @compounds = @model.training_compounds.clone
          @activities = @model.training_activities.clone
          @n_prop = @model.training_fingerprints.clone
          @q_prop = @model.query_fingerprint.clone
        end

        # Returns propositionalized data, if appropriate, or nil
        # @return [Array] Propositionalized data, or nil
        def props
          @model.propositionalized ? [ @n_prop, @q_prop ] : nil
        end

      end

    end

  end
end
