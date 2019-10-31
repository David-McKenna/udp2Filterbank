#!/bin/csh
#Original by Evan Keane.
#Write wrapper script for pcap to fil conversion

#chop up pcap file into ncores_avail chunks
#make sure they are integer number of packets

#for i in ncores_avail
# bf2fil.py file_part$i

#stitch back all the bits together

#stick on fil header

#process

#2019-03-05 Modified by Joe McCauley
#Comment the jump to skip before the file is chopped
#Add new argument to allow setting different frequencies for the top channel
#Add facility to grab the MJD from the input filename
#2019-03-22 Modified by Joe McCauley
#Add ra & dec optional parameters
#
#2019-10-* Modified by David McKenna
#   No longer apply chunking to the input dataset; use a new Cython-based backend
#   to read / process / write the data to a single output file. Also adds in time/
#   frequency tradeoffs for dealing with shorter period / higher DM pulsars.

if ($#argv < 6) then
    echo "Usage: csh bf2fil.csh [pcap_filename] [npackets] [mode] [ram_factor] [fch1] [output_filename] (optional parameters are [stokesI (0/1)] [stokesV (0/1)] [time_averaging_length] [frequency_FFT_window] [pulsar name] [RA](J2000, format hh:mm:ss.ddd) [DEC] (J2000, format dd.mm.ss.ddd))"
    goto marbh
endif


# Initialisation
set file       = $argv[1]
set npackets   = $argv[2]
set mode       = $argv[3] # evan or olaf
set ram_factor = $argv[4] # Set some kind of arbitrary nice-ness factor (sets what fraction of cpu cores/est. ram can be used)
set fch1       = $argv[5] # set the frequency of the top channel
set outfile    = $argv[6]

if ( $#argv > 6 ) then
    set stokesI = $argv[7]
    set stokesV = $argv[8]

    if ( $stokesI == $stokesV ) then
        if ( $stokesI == 0 ) then
            echo "You have to get some kind of Stokes output..."
            goto marbh
        endif
    endif
else
    set stokesI = 1
    set stokesV = 0
endif

if ( $#argv == 10 ) then
    set timeWindow = $argv[9]
    set fftWindow = $argv[10]
    echo "Time averaged over "$timeWindow" steps"
    echo "Trading time for frequency resolution over "$fftWindow" steps."
else 
    set timeWindow = 1
    set fftWindow = 1
endif


if ( $#argv == 11 ) then
    set psrName = $argv[11]
    echo "Pulsar Name "$psrName
else 
    set psrName = "J0000+0000"
endif

if ( $#argv == 13 ) then
    set ra     = $argv[12]
    set dec    = $argv[13]
    echo "RA="$ra
    echo "DEC="$dec
else
    set ra = 0
    set dec = 0
endif

set tel = 11 # LOFAR in PRESTO/Sigproc.



# Exit if the output file exists
if ( -f $outfile ) then
    echo "Output file "$outfile" already exists, exiting before we overwrite any data."
    goto marbh
endif



# What are we running on? How many CPU cores?
set host = `uname`
echo $host
if ($host == "Darwin") then       # We're on a Mac
    echo '2019-10 Changes: Compatibility has not been tested, attempting to continue...'
    set nprocessors = `sysctl -n hw.physicalcpu`
else if ($host == "Linux") then   # We're on a Linux
    set nprocessors = `nproc`
endif



# What resources are available?
set ram = `grep MemTotal /proc/meminfo | awk '{print $2*1024}'` # Get total RAM in bytes
set ramcap = `echo $ram | awk -v ram_factor=$ram_factor '{print int($1*ram_factor)}'`

echo 'You have '$ram' bytes of ram available.'
echo 'We will plan to use less than '$ramcap' bytes.'

echo "You have" $nprocessors "processors available."
set ncores_avail = `echo $nprocessors | awk -v ram_factor=$ram_factor '{print int($1*ram_factor)}'`
echo "Using up to" $ncores_avail "of these."



# Figure out the headersizes of the packets
if ($mode == "evan" ) then
    set headersize  = 98   # bytes
    set packet_size = 7882 # (120*4*1*16+98+104) bytes
else if ($mode == "olaf") then
    set headersize  = 16   # bytes
    set packet_size = 7824 # (122*4*1*16+16)
else
    echo "Don't recognise recording mode. Slán."
    goto marbh
endif

echo "Data recorded in" $mode "mode"



# Determine the size of each execution
set memal = `echo $packet_size $npackets | awk '{print 2*$1*$2}'` # 3 seems like a slightly overboard prediction comapred to runs, but theoretically it should
                                                                  # be closer to 4-5 but runtime is normally ~ 2-3.
set data_cap = `echo $ram | awk -v ram_factor=$ram_factor '{print $1*ram_factor}'`
set nloops = `echo $data_cap $memal | awk '{print int($2/$1)}'`
set nloopsprint = `echo $data_cap $memal | awk '{print int($2/$1)+1}'` # True lazy mode

echo ""
echo 'Processing data in '$nloopsprint' segments.'

# Known issue: final chunk is not handled gracefully here; Cython code should be able to handle it through.
set packets_per_chunk = `echo $npackets $nloopsprint | awk '{print int($1/$2)}'`
set chunksize = `echo $packets_per_chunk $packet_size | awk '{print $1*$2}'`
set total_data = `echo $packet_size $npackets | awk '{print $1*$2}'`

echo "Processing "$packets_per_chunk" packets every execution, giving a chunksize of "$chunksize
echo ""


# Prep the output filterbank with a fake header
echo "Sticking on a SIGPROC header"
echo""

# Our paths are too long for sigproc to process; cut them down to size a bit, assuming we're on REALTA
set rawfilepatch = `echo $file | sed "s/\/mnt\///g"`
set rawfilepatch = `echo $rawfilepatch | sed 's/\_data1//g'`

#get the obs start MJD from the filename for the header
set tmpstr=`python /home/obs/Joe/realta_scripts/dump_filetime_mjd.py -infile $file | grep MJD:`
set MJD=`echo $tmpstr | grep -o -E '[0-9.]+'`
set fo = `echo -0.1953125 $fftWindow | awk '{print $1/$2}'`
set nchan = `echo 122 $fftWindow | awk '{print $1*$2}'`
set tsamp = `echo 0.00000512 $fftWindow $timeWindow | awk '{print $1 * $2 * $3}'`
set npols = `echo $stokesI $stokesV | awk '{print $1 +$2 }'`

echo "Patched File Name = "$rawfilepatch
echo "Obs. MJD =  "$MJD
echo "Top channel: "$fch1"MHz"
echo "Channel Width: "$fo"MHz"
echo "Channel Count: "$nchan
echo "Sampling time: "$tsamp"s"
echo "Polarisations: "$npols
echo ""


if ( $ra == 0 ) then
#    /home/obs/Joe/realta_scripts/mockHeader/mockHeader -tel $tel -tsamp $tsamp -fch1 $fch1 -fo $fo -nchans $nchan -nbits 32 -tstart $MJD -nifs $npols -source $psrName headerfile_341
    /home/obs/Joe/realta_scripts/mockHeader/mockHeader -raw $rawfilepatch -tel $tel -tsamp $tsamp -fch1 $fch1 -fo $fo -nchans $nchan -nbits 32 -tstart $MJD -nifs $npols -source $psrName headerfile_341
#    /home/obs/Joe/realta_scripts/mockHeader/mockHeader -tel $tel -tsamp 0.00000512 -fch1 $fch1 -fo -0.01220703125 -nchans 1952 -nifs 1 -nbits 32 -tstart $MJD headerfile_341
else
    /home/obs/Joe/realta_scripts/mockHeader/mockHeader -raw $file -tel $tel -tsamp $tsamp -fch1 $fch1 -fo $fo -nchans $nchan -nbits 32 -tstart $MJD -nifs $npols -ra $ra -dec $dec -source $psrName headerfile_341
endif
cat headerfile_341 >> $outfile



foreach loop (`seq 0 $nloops`)
    set hd = `echo $loop $chunksize | awk '{print $1*$2}'`

    python3 ./udp2fil_cywrapper.py -infile $file -start $hd -readlength $chunksize -o $outfile -I $stokesI -V $stokesV -sumSize $timeWindow -fftSize $fftWindow -t $ncores_avail

end

marbh:
exit


