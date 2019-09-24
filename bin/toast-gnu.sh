#!/usr/bin/env bash

# * using the master libmadam and toast
# * TBB can't be found in SuiteSparse and TOAST

set -e

# customize these
# CONDAMPI=true
AATMVERSION=0.5
P=10
ENVNAME=toast-gnu-fftw
prefix="$SCRATCH/local/$ENVNAME"
# * assume FFTW from system's package manager
FFTWPATH=/usr

mkdir -p "$prefix" && cd "$prefix"

# assume Intel's env is loaded, e.g.
# . /opt/intel/bin/compilervars.sh -arch intel64

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

conda env create -f env.yml -p "$prefix"
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

# somehow icc doesn't work here
CC=gcc \
CXX=g++ \
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

FC=gfortran \
MPIFC=mpifort \
FCFLAGS="-O3 -fPIC -pthread -march=native -mtune=native" \
CC=gcc \
MPICC=mpicc \
CFLAGS="-O3 -fPIC -pthread -march=native -mtune=native" \
./configure \
    --with-fftw="$FFTWPATH" \
    --prefix="$prefix"

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
    -DCMAKE_C_COMPILER=gcc \
    -DCMAKE_CXX_COMPILER=g++ \
    -DMPI_C_COMPILER=mpicc \
    -DMPI_CXX_COMPILER=mpicxx \
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
