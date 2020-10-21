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
P="${P-$([ $(uname) = 'Darwin' ] && sysctl -n hw.physicalcpu_max || lscpu -p | grep -E -v '^#' | sort -u -t, -k 2,4 | wc -l)}"
echo "Using $P processes..."

# for the build directory
date=$(date +%Y%m%d)

. activate "$prefix"
# make sure intel paths has higher priorities then conda's
. /opt/intel/bin/compilervars.sh -arch intel64

# toast ##########################################################################################

# assume you pull the master or checkout whichever branch you like already

cd "$prefix/git"
cd toast

mkdir -p "build-$date"
cd "build-$date"

cmake \
    -DCMAKE_C_COMPILER=icc \
    -DCMAKE_CXX_COMPILER=icpc \
    -DMPI_C_COMPILER=mpiicc \
    -DMPI_CXX_COMPILER=mpiicpc \
    -DCMAKE_C_FLAGS="-O3 -g -fPIC -march=native -mtune=native -pthread" \
    -DCMAKE_CXX_FLAGS="-O3 -g -fPIC -march=native -mtune=native -pthread -std=c++11" \
    -DPYTHON_EXECUTABLE:FILEPATH=$(which python) \
    -DCMAKE_VERBOSE_MAKEFILE:BOOL=ON \
    -DCMAKE_INSTALL_PREFIX="$prefix" \
    -DFFTW_ROOT="$FFTWPATH" \
    ..

make -j$P
make install

python -c 'from toast.tests import run; run()'
