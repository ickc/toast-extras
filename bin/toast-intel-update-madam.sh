#!/usr/bin/env bash

# This script pull the lastest master of TOAST and build that again
# accompany toast-intel.sh

set -e

# customize these
CONDAMPI=true
AATMVERSION=0.5
ENVNAME=toast-intel-fftw
prefix="$SCRATCH/local/$ENVNAME"
# * assume FFTW from system's package manager
FFTWPATH=/usr

# c.f. https://stackoverflow.com/a/23378780/5769446
P="${P-$(if [[ "$(uname)" == Darwin ]]; then sysctl -n hw.physicalcpu_max; else lscpu -p | grep -E -v '^#' | sort -u -t, -k 2,4 | wc -l; fi)}"
echo "Using $P processes..."

. activate "$prefix"
# make sure intel paths has higher priorities then conda's
. /opt/intel/bin/compilervars.sh -arch intel64

# toast ##########################################################################################

# assume you pull the master or checkout whichever branch you like already

cd "$prefix/git"
cd libmadam

./autogen.sh

FC=ifort \
	MPIFC=mpiifort \
	FCFLAGS="-O3 -g -fPIC -march=native -mtune=native -fexceptions -pthread -heap-arrays 16" \
	CC=icc \
	MPICC=mpiicc \
	CFLAGS="-O3 -g -fPIC -march=native -mtune=native -pthread" \
	./configure \
	--with-fftw="$FFTWPATH" \
	--prefix="$prefix"

make -j$P
make install

. activate "$prefix"
# make sure intel paths has higher priorities then conda's
. /opt/intel/bin/compilervars.sh -arch intel64

cd python
python setup.py install
python setup.py test
