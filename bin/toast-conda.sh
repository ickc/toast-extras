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
    HOME="$HOME" \
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

version='0.1.4'

usage="${BASH_SOURCE[0]} [-mh] [-p prefix] --- Install TOAST software stack through conda

where:
    -h  show this help message
    -p  prefix directory
    -m  avoid git clone and compile whenever possible. e.g. you won't be able to develop TOAST.

version: $version
"

# reset getopts
OPTIND=1

# get the options
while getopts "p:mh" opt; do
    case "$opt" in
    p)  PREFIX="$OPTARG"
        ;;
    m)  MINIMAL=1
        ;;
    h)  printf "$usage"
        exit 0
        ;;
    *)  printf "$usage"
        exit 1
    esac
done

# intro ################################################################

check_env () {

local ERR_MSG='Try installing or loading conda environment to continue.'
check_var CONDA_PREFIX "$ERR_MSG"
check_file "$CONDA_PREFIX/bin/conda" "$ERR_MSG"
check_file "$CONDA_PREFIX/bin/activate" "$ERR_MSG"
mkdirerr "$PREFIX/git" 'Make sure you have permission or change the prefix specified in -p.'

}

# conda ################################################################

install_conda () {

cd "$PREFIX"

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
- suitesparse
- automake
- libtool
- libgfortran
- libblas=*=*mkl
- liblapack=*=*mkl
- lapack
EOF

[[ -z "$MINIMAL" ]] && echo '- cmake' >> env.yml || echo '- toast' >> env.yml

"$CONDA_PREFIX/bin/conda" env create -f env.yml -p "$PREFIX"

}

install_ipykernel () {
    local ENVNAME="${PREFIX##*/}"
    python -m ipykernel install --user --name "$ENVNAME" --display-name "$ENVNAME"
}

# PySM #################################################################

install_pysm () {

if [[ -z "$MINIMAL" ]]; then

cd "$PREFIX/git"
git clone git@github.com:healpy/pysm.git ||
git clone https://github.com/healpy/pysm.git
cd pysm

# on comet it has strange permission errors if it is a git repo
pip install . ||
pip install https://github.com/healpy/pysm/archive/master.zip

else

pip install https://github.com/healpy/pysm/archive/master.zip

fi

}

# libmadam #############################################################

install_libmadam () {

cd "$PREFIX/git"
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

}

# libsharp #############################################################

install_libsharp () {

cd "$PREFIX/git"
git clone git@github.com:Libsharp/libsharp.git --branch master --single-branch --depth 1 ||
git clone https://github.com/Libsharp/libsharp --branch master --single-branch --depth 1
cd libsharp

print_line
echo 'Running autoreconf...'
autoreconf

print_line
echo 'Running configure...'
CC="$CC" \
CFLAGS="-O3 -g -fPIC -march=native -mtune=native -pthread" \
./configure --enable-mpi --enable-pic --prefix="$PREFIX"

print_line
echo 'Running make...'
make -j"$N_CORES"

print_line
echo "Installing by copying to $PREFIX..."
# force overwrite in case it was installed previously
# explicit path to override shell alias
/usr/bin/cp -af auto/* "$PREFIX"

print_line
echo 'Run libsharp test...'
make test

print_line
echo 'Installing libsharp Python wrapper...'
cd python
LIBSHARP="$PREFIX" CC="$(command -v mpicc) -g" LDSHARED="$(command -v mpicc) -g -shared" \
    python setup.py install --prefix="$PREFIX"

}

# toast ################################################################

install_toast () {

if [[ -z "$MINIMAL" ]]; then

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

else
    echo 'Not compiling TOAST as you required a minimal build. Skipping...'
fi

print_line
echo 'Run TOAST test...'
python -c 'from toast.tests import run; run()'

}

# main #################################################################

main () {
    # intro
    print_double_line
    echo "Started with a clean environment:"
    printenv

    print_double_line
    echo "Checking environment..."
    check_env

    # conda
    print_double_line
    echo 'Creating conda environment...'
    install_conda

    print_double_line
    echo "Environment created in $PREFIX, activating and installing the ipykernel..."
    . "$CONDA_PREFIX/bin/activate" "$PREFIX"

    print_double_line
    echo 'Installing ipython kernel...'
    install_ipykernel

    # PySM
    print_double_line
    echo 'Installing pysm...'
    install_pysm

    # libmadam
    print_double_line
    echo 'Installing libmadam...'
    install_libmadam

    # libsharp
    print_double_line
    echo 'Installing libsharp...'
    install_libsharp || echo 'Having trouble installing libsharp, skipping...'

    # toast
    print_double_line
    echo 'Installing TOAST...'
    install_toast
}

main
