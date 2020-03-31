#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Created on Mon Dec 03 16:23:01 2018

@author: joe.mccauley@tcd.ie

Modified October 2019 by David McKenna
More arguments to handle expanded filterbanking script (start byte/length/stokesI/V/ summation/etc) and log the overall conversion time.
"""
import argparse
from datetime import datetime, timedelta
import cyUdp2fil as udp


if __name__ == '__main__':
	## Parse command line arguments & set default values
	parser = argparse.ArgumentParser()
	parser.add_argument('-infile', dest='infile', help='set the input file name', default='')
	parser.add_argument('-start', type=int, dest='start', help='Byte to start reading from file')
	parser.add_argument('-readlength', type=int, dest='length', help='How many bytes to read')
	parser.add_argument('-p', type=int, dest='startport', help="Base UDP port to start filterbanking on (lowest channel)", default=16130)
	parser.add_argument('-n', type=int, dest='nports', help='Number of ports to process', default=1)
	parser.add_argument('-o', dest='outfile', help='Set outfile name', default='')

	parser.add_argument('-I', dest='stokesI', help='Enable Stokes I processing.', default=0)
	parser.add_argument('-V', dest='stokesV', help='Enable Stokes V processing.', default=0)

	parser.add_argument('-sumSize', dest='timeDecimation', help='Set the size of the time averaging window.', default=1)
	parser.add_argument('-fftSize', dest='freqTrans', help='Set the number of timesteps to be FFT\'d into frequency channels.', default=1)

	parser.add_argument('-t', dest='threadCount', help='Set the number of threads to use when workload can be parallelised.', default=1)

	args      = parser.parse_args()
	infile    = args.infile
	outfile   = args.outfile
	startport = str(args.startport)
	nports    = int(args.nports)
	start     = int(args.start)
	length    = int(args.length)

	stokesI = int(args.stokesI)
	stokesV = int(args.stokesV)
	timeSize = int(args.timeDecimation)
	freqSize = int(args.freqTrans)

	threads = int(args.threadCount)

	startTime = datetime.utcnow()
	print('Raw to filterbank conversion started on ' + infile + ' at: ' + str(startTime)[0:19])
	print("Reading {} bytes starting at {}".format(length, start))

	#udp.readFile(str.encode("testfil.fil.16130.decompressed"), str.encode("16130"), 4, 1, 0, 78240000, 1, 1, 1, 32, str.encode("test"))
	#print(f"Library call: cyUdp2fil.readFile(str.encode({infile}), str.encode({startport}), {nports}, {threads}, {start}, {length}, {stokesI}, {stokesV}, {timeSize}, {freqSize}, str.encode({outfile}))")
	udp.readFile(str.encode(infile), str.encode(startport), nports, threads, start, length, stokesI, stokesV, timeSize, freqSize, str.encode(outfile))

	endTime = datetime.utcnow()
	print('Raw to filterbank conversion completed on ' + infile + ' at: ' + str(datetime.utcnow())[0:19])
	print("Filterbank Conversion took {} seconds.\n\n".format((endTime - startTime)))
	