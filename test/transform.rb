SERVICE="algorithm"
require 'bundler'
Bundler.require

require 'gsl'
require 'test/unit'

require '../lib/transform.rb'
require '../lib/algorithm.rb'

class Float

  def round_to(x)
    (self * 10**x).round.to_f / 10**x
  end

end




class TransformTest < Test::Unit::TestCase

  def test_pca
  
    d = GSL::Matrix.alloc([1.0, -5, 1.1, 2.0, -5, 1.9, 3.0, -5, 3.3], 3, 3) # 2nd col is const -5, gets removed
    rd = GSL::Matrix.alloc([1.0, 1.1, 1.9, 2.0, 3.1, 3.2], 3, 2)
    td = GSL::Matrix.alloc([-1.4142135623731, -0.14142135623731, 1.5556349186104],3,1)
    ev = GSL::Matrix.alloc([0.707106781186548, 0.707106781186548], 2, 1)
  
    # Lossy
    2.times do # repeat to ensure idempotency
      pca = OpenTox::Transform::PCA.new(d, 0.05)
      assert_equal pca.data_matrix, d
      assert_equal pca.data_transformed_matrix, td
      assert_equal pca.transform(d), td
      assert_equal pca.eigenvector_matrix, ev
      assert_equal pca.restore, rd
    end
  
    rd = GSL::Matrix.alloc([1.0, 1.1, 2.0, 1.9, 3.0, 3.3], 3, 2) # 2nd col of d is const -5, gets removed on rd
    td = GSL::Matrix.alloc([-1.4142135623731, -7.84962372879505e-17, -0.14142135623731, -0.14142135623731, 1.5556349186104, 0.141421356237309],3,2)
    ev = GSL::Matrix.alloc([0.707106781186548, -0.707106781186548, 0.707106781186548, 0.707106781186548], 2, 2)
  
    # Lossless
    2.times do
      pca = OpenTox::Transform::PCA.new(d, 0.0)
      assert_equal pca.data_matrix, d
      assert_equal pca.data_transformed_matrix, td
      assert_equal pca.transform(d), td
      assert_equal pca.eigenvector_matrix, ev
      assert_equal pca.restore, rd
    end

    rd = GSL::Matrix.alloc([1.0, 1.1, 1.9, 2.0, 3.1, 3.2], 3, 2)
    td = GSL::Matrix.alloc([-1.4142135623731, -0.14142135623731, 1.5556349186104],3,1)
    ev = GSL::Matrix.alloc([0.707106781186548, 0.707106781186548], 2, 1)
    # Lossy, but using maxcols constraint
    2.times do
      pca = OpenTox::Transform::PCA.new(d, 0.0, 1) # 1 column
      assert_equal pca.data_matrix, d
      assert_equal pca.data_transformed_matrix, td
      assert_equal pca.transform(d), td
      assert_equal pca.eigenvector_matrix, ev
      assert_equal pca.restore, rd
    end
  
  
  end

  def test_svd

     m = GSL::Matrix[
       [5,5,0,5],
       [5,0,3,4],
       [3,4,0,3],
       [0,0,5,3],
       [5,4,4,5],
       [5,4,5,5] 
     ]

     foo = GSL::Matrix[[5,5,3,0,5,5]]
     bar = GSL::Matrix[[5,4,5,5]]

     # AutoScale (mean and center) to improve on representation
     nr_cases, nr_features = m.size1, m.size2
     (0..nr_features-1).each { |i|
        autoscaler = OpenTox::Transform::AutoScale.new(m.col(i))
        m.col(i)[0..nr_cases-1] = autoscaler.vs
        bar.col(i)[0..0] = autoscaler.transform bar.col(i)
     }
     autoscaler = OpenTox::Transform::AutoScale.new(foo.transpose.col(0))
     foo = GSL::Matrix[autoscaler.vs]

     #puts
     #puts m.to_a.collect { |r| r.collect{ |v| sprintf("%.2f", v) }.join(", ") }.join("\n")
     #puts
     #puts foo.to_a.collect { |r| r.collect{ |v| sprintf("%.2f", v) }.join(", ") }.join("\n")
     #puts
     #puts bar.to_a.collect { |r| r.collect{ |v| sprintf("%.2f", v) }.join(", ") }.join("\n")

     # run SVD
     svd = OpenTox::Algorithm::Transform::SVD.new m, 0.2
     #puts
     #puts svd.restore.to_a.collect { |r| r.collect{ |v| sprintf("%.2f", v) }.join(", ") }.join("\n")
     #puts
     #puts svd.data_transformed_matrix.to_a.collect { |r| r.collect{ |v| sprintf("%.2f", v) }.join(", ") }.join("\n")

     # instance transform
     bar = svd.transform bar # alias for svd.transform_instance bar 
     sim = []
     svd.uk.each_row { |x|
       sim << OpenTox::Algorithm::Similarity.cosine_num(x,bar.row(0))
     }
     
     # # # NO AUTOSCALE
     #assert_equal sim[0].round_to(3), 0.346
     #assert_equal sim[1].round_to(3), 0.966
     #assert_equal sim[2].round_to(3), 0.282
     #assert_equal sim[3].round_to(3), 0.599
     #assert_equal sim[4].round_to(3), 0.975
     #assert_equal sim[5].round_to(3), 1.000 

     # # # AUTOSCALE
     assert_equal sim[0].round_to(3), -0.115
     assert_equal sim[1].round_to(3), 0.425
     assert_equal sim[2].round_to(3), -0.931
     assert_equal sim[3].round_to(3), -0.352
     assert_equal sim[4].round_to(3), 0.972
     assert_equal sim[5].round_to(3), 1.000 

      
     # feature transform, only for demonstration of concept
     foo = svd.transform_feature foo
     sim = []
     svd.vk.each_row { |x|
       sim << OpenTox::Algorithm::Similarity.cosine_num(x,foo.row(0))
     }

     # # # NO AUTOSCALE
     #assert_equal sim[0].round_to(3), 1.000
     #assert_equal sim[1].round_to(3), 0.874
     #assert_equal sim[2].round_to(3), 0.064
     #assert_equal sim[3].round_to(3), 0.895

     # # # AUTOSCALE
     assert_equal sim[0].round_to(3), 1.000
     assert_equal sim[1].round_to(3), 0.705
     assert_equal sim[2].round_to(3), 0.023
     assert_equal sim[3].round_to(3), 0.934

  end
  
end
