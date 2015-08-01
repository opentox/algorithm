require 'statsample'

ENV['FMINER_SMARTS'] = 'true'
ENV['FMINER_NO_AROMATIC'] = 'true'
ENV['FMINER_PVALUES'] = 'true'
ENV['FMINER_SILENT'] = 'true'
ENV['FMINER_NR_HITS'] = 'true'


# Require sub-Repositories
require_relative '../libfminer/libbbrc/bbrc' # include before openbabel
require_relative '../libfminer/liblast/last' # 
require_relative '../last-utils/lu.rb'

#Dir[File.join(File.dirname(__FILE__),"*.rb")].each{ |f| require_relative f}
require_relative "algorithm.rb"
require_relative "descriptor.rb"
require_relative "bbrc.rb"
#require_relative "fminer.rb"
require_relative "lazar.rb"
require_relative "transform.rb"
require_relative "similarity.rb"
#require_relative "neighbors.rb"
require_relative "classification.rb"
require_relative "regression.rb"
