#!/usr/bin/env bash

set -e

# start with a clean environment #######################################

# Initialize parameters
UNAME="${UNAME-$(uname)}"

# c.f. https://stackoverflow.com/a/23378780/5769446
if [[ -z $N_CORES ]]; then
	case "$UNAME" in
	Darwin)
		N_CORES="$(sysctl -n hw.physicalcpu_max)"
		;;
	Linux)
		N_CORES="$(lscpu -p | grep -E -v '^#' | sort -u -t, -k 2,4 | wc -l)"
		;;
	FreeBSD)
		N_CORES="$(sysctl -n hw.ncpu)"
		;;
	*)
		N_CORES="$(getconf _NPROCESSORS_ONLN 2> /dev/null || getconf NPROCESSORS_ONLN 2> /dev/null || echo 1)"
		;;
	esac
fi

if [[ -z $NOMKL ]]; then
	if [[ $UNAME == Linux ]] && (lscpu | grep -q AuthenticAMD); then
		NOMKL=1
	else
		NOMKL=0
	fi
fi

# c.f. https://unix.stackexchange.com/a/98846
# CIBUILDWHEEL is used to skipping toast timing test on CI
# c.f. https://github.com/hpc4cmb/toast/blob/eb1e65097f99ecac63d8976f7131764a43a7ff07/src/toast/tests/runner.py#L113-L117
[[ -z $IS_CLEAN_ENVIRONMENT ]] &&
	exec /usr/bin/env -i \
		IS_CLEAN_ENVIRONMENT=1 \
		CONDA_PREFIX="$CONDA_PREFIX" \
		SCRATCH="$SCRATCH" \
		UNAME="$UNAME" \
		N_CORES="$N_CORES" \
		NOMKL="$NOMKL" \
		TERM="$TERM" \
		HOME="$HOME" \
		CIBUILDWHEEL="$CIBUILDWHEEL" \
		bash "$0" "$@"
unset IS_CLEAN_ENVIRONMENT

# helpers ##############################################################

print_double_line() {
	eval printf %.0s= '{1..'"${COLUMNS:-$(tput cols)}"\}
}

print_line() {
	eval printf %.0s- '{1..'"${COLUMNS:-$(tput cols)}"\}
}

printerr() {
	printf '%s\n' "$@" >&2
	exit 1
}

mkdirerr() {
	mkdir -p "$1" || printerr "Cannot create $1. $2"
}

check_file() {
	if [[ -f $1 ]]; then
		echo "$1 exists."
	else
		printerr "$1 not found! $2"
	fi
}

check_var() {
	if [[ -n ${!1} ]]; then
		echo "$1 is defined."
	else
		printerr "$1 is not defined! $2"
	fi
}

# getopts ##############################################################

version='0.2.0'

PREFIX="$SCRATCH/local/toast-conda"
MAMBA=mamba

usage="${BASH_SOURCE[0]} [-nmUh] [-p prefix -c conda -j processes] --- Install TOAST software stack through conda

where:
    -h  show this help message
    -p  prefix directory. Default: $PREFIX
    -c  choose conda package solver. Valid options: conda, mamba. Default: $MAMBA
    -j  no of processes used in make. Default: $N_CORES
    -n  if specified, request nomkl for conda packages. Automatically specified if AMD CPU is detected.
    -m  avoid git clone and compile whenever possible. e.g. you won't be able to develop TOAST.
    -U  Upgrade environments (to master for git repositories.)

version: $version
"

# reset getopts
OPTIND=1

# get the options
while getopts "p:c:j:mnUh" opt; do
	case "$opt" in
	p)
		PREFIX="$OPTARG"
		;;
	c)
		MAMBA="$OPTARG"
		;;
	j)
		N_CORES="$OPTARG"
		;;
	m)
		MINIMAL=1
		;;
	n)
		NOMKL=1
		;;
	U)
		UPGRADE=1
		echo 'Upgrade not implemented.'
		exit 1
		;;
	h)
		printf '%s\n' "$usage"
		exit 0
		;;
	*)
		printf '%s\n' "$usage"
		exit 1
		;;
	esac
done

echo "Using $N_CORES processes..."

# intro ################################################################

check_env() {

	local ERR_MSG='Try installing or loading conda environment to continue.'
	check_var CONDA_PREFIX "$ERR_MSG"
	check_file "$CONDA_PREFIX/bin/conda" "$ERR_MSG"
	check_file "$CONDA_PREFIX/bin/activate" "$ERR_MSG"
	mkdirerr "$PREFIX/git" 'Make sure you have permission or change the prefix specified in -p.'

}

# conda ################################################################

install_conda() {

	cd "$PREFIX"

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
- h5py
- healpy
- numba
- toml
- cython
- mypy
- pylint
- pydocstyle
- flake8
- bandit
- pytest
- plotly
- nbformat
- astropy
- configobj
- mpi4py
- pysm3
- libsharp
- mpich-mpicc
- mpich-mpicxx
- mpich-mpifort
- fftw
- libaatm
- cfitsio
- suitesparse
- automake
- libtool
- lapack
- compilers
- quaternionarray
EOF

	if [[ -n $MINIMAL ]]; then
		echo '- toast' >> env.yml
	else
		echo '- cmake' >> env.yml
	fi
	if [[ $NOMKL == 1 ]]; then
		echo '- nomkl' >> env.yml
		echo '- libblas' >> env.yml
		echo '- liblapack' >> env.yml
	else
		echo '- libblas=*=*mkl' >> env.yml
		echo '- liblapack=*=*mkl' >> env.yml
	fi

	"$CONDA_PREFIX/bin/$MAMBA" env create -f env.yml -p "$PREFIX"

}

upgrade_conda() {
	. "$CONDA_PREFIX/bin/activate" "$PREFIX"
}

install_ipykernel() {
	local ENVNAME="${PREFIX##*/}"
	python -m ipykernel install --user --name "$ENVNAME" --display-name "$ENVNAME"
}

# libmadam #############################################################

install_libmadam() (

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
		MPIFC=mpifort \
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

)

# toast ################################################################

install_toast() (

	if [[ -z $MINIMAL ]]; then

		cd "$PREFIX/git"
		git clone git@github.com:hpc4cmb/toast.git ||
			git clone https://github.com/hpc4cmb/toast.git
		cd toast

		mkdir -p build
		cd build

		if [[ $UNAME == Darwin ]]; then
			LIBEXT=dylib
		else
			LIBEXT=so
		fi

		print_line
		echo 'Running cmake...'
		cmake \
			-DCMAKE_INSTALL_PREFIX="$PREFIX" \
			-DCMAKE_C_COMPILER="$CC" \
			-DCMAKE_C_FLAGS="-O3 -fPIC -pthread -march=native -mtune=native" \
			-DCMAKE_CXX_COMPILER="$CXX" \
			-DCMAKE_CXX_FLAGS="-O3 -fPIC -pthread -march=native -mtune=native" \
			-DMPI_C_COMPILER="$PREFIX/bin/mpicc" \
			-DMPI_CXX_COMPILER="$PREFIX/bin/mpicxx" \
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
	echo "finished TOAST test. You may want to cleanup $PWD/toast_test_output"

)

# main #################################################################

main() (
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

	# libmadam
	print_double_line
	echo 'Installing libmadam...'
	install_libmadam

	# toast
	print_double_line
	echo 'Installing TOAST...'
	install_toast
)

main
