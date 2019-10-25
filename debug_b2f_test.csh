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
#2019-10-7 Modified By David McKenna
#Make the ram_factor actually effect the ram allocation as well as core count
#   This was implemented through the new 'loop' system for chunking and running
#   the relevant filter script on the chunks.

if ($#argv < 6) then
    echo "Usage: csh bf2fil.csh [pcap_filename] [npackets] [mode] [ram_factor] [fch1] (optional parameters are [RA](J2000, format hh:mm:ss.ddd) [DEC] (J2000, format dd.mm.ss.ddd))"
    goto marbh
endif

set file       = $argv[1]
set npackets   = $argv[2]
set mode       = $argv[3] # evan or olaf
set ram_factor = $argv[4] # Set some kind of arbitrary nice-ness factor (sets what fraction of cpu cores to use)
set fch1       = $argv[5] # set the frequency of the top channel
set outfile    = $argv[6]
if ( $#argv == 7 ) then
    set ra     = $argv[6]
    set dec    = $argv[7]
    echo "RA="$ra
    echo "DEC="$dec
else
    set ra = 0
    set dec = 0
endif
set tel = 11
# How many processors do we have?
set host = `uname`
echo $host
if ($host == "Darwin") then       # We're on a Mac
    echo '2019-10-07 Changes: May no longer be comptible, atteppting to continue...'
    set nprocessors = `sysctl -n hw.physicalcpu`
else if ($host == "Linux") then   # We're on a Linux
    set nprocessors = `nproc`
endif

set ram = `grep MemTotal /proc/meminfo | awk '{print $2*1024}'` # Get total RAM in bytes

echo 'Available memory '$ram

echo "You have" $nprocessors "processors available"
set ncores_avail = `echo $nprocessors | awk -v ram_factor=$ram_factor '{print int($1*ram_factor)}'`
echo "Using" $ncores_avail "of these"

set ncores_avail = 4
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

set memal = `echo $packet_size $npackets | awk '{print 3*$1*$2}'` # 3 seems like a slightly overboard prediction, but better to be safe than sorry.
set data_cap = `echo $ram | awk -v ram_factor=$ram_factor '{print $1*ram_factor}'`
set nloops = `echo $data_cap $memal | awk '{print int($2/$1)}'`
#set nloops = 1

set nloopsprint = `echo $data_cap $memal | awk '{print int($2/$1)+1}'` # True lazy mode


echo 'Predicted memory allocation '$memal
echo 'Memory cap '$data_cap

set nloops = 1
#set outfile = "file_stokesV.fil"

#Chop up the file
if ($nloops == 0) then
    
    echo 'Processing data in 1 loop.'
    set packets_per_chunk = `echo $ncores_avail $npackets | awk '{print int($2/$1)-int($2/$1)}'`
    set chunksize = `echo $packets_per_chunk $packet_size | awk '{print $1*$2}'`
    echo 'Chunksize ' $chunksize ' Packets per chunk' $packets_per_chunk

    foreach chunk (`seq 1 $ncores_avail`)
        set hd = `echo $chunk $chunksize | awk '{print $1*$2}'`
        echo "Chunk" $chunk
        schedtool -a $chunk -e head -c $hd $file | tail -c $chunksize > "chunk"$chunk &
#       head -c $hd $file | tail -c $chunksize > "chunk"$chunk
        echo "Done"
    end
    wait # wait for the chunking up of the data to be complete before 

    # Run bf2fil.py on each chunk, using a different processor for each
    foreach chunk (`seq 1 $ncores_avail`)
        if ($mode == "evan") then
            echo "Running bf2fil.py on chunk" $chunk
            schedtool -a $chunk -e python /home/obs/Joe/realta_scripts/bf2fil.py -infile "chunk"$chunk -npackets $packets_per_chunk -nbeamlets 122 -nbits 8 -mode $mode -o "chunk"$chunk".tmp" &
        else if ($mode == "olaf") then
            echo "Running udp2fil.py on chunk" $chunk
            schedtool -a $chunk -e python3 ./udp2fil_cywrapper.py -infile "chunk"$chunk -npackets $packets_per_chunk -o "chunk"$chunk".tmp" &
        endif
    end
    wait # wait for all the bf2fil.py calls to finish before progressing
    
    skip:
    rm full.tmp
    echo "Re-stitching the chunks"
    foreach chunk (`seq 1 $ncores_avail`)
        cat "chunk"$chunk".tmp" >> full.tmp
    end


else

    echo 'Processing data in '$nloopsprint' loops.'

    set packets_per_chunk = `echo $ncores_avail $npackets $nloopsprint | awk '{print int($2/$1/$3)-int($2/$1/$3)%16}'`
    set chunksize = `echo $packets_per_chunk $packet_size | awk '{print $1*$2}'`
    set total_data = `echo $packet_size $npackets | awk '{print $1*$2}'`
    echo 'Chunksize ' $chunksize ' Packets per chunk' $packets_per_chunk
    #goto skiptome
    #goto skip

    echo "Sticking on a SIGPROC header"
    #get the obs start MJD from the filename for the header
    echo 'this is the file'$file
    set tmpstr=`python /home/obs/Joe/realta_scripts/dump_filetime_mjd.py -infile $file | grep MJD:`
    set MJD=`echo $tmpstr | grep -o -E '[0-9.]+'`
    echo "Obs. MJD =  "$MJD
    if ( $ra == 0 ) then
        /home/obs/Joe/realta_scripts/mockHeader/mockHeader -tel $tel -tsamp 0.00008192 -fch1 $fch1 -fo -0.01220703125 -nchans 1952 -nbits 32 -tstart $MJD headerfile_341
#        /home/obs/Joe/realta_scripts/mockHeader/mockHeader -tel $tel -tsamp 0.00000512 -fch1 $fch1 -fo -0.01220703125 -nchans 1952 -nifs 1 -nbits 32 -tstart $MJD headerfile_341
    else
        /home/obs/Joe/realta_scripts/mockHeader/mockHeader -tel $tel -tsamp 0.00008192 -fch1 $fch1 -fo -0.1953125 -nchans 122 -nbits 32 -tstart $MJD  -ra $ra -dec $dec headerfile_341
    endif
    cat headerfile_341 >> $outfile


    foreach loop (`seq 0 $nloops`)
        foreach chunk (`seq 1 $ncores_avail`)
            set newchunk = `echo $chunk $loop $ncores_avail | awk '{print $1+$2*$3}'`
            set hd = `echo $newchunk $chunksize | awk '{print $1*$2}'`
            echo "Chunk" $newchunk", hd "$hd", File Size "$total_data""
	    #python3 ./udp2fil_cywrapper.py -infile "chunk"$newchunk -npackets $packets_per_chunk -o "chunk"$newchunk".tmp"
            python3 ./udp2fil_cywrapper.py -infile $file -start $hd -readlength $chunksize -o $outfile
#            schedtool -a $chunk -e head -c $hd $file | tail -c $chunksize > "chunk"$newchunk &
#           head -c $hd $file | tail -c $chunksize > "chunk"$chunk
            echo "Done"
        end
#        wait # wait for the chunking up of the data to be complete before
    end
    goto skip3
    skiptome:
    foreach loop (`seq 0 $nloops`)
        foreach chunk (`seq 1 $ncores_avail`)
            set newchunk = `echo $chunk $loop $ncores_avail | awk '{print $1+$2*$3}'`
            if ($mode == "evan") then
                echo "Running bf2fil.py on chunk" $newchunk
                schedtool -a $chunk -e python /home/obs/Joe/realta_scripts/bf2fil.py -infile "chunk"$newchunk -npackets $packets_per_chunk -nbeamlets 122 -nbits 8 -mode $mode -o "chunk"$newchunk".tmp" &
            else if ($mode == "olaf") then
                echo "Running udp2fil.py on chunk" $newchunk
                #schedtool -a $chunk -e python3 ./udp2fil_cywrapper.py -infile "chunk"$newchunk -npackets $packets_per_chunk -o "chunk"$newchunk".tmp" &
#                schedtool -a $chunk -e python3 ./udp2fil_cywrapper.py -infile "chunk"$newchunk -npackets $packets_per_chunk -o "chunk"$newchunk".tmp" &
		# New code has inbuild paralelisation
		python3 ./udp2fil_cywrapper.py -infile "chunk"$newchunk -npackets $packets_per_chunk -o "chunk"$newchunk".tmp"
		#echo "Sleeping for "$varsleep"s for prevent file i/o bottleneck
            endif
        end
#        wait # wait for all the bf2fil.py calls to finish before progressing
    end
    skip3:
    exit
endif



skip:

echo "Sticking on a SIGPROC header"
#get the obs start MJD from the filename for the header
echo 'this is the file'$file
set tmpstr=`python /home/obs/Joe/realta_scripts/dump_filetime_mjd.py -infile $file | grep MJD:`
set MJD=`echo $tmpstr | grep -o -E '[0-9.]+'`
echo "Obs. MJD =  "$MJD
if ( $ra == 0 ) then
    /home/obs/Joe/realta_scripts/mockHeader/mockHeader -tel $tel -tsamp 0.00000512 -fch1 $fch1 -fo -0.01220703125 -nchans 1952 -nbits 32 -tstart $MJD headerfile_341
else
    /home/obs/Joe/realta_scripts/mockHeader/mockHeader -tel $tel -tsamp 0.00008192 -fch1 $fch1 -fo -0.1953125 -nchans 122 -nbits 32 -tstart $MJD  -ra $ra -dec $dec headerfile_341
endif
cat headerfile_341 full.tmp > "file2.fil"
rm chunk*
rm full.tmp
marbh:
exit


