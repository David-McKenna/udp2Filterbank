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



#2019-10-* Modified by David McKenna
#   No longer apply chunking to the input dataset; use a new Cython-based backend
#   to read / process / write the data to a single output file. Also adds in time/
#   frequency tradeoffs for dealing with shorter period / higher DM pulsars.

if ($#argv < 6) then
    printf "\033[1;33mUsage:\033[0m"
    echo "csh bf2fil.csh [pcap_filename] [npackets] [mode] [ram_factor] [cpu_factor] [fch1] [output_filename] (optional parameters are [stokesI (0/1)] [stokesV (0/1)] [time_averaging_length] [frequency_FFT_window] [startport] [number of ports] [pulsar name] [RA](J2000, format hh:mm:ss.ddd) [DEC] (J2000, format dd.mm.ss.ddd))"
    goto marbh
endif


# Initialisation
set file       = $argv[1]
set npackets   = $argv[2]
set mode       = $argv[3] # evan or olaf
set ram_factor = $argv[4] # Set some kind of arbitrary nice-ness factor (sets what fraction of cpu cores/est. ram can be used)
set cpu_cores  = $argv[5]
set fch1       = $argv[6] # set the frequency of the top channel
set outfile    = $argv[7]

echo "Parsing: "$file
echo "Total Packets: "$npackets
echo "Obs Mode: "$mode

if ( $#argv > 7 ) then
    set stokesI = $argv[8]
    set stokesV = $argv[9]

    if ( $stokesI == $stokesV ) then
        if ( $stokesI == 0 ) then
            printf "\033[5;31m"
            echo "ERROR: You have to get some kind of Stokes output..."
            printf "\033[0m\n"
            goto marbh
        endif
    endif
else
    set stokesI = 1
    set stokesV = 0
endif

if ( $#argv > 9 ) then
    set timeWindow = $argv[10]
    set fftWindow = $argv[11]
    echo "Time averaged over "$timeWindow" steps"
    echo "Trading time for frequency resolution over "$fftWindow" steps."
else 
    set timeWindow = 1
    set fftWindow = 1
endif

if ( $#argv > 11 ) then
    set startport = $argv[12]
    set nports = $argv[13]
    if ( $nports == "" ) then
        set nports = 1
    endif
else
    set startport = `echo -e $file:t | sed -e 's/[^0-9]/ /g' -ne 's/^.*\([0-9]\{5\}\).*$/\1/p'`
    set nports = 1
endif
echo "Processing "$nports" ports of standard data starting at port "$startport

if ( $#argv > 13 ) then
    set psrName = $argv[14]
    echo "Pulsar Name "$psrName
else 
    set psrName = "J0000+0000"
endif

if ( $#argv > 14 ) then
    set ra     = $argv[15]
    set dec    = $argv[16]
    echo "RA="$ra
    echo "DEC="$dec
else
    set ra = 0
    set dec = 0
endif

set tel = 11 # LOFAR faked in PRESTO/Sigproc.



if ( $stokesI == 1 ) then
        if ( -f $outfile"_stokesI.fil" ) then 
            goto exists
        endif
endif
if ( $stokesV == 1 ) then
        if ( -f $outfile"_stokesV.fil" ) then 
            goto exists
        endif
endif


# Exit if the output file exists
if ( -f $outfile ) then
    exists:
    printf "\033[5;31m"
    echo "Output file "$outfile" already exists, exiting before we overwrite any data."
    printf "\033[0m\n"
    goto marbh
endif



# What are we running on? How many CPU cores?
set host = `uname`
echo "Host system: "$host
if ( $host == "Darwin" ) then       # We're on a Mac
    printf "\033[5;31m"
    echo '2019-10 Changes: Compatibility has not been tested, attempting to continue...'
    printf "\033[0m\n"
    sleep 3

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
set ncores_avail = `echo $nprocessors | awk -v cpu_cores=$cpu_cores '{print int($1*cpu_cores)}'`
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

if ( "$outfile" =~ */* ) then
    mkdir -p "`dirname $outfile`"
endif


# REALTA doesn't have mockHeader on the path, fallback to self-compiled binaries
set mockHeaderCmd=`which mockHeader`
echo "Testing mockHeader: "$mockHeaderCmd
if( $mockHeaderCmd == "" ) then

    set mockHeaderCmd = `printenv MOCKHEADER_CMD`
    if ( -f $mockHeaderCmd ) then
        echo $mockHeaderCmd" exists; will be used."
    else
        printf "\033[5;31m"
        echo 'Unable to find mockHeader command, exiting...'
        printf "\033[0m\n"
        goto marbh 
    endif
endif


# TODO: determine if we can just pipe the raw pipes into the Cython program for a significant speedup (1 less read/write op is a lot of time saved)
if ( "$file" =~ *.zst ) then
    echo ""
    echo "Compressed observation detected, decompressing to "$outfile'.port.decompressed'
    
    # ucc2 doesn't have zstd installed, fallback to self-compiled binaries
    set zstdcmd = `which zstd`
    if( $zstdcmd == "" ) then
        set zstdcmd = "/home/dmckenna/bin/zstd"
    
        if ( -f $zstdcmd ) then 
            echo $zstdcmd" exists; will be used."
        else 
            set zstdcmd = `printenv ZSTD_CMD`
            if ( -f $zstdcmd ) then
                echo $zstdcmd" exists; will be used."
            else
                printf "\033[5;31m"
                echo 'Unable to find zstd command, exiting...'
                printf "\033[0m\n" 
                goto marbh   
            endif
        endif
    endif

    set procports=`echo $nports | awk '{print $1-1}'`
    foreach portoff (`seq 0 1 $procports`)
        set portid = `echo $startport $portoff | awk '{print $1 + $2}'`

        echo "Swapping port "$startport" for port "$portid
        set filepatch=`echo $file | sed -e 's/'"$startport"'/'"$portid"'/'`
        echo "Decompressing "$filepatch" to "$outfile'.'$portid'.decompressed'

        $zstdcmd -d $filepatch -o $outfile'.'$portid'.decompressed'
        set mjdname = `echo $file | sed 's/.\{4\}$//'`

        if ( $portoff == 0 ) then
            set readfile = $outfile'.'$portid'.decompressed'
        endif

    end
    echo ""
else
    set mjdname = $file
    set readfile = $file
endif


# Determine the size of each execution
set memal = `echo $packet_size $npackets $nports | awk '{print 2*$1*$2*$3}'` # 3 seems like a slightly overboard prediction comapred to runs, but theoretically it should
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
echo ""

# Our paths are too long for sigproc to process; cut them down to size a bit, assuming we're on REALTA
set rawfilepatch = `echo $file | sed "s/\/mnt\///g"`
set rawfilepatch = `echo $rawfilepatch | sed 's/\_data1//g'`

#get the obs start MJD from the filename for the header
set dumpCmd=`which dump_filename_mjd.py`
set tmpstr=`$dumpCmd -infile $mjdname | grep MJD:`
set MJD=`echo $tmpstr | grep -o -E '[0-9.]+'`
set fo = `echo -0.1953125 $fftWindow | awk '{print $1/$2}'`
set nchan = `echo 122 $fftWindow $nports | awk '{print $1*$2*$3}'`
set tsamp = `echo 0.00000512 $fftWindow $timeWindow | awk '{print $1 * $2 * $3}'`
set npols = `echo $stokesI $stokesV | awk '{print $1 + $2 }'`

echo "Patched File Name = "$rawfilepatch
echo "Obs. MJD =  "$MJD
echo "Top channel: "$fch1"MHz"
echo "Channel Width: "$fo"MHz"
echo "Channel Count: "$nchan
echo "Sampling time: "$tsamp"s"
echo "Polarisations: "$npols
echo ""


if ( $ra == 0 ) then
    echo "$mockHeaderCmd -raw $rawfilepatch -tel $tel -tsamp $tsamp -fch1 $fch1 -fo $fo -nchans $nchan -nbits 32 -tstart $MJD -nifs $npols -source $psrName $outfile'.sigprochdr'"
    $mockHeaderCmd -raw $rawfilepatch -tel $tel -tsamp $tsamp -fch1 $fch1 -fo $fo -nchans $nchan -nbits 32 -tstart $MJD -nifs $npols -source $psrName $outfile".sigprochdr"

else
    echo "$mockHeaderCmd -raw $rawfilepatch -tel $tel -tsamp $tsamp -fch1 $fch1 -fo $fo -nchans $nchan -nbits 32 -tstart $MJD -nifs $npols -ra $ra -dec $dec -source $psrName $outfile'.sigprochdr'"
    $mockHeaderCmd -raw $rawfilepatch -tel $tel -tsamp $tsamp -fch1 $fch1 -fo $fo -nchans $nchan -nbits 32 -tstart $MJD -nifs $npols -ra $ra -dec $dec -source $psrName $outfile".sigprochdr"

endif

if ( $stokesI == 1 ) then
        cat $outfile".sigprochdr" > $outfile"_stokesI.fil"
endif
if ( $stokesV == 1 ) then
        cat $outfile".sigprochdr" > $outfile"_stokesV.fil"
endif




foreach loop (`seq 0 $nloops`)
    set hd = `echo $loop $chunksize | awk '{print $1*$2}'`

    set wrappercmd = `which udp2fil_cywrapper.py`
    echo "bash -c 'python3 $wrappercmd -infile $readfile -start $hd -readlength $chunksize -o $outfile -I $stokesI -V $stokesV -sumSize $timeWindow -fftSize $fftWindow -t $ncores_avail -p $startport -n $nports'"
    bash -c "python3 $wrappercmd -infile $readfile -start $hd -readlength $chunksize -o $outfile -I $stokesI -V $stokesV -sumSize $timeWindow -fftSize $fftWindow -t $ncores_avail -p $startport -n $nports"

end

if ( "$file" =~ *.zst ) then
    echo ""
    echo "Clean up decompression artefacts? [yes/NO]"
    set input = $<
    if ( $input == 'yes' ) then
        echo "Cleaning up decompression artefacts."
        rm $outfile'.decompressed'
    endif
endif

marbh:
exit

