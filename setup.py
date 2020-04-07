#!/usr/bin/env python3

# Initialise + compile our cython extension.
#from distutils.core import setup, Extension
from setuptools import setup, Extension
from Cython.Build import cythonize

udp2FilExt = [Extension(        "",
                                sources = ["./cyUdp2rawfil.pyx"],
                                libraries = ["fftw3f_threads", "fftw3f"],
                                #library_dirs=["/home/dmckenna/bin/", "/home/dmckenna/bin/lib/", "/home/dmckenna/bin/include", "~/bin/", "~/bin/lib/", "~/bin/include/"], # ucc2 doesn't have fftw3, self compiled
                                extra_compile_args = ['-fopenmp', '-O3', '-march=native', "-lfftw3f_threads", "-lfftw3f", "-fPIC"],
                                extra_link_args = ["-fopenmp", "-lfftw3f_threads", "-lfftw3f"] ),
]


setup(name='ilofarCyxDataProcessor',
        version='0.0.2__rawfil',
        description='BF UDP datastream to sigproc filterbank processor backend.',
        ext_modules=cythonize(udp2FilExt),
        install_requires=["cython", "numpy", "astropy"])
