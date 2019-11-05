#!/usr/bin/env bash

# This script pull the lastest master of TOAST and build that again
# accompany toast-gnu.sh

set -e
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# customize these
# CONDAMPI=True
# SYSTEMFFTW=True
AATMVERSION=0.5
P=${P-$(($(getconf _NPROCESSORS_ONLN) / 2))}
ENVNAME=toast-gnu
prefixBase="$SCRATCH/local/$ENVNAME"
prefixDownload="$prefixBase/git"
prefixCompile="$prefixBase/compile"
prefixConda="$prefixBase/conda"

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

# libmadam ##########################################################################################

# * assume CFITSIO installed using system's package manager

cd "$prefixDownload"
cd libmadam

./autogen.sh

if [[ $(uname) == Darwin ]]; then
LD_LIBRARY_PATH=$prefixCompile/lib \
FC=gfortran-9 \
MPIFC=$MPIFORT \
FCFLAGS="-O3 -fPIC -pthread -march=native -mtune=native" \
CC=$GCC \
MPICC=$MPICC \
CFLAGS="-O3 -fPIC -pthread -march=native -mtune=native" \
./configure \
    --with-fftw="$FFTWPATH" \
    --with-blas='-L/usr/local/opt/openblas/lib -I/usr/local/opt/openblas/include' \
    --with-lapack='-L/usr/local/opt/lapack/lib -I/usr/local/opt/lapack/include' \
    --with-cfitsio='/usr/local/Cellar/cfitsio/3.450_1' \
    --prefix="$prefixCompile"
else
FC=gfortran \
MPIFC=$MPIFORT \
FCFLAGS="-O3 -fPIC -pthread -march=native -mtune=native" \
CC=$GCC \
MPICC=$MPICC \
CFLAGS="-O3 -fPIC -pthread -march=native -mtune=native" \
./configure \
    --with-fftw="$FFTWPATH" \
    --prefix="$prefixCompile"
fi

make -j$P
make install

. activate "$prefixConda"

cd python
python setup.py install
python setup.py test
