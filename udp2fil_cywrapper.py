# -*- coding: utf-8 -*-
"""
Created on Mon Dec 03 16:23:01 2018

@author: joe.mccauley@tcd.ie

Modified October 2019 by David McKenna
More arguments to handle expanded filterbanking script (start byte/length/stokesI/V/ summation/etc) and log the overall conversion time.
"""
import argparse
from datetime import datetime, timedelta

#from Tkinter import Tk
#from tkFileDialog import askopenfilenames
#import tkSimpleDialog 

## Parse command line arguments & set default values
parser = argparse.ArgumentParser()
parser.add_argument('-infile', dest='infile', help='set the input file name', default='')
parser.add_argument('-start', type=int, dest='start', help='Byte to start reading from file')
parser.add_argument('-readlength', type=int, dest='length', help='How many bytes to read')
parser.add_argument('-o', dest='outfile', help='Set outfile name', default='')

parser.add_argument('-I', dest='stokesI', help='Enable Stokes I processing.', default=0)
parser.add_argument('-V', dest='stokesV', help='Enable Stokes V processing.', default=0)

parser.add_argument('-sumSize', dest='timeDecimation', help='Set the size of the time averaging window.', default=1)
parser.add_argument('-fftSize', dest='freqTrans', help='Set the number of timesteps to be FFT\'d into frequency channels.', default=1)

parser.add_argument('-t', dest='threadCount', help='Set the number of threads to use when workload can be parallelised.', default=1)

args      = parser.parse_args()
infile    = args.infile
outfile   = args.outfile
start     = int(args.start)
length    = int(args.length)

stokesI = int(args.stokesI)
stokesV = int(args.stokesV)
timeSize = int(args.timeDecimation)
freqSize = int(args.freqTrans)

threads = int(args.threadCount)

starttime = datetime.utcnow()

import cyUdp2fil as udp

startTime = datetime.utcnow()
print('Raw to filterbank conversion started on ' + infile + ' at: ' + str(startTime)[0:19])
print("Reading {} bytes starting at {}".format(length, start))

udp.readFile(str.encode(infile), threads, start, length, stokesI, stokesV, timeSize, freqSize, str.encode(outfile))

endTime = datetime.utcnow()
print('Raw to filterbank conversion completed on ' + infile + ' at: ' + str(datetime.utcnow())[0:19])
print("Filterbank Conversion took {} seconds.\n\n".format((endTime - startTime)))
