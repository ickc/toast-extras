#!/usr/bin/env bash

# * using the master libmadam and toast
# * TBB can't be found in SuiteSparse and TOAST

set -e

# customize these
CONDAMPI=true
AATMVERSION=0.5
P=10
ENVNAME=toast-intel-fftw
prefix="$SCRATCH/local/$ENVNAME"

mkdir -p "$prefix" && cd "$prefix"

# assume Intel's env is loaded, e.g.
# . /opt/intel/bin/compilervars.sh -arch intel64

# Install Python dep. via conda ##################################################################

cat << EOF > env.yml
channels:
- intel
- conda-forge
dependencies:
- python=3
- intelpython3_core
- ipykernel
- numpy
- scipy
- matplotlib
- pyephem
- healpy
EOF

if [[ -n "$CONDAMPI" ]]; then
    echo '- mpi4py' >> env.yml
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

FC=ifort \
MPIFC=mpiifort \
FCFLAGS="-O3 -g -fPIC -march=native -mtune=native -fexceptions -pthread -heap-arrays 16" \
CC=icc \
MPICC=mpicc \
CFLAGS="-O3 -g -fPIC -march=native -mtune=native -pthread" \
./configure \
    --with-fftw=/usr \
    --prefix="$prefix"

make -j$P
make install

. activate "$prefix"
# make sure intel paths has higher priorities then conda's
. /opt/intel/bin/compilervars.sh -arch intel64

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
    -DCMAKE_C_COMPILER=icc \
    -DCMAKE_CXX_COMPILER=icpc \
    -DMPI_C_COMPILER=mpiicc \
    -DMPI_CXX_COMPILER=mpiicpc \
    -DCMAKE_C_FLAGS="-O3 -g -fPIC -march=native -mtune=native -pthread" \
    -DCMAKE_CXX_FLAGS="-O3 -g -fPIC -march=native -mtune=native -pthread -std=c++11" \
    -DPYTHON_EXECUTABLE:FILEPATH=$(which python) \
    -DCMAKE_VERBOSE_MAKEFILE:BOOL=ON \
    -DCMAKE_INSTALL_PREFIX="$prefix" \
    -DFFTW_ROOT=/usr \
    ..

make -j$P
make install

python -c 'import toast.tests; toast.tests.run()'
