#!/usr/bin/env bash

# This script pull the lastest master of TOAST and build that again
# accompany toast-intel.sh

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
P="${P-$([ $(uname) = 'Darwin' ] && sysctl -n hw.physicalcpu_max || lscpu -p | grep -E -v '^#' | sort -u -t, -k 2,4 | wc -l)}"
echo "Using $P processes..."

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

mkdir -p "$prefixDownload"
mkdir -p "$prefixCompile"
mkdir -p "$prefixConda"

# for the build directory
date=$(date +%Y%m%d)

# toast ##########################################################################################

# * assume suite-sparse installed using system's package manager

export LD_LIBRARY_PATH="$prefixCompile/lib:$LD_LIBRARY_PATH"

cd "$prefixDownload"
cd toast

mkdir -p "build-$date"
cd "build-$date"

if [[ $(uname) == Darwin ]]; then
	export LDFLAGS="-L/usr/local/opt/openblas/lib -L/usr/local/opt/lapack/lib"
	export CPPFLAGS="-I/usr/local/opt/openblas/include -I/usr/local/opt/lapack/include"
	export PKG_CONFIG_PATH="/usr/local/opt/openblas/lib/pkgconfig:/usr/local/opt/lapack/lib/pkgconfig:$PKG_CONFIG_PATH"
fi

cmake \
	-DCMAKE_C_COMPILER=$GCC \
	-DCMAKE_CXX_COMPILER=$GXX \
	-DMPI_C_COMPILER=$MPICC \
	-DMPI_CXX_COMPILER=$MPICXX \
	-DCMAKE_C_FLAGS="-O3 -fPIC -pthread -march=native -mtune=native" \
	-DCMAKE_CXX_FLAGS="-O3 -fPIC -pthread -march=native -mtune=native" \
	-DPYTHON_EXECUTABLE:FILEPATH="$prefixConda/bin/python" \
	-DCMAKE_VERBOSE_MAKEFILE:BOOL=ON \
	-DCMAKE_INSTALL_PREFIX="$prefixCompile" \
	-DFFTW_ROOT="$FFTWPATH" \
	..

make -j$P
make install

. activate "$prefixConda"
export PYTHONPATH="$(realpath $prefixCompile/lib/python*/site-packages):$PYTHONPATH"

python -c 'from toast.tests import run; run()'
