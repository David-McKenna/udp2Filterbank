#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Created on Thu Feb 14 08:40:26 2019

@author: Joe McCauley
#Given a datafile created by either Olaf's dump program or evan's dump script, it parses the filename to return the MJD time
"""
import os
from astropy.time import Time

import argparse

parser = argparse.ArgumentParser()
parser.add_argument('-infile', dest='infile', help='set the input file name')
args      = parser.parse_args()
infile    = args.infile
print('mjd code working with '+infile)
if '/' in infile:
        infile = os.path.basename(infile)
if 'udp' in infile:
    #if its an 'olaf' file treat as such
    ISOtime = infile[-23:]
else:
    #assume an 'evan' file
    ISOtime = infile[-19:-9] + 'T' + infile[-8:]
print(ISOtime)


t = Time(ISOtime, format = 'isot', scale = 'utc')
print('MJD:'+ str(t.mjd))
