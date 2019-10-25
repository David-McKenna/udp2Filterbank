# -*- coding: utf-8 -*-
"""
Created on Mon Dec 03 16:23:01 2018

@author: joe.mccauley@tcd.ie
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
parser.add_argument('-o', dest='outfile', help='Set outfile name', default='outfile')
args      = parser.parse_args()
infile    = args.infile
outfile   = args.outfile
start     = args.start
length    = args.length
starttime = datetime.utcnow()
print ('Raw to filterbank conversion started on ' + infile + ' at: ' + str(datetime.utcnow())[0:19])


import cyUdp2fil as udp

udp.readFile(str.encode(infile), 60, start, length, 1, 0, 1, 16, str.encode(outfile))

