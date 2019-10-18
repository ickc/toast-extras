#!/usr/bin/env bash

# This script pull the lastest master of TOAST and build that again
# accompany toast-intel.sh

set -e

# customize these
CONDAMPI=true
AATMVERSION=0.5
P=${P-$(($(getconf _NPROCESSORS_ONLN) / 2))}
ENVNAME=toast-intel-fftw
prefix="$SCRATCH/local/$ENVNAME"
# * assume FFTW from system's package manager
FFTWPATH=/usr

# for the build directory
date=$(date +%Y%m%d)

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
