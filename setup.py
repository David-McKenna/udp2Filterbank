#!/usr/bin/env python3

# Initialise + compile our cython extension.
from distutils.core import setup, Extension
from Cython.Build import cythonize

parkes_data_module = Extension('parkesData', sources = ['parkesData.c'])

udp2FilExt = [
	Extension( 	"",
			 	sources = ["./cyUdp2fil.pyx"],
				libraries = ["fftw3f_threads"],
				library_dirs=["/home/dmckenna/bin/", "/home/dmckenna/bin/lib/", "/home/dmckenna/bin/include"], # ucc2 doesn't have fftw3, self compiled
			 	extra_compile_args = ['-fopenmp', '-O3', '-march=native',  "-I/home/dmckenna/bin/include", "-lfftw3f", "-fPIC"],
			 	extra_link_args = ["-fopenmp", "-lfftw3f_threads"] )
]


setup(name='lofarCyxData',
	version='0.0.0',
	description='Attempt 2',
	ext_modules=cythonize(udp2FilExt))

