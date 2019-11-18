#!/usr/bin/env bash

set -e

# start with a clean environment #######################################

# Initialize parameters
PREFIX="${PREFIX-"$SCRATCH/local/toast-conda"}"

# c.f. https://unix.stackexchange.com/questions/98829/how-to-start-a-script-with-clean-environment?noredirect=1&lq=1
[[ -z "$IS_CLEAN_ENVIRONMENT" ]] && exec /usr/bin/env -i IS_CLEAN_ENVIRONMENT=1 CONDA_PREFIX="$CONDA_PREFIX" PREFIX="$PREFIX" TERM="$TERM" bash "$0" "$@"
unset IS_CLEAN_ENVIRONMENT

# helpers ###############################################################

print_double_line () {
    eval printf %.0s= '{1..'"${COLUMNS:-$(tput cols)}"\}
}

print_line () {
    eval printf %.0s- '{1..'"${COLUMNS:-$(tput cols)}"\}
}

# getopts ##############################################################

version='0.1.1'

usage="${BASH_SOURCE[0]} [-h] [-p prefix] --- Install TOAST software stack through conda

where:
	-h	show this help message
	-p	prefix directory

version: $version
"

# reset getopts
OPTIND=1

# get the options
while getopts "p:h" opt; do
	case "$opt" in
	p)	PREFIX="$OPTARG"
		;;
	h)	printf "$usage"
        exit 0
		;;
	*)	printf "$usage"
        exit 1
	esac
done

# TODO: emit error when CONDA_PREFIX, PREFIX not exist

# intro ##############################################################

echo "Started with a clean environment:"
printenv

P=${P-$(($(getconf _NPROCESSORS_ONLN) / 2))}
mkdir -p "$PREFIX" && cd "$PREFIX"

# conda ###############################################################

print_double_line
echo 'Creating conda environment...'

# TODO
# python stack
# mpi4py
# ipykernel
# aatm

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
- 'astropy>=3.1'
- configobj
- conda-forge::mpi4py
- conda-forge::mpich-mpicc
- conda-forge::mpich-mpicxx
- conda-forge::mpich-mpifort
- conda-forge::fftw
- conda-forge::libaatm
- conda-forge::cfitsio
- conda-forge::automake
- conda-forge::libtool
- conda-forge::libgfortran
- conda-forge::libblas
- conda-forge::liblapack
- conda-forge::lapack
- conda-forge::suitesparse
- conda-forge::libsharp
EOF

"$CONDA_PREFIX/bin/conda" env create -f env.yml -p "$PREFIX"

. "$CONDA_PREFIX/bin/activate" "$PREFIX"

print_line
echo 'Activated conda environment:'
printenv

# libmadam ##########################################################################################

mkdir -p "$PREFIX/git" && cd "$PREFIX/git"
git clone git@github.com:hpc4cmb/libmadam.git
cd libmadam

./autogen.sh

FCFLAGS="-O3 -fPIC -pthread -march=native -mtune=native" \
CFLAGS="-O3 -fPIC -pthread -march=native -mtune=native" \
./configure --prefix="$PREFIX"

make -j$P
make install

cd python
python setup.py install
python setup.py test

# PySM ##########################################################################################

cd "$PREFIX/git"
git clone https://github.com/healpy/pysm.git
cd pysm

pip install .

# toast ##########################################################################################

cd "$PREFIX/git"
git clone git@github.com:hpc4cmb/toast.git
cd toast

mkdir -p build
cd build

[[ $(uname) == Darwin ]] && LIBEXT=dylib || LIBEXT=so

cmake \
    -DCMAKE_INSTALL_PREFIX="$PREFIX" \
    -DCMAKE_C_COMPILER="$CC" \
    -DCMAKE_C_FLAGS="-O3 -fPIC -pthread -march=native -mtune=native" \
    -DCMAKE_CXX_COMPILER="$CXX" \
    -DCMAKE_CXX_FLAGS="-O3 -fPIC -pthread -march=native -mtune=native" \
    -DMPI_C_COMPILER="$(which mpicc)" \
    -DMPI_CXX_COMPILER="$(which mpicxx)" \
    -DPYTHON_EXECUTABLE:FILEPATH="$PREFIX/bin/python" \
    -DBLAS_LIBRARIES="$PREFIX/lib/libblas.$LIBEXT" \
    -DLAPACK_LIBRARIES="$PREFIX/lib/liblapack.$LIBEXT" \
    -DCMAKE_VERBOSE_MAKEFILE:BOOL=ON \
    -DFFTW_ROOT="$PREFIX" \
    -DSUITESPARSE_INCLUDE_DIR_HINTS="$PREFIX/include" \
    -DSUITESPARSE_LIBRARY_DIR_HINTS="$PREFIX/lib" \
    ..

make -j$P
make install

python -c 'from toast.tests import run; run()'
