udp2Filterbank
==============

udp2Filterbank is a Cython-based backend script for processng LOFAR beamformed data streams recoreded with Olaf Wucknitz's (MPIfRA) VLBI recordering script to generate sigproc-style filterbanks. 

Based on frontend work by Evan Keane (SKA) and further modified by Joe McCauley (TCD), a Cython backend was written to improve processing speed, while the bf2fil script was re-written to minimise rewrites that were previously taking place. It was used for performing high time resolution observations with the Irish LOFAR station.


Caveats
-------	
### Some parts are hardcoded for running on the I-LOFAR REALTA nodes
* zstd binaries must be on the path or they will fallback to '/home/dmckenna/bin/zstd'
* [mockHeader](https://github.com/evanocathain/mockHeader) binaries must be on the path or they will fallback to '/home/obs/Joe/realta_scripts/mockHeader/mockHeader'

### The setup.py will require editing to point at fftwf libraries if they are not available on your system

### This script does not install fully install itself into your path and the frontend scripts depend on local references, call the scripts the location you clone your repo and try not to move things around.

Usage
-----
While the python library can be directly called, it is significnatly easier to reference the bf2fil.csh script to ensure the sigproc header is properly added and all memory/cpu usage restrictions are met.

```
csh bf2fil.csh [pcap_filename] [npackets] [mode] [ram_factor] [fch1] [output_filename] \
				(optional parameters are [stokesI (0/1)] [stokesV (0/1)] \
				[time_averaging_length] [frequency_FFT_window] [target_name] \
				[RA](J2000, format hh:mm:ss.ddd) [DEC] (J2000, format dd.mm.ss.ddd))
```

#### pcap_filename [str]
- Input recorded data file to process. These can take the form of a processed pcap dump, raw or compressed with zstd.

#### npackets [int]
- Upper limit of pakcets to process from the input file.

#### mode [str ('evan' or 'olaf')]
- Observing mode, backends created by Evan Keane ('evan') or Olaf Wucknitz ('olaf') are supported.

#### ram_factor [float]
- Limits the maximum percentage of ram and number of CPU cores to ram_factor * system amount.

#### fch1 [float]
- Frequency of the top channel in MHz.

#### output_filename [str]
- Location to save the processed output to.

##Optional Parameters
#### stokesI [0/1], stokesV [0/1]
- Choose which stokes vectors filterbanks to produce.

#### time_averaging_length [int, 1+]
- Number of time samples to sum to generate increased SNR at cost of time resolution.

#### frequency_FFT_window [int, 1+]
- Number of time samples to use as a fft window to perform channelisation.

#### target_name [str]
- Name of the target source (or pointing) to save in the header

#### ra [str, hh:mm:ss.ddd], dec [str, dd:mm:ss.ddd]
- RA/DEC of pointing to save into the header.