#!/usr/bin/env bash

# * using the master libmadam and toast

set -e
DIR="${BASH_SOURCE[0]%/*}"

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

mkdir -p "$prefixDownload"
mkdir -p "$prefixCompile"
mkdir -p "$prefixConda"

# Install Python dep. via conda ##################################################################

cd "$prefixConda"

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
- 'numba>=0.45'
- toml
- cython
- mypy
- pylint
- 'plotly>=4.1'
- nbformat
EOF

if [[ -n "$CONDAMPI" ]]; then
    echo '- mpi4py' >> env.yml
fi

conda env create -f env.yml -p "$prefixConda"
# rm -f env.yml

. activate "$prefixConda"

# mpi4py
# * hardcoded the location of these scripts for now
[[ -n "$CONDAMPI" ]] || "$DIR/../../reproducible-os-environments/common/conda/cray-mpi4py.sh"
if [[ -n "$SYSTEMFFTW" ]]; then
    # * assume FFTW from system's package manager
    FFTWPATH=/usr
else
    FFTWPATH="$prefixCompile"
    "$DIR/../../reproducible-os-environments/install/fftw.sh"
fi

# ipython kernel
python -m ipykernel install --user --name "$ENVNAME" --display-name "$ENVNAME"

# make sure the following dep. are not conda's
conda deactivate

# AATM ##########################################################################################

cd "$prefixDownload"
wget -qO- "https://launchpad.net/aatm/trunk/0.5/+download/aatm-${AATMVERSION}.tar.gz" | tar -xzf -
cd "aatm-$AATMVERSION"

CC=$GCC \
CXX=$GXX \
CFLAGS="-O3 -g -fPIC -march=native -mtune=native -pthread" \
CXXFLAGS="-O3 -g -fPIC -march=native -mtune=native -pthread -std=c++11" \
./configure \
    --prefix="$prefixCompile"

make -j$P
make install

# libmadam ##########################################################################################

# * assume CFITSIO installed using system's package manager

cd "$prefixDownload"
git clone git@github.com:hpc4cmb/libmadam.git
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

conda deactivate

# toast ##########################################################################################

# * assume suite-sparse installed using system's package manager

export LD_LIBRARY_PATH="$prefixCompile/lib:$LD_LIBRARY_PATH"

cd "$prefixDownload"
git clone git@github.com:hpc4cmb/toast.git
cd toast

mkdir -p build
cd build

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

export PYTHONPATH="$(realpath $prefixCompile/lib/python*/site-packages):$PYTHONPATH"

python -c 'from toast.tests import run; run()'
