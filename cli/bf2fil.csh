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


set testval = `echo 1000000000001 | awk --bignum '{print $1*2}'`
if ( $testval != 2000000000002 ) then
    printf "\033[5;31m"
    echo "The installed awk version is not complying with '--bignum', we cannot procced."
    printf "\033[0m\n"
    echo "You mayneed to upgrade your awk version, we require (g)awk>=4.1"
    printf "Your current version: "
    awk -Wversion
    echo ""

    set exitvar = 2
    goto marbhfail
endif


if ($#argv < 6) then
    printf "\033[1;33mUsage:\033[0m"
    echo " csh bf2fil.csh [proc_mode] [pcap_filename] [npackets] [ram_factor] [cpu_factor] [fch1/table location] [output_filename_prefix] <proc_mode options>"

    printf "\n\n\033[1;33mStandard optional parameters\033[0m: [stokesI] [stokesV] [time_averaging_length] [frequency_FFT_window] [startport] [number of ports] [target name] [RA](J2000, format hh:mm:ss.ddd) [DEC] (J2000, format dd.mm.ss.ddd))\n\n"

    printf "\033[1;33mCDMT optional parameters\033[0m: [REQUIRED cdmt_dms] [cdmt_ngulp] [cdmt_overlap] [cdmt_time_averaging_length] [startport] [number of ports] [target name] [RA](J2000, format hh:mm:ss.ddd) [DEC] (J2000, format dd.mm.ss.ddd))\n"
    
    set exitvar = 3
    goto marbhfail
endif


# Initialisation
set debug=`printenv B2FDEBUG`
if ( $debug == 1 ) printf "\033[1;33mDEBUG MODE ENABLED\033[0m\n"


set headersize  = 16   # bytes
set packet_size = 7824 # (122*4*1*16+16)
set dumpCmd=`which dump_filename_mjd.py`

if ( $status > 0 ) then
    printf "\033[5;31m"
    echo "ERROR: Unable to find dump_filename_mjd.py on path, exiting.. "
    printf "\033[0m\n"
endif

# What are we running on? How many CPU cores?
set host = `uname`
echo "Host system: "$host
if ( $host == "Darwin" ) then       # We're on a Mac
    printf "\033[5;31m"
    echo '2019-10+ Changes: Compatibility has not been tested, attempting to continue...'
    printf "\033[0m\n"
    sleep 3

    set nprocessors = `sysctl -n hw.physicalcpu`
else if ( $host == "Linux" ) then   # We're on a Linux
    set nprocessors = `nproc`
endif

set mode       = $argv[1] 
set file       = $argv[2]
set npackets   = $argv[3]
set ram_factor = $argv[4]
set cpu_factor = $argv[5]
set fch1       = $argv[6] # set the frequency of the top channel / location of table file
set outfile    = $argv[7]

echo "Processing mode: "$mode
echo "Parsing: "$file
echo "Total Packets: "$npackets

# Check if we have a fch1 or table location

echo $fch1 | grep -q -e '^[0-9]\+\([\.][0-9]\+\)\?$'
set freqtable=$status
if ( $freqtable == 0 ) then
    echo "Frequency defined by input fch1 and calculatoed foff."
else 
    echo "Frequency passed along via table located at $fch1"
endif

if ( $mode == "standard" || $mode == "4bit" ) then
    if ( $#argv > 7 ) then
        set stokesI = $argv[8]
        set stokesV = $argv[9]

        if ( $stokesV == "" ) set stokesV = 0
    
        if ( $stokesI == $stokesV ) then
            if ( $stokesI == 0 ) then
                printf "\033[5;31m"
                echo "ERROR: You have to get some kind of Stokes output..."
                printf "\033[0m\n"

                set exitvar = 4
                goto marbhfail
            else 
                set stokesBoth = 1
            endif
        else 
            set stokesBoth = 0
        endif
    else
        set stokesI = 1
        set stokesV = 0
        set stokesBoth = 0
    endif

    echo "Stokes I: "$stokesI
    echo "Stokes V: "$stokesV

    if ( $#argv > 9 ) then
        set timeWindow = $argv[10]
        set fftWindow = $argv[11]
    else 
        set timeWindow = 1
        set fftWindow = 1
    endif

    echo "Time averaged over "$timeWindow" steps"
    echo "Trading time for frequency resolution over "$fftWindow" steps."

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

    # Header data information
    set nbit = 32
    set dtype = 1


else if ( $mode == "cdmt" || $mode == "cdmt-4bit" ) then
    if ( $freqtable == 1 ) then 
        printf "\033[5;31m"
        echo "CDMT cannot handle being passed a frequency table; exiting."
        printf "\033[0m\n"

        set exitvar = 4
        goto marbhfail
    endif

    if ( $#argv > 7 ) then
        set cdmt_dm = $argv[8]
    else
        printf "\033[5;31m"
        echo "ERROR: CDMT requires a DM to target..."
        printf "\033[0m\n"

        set exitvar = 4
        goto marbhfail
    endif
    echo "CDMT DM: "$cdmt_dm
    
    if ( $#argv > 8 ) then
        set cdmt_ngulp = $argv[9]
    else
        set cdmt_ngulp = 4096
    endif
    echo "CDMT FFT Size: "$cdmt_ngulp

    if ( $#argv > 9 ) then
        set cdmt_overlap = $argv[10]
    else
        set cdmt_overlap = `echo $cdmt_ngulp | awk --bignum '{a = 2**(log($1)/log(2)-4); print a}'`
    endif
    echo "CDMT Overlap: "$cdmt_overlap

    if ( $#argv > 10 ) then
        set cdmt_time_avg = $argv[11]
    else
        set cdmt_time_avg = 1
    endif
    echo "CDMT Sample Averaging: "$cdmt_time_avg

    if ( -f $outfile"_S0.rawfil" || -f $outfile"_S1.rawfil" || -f $outfile"_S2.rawfil" || -f $outfile"_S3.rawfil" ) then 
        goto exists
    endif

    # Data information
    set nbit = 8
    set dtype = 0

    # Populate the standard mode variables
    set stokesI = 0
    set stokesV = 0
    set stokesBoth = 0
    set timeWindow = 1
    set fftWindow = 1

else 
    printf "\033[5;31m"
    echo "ERROR: Undefined mode '"$mode"'"
    printf "\033[0m\n"

    set exitvar = 4
    goto marbhfail
endif


if ( $#argv > 12 ) then
    set startport = $argv[12]
    set nports = $argv[13]
    if ( $mode == "cdmt" ) then
        if ( $nports != "4" ) then
            echo "CDMT (8bit) must be provided 4 ports of data; setting nports to 4."
            set nports = 4
    else if ( $nports == "" ) then
        set nports = 1
    endif
else
    set startport = `echo -e $file:t | sed -e 's/[^0-9]/ /g' -ne 's/^.*\([0-9]\{5\}\).*$/\1/p'`
    set nports = 1
endif
echo "Processing "$nports" ports of standard data starting at port "$startport

if ( $#argv > 13 ) then
    set psrName = $argv[14]
else 
    set psrName = "J0000+0000"
endif
echo "Source Name: "$psrName


if ( $#argv > 14 ) then
    set ra     = $argv[15]
    set dec    = $argv[16]
else
    set ra = 0
    set dec = 0
endif
echo "RA: "$ra
echo "DEC: "$dec

if ( $#argv > 16 ) then
    set telescope_id = $argv[17]
else
    set telescope_id = 1916 # Damnit Evan... Default code for IE613 in sigproc/presto
    echo "Defaulting to internal I-LOFAR telescope ID (1916)"
endif
    
echo "TelID: "$telescope_id


if  ( $mode == "4bit" || $mode == "cdmt-4bit" ) then
    set bitoffset = 2
else
    set bitoffset = 1
endif

# Exit if the output file exists
if ( -f $outfile ) then
    exists:
    printf "\033[5;31m"
    echo "Output file "$outfile" already exists, exiting before we overwrite any data."
    printf "\033[0m\n"

    set exitvar = 5
    goto marbhfail
else if ( -f $outfile".sigprochdr" ) then
    printf "\033[5;31m"
    echo "Output header "$outfile".sigprochdr already exists, exiting before we overwrite any data."
    printf "\033[0m\n"

    set exitvar = 5
    goto marbhfail
endif



# What resources are available?
set ram = `grep MemTotal /proc/meminfo | awk --bignum '{print $2*1024}'` # Get total RAM in bytes
set data_cap = `echo $ram | awk --bignum -v ram_factor=$ram_factor '{print int($1*ram_factor)}'`

echo 'You have '$ram' bytes of ram available.'
echo 'We will plan to use less than '$data_cap' bytes.'
if ( $data_cap > 536900000000 ) then
    printf "\033[1;33m"
    echo "We recommend keeping this value below 50GB; consider lowering ram_factor in future runs."
    printf "\033[0m\n"
endif

echo "You have" $nprocessors "processors available."
set ncores_avail = `echo $nprocessors | awk -v cpu_factor=$cpu_factor '{print int($1*cpu_factor)}'`
echo "Using up to" $ncores_avail "of these."




if ( "$outfile" =~ */* ) then
    mkdir -p "`dirname $outfile`"
endif


# REALTA doesn't have mockHeader on the path, fallback to self-compiled binaries
set mockHeaderCmd=`which mockHeader`

if( $status > 0 ) then

    set mockHeaderCmd = `printenv MOCKHEADER_CMD`
    if ( $status > 0 ) then
        goto mockfail
    endif

    if ( -f $mockHeaderCmd ) then
        echo $mockHeaderCmd" exists; will be used."
    else
        mockfail:
        printf "\033[5;31m"
        echo 'Unable to find mockHeader command, exiting...'
        printf "\033[0m\n"

        set exitvar = 6
        goto marbhfail
    endif
endif
echo "Using mockHeader: "$mockHeaderCmd


# TODO: determine if we can just pipe the raw pipes into the Cython program for a significant speedup (1 less read/write op is a lot of time saved)
if ( "$file" =~ *.zst ) then
    echo ""
    echo "Compressed observation detected, decompressing to "$outfile'.port.decompressed'

    set zstd_auto = `printenv ZSTD_AUTO`
    echo "ZSTD_AUTO Flag: "$zstd_auto
    
    # ucc2 doesn't have zstd installed, fallback to self-compiled binaries
    set zstdcmd = `which zstd`

    if( $status > 0 ) then
        set zstdcmd = `printenv ZSTD_CMD`
        if ( $status > 0 ) then 
            goto zstdfail
        endif
        if ( -f $zstdcmd ) then 
            echo $zstdcmd" exists; will be used."
        else 
            zstdfail:
            printf "\033[5;31m"
            echo 'Unable to find zstd command, exiting...'
            printf "\033[0m\n" 

            set exitvar = 7
            goto marbhfail
        endif
    endif

    set procports=`echo $nports | awk '{print $1-1}'`
    foreach portoff (`seq 0 1 $procports`)
        set portid = `echo $startport $portoff | awk '{print $1 + $2}'`

        echo "Swapping port "$startport" for port "$portid
        set filepatch=`echo $file | sed -e 's/'"$startport"'/'"$portid"'/'`
        echo "Decompressing "$filepatch" to "$outfile'.'$portid'.decompressed'
        if ( ! -f $outfile'.'$portid'.decompressed' ||  ! $zstd_auto ) then
            $zstdcmd -d $filepatch -o $outfile'.'$portid'.decompressed'
        else
            echo "File exists and ZSTD_AUTO=1 is set."
        endif
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
set memal = `echo $packet_size $npackets $nports | awk --bignum '{print 2*$1*$2*$3}'` # 3 seems like a slightly overboard prediction comapred to runs, but theoretically it should
                                                                                      # be closer to 4-5 but runtime is normally ~ 2-3.
set nloops = `echo $data_cap $memal | awk '{print int($2/$1)}'`
set nloopsprint = `echo $data_cap $memal | awk '{print int($2/$1)+1}'` # True lazy mode


# Known issue: final chunk is not handled gracefully here; Cython code should be able to handle it though.
set packets_per_chunk = `echo $npackets $nloopsprint $timeWindow $fftWindow | awk --bignum '{print int($1/$2)-(int($1/$2)%($3*$4))}'`
set chunksize = `echo $packets_per_chunk $packet_size | awk --bignum '{print $1*$2}'`
set total_data = `echo $packet_size $npackets | awk --bignum '{print $1*$2}'`

set nloops = `echo $npackets $packets_per_chunk | awk '{printf "%.0f", $1/$2-1}'`
set nloopsprint = `echo $npackets $packets_per_chunk | awk '{printf "%.0f", $1/$2}'` # True lazy mode

echo ""
echo 'Processing data in '$nloopsprint' segments.'
echo "Processing "$packets_per_chunk" packets every execution, giving a chunksize of "$chunksize
echo ""

# Our paths are too long for sigproc to process; cut them down to size a bit, assuming we're on REALTA
set rawfilepatch = `echo $file | sed "s/\/mnt\///g"`
set rawfilepatch = `echo $rawfilepatch | sed 's/\_data1//g'`

#get the obs start MJD from the filename for the header
set tmpstr=`$dumpCmd -infile $mjdname | grep MJD:`
set MJD=`echo $tmpstr | grep -o -E '[0-9.]+'`
set fo = `echo -0.1953125 $fftWindow | awk '{f=$1/$2; printf("%0.9lf\n", f)}'`
set nchan = `echo 122 $fftWindow $nports $bitoffset | awk '{print $1*$2*$3*$4}'`
set tsamp = `echo 0.00000512 $fftWindow $timeWindow | awk '{ts= $1*$2*$3; printf("%0.9lf\n", ts)}'`

if ( ! ( $fo != "-0.19531250" ) && $freqtable == 0 ) then
    set fch1 = `echo $fch1 0.1953125 $fo | awk --bignum '{ch=(($1 + ($2 / 2) - $3)); printf("%0.9lf\n", ch)}'`
endif

echo "Patched File Name = "$rawfilepatch
echo "Obs. MJD =  "$MJD
echo "Telescope ID = "$telescope_id

if ( $freqtable == 0 ) then 
    echo "Top channel: "$fch1"MHz"
    echo "Channel Width: "$fo"MHz"
else 
    echo "Frequency Table: $fch1"
endif
echo "Channel Count: "$nchan
echo "Sampling time: "$tsamp"s"
echo ""



# Prep the output filterbank with a fake header
echo "Sticking on a SIGPROC header"
echo ""
if ( $freqtable == 0 ) then 
    if ( $ra == 0 ) then
        echo "$mockHeaderCmd -type $dtype -raw $rawfilepatch -tel $telescope_id -tsamp $tsamp -fch1 $fch1 -fo $fo -nchans $nchan -nbits $nbit -tstart $MJD -nifs 1 -source $psrName $outfile'.sigprochdr'"
        $mockHeaderCmd -raw $rawfilepatch -tel $telescope_id -tsamp $tsamp -fch1 $fch1 -fo $fo -nchans $nchan -nbits $nbit -tstart $MJD -nifs 1 -source $psrName $outfile".sigprochdr"

    else
        echo "$mockHeaderCmd -type $dtype -raw $rawfilepatch -tel $telescope_id -tsamp $tsamp -fch1 $fch1 -fo $fo -nchans $nchan -nbits $nbit -tstart $MJD -nifs 1 -ra $ra -dec $dec -source $psrName $outfile'.sigprochdr'"
        $mockHeaderCmd -raw $rawfilepatch -tel $telescope_id -tsamp $tsamp -fch1 $fch1 -fo $fo -nchans $nchan -nbits $nbit -tstart $MJD -nifs 1 -ra $ra -dec $dec -source $psrName $outfile".sigprochdr"

    endif
else
    if ( $ra == 0 ) then
        echo "$mockHeaderCmd -type $dtype -raw $rawfilepatch -tel $telescope_id -tsamp $tsamp -freqtab $fch1 -nchans $nchan -nbits $nbit -tstart $MJD -nifs 1 -source $psrName $outfile'.sigprochdr'"
        $mockHeaderCmd -raw $rawfilepatch -tel $telescope_id -tsamp $tsamp -freqtab $fch1 -nchans $nchan -nbits $nbit -tstart $MJD -nifs 1 -source $psrName $outfile".sigprochdr"

    else
        echo "$mockHeaderCmd -type $dtype -raw $rawfilepatch -tel $telescope_id -tsamp $tsamp -freqtab -fo $fch1 -nchans $nchan -nbits $nbit -tstart $MJD -nifs 1 -ra $ra -dec $dec -source $psrName $outfile'.sigprochdr'"
        $mockHeaderCmd -raw $rawfilepatch -tel $telescope_id -tsamp $tsamp -freqtab $fch1 -nchans $nchan -nbits $nbit -tstart $MJD -nifs 1 -ra $ra -dec $dec -source $psrName $outfile".sigprochdr"

    endif
endif


if ( ! -f $outfile.sigprochdr ) then
        printf "\033[5;31m"
        echo 'Unable to find mockHeader header, processing must have failed, exiting...'
        printf "\033[0m\n"

        set exitvar = 8
        goto marbhfail
endif

if ( $mode == "standard" || $mode == "4bit" ) then

    if ( $stokesI == 1 ) then
            cat $outfile".sigprochdr" > $outfile"_stokesI.fil"
            if ( $stokesBoth == 0 ) then
                set outfile = $outfile"_stokesI.fil"
            endif
    endif
    if ( $stokesV == 1 ) then
            cat $outfile".sigprochdr" > $outfile"_stokesV.fil"
            if ( $stokesBoth == 0 ) then
                set outfile = $outfile"_stokesV.fil"
            endif
    endif

else if ( $mode == "cdmt" || $mode == "cdmt-4bit" ) then

    #echo "Let this be a reminder of the time you offset the entire observation by cat'ing the header into raw files..."
    if ( $mode == "cdmt" ) then 
        set procports=`echo $nports | awk '{print $1-1}'`
        foreach portoff (`seq 0 1 $procports`)
            set portid = `echo $startport $portoff | awk '{print $1 + $2}'`

            set filepatch=`echo $readfile | sed -e 's/'"$startport"'/'"$portid"'/'`
            echo "Forming symlink for CDMT between "$filepatch" and "$outfile'_S'$portoff

            ln -s $filepatch $outfile'_S'$portoff

        end
    endif

else
    printf "\033[5;31m"
    echo 'Undefined mode '$mode' exiting...'
    printf "\033[0m\n"
endif

if ( $debug == 1 ) then
    echo "testval: "$testval" "
    echo "debug: "$debu $headersize" "
    echo "packet_size: "$packet_size" "
    echo "dumpCmd: "$dumpCmd" "
    echo "host: "$host" "
    echo "nprocessors: "$nprocessors" "
    echo "mode: "$mode" "
    echo "file: "$file" "
    echo "npackets: "$npackets" "
    echo "ram_factor: "$ram_factor" "
    echo "cpu_factor: "$cpu_factor" "
    echo "freqtable: "$freqtable" "
    echo "stokesBoth: "$stokesBoth" "
    echo "stokesI: "$stokesI" "
    echo "stokesV: "$stokesV" "
    echo "timeWindow: "$timeWindow" "
    echo "fftWindow: "$fftWindow" "
    if ( $mode == "cdmt" || $mode == "cdmt-4bit" ) then
        echo "cdmt_dm: "$cdmt_dm" "
        echo "cdmt_ngulp: "$cdmt_ngulp" "
        echo "cdmt_overlap: "$cdmt_overlap" "
        echo "cdmt_time_avg: "$cdmt_time_avg" "
    endif
    echo "nbit: "$nbit" "
    echo "dtype: "$dtype" "
    echo "startport: "$startport" "
    echo "nports: "$nports" "
    echo "psrName: "$psrName" "
    echo "ra: "$ra" "
    echo "dec: "$dec" "
    echo "telescope_id: "$telescope_id" "
    echo "ram: "$ram" "
    echo "data_cap: "$data_cap" "$
    echo "ncores_avail: "$ncores_avail" "
    echo "mockHeaderCmd: "$mockHeaderCmd" "
    if ( "$file" =~ *.zst ) then
        echo "zstd_auto: "$zstd_auto" "
        echo "zstdcmd: "$zstdcmd" "
        echo "procports: "$procports" "
        echo "portid: "$portid" "
        echo "filepatch: "$filepatch" "
    endif
    echo "mjdname: "$mjdname" "
    echo "readfile: "$readfile" "
    echo "memal: "$memal" "
    echo "packets_per_chunk: "$packets_per_chunk" "
    echo "chunksize: "$chunksize" "
    echo "total_data: "$total_data" "
    echo "nloops: "$nloops" "
    echo "nloopsprint: "$nloopsprint" "
    echo "rawfilepatch: "$rawfilepatch" "
    echo "tmpstr: "$tmpstr" "
    echo "MJD: "$MJD" "
    echo "fo: "$fo" "
    echo "nchan: "$nchan" "
    echo "tsamp: "$tsamp" "
    echo "fch1: "$fch1" "
    echo "outfile: "$outfile" "
    printf "\n\n"
endif


set wrappercmd = `which udp2fil_cywrapper.py`
if ($status > 0) then
    echo "ERROR: Unable to find udp2fil_cywrapper.py script. Exiting."

    set exitvar = 9
    goto marbhfail
endif

if ( $mode != "cdmt" ) then 
    foreach loop (`seq 0 $nloops`)
        set hd = `echo $loop $chunksize | awk --bignum '{print $1*$2}'`

        echo "Iteration "$loop" of "$nloops
        echo "bash -c 'python3 $wrappercmd -mode $mode -infile $readfile -start $hd -readlength $chunksize -o $outfile -I $stokesI -V $stokesV -sumSize $timeWindow -fftSize $fftWindow -t $ncores_avail -p $startport -n $nports'"
        if (! $debug == 1) bash -c "python3 $wrappercmd -mode $mode -infile $readfile -start $hd -readlength $chunksize -o $outfile -I $stokesI -V $stokesV -sumSize $timeWindow -fftSize $fftWindow -t $ncores_avail -p $startport -n $nports"
        
        if ( $status == 2 ) then
            set exitcode = 11
            goto marbhfail
        endif
    end

    printf "\n\n"
    echo "Filterbank formed."
    printf "\n\n"

    if ( "$file" =~ *.zst ) then
        compcleanup:
        echo ""

        set zstdcleanup = `printenv ZSTD_CLEANUP`
        if ( $zstdcleanup == "1" ) then 
            echo "ZSTD_CLEANUP=1: Removing ZSTD artefacts"
            goto zstdcleanup
        else if ( $zstdcleanup == "0" ) then 
            echo "ZSTD_CLEANUP=0: Skipping cleanup"
            goto endzstdcleanup
        endif

        echo "Clean up decompression artefacts? [yes/NO]"
        set input = $<
        if ( $input == 'yes' ) then
            zstdcleanup:
            echo "Cleaning up decompression artefacts."
            foreach portoff (`seq 0 1 $procports`)
                set portid = `echo $startport $portoff | awk '{print $1 + $2}'`
                rm $outfile'.'$portid'.decompressed'

            end
            rm "$outfile"*.decompressed
        endif
        endzstdcleanup:

        if ( $mode == "cdmt" ) then
            goto marbh
        endif
    endif
endif

if ( $mode == "cdmt" || $mode == "cdmt-4bit" ) then

    set cdmtcmd = `which cdmt_udp`

    if ( $status > 0 ) then 
        set cdmtcmd = `printenv CDMT_CMD`
        if ( $status > 0 ) then
            echo "Unable to find CDMT_CMD enviroment variable for fallback. Exiting."

            set exitvar = 10
            goto marbhfail
        endif

        if ( -f $cdmtcmd ) then
            echo $cdmtcmd" exists; will be used."
        else
            printf "\033[5;31m"
            echo 'Unable to find cdmt_udp command, exiting...'
            printf "\033[0m\n" 

            set exitvar = 10
            goto marbhfail
        endif

    endif

    if ( $mode == "cdmt" ) then
        set extraflag = '-u'
    else
        set extraflag = ""
    endif

    set extraflag=$extraflag" "`printenv CDMT_FLAGS`

    echo "Executing CDMT command..."
    echo "bash -c $cdmtcmd -b $cdmt_time_avg -N $cdmt_ngulp -n $cdmt_overlap -d $cdmt_dm $extraflag -o $outfile $outfile"
    bash -c "$cdmtcmd -b $cdmt_time_avg -N $cdmt_ngulp -n $cdmt_overlap -d $cdmt_dm $extraflag -o $outfile $outfile"
    
    if ( $status > 0 ) then
        echo "CDMT exiting unexpectedly. Exiting."
        set exitvar = 11
        goto marbhfail
    endif

    if ( $mode == "cdmt-4bit" ) then
        set cdmtcleanup = `printenv CDMT_CLEANUP`
        if ( $cdmtcleanup == "1" ) then 
            echo "CDMT_CLEANUP=1: Removing CDMT artefacts"
            goto cdmtcleanup
        else if ( $cdmtcleanup == "0" ) then 
            echo "CDMT_CLEANUP=0: Skipping cleanup"
            goto marbh
        endif
        
        echo 'Remove intermediate filterbanks? [YES/no]'
        set input = $<

        if ( $input == 'no' ) then
            echo "Not removing intermediate filterbanks."
            goto symclean
        endif

        cdmtcleanup:
        echo "Removing intermediate filterbanks..."
        # tcsh can't RM on a wildcard? 
        rm "$outfile"_S*.rawfil
        echo "Filterbanks removed." 
    endif

    symclean:
    if ( $mode == "cdmt" ) then 
        set procports=`echo $nports | awk '{print $1-1}'`
        foreach portoff (`seq 0 1 $procports`)
            set portid = `echo $startport $portoff | awk '{print $1 + $2}'`

            set filepatch=`echo $readfile | sed -e 's/'"$startport"'/'"$portid"'/'`
            echo "Removing symlink for CDMT between "$filepatch" and "$outfile'_S'$portoff

            rm $outfile'_S'$portoff

        end

        if ( "$file" =~ *.zst ) then
            goto compcleanup
        endif
    endif
endif


marbh:
printf '\xe2\x9c\x94\xef\xb8\x8f '
echo "Processing Finished, exiting."
exit 0

marbhfail:
exit $exitvar

