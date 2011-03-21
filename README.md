OpenTox Algorithm
=================

- An [OpenTox](http://www.opentox.org) REST Webservice
- Implements the OpenTox algorithm API for
    - fminer
    - lazar

REST operations
---------------

    Get a list of all algorithms  GET   /             -                       URIs of algorithms        200
    Get a representation of the   GET   /fminer/      -                       fminer representation     200,404
     fminer algorithms
    Get a representation of the   GET   /fminer/bbrc  -                       bbrc representation       200,404
    bbrc algorithm
    Get a representation of the   GET   /fminer/last  -                       last representation       200,404
     last algorithm
    Get a representation of the   GET   /lazar        -                       lazar representation      200,404
     lazar algorithm
     Create bbrc features          POST  /fminer/bbrc dataset_uri,            URI for feature dataset   200,400,404,500
                                                      feature_uri,
                                                      min_frequency
     Create last features          POST  /fminer/last dataset_uri,            URI for feature dataset   200,400,404,500
                                                      feature_uri,
                                                      min_frequency
     Create lazar model            POST  /lazar       dataset_uri,            URI for lazar model       200,400,404,500
                                                      prediction_feature,
                                                      feature_generation_uri

Supported MIME formats
----------------------

- application/rdf+xml (default): read/write OWL-DL
- application/x-yaml: read/write YAML

Examples
--------

### Get the OWL-DL representation of fminer

    curl http://webservices.in-silico.ch/algorithm/fminer

### Get the OWL-DL representation of lazar

    curl http://webservices.in-silico.ch/algorithm/lazar

### Create [BBRC](http://bbrc.maunz.de) features

    curl -X POST -d dataset_uri={datset_uri} -d prediction_feature={feature_uri} -d min_frequency={min_frequency} http://webservices.in-silico.ch/algorithm/fminer/bbrc

feature_uri specifies the dependent variable from the dataset.

### Create [LAST-PM](http://last-pm.maunz.de) features

    curl -X POST -d dataset_uri={datset_uri} -d prediction_feature={feature_uri} -d min_frequency={min_frequency} http://webservices.in-silico.ch/algorithm/fminer/last

feature_uri specifies the dependent variable from the dataset.

Creates a dataset with fminer features (backbone refinement class representatives from supervised graph mining, see http://www.maunz.de/libfminer-doc/). These features can be used e.g. as structural alerts, as descriptors (fingerprints) for prediction models or for similarity calculations.

### Create lazar model

    curl -X POST -d dataset_uri={datset_uri} -d prediction_feature={feature_uri} -d feature_generation_uri=http://webservices.in-silico.ch/algorithm/fminer http://webservices.in-silico.ch/test/algorithm/lazar

feature_uri specifies the dependent variable from the dataset

[API documentation](http://rdoc.info/github/opentox/algorithm)
--------------------------------------------------------------

Copyright (c) 2009-2011 Christoph Helma, Martin Guetlein, Micha Rautenberg, Andreas Maunz, David Vorgrimmler, Denis Gebele. See LICENSE for details.
