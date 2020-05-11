udp2Filterbank
==============

udp2Filterbank is a Cython-based backend script for processng LOFAR beamformed data streams recorded with Olaf Wucknitz's (MPIfRA) VLBI recording script to generate sigproc-style filterbanks. 

Based on frontend work by Evan Keane (SKA) and further modified by Joe McCauley (TCD), a Cython backend was written to improve processing speed, while the bf2fil script was re-written to minimise multiple read/writes that were previously taking place and implement new processing modes. It is used for performing high time resolution observations with the Irish LOFAR station.

This setup also allows for the coherent dedispersion of data through a modified version of Cees Bassa's [CDMT](https://github.com/cbassa/cdmt) software.

Requirements
-------	
### Prerequisits
**(G)awk v4.1** or greater is required for full double precision / long int support in the filterbanking scripts.

The **FFTW3 (and FFTW3F)** development library and zstd must be installed and available on the path to compile.

Ubuntu-derivatives:
```
sudo apt install gawk libfftw3-dev libfftw3-single3 zstd
```

We provide modified versions of [mockHeader](https://github.com/David-McKenna/mockHeader) (with extra path length precauations and the option to provide a frequency table for non-continuous subbands, see *cli/sigproc_freqtable_builder.py* to generate these tables) and [cdmt](https://github.com/David-McKenna/cdmt) (modified for taking fitlerbanks as an input rather than H5 files) which are tuned for these scripts and advise using the provided makefile to install them.

If the zstd, mockHeader or cdmt binaries are not on the path then we will fall back to the enviroment variables *ZSTD_CMD*, *MOCKHEADER_CMD* and *CDMT_CMD*. The python wrapper scripts must always be on the path (by default, we install to *~/.local/bin/*, though the global install option changes this to */usr/local/bin/*). 

#### CDMT (CUDA GPU)
To use the CUDA component of this repo; you will need a GPU with the NVIDIA propriatary drivers installed with CUDA (tested with 10.2) and [cuFFT](https://developer.nvidia.com/cufft) available on the path. You may need to modify the CDMT makefile to point at your CUDA install directory if is in not located in */usr/lib/cuda* (sometimes located in */usr/local/cuda*).

Installation
------------
A Makefile is provided with four options, installing the system to the local user directories (*make all*), to the system (*make all-global*) and non-gpu versions of both (make *all-cpu all-global-cpu*).

This will checkout and build the mockHeader and (if needed) cdmt repos, compile the Cython code and copy all the resulting modules and scripts to the relevant location for later usage. The CLI scripts and mockHeader should be available on your path after running `make <install type|all>`.

Usage
-----
While the python library can be directly called, it is significnatly easier to reference the **bf2filcsh** script to ensure the sigproc header is properly added and all memory/cpu usage restrictions are met.

We recommend tuning the system to always leave at least 2 CPU cores free and use less than 50GB of RAM per iteration (higher values resulted in significantly slower disk read speeds during development).

### Enviroment Variables
Some enviroment variables are used to make the script fully non-interactive:
```
ZSTD_SKIP=1; ZSTD_CLEANUP=1; CDMT_CLEANUP=1; csh bf2fil.csh
```
#### ZSTD_AUTO [0/1]
- Skip decompression if a file exists at the output location

#### ZSTD_CLEANUP [0/1]
- Cleanup decompression artefacts if true, skip otherwise.

#### CDMT_CLEANUP [0/1]
- Cleanup intermediate raw udp filterbanks if true (keeps original header file)

### Required Parameters
```
csh bf2fil.csh [execution_mode] [pcap_filename] [npackets] [ram_factor] [cpu_factor] [fch1/freq table location] [output_filename]

```

#### execution_mode [str, "standard", "4bit", "cdmt", "4bit-cdmt"]
- Input/output data product type

#### pcap_filename [str]
- Input recorded data file to process. These can take the form of a processed pcap dump, raw or compressed with zstd. Provide the lowest frequency lane of a single output filterbank if processing multiple at once.

#### npackets [int, 0+]
- Upper limit of pakcets to process from the input file (backend should limit this if you overestimate the number of packets on any of the input files).

#### ram_factor [float, 0.0-1.0]
- Limits the about of RAM used to a fraction of the available RAM (recommended to keep usage below 100GB due to disk i/o hangs above this.)

#### cpu_factor [float, 0.0-1.0]
- Limits the number of CPU cores to a fraction of the available cores on the machine.

#### fch1 [float/str]
- (float)  Frequency of the top (bottom for cdmt) channel in MHz.
- (string) Location of a frequency table to pass to the sigproc header (list of doubles in MHz separated by newlines).

#### output_filename [str]
- Location prefix to save the processed output to.

## Optional Parameters
### standard. 4bit
```
csh bf2fil.csh standard/4bit
				[pcap_filename] [npackets] [ram_factor] [cpu_factor] [fch1] [output_filename] \
			   	(optional parameters are [stokesI] [stokesV] \
			   	[time_averaging_length] [frequency_FFT_window] \
			   	[startport] [number of ports] \
			   	[target name] \
				[RA](J2000, format hh:mm:ss.ddd) [DEC] (J2000, format dd.mm.ss.ddd))"
```
#### stokesI [0/1], stokesV [0/1]
- Choose which stokes vectors filterbanks to produce.

#### time_averaging_length [int, 1+]
- Number of time samples to sum to generate increased SNR at cost of time resolution.

#### frequency_FFT_window [int, 1+]
- Number of time samples to use as a fft window to perform channelisation.

#### startport [int/str]
- Set the number of the start port encase the regex fails (provide the lowest frequency lane to process).

#### number_of_ports [int]
- Number of incremental ports to process.

#### target_name [str]
- Name of the target source (or pointing) to save in the header

#### ra [str, hh:mm:ss.ddd], dec [str, dd:mm:ss.ddd]
- RA/DEC of pointing to save into the header.

### cdmt, 4bit-cdmt
```
csh bf2fil.csh cdmt/4bit-cdmt
				[pcap_filename] [npackets] [ram_factor] [cpu_factor] [fch1] [output_filename] \
				[cdmt_dms] [cdmt_ngulp] [cdmt_overlap] [cdmt_time_averaging_length] \
			   	[startport] [number of ports] \
			   	[target name] \
			   	[RA](J2000, format hh:mm:ss.ddd) [DEC] (J2000, format dd.mm.ss.ddd))"

```
#### cdmt_dms [str]
- CDMT input DM scheme, a string in the format "START_DM,NUM_SAMPLES,SERPARATION".

### cdmt_nulp [int]
- Number of samples per FFT action.

### cdmt_overlap
- Number of 0s to pad each FFT with.

### cdmt_time_averaging_overlap
- Number of time samples to decimate.

#### startport [int/str]
- Set the number of the start port encase the regex fails (provide the lowest frequency lane to process).

#### number_of_ports [int]
- Number of incremental ports to process.

#### target_name [str]
- Name of the target source (or pointing) to save in the header

#### ra [str, hh:mm:ss.ddd], dec [str, dd:mm:ss.ddd]
- RA/DEC of pointing to save into the header.