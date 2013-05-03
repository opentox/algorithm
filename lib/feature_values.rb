=begin
* Name: feature_values.rb
* Description: Feature value calculation
* Author: Andreas Maunz <andreas@maunz.de>
* Date: 10/2012
=end

module OpenTox
  class Algorithm

    class FeatureValues
      # Substructure matching
      # @param [Hash] keys: compound, feature_dataset, values: OpenTox::Compound, Array of SMARTS strings
      # @return [Array] Array with matching Smarts
      def self.match(params, subjectid)
        features = params[:feature_dataset].features.collect{ |f| f[RDF::DC.title] }
        params[:compound].match(features)
      end

      # Substructure matching with number of non-unique hits
      # @param [Hash] keys: compound, feature_dataset, values: OpenTox::Compound, Array of SMARTS strings
      # @return [Hash] Hash with matching Smarts and number of hits 
      def self.match_hits(params, subjectid)
        features = params[:feature_dataset].features.collect{ |f| f[RDF::DC.title] },
        params[:compound].match_hits(features)
      end

      # PC descriptor calculation
      # @param [Hash] keys: compound, feature_dataset, pc_type, lib, values: OpenTox::Compound, String, String
      # @return [Hash] Hash with feature name as key and value as value
      def self.lookup(params, subjectid)
        puts "lookup started"
        ds = params[:feature_dataset]
        #ds.build_feature_positions
        cmpd_inchi = params[:compound].inchi
        cmpd_idxs = ds.compounds.each_with_index.collect{ |cmpd,idx|
          idx if cmpd.inchi == cmpd_inchi
        }.compact
        if cmpd_idxs.size > 0 # We have entries
          puts "entries"
          cmpd_numeric_f = ds.features.collect { |f|
            f if f[RDF.type].include? RDF::OT.NumericFeature
          }.compact
          cmpd_data_entries = cmpd_idxs.collect { |idx|
            ds.data_entries[idx]
          }
          cmpd_fingerprints = cmpd_numeric_f.inject({}) { |h,f|
            values = cmpd_data_entries.collect { |entry| 
              val = entry[ds.feature_positions[f.uri]]
              val.nil? ? nil : val.to_f
            }.compact
            h[f.title] = (values.size > 0) ? values.to_scale.median : nil # AM: median for numeric features
            h
          }
          (ds.features - cmpd_numeric_f).each { |f|
            values = cmpd_data_entries.collect { |entry|
              val = entry[ds.feature_positions[f.uri]]
              val.nil? ? nil : val
            }.compact
            cmpd_fingerprints[f.title] = values.to_scale.mode # AM: mode for the others
          }
        else # We need lookup
          puts "no entries"
          params[:subjectid] = subjectid
          [:compound, :feature_dataset].each { |p| params.delete(p) }; [:pc_type, :lib].each { |p| params.delete(p) if params[p] == "" }
          single_cmpd_ds = OpenTox::Dataset.new(nil,subjectid)
          # TODO: ntriples !!!
          single_cmpd_ds.parse_rdfxml(RestClientWrapper.post(File.join($compound[:uri],cmpd_inchi,"pc"), params, {:accept => "application/rdf+xml"}))
          single_cmpd_ds.get(true)
          #single_cmpd_ds.build_feature_positions
          cmpd_fingerprints = single_cmpd_ds.features.inject({}) { |h,f|
            h[f.title] = single_cmpd_ds.data_entries[0][single_cmpd_ds.feature_positions[f.uri]]
            h
          }
        end
        cmpd_fingerprints
      end
    end

  end
end
