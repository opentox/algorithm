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
                                                        [prediction_feature],
                                                        [feature_generation_uri],
                                                        [prediction_algorithm],
                                                        [feature_dataset_uri],
                                                        [pc_type=null],
                                                        [nr_hits=false (class. using wt. maj. vote), true (else)],
                                                        [min_sim=0.3 (nominal), 0.4 (numeric features)]
                                                        [min_train_performance=0.1]

Synopsis
--------

- prediction\_algorithm: One of "weighted\_majority\_vote" (default for classification),  "local\_svm\_classification", "local\_svm\_regression" (default for regression). "weighted\_majority\_vote"  is not applicable for regression.
- pc_type: Mandatory for feature dataset, one of [geometrical, topological, electronic, constitutional, hybrid, cpsa].
- nr_hits: Whether nominal features should be instantiated with their occurrence counts in the instances. One of "true", "false". 
- min_sim: The minimum similarity threshold for neighbors. Numeric value in [0,1].
- min_train_performance. The minimum training performance for "local\_svm\_classification" (Accuracy) and "local\_svm\_regression" (R-squared). Numeric value in [0,1].

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
