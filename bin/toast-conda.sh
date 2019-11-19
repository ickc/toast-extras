#!/usr/bin/env bash

set -e

# start with a clean environment #######################################

# Initialize parameters
PREFIX="${PREFIX-"$SCRATCH/local/toast-conda"}"

# c.f. https://unix.stackexchange.com/a/98846
[[ -z "$IS_CLEAN_ENVIRONMENT" ]] &&
exec /usr/bin/env -i \
    IS_CLEAN_ENVIRONMENT=1 \
    CONDA_PREFIX="$CONDA_PREFIX" \
    PREFIX="$PREFIX" \
    TERM="$TERM" \
    bash "$0" "$@"
unset IS_CLEAN_ENVIRONMENT

N_CORES=${N_CORES-$(($(getconf _NPROCESSORS_ONLN) / 2))}

# helpers ##############################################################

print_double_line () {
    eval printf %.0s= '{1..'"${COLUMNS:-$(tput cols)}"\}
}

print_line () {
    eval printf %.0s- '{1..'"${COLUMNS:-$(tput cols)}"\}
}

printerr () {
	printf "%s\\n" "$@" >&2
	exit 1
}

mkdirerr () {
    mkdir -p "$1" || printerr "Cannot create $1. $2"
}

check_file () {
    if [[ -f "$1" ]]; then
        echo "$1 exists."
    else
        printerr "$1 not found! $2"
    fi
}

check_var () {
    if [[ -z "${!1}" ]]; then
        printerr "$1 is not defined! $2"
    else
        echo "$1 is defined."
    fi
}

# getopts ##############################################################

version='0.1.2'

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

# intro ################################################################

print_double_line
echo "Started with a clean environment:"
printenv

print_line
echo "Checking conda..."
ERR_MSG='Try installing or loading conda environment to continue.'
check_var CONDA_PREFIX "$ERR_MSG"
check_file "$CONDA_PREFIX/bin/conda" "$ERR_MSG"
check_file "$CONDA_PREFIX/bin/activate" "$ERR_MSG"

# conda ################################################################

print_double_line
echo 'Creating conda environment...'
mkdirerr "$PREFIX" 'Make sure you have permission or change the prefix specified in -p.'

cat << EOF > env.yml
channels:
- conda-forge
dependencies:
- python=3
- ipykernel
- numpy
- scipy
- matplotlib
- pyephem
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
- mpi4py
- mpich-mpicc
- mpich-mpicxx
- mpich-mpifort
- fftw
- libaatm
- cfitsio
- automake
- libtool
- libgfortran
- libblas=*=*mkl
- liblapack=*=*mkl
- lapack
- suitesparse
- libsharp
EOF

"$CONDA_PREFIX/bin/conda" env create -f env.yml -p "$PREFIX"

print_line
echo "Environment created in $PREFIX, activating and installing the ipykernel..."

. "$CONDA_PREFIX/bin/activate" "$PREFIX"

# ipython kernel
ENVNAME="${PREFIX##*/}"
python -m ipykernel install --user --name "$ENVNAME" --display-name "$ENVNAME"

# libmadam #############################################################

print_double_line
echo 'Installing libmadam...'

mkdir -p "$PREFIX/git" && cd "$PREFIX/git"
git clone git@github.com:hpc4cmb/libmadam.git ||
git clone https://github.com/hpc4cmb/libmadam.git
cd libmadam

print_line
echo 'Running autogen.sh...'
./autogen.sh

print_line
echo 'Running configure...'
FCFLAGS="-O3 -fPIC -pthread -march=native -mtune=native" \
CFLAGS="-O3 -fPIC -pthread -march=native -mtune=native" \
./configure --prefix="$PREFIX"

print_line
echo 'Running make...'
make -j"$N_CORES"

print_line
echo 'Running make install...'
make install -j"$N_CORES"

print_line
echo 'Installing libmadam Python wrapper...'
cd python
python setup.py install

print_line
echo 'Run libmadam test...'
python setup.py test

# PySM #################################################################

print_double_line
echo 'Installing pysm...'

cd "$PREFIX/git"
git clone git@github.com:healpy/pysm.git ||
git clone https://github.com/healpy/pysm.git
cd pysm

pip install .

# toast ################################################################

print_double_line
echo 'Installing TOAST...'

cd "$PREFIX/git"
git clone git@github.com:hpc4cmb/toast.git ||
git clone https://github.com/hpc4cmb/toast.git
cd toast

mkdir -p build
cd build

[[ $(uname) == Darwin ]] && LIBEXT=dylib || LIBEXT=so

print_line
echo 'Running cmake...'
cmake \
    -DCMAKE_INSTALL_PREFIX="$PREFIX" \
    -DCMAKE_C_COMPILER="$CC" \
    -DCMAKE_C_FLAGS="-O3 -fPIC -pthread -march=native -mtune=native" \
    -DCMAKE_CXX_COMPILER="$CXX" \
    -DCMAKE_CXX_FLAGS="-O3 -fPIC -pthread -march=native -mtune=native" \
    -DMPI_C_COMPILER="$(command -v mpicc)" \
    -DMPI_CXX_COMPILER="$(command -v mpicxx)" \
    -DPYTHON_EXECUTABLE:FILEPATH="$PREFIX/bin/python" \
    -DBLAS_LIBRARIES="$PREFIX/lib/libblas.$LIBEXT" \
    -DLAPACK_LIBRARIES="$PREFIX/lib/liblapack.$LIBEXT" \
    -DCMAKE_VERBOSE_MAKEFILE:BOOL=ON \
    -DFFTW_ROOT="$PREFIX" \
    -DSUITESPARSE_INCLUDE_DIR_HINTS="$PREFIX/include" \
    -DSUITESPARSE_LIBRARY_DIR_HINTS="$PREFIX/lib" \
    ..


print_line
echo 'Running make...'
make -j"$N_CORES"

print_line
echo 'Running make install...'
make install -j"$N_CORES"

print_line
echo 'Run TOAST test...'
python -c 'from toast.tests import run; run()'
