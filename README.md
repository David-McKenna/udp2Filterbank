udp2Filterbank
==============

udp2Filterbank is a Cython-based backend script for processng LOFAR beamformed data streams recoreded with Olaf Wucknitz's (MPIfRA) VLBI recordering script to generate sigproc-style filterbanks. 

Based on frontend work by Evan Keane (SKA) and further modified by Joe McCauley (TCD), a Cython backend was written to improve processing speed, while the bf2fil script was re-written to minimise rewrites that were previously taking place. It was used for performing high time resolution observations with the Irish LOFAR station.

A forked version of mockHeader is provided with safeguards that prevent header corruption from long path names.

Caveats
-------	

* zstd binaries must be on the path or they will fallback to whatever is set at the ZSTD_CMD enviroment variable
* [mockHeader](https://github.com/evanocathain/mockHeader) binaries must be on the path or they will fallback to MOCKHEADER_CMD enviroment variable

### The setup.py will require editing to point at fftwf libraries if they are not available via ld on your system


Installation
------------
A Makefile is provided with two options, installing the system to the local user directories (make all) or to the system (make all-global).

This will checkout and build the mockHeader repo, compile the Cython code and copy all the resulting modules and scripts to the relevant location for later usage. The CLI scripts and mockHeader should be available on your path after running `make`.

**We will also assume you have a (G)awk version greater than 4.1; bf2fil.csh has a check to ensure that this is true and will not run otherwise (we need '--bignum' support for file byte location references).**

Usage
-----
While the python library can be directly called, it is significnatly easier to reference the bf2fil.csh script to ensure the sigproc header is properly added and all memory/cpu usage restrictions are met.

```
csh bf2fil.csh [pcap_filename] [npackets] [mode] [ram_factor] [cpu_factor] [fch1] [output_filename] \
			   (optional parameters are [stokesI (0/1)] [stokesV (0/1)] \
			   [time_averaging_length] [frequency_FFT_window] \
			   [startport] [number of ports] \
			   [target name] [RA](J2000, format hh:mm:ss.ddd) [DEC] (J2000, format dd.mm.ss.ddd))"

```

#### pcap_filename [str]
- Input recorded data file to process. These can take the form of a processed pcap dump, raw or compressed with zstd. Provide the lowest frequency lane if processing multiple ports at once.

#### npackets [int]
- Upper limit of pakcets to process from the input file.

#### mode [str ('evan' or 'olaf')]
- Observing mode, backends created by Evan Keane ('evan') or Olaf Wucknitz ('olaf') are supported.

#### ram_factor [float]
- Limits the maximum percentage of ram to ram_factor * system amount.

#### cpu_factor [float]
- Limits the number of CPU coresto a percentage of the available cores on the machine.

#### fch1 [float]
- Frequency of the top channel in MHz.

#### output_filename [str]
- Location to save the processed output to.

### Optional Parameters

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