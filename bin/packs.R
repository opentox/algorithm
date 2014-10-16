# CRAN package installer for opentox-ruby
# AM/ DV, 2014


# set mirror to avoid questioning the user
options(repos=Sys.getenv("CRAN_MIRROR"))
install.packages(c("caret", "doMC", "e1071", "foreach", "iterators", "kernlab", "multicore", "plyr", "reshape", "randomForest", "RANN", "TunePareto"),lib=Sys.getenv("R_LIBS"))
