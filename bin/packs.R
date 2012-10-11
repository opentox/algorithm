# CRAN package installer for opentox-ruby
# AM, 2012

# set mirror to avoid questioning the user
options(repos="http://mirrors.softliste.de/cran")
install.packages(c("caret", "doMC", "e1071", "foreach", "iterators", "kernlab", "multicore", "plyr", "reshape", "randomForest", "RANN", "TunePareto"),lib=Sys.getenv("R_LIBS"))
