#!/usr/bin/env bash

# This script pull the lastest master of TOAST and build that again
# accompany toast-gnu.sh

set -e
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# customize these
# CONDAMPI=True
# SYSTEMFFTW=True
AATMVERSION=0.5
ENVNAME=toast-gnu
prefixBase="$SCRATCH/local/$ENVNAME"
prefixDownload="$prefixBase/git"
prefixCompile="$prefixBase/compile"
prefixConda="$prefixBase/conda"

# c.f. https://stackoverflow.com/a/23378780/5769446
P="${P-$(if [[ "$(uname)" == Darwin ]]; then sysctl -n hw.physicalcpu_max; else lscpu -p | grep -E -v '^#' | sort -u -t, -k 2,4 | wc -l; fi)}"
echo "Using $P processes..."

# for the build directory
date=$(date +%Y%m%d)

# on macOS try this for dependencies
# brew install fftw cfitsio suite-sparse
# note that homebrew consistenly uses open-mpi
# see https://github.com/Homebrew/homebrew-core/issues/36871
# compile from source to force open-mpi built with gcc
# brew install mpich fftw gmp --build-from-source

if [[ $(uname) == Darwin ]]; then
	GCC=gcc-9
	GXX=g++-9
	MPIFORT=/usr/local/bin/mpifort
else
	GCC=gcc
	GXX=g++
	MPIFORT=mpifort
fi

MPICC=mpicc
MPICXX=mpicxx

# AATM ##########################################################################################

cd "$prefixDownload"
cd "libaatm"
mkdir -p "build-$date"
cd "build-$date"

CC=$GCC \
	CXX=$GXX \
	CFLAGS="-O3 -g -fPIC -march=native -mtune=native -pthread" \
	CXXFLAGS="-O3 -g -fPIC -march=native -mtune=native -pthread -std=c++11" \
	cmake -DCMAKE_INSTALL_PREFIX="$prefixCompile" ..

make -j$P
make test
make install
