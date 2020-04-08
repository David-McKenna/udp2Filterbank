# distutils: extra_compile_args = -fopenmp -O3 -march=native
# distutils: extra_link_args = -fopenmp -lfftw3f_threads -lfftw3f
# cython: language_level=3
# cython: embedsignature=False
# cython: boundscheck=False
# cython: wraparound=False
# cython: nonecheck=False
# cython: cdivision=True
# cython: CYTHON_WITHOUT_ASSERTIONS=True
# 
#define NPY_NO_DEPRECATED_API NPY_1_7_API_VERSION
#

import numpy as np
import time

cimport numpy as np

from cython.parallel cimport prange

# Import C native functions
from libc.stdio cimport fseek, fread, fwrite, ftell, fopen, fclose, FILE, SEEK_SET, SEEK_END, printf, sprintf
from libc.stdlib cimport malloc, free, calloc
from libc.string cimport memcpy
from libc.math cimport pow, sin


# Define numpy/memoryview types
DTYPE_1 = np.uint8
DTYPE_2 = np.float32
ctypedef np.uint8_t DTYPE_t_1
ctypedef np.float32_t DTYPE_t_2


# Define  data dumping unctions for different sizes outputs (1pol/2pol)
cdef void writeDataShrunk(DTYPE_t_1[:, ::1] dataSet, long long dataLength, char outputLoc[]) nogil:
	printf("Writing %lld output elements to %s\n", dataLength, outputLoc)
	cdef FILE *outRef = fopen(outputLoc, 'a')
	if (outRef != NULL):
		fwrite(&dataSet[0,0], sizeof(DTYPE_t_1), dataLength, outRef) # Write as little endian, C order (last axis first)
		fclose(outRef)
	else:
		printf("ERROR: UNABLE TO OPEN OUTFPUT FILE; EXITING")




# Main read function: handles getting all data from disk into memory.
cpdef void readFile(char* fileLoc, char* portPattern, int ports, int threadCount, long long readStart, long long readLength, unsigned char stokesIT, unsigned char stokesVT, int timeDecimation, int freqDecimation, char* outputLoc):
	printf("\nVerifiyng input parameters...\n\n")
	ports = max(1, ports)

	if (readStart < 0):
		raise RuntimeError(f"Issue with input Parameter: readStart, {readStart}")

	if (readLength < -1):
		raise RuntimeError(f"Issue with input Parameter: readStart, {readLength}")

	cdef object t0, t1, t2, t3, dt

	cdef long long charSize = 9223372036854775806
	cdef int i
	cdef DTYPE_t_1* fileData
	cdef FILE* fileRef
	cdef FILE** fileRefs = <FILE**> malloc(sizeof(FILE*) * ports)

	printf("Beinging file read checks...\n\n")
	for i in range(ports):
		fileTemp = str.encode(fileLoc.decode("utf-8").replace(portPattern.decode('utf-8'), str(int(portPattern.decode('utf-8')) + i)))
		print("Attempting to open file for port {} at {}....".format(str(int(portPattern.decode('utf-8')) + i), fileTemp.decode('utf-8')))
		fileRefs[i] = fopen(fileTemp, 'r')
	
		if (fileRefs[i] == NULL):
			printf("\033[5;31m\xf0\x9f\x9b\x91	ERROR: Unable to open file!\033[0m\n")
			raise RuntimeError(f"Unable to open file at {fileTemp}")

		# Check file length against requested read length -- different ports may have different numbers of packets
		# 	due to packet loss, only save the shortest data length as the read target if needed.
		fseek(fileRefs[i], 0, SEEK_END)
		charSize = ftell(fileRefs[i]) # Get the length of the file

		# Handle the case where we are asked to read beyond the EOF
		if readLength > charSize - readStart:
			printf("\033[5;31m\xf0\x9f\x9b\x91	ERROR: File is %lld bytes long but you want to read %lld bytes from %lld.\033[0m\n", charSize, readLength, readStart)
			readLength = charSize - readStart
			printf("\033[5;31m\xf0\x9f\x9b\x91	ERROR: READ LENGTH TOO LONG\nERROR: Changing read length to EOF after %lld bytes.\033[0m\n", readLength)
		else:
			printf("File read successfully and is long enough for provided readsize of %lld bytes.\n\n", readLength)

	cdef long long packetCount = readLength // 7824 # Divide by the length of a standard UDP packet
	printf("File read checks complete; we will be scanning %lld packets into %lld bytes from each input file.\n", packetCount, readLength * sizeof(DTYPE_t_1))

	# Initialise memory for our data, setup memviews
	# Cython requires empties be setup if we are going to define a variable,
	# 	so file 1 element arrays for the unused shape.

	printf("\n\nAllocating %lld bytes to store raw data...\n", readLength * ports * sizeof(DTYPE_t_1))
	fileData = <DTYPE_t_1*> malloc(readLength * ports * sizeof(DTYPE_t_1))

	printf("\n\n\nBegining Data Read...\n\n")
	t0 = time.time()
	for i in range(ports):
		t1 = time.time()
		printf("Reading file %d, offloading %lld bytes to offset %lld...\n", i, readLength, sizeof(DTYPE_t_1) * i * readLength)
		fileRef = fileRefs[i]

		# nogil = No python memory locks
		with nogil:
			fseek(fileRef, readStart, SEEK_SET)

			if not fread(fileData + sizeof(DTYPE_t_1) * i * readLength, 1, readLength, fileRef):
				raise IOError(f"Unable to read file at {fileLoc}")

		fclose(fileRef)

		t2 = time.time()
		dt = t2 - t1
		printf("Successfully Read %lld Packets into %lld bytes.\n", packetCount, readLength * sizeof(DTYPE_t_1))
		print("This took {:.2f} seconds, with a read speed of {:.2f}MB/s".format(dt, readLength * sizeof(DTYPE_t_1) / 1024 / 1024 / dt))
		printf("\n")

	free(fileRefs)
	t3 = time.time()
	dt = t3 - t0
	printf("\n\n")
	printf("Data reading complete for all ports.\n")
	printf("Successfully Read All Data, %lld Packets into %lld bytes.\n", packetCount * ports, ports * readLength * sizeof(DTYPE_t_1))
	print("This took {:.2f} seconds, giving an overall read speed of {:.2f}MB/s".format(dt, readLength * ports * sizeof(DTYPE_t_1) / 1024 / 1024 / dt))
	printf("\n\n\n")

	cdef char outputF0[2048]
	cdef char outputF1[2048]
	cdef char outputF2[2048]
	cdef char outputF3[2048]
	sprintf(outputF0, "%s_S0.rawfil", outputLoc)
	sprintf(outputF1, "%s_S1.rawfil", outputLoc)
	sprintf(outputF2, "%s_S2.rawfil", outputLoc)
	sprintf(outputF3, "%s_S3.rawfil", outputLoc)
	printf("Data will be saved to %s_SN.rawfil once processing is finished.\n\n", outputLoc)



	cdef int j, k, kSet
	cdef int rawBeamletCount = 122
	cdef int beamletCount = rawBeamletCount * ports
	cdef int scans = 16
	cdef int port, beamletBase

	cdef long iL, baseOffset, beamletIdx
	cdef long udpPacketLength = 7824
	cdef long udpHeaderLength = 16
	cdef long timeIdx = 0

	cdef long long dataLength = int(packetCount * beamletCount * scans)

	printf("Output expected to be %lld bytes long per component, from %ld packets.\n", dataLength * sizeof(DTYPE_t_2), packetCount)
	printf("Allocating memory for processing operations...\n")


	# Initialise memory for our data, setup memviews
	# Cython requires empties be setup if we are going to define a variable,
	# 	so file 1 element arrays for the unused shape.
	structuredFileData0 = np.zeros((packetCount * scans, beamletCount), dtype = DTYPE_1)
	structuredFileData1 = np.zeros((packetCount * scans, beamletCount), dtype = DTYPE_1)
	structuredFileData2 = np.zeros((packetCount * scans, beamletCount), dtype = DTYPE_1)
	structuredFileData3 = np.zeros((packetCount * scans, beamletCount), dtype = DTYPE_1)

	cdef DTYPE_t_1[:, ::1] structuredFileData_view0 = structuredFileData0
	cdef DTYPE_t_1[:, ::1] structuredFileData_view1 = structuredFileData1
	cdef DTYPE_t_1[:, ::1] structuredFileData_view2 = structuredFileData2
	cdef DTYPE_t_1[:, ::1] structuredFileData_view3 = structuredFileData3

	printf("\n\nRemoving UDP headers in memory...\n")

	for port in range(ports):
		for iL in prange(packetCount, nogil = True, schedule = 'guided', num_threads = threadCount):
			baseOffset = udpPacketLength * (packetCount * port) + udpPacketLength * iL + udpHeaderLength
			beamletBase = beamletCount - (rawBeamletCount * port)

			for j in range(rawBeamletCount):
				beamletIdx = baseOffset + j * scans * 4
				for k in range(scans):
					# Filterbank expects the frequency to be reversed compared to input flow
					kSet = k * 4
					timeIdx = iL * scans + k
					structuredFileData_view0[timeIdx][beamletBase - 1 - j] = fileData[beamletIdx + kSet] # Xr
					structuredFileData_view1[timeIdx][beamletBase - 1 - j] = fileData[beamletIdx + kSet + 1] # Xi
					structuredFileData_view2[timeIdx][beamletBase - 1 - j] = fileData[beamletIdx + kSet + 2] # Yr
					structuredFileData_view3[timeIdx][beamletBase - 1 - j] = fileData[beamletIdx + kSet + 3] # Yi

	printf("Writing data block to disk...\n")
	writeDataShrunk(structuredFileData_view0, dataLength, outputF0)
	writeDataShrunk(structuredFileData_view1, dataLength, outputF1)
	writeDataShrunk(structuredFileData_view2, dataLength, outputF2)
	writeDataShrunk(structuredFileData_view3, dataLength, outputF3)
	# Release the raw data.
	printf("Releasing raw file data...\n")
	free(fileData)

