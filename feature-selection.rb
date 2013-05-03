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
  get '/feature-selection/?' do
    list = [ to('/feature-selection/recursive-feature-elimination', :full) ].join("\n") + "\n"
    render(list)
  end
  
  # Get representation of Recursive Feature Elimination algorithm
  # @return [String] Representation
  get "/feature-selection/recursive-feature-elimination/?" do
    algorithm = OpenTox::Algorithm.new(to('/feature-selection/recursive-feature-elimination',:full))
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
    render(algorithm)
  end
  
  end
end
