#!/usr/bin/env bash

# * using the master libmadam and toast

set -e
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# customize these
CONDAMPI=True
SYSTEMFFTW=True
ENVNAME=toast-gnu
prefixBase="$SCRATCH/local/$ENVNAME"
prefixDownload="$prefixBase/git"
prefixCompile="$prefixBase/compile"
prefixConda="$prefixBase/conda"
# set MAMBA to conda if you don't have mamba
MAMBA="${MAMBA-mamba}"

# c.f. https://stackoverflow.com/a/23378780/5769446
P="${P-$([ $(uname) = 'Darwin' ] && sysctl -n hw.physicalcpu_max || lscpu -p | grep -E -v '^#' | sort -u -t, -k 2,4 | wc -l)}"
echo "Using $P processes..."

if [[ $(uname) == Darwin ]]; then
    # assuming macports, do these if you haven't yet
    # sudo port install gcc10 mpich mpich-gcc10 fftw-3 cfitsio SuiteSparse
    GCC=gcc-mp-10
    GXX=g++-mp-10
    MPIFORT=mpifort-mpich-mp
    MPICC=mpicc-mpich-gcc10
    MPICXX=mpicxx-mpich-gcc10
    # if you do
    # sudo port select --set gcc mp-gcc10
    # sudo port select --set mpi mpich-gcc10
    # then the linux setup below can also be used in macOS
else
    GCC=gcc
    GXX=g++
    MPIFORT=mpifort
    MPICC=mpicc
    MPICXX=mpicxx
fi


mkdir -p "$prefixDownload"
mkdir -p "$prefixCompile"
mkdir -p "$prefixConda"

# Install Python dep. via conda ##################################################################

cd "$prefixConda"

cat << EOF > env.yml
channels:
- conda-forge
dependencies:
- python=3.8
- ipykernel
- numpy
- scipy
- matplotlib
- ephem
- healpy
- numba
- toml
- cython
- mypy
- pylint
- plotly
- nbformat
- astropy
- configobj
- pysm3
EOF

if [[ -n "$CONDAMPI" ]]; then
    echo '- mpi4py' >> env.yml
    echo '- mpich=3.3.*=external_*' >> env.yml
fi

"$MAMBA" env create -f env.yml -p "$prefixConda"
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
git clone https://github.com/hpc4cmb/libaatm.git
cd "libaatm"

CC=$GCC \
CXX=$GXX \
CFLAGS="-O3 -g -fPIC -march=native -mtune=native -pthread" \
CXXFLAGS="-O3 -g -fPIC -march=native -mtune=native -pthread -std=c++11" \
cmake -DCMAKE_INSTALL_PREFIX="$prefixCompile" ..

make -j$P
make test
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
    --with-blas='-L/opt/local/lib -I/opt/local/include' \
    --with-lapack='-L/opt/local/lib -I/opt/local/include' \
    --with-cfitsio='/opt/local/lib' \
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

# libsharp #####################################################################

cd "$prefixDownload"
git clone https://github.com/Libsharp/libsharp --branch master --single-branch --depth 1
cd libsharp

autoreconf

CC=$MPICC \
CFLAGS="-O3 -g -fPIC -march=native -mtune=native -pthread" \
./configure --enable-mpi --enable-pic --prefix="$prefixCompile"

make -j$P

# force overwrite in case it was installed previously
# explicit path to override shell alias
/usr/bin/cp -af auto/* "$prefixCompile"

. activate "$prefixConda"

cd python
LIBSHARP="$prefixCompile" CC="$MPICC -g" LDSHARED="$MPICC -g -shared" \
    python setup.py install --prefix="$prefixConda"

# libconviqt #####################################################################################

cd "$prefixDownload"
git clone git@github.com:hpc4cmb/libconviqt.git
cd libconviqt

./autogen.sh

CC=$MPICC \
CXX=$MPICXX \
MPICC=$MPICC \
MPICXX=$MPICXX \
CFLAGS="-O3 -fPIC -pthread -march=native -mtune=native -std=gnu99" \
CXXFLAGS="-O3 -g -fPIC -march=native -mtune=native -pthread" \
OPENMP_CFLAGS='-fopenmp' \
OPENMP_CXXFLAGS='-fopenmp' \
LDFLAGS='-fopenmp -lpthread' \
./configure \
    --prefix="$prefixCompile"


make -j$P
make check
make install

. activate "$prefixConda"

cd python
python setup.py install --prefix="$prefixConda"
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
    export LDFLAGS="-L/opt/local/lib"
    export CPPFLAGS="-I/opt/local/include"
    export PKG_CONFIG_PATH="/opt/local/lib/pkgconfig:$PKG_CONFIG_PATH"
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
echo "finished TOAST test. You may want to cleanup $PWD/toast_test_output"
