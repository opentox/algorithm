OpenTox Algorithm
=================

- An [OpenTox](http://www.opentox.org) REST Webservice
- Implements the OpenTox algorithm API for
    - fminer
    - lazar

REST operations
---------------

    Get a list of all algorithms  GET   /               -                           URIs of algorithms        200
    Get a representation of the   GET   /fminer/        -                           fminer representation     200,404
     fminer algorithms
    Get a representation of the   GET   /fminer/bbrc    -                           bbrc representation       200,404
    bbrc algorithm
    Get a representation of the   GET   /fminer/last    -                           last representation       200,404
     last algorithm
    Get a representation of the   GET   /lazar          -                           lazar representation      200,404
     lazar algorithm
    Create bbrc features          POST  /fminer/bbrc    dataset_uri,                URI for feature dataset   200,400,404,500
                                                        feature_uri,
                                                        [min_frequency=5 per-mil],
                                                        [feature_type=trees],
                                                        [backbone=true],
                                                        [min_chisq_significance=0.95],
                                                        [nr_hits=false]
    Create last features          POST  /fminer/last    dataset_uri,                URI for feature dataset   200,400,404,500
                                                        feature_uri,
                                                        [min_frequency=8 %],
                                                        [feature_type=trees],
                                                        [nr_hits=false]
    Create lazar model            POST  /lazar          dataset_uri,                URI for lazar model       200,400,404,500
                                                        prediction_feature,
                                                        feature_generation_uri
                                                        prediction_algorithm
                                                        [local_svm_kernel=weighted_tanimoto]
                                                        [min_sim=0.3]
                                                        [nr_hits=false]
                                                        [conf_stdev=false]

Synopsis
--------

- prediction\_algorithm: One of "weighted\_majority\_vote" (default for classification),  "local\_svm\_classification", "local\_svm\_regression (default for regression)", "local\_mlr\_prop". "weighted\_majority\_vote"  is not applicable for regression. "local\_mlr\_prop" is not applicable for classification.
- local\_svm\_kernel: One of "weighted\_tanimoto", "propositionalized". local\_svm\_kernel is not appplicable when prediction\_algorithm="weighted\_majority\_vote".
- min_sim: The minimum similarity threshold for neighbors. Numeric value in [0,1]. 
- nr_hits: Whether for instantiated models (local\_svm\_kernel = "propositionalized" for prediction_algorithm="local\_svm\_classification" or "local\_svm\_regression", or for prediction_algorithm="local\_mlr\_prop") nominal features should be instantiated with their occurrence counts in the instances. For non-instantiated models (local\_svm\_kernel = "weighted\_tanimoto" for prediction_algorithm="local\_svm\_classification" or "local\_svm\_regression", or for prediction_algorithm="weighted\_majority\_vote") the neighbor-to-neighbor and neighbor-to-query similarity also integrates these counts, when the parameter is set. One of "true", "false". 
- conf_stdev: Whether confidence integrates distribution of neighbor activity values. When "true", the exp(-1.0*(standard deviation of neighbor activities)) is multiplied on the similarity. One of "true", "false".

See http://www.maunz.de/wordpress/opentox/2011/lazar-models-and-how-to-trigger-them for a graphical overview.


Supported MIME formats
----------------------

- application/rdf+xml (default): read/write OWL-DL
- application/x-yaml: read/write YAML

Examples
--------

NOTE: http://webservices.in-silico.ch hosts the stable version that might not have complete functionality yet. **Please try http://ot-test.in-silico.ch** for latest versions.

### Get the OWL-DL representation of fminer

    curl http://webservices.in-silico.ch/algorithm/fminer

### Get the OWL-DL representation of lazar

    curl http://webservices.in-silico.ch/algorithm/lazar

* * * 

The following creates datasets with backbone refinement class representatives or latent structure patterns, using supervised graph mining, see http://cs.maunz.de. These features can be used e.g. as structural alerts, as descriptors (fingerprints) for prediction models or for similarity calculations.

### Create the full set of frequent and significant subtrees

    curl -X POST -d dataset_uri={datset_uri} -d prediction_feature={feature_uri} -d min_frequency={min_frequency} -d "backbone=false" http://webservices.in-silico.ch/algorithm/fminer/bbrc

feature_uri specifies the dependent variable from the dataset.
backbone=false reduces BBRC mining to frequent and correlated subtree mining (much more descriptors are produced).

### Create [BBRC](http://bbrc.maunz.de) features, recommended for large and very large datasets.

    curl -X POST -d dataset_uri={datset_uri} -d prediction_feature={feature_uri} -d min_frequency={min_frequency} http://webservices.in-silico.ch/algorithm/fminer/bbrc

feature_uri specifies the dependent variable from the dataset.   
Adding -d nr_hits=true produces frequency counts per pattern and molecule.
Please click [here](http://bbrc.maunz.de#usage) for more guidance on usage.

### Create [LAST-PM](http://last-pm.maunz.de) descriptors, recommended for small to medium-sized datasets.

    curl -X POST -d dataset_uri={datset_uri} -d prediction_feature={feature_uri} -d min_frequency={min_frequency} http://webservices.in-silico.ch/algorithm/fminer/last

feature_uri specifies the dependent variable from the dataset.   
Adding -d nr_hits=true produces frequency counts per pattern and molecule.
Please click [here](http://last-pm.maunz.de#usage) for guidance for more guidance on usage.

* * * 

### Create lazar model

Creates a standard Lazar model.

    curl -X POST -d dataset_uri={datset_uri} -d prediction_feature={feature_uri} -d feature_generation_uri=http://webservices.in-silico.ch/algorithm/fminer/bbrc http://webservices.in-silico.ch/test/algorithm/lazar 

[API documentation](http://rdoc.info/github/opentox/algorithm)
--------------------------------------------------------------

Copyright (c) 2009-2011 Christoph Helma, Martin Guetlein, Micha Rautenberg, Andreas Maunz, David Vorgrimmler, Denis Gebele. See LICENSE for details.
