=begin
* Name: fs.rb
* Description: feature selection
* Author: Andreas Maunz <andreas@maunz.de>
* Date: 10/2012
=end

module OpenTox
  class Application < Service

  # Get list of feature selection algorithms
  # @return [text/uri-list] URIs
  get '/fs/?' do
    list = [ to('/fs/rfe', :full) ].join("\n") + "\n"
    format_output(list)
  end
  
  # Get representation of Recursive Feature Elimination algorithm
  # @return [String] Representation
  get "/fs/rfe/?" do
    algorithm = OpenTox::Algorithm.new(to('/fs/rfe',:full))
    algorithm.metadata = {
      RDF::DC.title => 'Recursive Feature Elimination',
      RDF::DC.creator => "andreas@maunz.de",
      RDF.type => [RDF::OT.Algorithm,RDF::OTA.PatternMiningSupervised]
    }
    algorithm.parameters = [
        { RDF::DC.description => "Dataset URI", RDF::OT.paramScope => "mandatory", RDF::DC.title => "dataset_uri" },
        { RDF::DC.description => "Prediction Feature URI", RDF::OT.paramScope => "mandatory", RDF::DC.title => "prediction_feature" },
        { RDF::DC.description => "Feature Dataset URI", RDF::OT.paramScope => "mandatory", RDF::DC.title => "feature_dataset_uri" },
        { RDF::DC.description => "Delete Instances with missing values", RDF::OT.paramScope => "optional", RDF::DC.title => "del_missing" }
    ]
    format_output(algorithm)
  end
  
  end
end
