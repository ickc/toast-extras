#!/usr/bin/env bash

# * using the master libmadam and toast
# * TBB can't be found in SuiteSparse and TOAST

set -e

# customize these
CONDAMPI=true
AATMVERSION=0.5
P=${P-$(($(getconf _NPROCESSORS_ONLN) / 2))}
ENVNAME=toast-gnu-fftw
prefix="$SCRATCH/local/$ENVNAME"
# * assume FFTW from system's package manager
FFTWPATH=/usr

mkdir -p "$prefix" && cd "$prefix"

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

# Install Python dep. via conda ##################################################################

# nomkl to force OpenBLAS
cat << EOF > env.yml
channels:
- defaults
- conda-forge
dependencies:
- python=3
- ipykernel
- numpy
- scipy
- matplotlib
- pyephem
- healpy
- nomkl
EOF

if [[ -n "$CONDAMPI" ]]; then
    echo '- conda-forge::mpi4py' >> env.yml
fi

# conda env create -f env.yml -p "$prefix"
rm -f env.yml

. activate "$prefix"

# mpi4py
# * hardcoded the location of this script for now
[[ -n "$CONDAMPI" ]] || ~/git/source/reproducible-os-environments/common/conda/cray-mpi4py.sh

# ipython kernel
python -m ipykernel install --user --name "$ENVNAME" --display-name "$ENVNAME"

# make sure the following dep. are not conda's
conda deactivate

# AATM ##########################################################################################

mkdir -p "$prefix/git"
cd "$prefix/git"
wget -qO- "https://launchpad.net/aatm/trunk/0.5/+download/aatm-${AATMVERSION}.tar.gz" | tar -xzf -
cd "aatm-$AATMVERSION"

CC=$GCC \
CXX=$GXX \
CFLAGS="-O3 -g -fPIC -march=native -mtune=native -pthread" \
CXXFLAGS="-O3 -g -fPIC -march=native -mtune=native -pthread -std=c++11" \
./configure \
    --prefix="$prefix"

make -j$P
make install

# libmadam ##########################################################################################

# * assume CFITSIO installed using system's package manager

cd "$prefix/git"
git clone git@github.com:hpc4cmb/libmadam.git
cd libmadam

./autogen.sh

if [[ $(uname) == Darwin ]]; then
LIBRARY_PATH=/usr/local/Cellar/cfitsio/3.450_1/lib \
LD_LIBRARY_PATH=$prefix/lib \
FC=gfortran-9 \
MPIFC=$MPIFORT \
FCFLAGS="-O3 -fPIC -pthread -march=native -mtune=native" \
CC=$GCC \
MPICC=$MPICC \
CFLAGS="-O3 -fPIC -pthread -march=native -mtune=native" \
./configure \
    --with-fftw="$FFTWPATH" \
    --prefix="$prefix"
else
FC=gfortran \
MPIFC=$MPIFORT \
FCFLAGS="-O3 -fPIC -pthread -march=native -mtune=native" \
CC=$GCC \
MPICC=$MPICC \
CFLAGS="-O3 -fPIC -pthread -march=native -mtune=native" \
./configure \
    --with-fftw="$FFTWPATH" \
    --prefix="$prefix"
fi

make -j$P
make install

. activate "$prefix"

cd python
python setup.py install
python setup.py test

# toast ##########################################################################################

# * assume suite-sparse installed using system's package manager

cd "$prefix/git"
git clone git@github.com:hpc4cmb/toast.git
cd toast

mkdir -p build
cd build

cmake \
    -DCMAKE_C_COMPILER=$GCC \
    -DCMAKE_CXX_COMPILER=$GXX \
    -DMPI_C_COMPILER=$MPICC \
    -DMPI_CXX_COMPILER=$MPICXX \
    -DCMAKE_C_FLAGS="-O3 -fPIC -pthread -march=native -mtune=native" \
    -DCMAKE_CXX_FLAGS="-O3 -fPIC -pthread -march=native -mtune=native" \
    -DPYTHON_EXECUTABLE:FILEPATH=$(which python) \
    -DCMAKE_VERBOSE_MAKEFILE:BOOL=ON \
    -DCMAKE_INSTALL_PREFIX="$prefix" \
    -DFFTW_ROOT="$FFTWPATH" \
    ..

make -j$P
make install

python -c 'from toast.tests import run; run()'
