# fs.rb
# Feature Selection
# Author: Andreas Maunz

module OpenTox
  class Application < Service

  # Get list of feature selection algorithms
  # @return [text/uri-list] URIs
  get '/fs/?' do
    list = [ url_for('/fs/rfe', :full) ].join("\n") + "\n"
    format_output(list)
  end
  
  # Get representation of Recursive Feature Elimination algorithm
  # @return [String] Representation
  get "/fs/rfe/?" do
    algorithm = OpenTox::Algorithm.new(url_for('/fs/rfe',:full))
    algorithm.metadata = {
      DC.title => 'Recursive Feature Elimination',
      DC.creator => "andreas@maunz.de",
      RDF.type => [OT.Algorithm,OTA.PatternMiningSupervised]
    }
    algorithm.parameters = [
        { DC.description => "Dataset URI", OT.paramScope => "mandatory", DC.title => "dataset_uri" },
        { DC.description => "Prediction Feature URI", OT.paramScope => "mandatory", DC.title => "prediction_feature" },
        { DC.description => "Feature Dataset URI", OT.paramScope => "mandatory", DC.title => "feature_dataset_uri" },
        { DC.description => "Delete Instances with missing values", OT.paramScope => "optional", DC.title => "del_missing" }
    ]
    format_output(algorithm)
  end
  
  end
end
