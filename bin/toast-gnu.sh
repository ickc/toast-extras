#!/usr/bin/env bash

# * using the master libmadam and toast
# TODO: error detection within function not checked
# TODO: seems like the PATHs setup within test isn't done yet

set -e
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# customize these
# CONDAMPI=True
MPIVERSION=3.1.4
SYSTEMFFTW=True
ENVNAME=toast-gnu
prefixBase="/opt/cmb/$ENVNAME"
prefixDownload="$prefixBase/git"
prefixCompile="$prefixBase/compile"
prefixConda="$prefixBase/conda"
# set MAMBA to conda if you don't have mamba
MAMBA="${MAMBA-mamba}"

UNAME="$(uname)"
# c.f. https://stackoverflow.com/a/23378780/5769446
N_CORES="${N_CORES-$([ "$UNAME" = Darwin ] && sysctl -n hw.physicalcpu_max || lscpu -p | grep -E -v '^#' | sort -u -t, -k 2,4 | wc -l)}"
echo "Using $N_CORES processes..."

if [[ $UNAME == Darwin ]]; then
	# assuming macports, do these if you haven't yet
	# sudo port install gcc10 mpich mpich-gcc10 fftw-3 cfitsio SuiteSparse
	GCC=gcc-mp-10
	GXX=g++-mp-10
	FC=gfortran-mp-10
	MPIFORT=mpifort-mpich-mp
	MPICC=mpicc-mpich-gcc10
	MPICXX=mpicxx-mpich-gcc10
	# if you do
	# sudo port select --set gcc mp-gcc10
	# sudo port select --set mpi mpich-gcc10
	# then the linux setup below can also be used in macOS
else
	# on ubuntu try this for dep
	# gfortran autoconf automake libtool m4 cmake python3 python3-dev python3-tk python3-pip zlib1g-dev libbz2-dev libopenblas-dev liblapack-dev libboost-all-dev libcfitsio-dev libfftw3-dev libhdf5-dev libflac-dev libsuitesparse-dev libmetis-dev
	# optionally install libmkl-dev libmkl-avx512 etc. for MKL
	GCC=gcc
	GXX=g++
	FC=gfortran
	MPIFORT=mpifort
	MPICC=mpicc
	MPICXX=mpicxx
fi

mkdir -p "$prefixDownload"
mkdir -p "$prefixCompile"
mkdir -p "$prefixConda"

# helpers ##############################################################

print_double_line() {
	eval printf %.0s= '{1..'"${COLUMNS:-$(tput cols)}"\}
}

print_line() {
	eval printf %.0s- '{1..'"${COLUMNS:-$(tput cols)}"\}
}

ld_library_path_prepend() {
	if [[ -d $1 ]]; then
		case ":$LD_LIBRARY_PATH:" in
		*":$1:"*) : ;;
		*) export LD_LIBRARY_PATH="${1}${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}" ;;
		esac
	fi
}

pythonpath_prepend() {
	if [[ -d $1 ]]; then
		case ":$PYTHONPATH:" in
		*":$1:"*) : ;;
		*) export PYTHONPATH="${1}${PYTHONPATH:+:${PYTHONPATH}}" ;;
		esac
	fi
}

pkg_config_path_prepend() {
	if [[ -d $1 ]]; then
		case ":$PKG_CONFIG_PATH:" in
		*":$1:"*) : ;;
		*) export PKG_CONFIG_PATH="${1}${PKG_CONFIG_PATH:+:${PKG_CONFIG_PATH}}" ;;
		esac
	fi
}

# PATH ##################################################################

ld_library_path_prepend "$prefixCompile/lib"
[[ $__UNAME == Darwin ]] && ld_library_path_prepend /opt/local/lib/mpich-mp

# Install Python dep. via conda ##################################################################

install_conda() {

	cd "$prefixConda"

	cat << EOF > env.yml
channels:
- conda-forge
dependencies:
- python=3.10
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
- h5py
EOF

	if [[ -n $CONDAMPI ]]; then
		echo '- mpi4py' >> env.yml
		echo '- mpich=4.1.*=external_*' >> env.yml
	fi

	if [[ $UNAME == Darwin ]]; then
		echo 'Installing libsharp through conda on Darwin...'
		echo '- libsharp' >> env.yml
	fi

	"$MAMBA" env create -f env.yml -p "$prefixConda"
	# rm -f env.yml

}

install_ipykernel() {

	# ipython kernel
	python -m ipykernel install --user --name "$ENVNAME" --display-name "$ENVNAME"

}

# mpi4py ########################################################################################

install_mpi4py() {
	cd "$prefixDownload"
	git clone --single-branch --depth 1 https://github.com/mpi4py/mpi4py.git --branch "$MPIVERSION"
	cd mpi4py

	python setup.py build
	python setup.py install
	# test
	python -c 'from mpi4py import MPI'
}

# AATM ##########################################################################################

install_aatm() {

	cd "$prefixDownload"
	git clone --single-branch --depth 1 https://github.com/hpc4cmb/libaatm.git
	cd "libaatm"

	CC=$GCC \
		CXX=$GXX \
		CFLAGS="-O3 -g -fPIC -march=native -mtune=native -pthread" \
		CXXFLAGS="-O3 -g -fPIC -march=native -mtune=native -pthread -std=c++11" \
		cmake -DCMAKE_INSTALL_PREFIX="$prefixCompile" .

	make -j"$N_CORES"
	make test
	make install

}

# libmadam ##########################################################################################

install_libmadam() {

	# * assume CFITSIO installed using system's package manager

	cd "$prefixDownload"
	git clone --single-branch --depth 1 git@github.com:hpc4cmb/libmadam.git
	cd libmadam

	./autogen.sh

	if [[ $UNAME == Darwin ]]; then
		FC=$MPIFORT \
			MPIFC=$MPIFORT \
			FCFLAGS="-O3 -fPIC -pthread -march=native -mtune=native -fallow-argument-mismatch" \
			CC=$GCC \
			MPICC=$MPICC \
			CFLAGS="-O3 -fPIC -pthread -march=native -mtune=native" \
			./configure \
			--with-fftw="$FFTWPATH" \
			--with-blas='-L/opt/local/lib -I/opt/local/include' \
			--with-lapack='-L/opt/local/lib -I/opt/local/include' \
			--with-cfitsio='/opt/local' \
			--prefix="$prefixCompile"
	else
		FC=$MPIFORT \
			MPIFC=$MPIFORT \
			FCFLAGS="-O3 -fPIC -pthread -march=native -mtune=native -fallow-argument-mismatch" \
			CC=$GCC \
			MPICC=$MPICC \
			CFLAGS="-O3 -fPIC -pthread -march=native -mtune=native" \
			./configure \
			--with-fftw="$FFTWPATH" \
			--prefix="$prefixCompile"
	fi

	make -j"$N_CORES"
	make install

}

test_libmadam() {

	cd "$prefixDownload/libmadam/python"
	python setup.py install
	python setup.py test

}

# libsharp #####################################################################

install_libsharp() {

	cd "$prefixDownload"
	# cleanup the patch which may have been applied earlier
	rm -rf libsharp
	git clone --single-branch --depth 1 https://github.com/Libsharp/libsharp --branch v1.0.0
	cd libsharp

	# apply patch. See https://github.com/hpc4cmb/cmbenv/blob/master/pkgs/patch_libsharp
	wget https://github.com/hpc4cmb/cmbenv/raw/5ce12fc851434d9fc7af74533c4deb1864aa85f0/pkgs/patch_libsharp
	patch -p1 < patch_libsharp
	# fix "libtool:   error: unrecognised option: '-static'"
	if [[ $UNAME == Darwin ]]; then
		grep -rl libtool | xargs sed -i 's/libtool/\/opt\/local\/bin\/libtool/'
	fi

	autoreconf

	CC=$MPICC \
		CFLAGS="-O3 -g -fPIC -march=native -mtune=native -pthread" \
		./configure --enable-mpi --enable-pic --prefix="$prefixCompile"

	make -j"$N_CORES"

	# force overwrite in case it was installed previously
	# explicit path to override shell alias
	command cp -af auto/* "$prefixCompile"

}

install_libsharp_python() {

	cd "$prefixDownload/libsharp/python"
	LIBSHARP="$prefixCompile" CC="$MPICC -g" LDSHARED="$MPICC -g -shared" \
		python setup.py install --prefix="$prefixConda"

}

# libconviqt #####################################################################################

install_libconviqt() {

	cd "$prefixDownload"
	git clone --single-branch --depth 1 git@github.com:hpc4cmb/libconviqt.git
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
		--with-cfitsio='/opt/local' \
		--prefix="$prefixCompile"

	make -j"$N_CORES"
	make check
	make install

}

install_libconviqt_python() {

	cd "$prefixDownload/libconviqt/python"
	python setup.py install --prefix="$prefixConda"
	python setup.py test

}

# toast ##########################################################################################

install_toast() {

	# * assume suite-sparse installed using system's package manager

	cd "$prefixDownload"
	git clone --single-branch --depth 1 git@github.com:hpc4cmb/toast.git
	cd toast

	mkdir -p build
	cd build

	if [[ $UNAME == Darwin ]]; then
		export LDFLAGS="-L/opt/local/lib"
		export CPPFLAGS="-I/opt/local/include"
		pkg_config_path_prepend /opt/local/lib/pkgconfig
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

	make -j"$N_CORES"
	make install

}

test_toast() {

	pythonpath_prepend "$(realpath "$prefixCompile"/lib/python*/site-packages)"

	python -c 'from toast.tests import run; run()'
	echo "finished TOAST test. You may want to cleanup $PWD/toast_test_output"

}

# main #################################################################

main() (
	# conda
	print_double_line
	echo 'Creating conda environment...'
	install_conda

	print_double_line
	echo "Environment created in $PREFIX, activating and installing the ipykernel..."
	. activate "$prefixConda"

	# mpi4py
	if [[ -z $CONDAMPI ]]; then
		if [[ -n $NERSC_HOST ]]; then
			# * hardcoded the location of these scripts for now
			"$DIR/../../reproducible-os-environments/common/conda/cray-mpi4py.sh"
		else
			install_mpi4py
		fi
	fi
	if [[ -n $SYSTEMFFTW ]]; then
		# * assume FFTW from system's package manager
		[[ $UNAME == Darwin ]] && FFTWPATH=/opt/local || FFTWPATH=/usr
	else
		FFTWPATH="$prefixCompile"
		"$DIR/../../reproducible-os-environments/install/fftw.sh"
	fi

	print_double_line
	echo 'Installing ipython kernel...'
	install_ipykernel
	# make sure the following dep. are not conda's
	conda deactivate

	# aatm
	print_double_line
	echo 'Installing aatm...'
	install_aatm

	# libmadam
	print_double_line
	echo 'Installing libmadam...'
	install_libmadam
	print_line
	echo 'Testing libmadam...'
	. activate "$prefixConda"
	test_libmadam
	conda deactivate

	# libsharp
	if [[ $UNAME != Darwin ]]; then
		print_double_line
		echo 'Installing libsharp...'
		install_libsharp
		print_line
		echo 'Installing python libsharp interface...'
		. activate "$prefixConda"
		install_libsharp_python
		conda deactivate
	fi

	# libconviqt
	print_double_line
	echo 'Installing libconviqt...'
	install_libconviqt
	print_line
	echo 'Installing python libconviqt interface...'
	. activate "$prefixConda"
	install_libconviqt_python
	conda deactivate

	# toast
	print_double_line
	echo 'Installing TOAST...'
	install_toast
	print_line
	echo 'Testing TOAST...'
	. activate "$prefixConda"
	test_toast
)

main
