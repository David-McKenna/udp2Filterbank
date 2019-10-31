# distutils: extra_compile_args = -fopenmp -O3 -march=native
# distutils: extra_link_args = -fopenmp -lfftw3f
# cython: language_level=3
# cython: embedsignature=False
# cython: boundscheck=False
# cython: wraparound=False
# cython: noncheck=False
# cython: cdivision=True
# cython: CYTHON_WITHOUT_ASSERTIONS=True
# 
#define NPY_NO_DEPRECATED_API NPY_1_7_API_VERSION

import numpy as np
import time

cimport numpy as np

from cython.parallel cimport prange

# Import C native functions
from libc.stdio cimport fseek, fread, fwrite, ftell, fopen, fclose, FILE, SEEK_SET, SEEK_END, printf, sprintf
from libc.stdlib cimport malloc, free
from libc.string cimport memcpy
from libc.math cimport pow, sin


# Define numpy/memoryview types
DTYPE_1 = np.uint8
DTYPE_2 = np.float32
ctypedef np.uint8_t DTYPE_t_1
ctypedef np.float32_t DTYPE_t_2


# Import fftw3 functions (fftw3f for floating point precision)
cdef extern from "fftw3.h" nogil:
	ctypedef DTYPE_t_2 fftwf_complex[2]
	ctypedef struct fftwf_plan:
		pass

	cdef fftwf_plan fftwf_plan_dft_1d(int N, fftwf_complex *inVar, fftwf_complex *outVar, int direction, unsigned char flags)
	cdef void fftwf_execute(const fftwf_plan plan)
	cdef void *fftwf_malloc(size_t size)
	cdef void fftwf_destroy_plan(fftwf_plan plan)
	cdef void fftwf_free(fftwf_complex[2] arr)
	cdef unsigned char FFTW_ESTIMATE = 1U << 6

	cdef int fftw_import_wisdom_from_filename(const char *filename)




# Define our stokes functions for different forms / precisions
cdef DTYPE_t_2 stokesI(unsigned char Xr, unsigned char Xi, unsigned char Yr, unsigned char Yi) nogil:
	return <DTYPE_t_2> ((Xr * Xr) + (Yr * Yr) + (Xi * Xi) + (Yi * Yi))

cdef DTYPE_t_2 stokesIf(DTYPE_t_2 Xr, DTYPE_t_2 Xi, DTYPE_t_2 Yr, DTYPE_t_2 Yi) nogil:
	return <DTYPE_t_2> ((Xr * Xr) + (Yr * Yr) + (Xi * Xi) + (Yi * Yi))


cdef DTYPE_t_2 stokesV(unsigned char Xr, unsigned char Xi, unsigned char Yr, unsigned char Yi) nogil:
	return <DTYPE_t_2> (2 * ((Xr * Yi) + (-1 * Xi * Yr)))




# Define  data dumping unctions for different sizes outputs (1pol/2pol)
cdef void writeDataShrunk(DTYPE_t_2[:, ::1] dataSet, long long dataLength, char outputLoc[]) nogil:
	printf("Writing %lld output elements to %s\n", dataLength, outputLoc)
	cdef FILE *outRef = fopen(outputLoc, 'a')
	if (outRef != NULL):
		fwrite(&dataSet[0,0], sizeof(DTYPE_t_2), dataLength, outRef) # Write as little endian, C order (last axis first)
		fclose(outRef)
	else:
		printf("ERROR: UNABLE TO OPEN OUTFPUT FILE; EXITING")

cdef void writeData(DTYPE_t_2[:, :, ::1] dataSet, long long dataLength, char outputLoc[]) nogil:
	printf("Writing %lld output elements to %s\n", dataLength, outputLoc)
	cdef FILE *outRef = fopen(outputLoc, 'a')
	if (outRef != NULL):
		fwrite(&dataSet[0,0,0], sizeof(DTYPE_t_2), dataLength, outRef) # Write as little endian, C order (last axis first)
		fclose(outRef)
	else:
		printf("ERROR: UNABLE TO OPEN OUTFPUT FILE; EXITING")



# Main read function: handles getting all data from disk into memory.
cpdef void readFile(char* fileLoc, int threadCount, long long readStart, long long readLength, unsigned char stokesIT, unsigned char stokesVT, int timeDecimation, int freqDecimation, char* outputLoc):


	# Standard sanity checks.
	if (timeDecimation <= 0):
		raise RuntimeError(f"Issue with input Parameter: timeDecimation, {timeDecimation}")
	if (freqDecimation <= 0):
		raise RuntimeError(f"Issue with input Parameter: timeDecimation, {freqDecimation}")
	if (not stokesIT and not stokesVT):
		raise RuntimeError(f"Issue with input Parameter: neither Stokes I or V selected, {stokesIT}, {stokesVT}")
	if (readStart < 0):
		raise RuntimeError(f"Issue with input Parameter: readStart, {readStart}")

	if (readLength < -1):
		raise RuntimeError(f"Issue with input Parameter: readStart, {readLength}")

	cdef long long charSize
	cdef DTYPE_t_1* fileData
	cdef FILE *fileRef = fopen(fileLoc, 'r')
	
	if (fileRef == NULL):
		raise RuntimeError(f"Unable to open file at {fileLoc}")

	printf("Begining Data Read...\n")
	t1 = time.time()

	# nogil = No python memory locks
	with nogil:
		fseek(fileRef, 0, SEEK_END)
		charSize = ftell(fileRef) # Get the length of the file

		# Handle the case where we are asked to read beyond the EOF
		if readLength > charSize - readStart:
			printf("ERROR: File is %lld bytes long but you want to read %lld bytes from %lld.", charSize, readLength, readStart)
			charSize = charSize - readStart
			printf("ERROR: READ LENGTH TOO LONG\nERROR: Changing read length to EOF after %lld bytes", charSize)
		else:
			charSize = readLength

		fseek(fileRef, readStart, SEEK_SET)

		# malloc to hold the data in memory; free'd in the sub function.
		fileData = <DTYPE_t_1*>malloc(charSize * sizeof(DTYPE_t_1))
		if not fread(fileData, 1, charSize, fileRef):
			raise IOError(f"Unable to read file at {fileLoc}")

		fclose(fileRef)


	t2 = time.time()
	cdef long long packetCount = charSize // 7824 # Divide by the length of a standard UDP packet
	printf("Successfully Read %lld Packets into %lld bytes.\n", packetCount, charSize * sizeof(DTYPE_t_1))
	print("This took {:.2f} seconds, giving a read speed of {:.2f}MB/s".format(t2 - t1, charSize / 1024 / 1024 / (t2 - t1)))


	# Assume our output location is less than 1k characters long...
	cdef char[1000] outputF
	if outputLoc == b"":
		sprintf(outputF, "%s.tmp", fileLoc)
	else:
		sprintf(outputF, "%s", outputLoc)

	# fileData is free'd in this function
	processData(fileData, threadCount, packetCount, stokesIT, stokesVT, timeDecimation, freqDecimation, outputF)

#cdef tuple processData(DTYPE_t_1* fileData, long packetCount, unsigned char stokesIT, unsigned char stokesVT, int timeDecimation, int freqDecimation, char* outputLoc):
cdef void processData(DTYPE_t_1* fileData, int threadCount, long packetCount, unsigned char stokesIT, unsigned char stokesVT, int timeDecimation, int freqDecimation, char* outputLoc):

	# Initialise all variables.
	cdef unsigned char Xr, Xi, Yr, Yi

	cdef int j, k, kSet, l
	cdef int beamletCount = 122
	cdef int scans = 16
	cdef int filterbankIdx = 0
	cdef int filterbankLim = freqDecimation - 1
	cdef int fftOffset = freqDecimation // 2
	cdef int mirror = 0

	cdef DTYPE_t_2 *hannWindow = <DTYPE_t_2*>malloc(sizeof(DTYPE_t_2) * freqDecimation)
	cdef DTYPE_t_2 pi = np.pi

	cdef long i, iSet
	cdef long udpPacketLength = 7824
	cdef long udpHeaderLength = 16
	cdef long timeIdx = 0
	cdef long timeSteps = packetCount * scans // timeDecimation

	cdef long long dataLength = int(packetCount * (beamletCount) * (scans / timeDecimation) * (stokesIT + stokesVT)) # freqDecimation has a 1:1 transfer between time/freq, so no effect on output size.


	printf("Output expected to be %lld bytes long, from %ld packets and %d modes.\n", dataLength * sizeof(DTYPE_t_2), packetCount, stokesIT + stokesVT)


	# Initialise memory for our data
	structuredFileData = np.zeros((beamletCount, packetCount * scans,  4), dtype = DTYPE_1)

	if stokesVT + stokesIT == 1:
		stokesSingleData = np.zeros((beamletCount, packetCount * scans), dtype = DTYPE_2)
		stokesSingleOut = np.zeros((packetCount * scans // timeDecimation // freqDecimation, beamletCount * freqDecimation), dtype = DTYPE_2)

		stokesDualData = np.zeros((1,1,1), dtype = DTYPE_2)
		stokesDualOut = np.zeros((1,1,1), dtype = DTYPE_2)
	else:
		stokesDualData = np.zeros((beamletCount, 2, packetCount * scans), dtype = DTYPE_2)
		stokesDualOut = np.zeros((packetCount * scans // timeDecimation // freqDecimation, 2, beamletCount * freqDecimation), dtype = DTYPE_2)

		stokesSingleData = np.zeros((1,1), dtype = DTYPE_2)
		stokesSingleOut = np.zeros((1,1), dtype = DTYPE_2)
	
	cdef DTYPE_t_1[:, :, ::1] structuredFileData_view = structuredFileData
	cdef DTYPE_t_2[:, ::1] stokesSingle_view = stokesSingleData
	cdef DTYPE_t_2[:, :, ::1] stokesDual_view = stokesDualData
	cdef DTYPE_t_2[:, ::1] stokesSingleOut_view = stokesSingleOut
	cdef DTYPE_t_2[:, :, ::1] stokesDualOut_view = stokesDualOut


	# Initialise FFTW, WARNING, THIS IS NOT THREAD SAFE, DO NOT ATTEMPT TO OMP/PRANGE YOUR WAY TO PARALLELISM AGAIN
	cdef fftwf_complex* inVarX = <fftwf_complex*> fftwf_malloc(sizeof(fftwf_complex) * freqDecimation);
	cdef fftwf_complex* outVarX = <fftwf_complex*> fftwf_malloc(sizeof(fftwf_complex) * freqDecimation);
	cdef fftwf_plan fftPlanX = fftwf_plan_dft_1d(freqDecimation, inVarX, outVarX, -1, FFTW_ESTIMATE)

	cdef fftwf_complex* inVarY = <fftwf_complex*> fftwf_malloc(sizeof(fftwf_complex) * freqDecimation);
	cdef fftwf_complex* outVarY = <fftwf_complex*> fftwf_malloc(sizeof(fftwf_complex) * freqDecimation);
	cdef fftwf_plan fftPlanY = fftwf_plan_dft_1d(freqDecimation, inVarY, outVarY, -1, FFTW_ESTIMATE)


	# Change the memory from time continuous to beam continuous
	# Easy optimisation: do this when dealing with the rest of the memory operations
	# This is simply to make my life easier while creating this script.
	printf("Restructuring the dataset in memory...\n")
	cdef long baseOffset, beamletIdx, __
	for i in prange(packetCount, nogil = True, schedule = 'guided', num_threads = threadCount):
		baseOffset = udpPacketLength * i + udpHeaderLength
		for j in range(beamletCount):
			beamletIdx = baseOffset + j * scans * 4
			for k in range(scans):
				# Filterbank expects the frequency to be reversed compared to input flow
				kSet = k * 4
				timeIdx = (i * scans + k) / timeDecimation
				structuredFileData_view[beamletCount - 1 - j][timeIdx][0] += fileData[beamletIdx + kSet] # Xr
				structuredFileData_view[beamletCount - 1 - j][timeIdx][1] += fileData[beamletIdx + kSet + 1] # Xi
				structuredFileData_view[beamletCount - 1 - j][timeIdx][2] += fileData[beamletIdx + kSet + 2] # Yr
				structuredFileData_view[beamletCount - 1 - j][timeIdx][3] += fileData[beamletIdx + kSet + 3] # Yi

	# Release the raw data.
	free(fileData)


	# Initialise the Hann window
	for i in range(freqDecimation):
		hannWindow[i] = pow(sin(pi * i / freqDecimation), 2)

	if stokesVT and stokesIT:
		printf("Processing Stoves I and Stokes V...\n")
		"""
		for j in prange(beamletCount, nogil = True, schedule = 'guided', num_threads = threadCount):
			for i in range(packetCount * scans):
				Xr = structuredFileData_view[j][i][0]
				Xi = structuredFileData_view[j][i][1]
				Yr = structuredFileData_view[j][i][2]
				Yi = structuredFileData_view[j][i][3]

				stokesDual_view[j, 0, i] = stokesI(Xr, Xi, Yr, Yi)
				stokesDual_view[j, 1, i] = stokesV(Xr, Xi, Yr, Yi)

		printf("Stokes I and V formed, performing decimations...\n")
		for j in prange(beamletCount, nogil = True, schedule = 'guided', num_threads = threadCount):
			for timeIdx in range(timeSteps):
				holdVar = 0
				holdVar2 = 0
				for k in range(timeDecimation):
					holdVar = holdVar + stokesDual_view[j, 0, timeIdx * timeDecimation + k]
					holdVar2 = holdVar2 + stokesDual_view[j, 1, timeIdx * timeDecimation + k]
				stokesDualOut_view[timeIdx, 0, j] = holdVar
				stokesDualOut_view[timeIdx, 1, j] = holdVar2

		writeData(stokesDualOut_view, dataLength, &outputLoc[0])

		#return(stokesDualOut,)
		"""
	elif stokesIT:
		printf("Processing Stokes I...\n")

		if freqDecimation > 1:
			#for j in prange(beamletCount, nogil = True, schedule = 'guided', num_threads = threadCount):
			for j in range(beamletCount):
				filterbankIdx = 0
				filterbankLim = freqDecimation - 1
				timeIdx = 0

				for i in range(timeSteps):
					#Xr = structuredFileData_view[j][i][0]
					#Xi = structuredFileData_view[j][i][1]
					#Yr = structuredFileData_view[j][i][2]
					#Yi = structuredFileData_view[j][i][3]

					inVarX[filterbankIdx][0] = structuredFileData_view[j][i][0] * hannWindow[filterbankIdx]
					inVarX[filterbankIdx][1] = structuredFileData_view[j][i][1] * hannWindow[filterbankIdx]
					inVarY[filterbankIdx][0] = structuredFileData_view[j][i][2] * hannWindow[filterbankIdx]
					inVarY[filterbankIdx][1] = structuredFileData_view[j][i][3] * hannWindow[filterbankIdx]
					#stokesSingle_view[j, i] = stokesI(Xr, Xi, Yr, Yi)

					#inVar[filterbankIdx] = stokesI(Xr, Xi, Yr, Yi)
					if filterbankIdx == filterbankLim:
						filterbankIdx = 0
						#fftwf_execute(fftPlan)
						fftwf_execute(fftPlanX)
						fftwf_execute(fftPlanY)
					
						#for i in range(fftOffset):
						#	stokesSingleOut_view[timeIdx, j * freqDecimation + i] = outVar[i][0]
						#	stokesSingleOut_view[timeIdx, j * freqDecimation + (freqDecimation - 1 - i)] = outVar[i][0]
						#stokesSingleOut_view[timeIdx, j * freqDecimation + fftOffset] = outVar[fftOffset][0]

						for l in range(fftOffset):
							mirror = l + fftOffset
							stokesSingleOut_view[timeIdx, j * freqDecimation + mirror] = stokesIf(outVarX[l][0], outVarX[l][1], outVarY[l][0], outVarY[l][1])
							stokesSingleOut_view[timeIdx, j * freqDecimation + l] = stokesIf(outVarX[mirror][0], outVarX[mirror][1], outVarY[mirror][0], outVarY[mirror][1])

						timeIdx = timeIdx + 1
					else:
						filterbankIdx = filterbankIdx + 1

		else:
			for j in range(beamletCount):
				for i in range(timeSteps):
					stokesSingleOut_view[i, j] = stokesI(structuredFileData_view[j][i][0], structuredFileData_view[j][i][1], structuredFileData_view[j][i][2], structuredFileData_view[j][i][3])


		#fftwf_destroy_plan(fftPlan)
		#free(inVar)
		#fftwf_free(outVar)
		#
		fftwf_destroy_plan(fftPlanX)
		fftwf_destroy_plan(fftPlanY)
		fftwf_free(inVarX)
		fftwf_free(inVarY)
		fftwf_free(outVarX)
		fftwf_free(outVarY)

		writeDataShrunk(stokesSingleOut_view, dataLength, &outputLoc[0])

		#return (stokesSingleOut,)

	else: 
		printf("Processing Stoves V...\n")
		"""
		for j in prange(beamletCount, nogil = True, schedule = 'guided', num_threads = threadCount):
			for i in range(packetCount * scans):
				iSet = i * 4
				Xr = structuredFileData_view[j][i][0]
				Xi = structuredFileData_view[j][i][1]
				Yr = structuredFileData_view[j][i][2]
				Yi = structuredFileData_view[j][i][3]

				stokesSingle_view[j, i] = stokesV(Xr, Xi, Yr, Yi)

		printf("Stokes V formed, performing decimations...\n")
		for j in prange(beamletCount, nogil = True, schedule = 'guided', num_threads = threadCount):
			for timeIdx in range(timeSteps):
				holdVar = 0
				for k in range(timeDecimation):
					holdVar = holdVar + stokesSingle_view[j, timeIdx * timeDecimation + k]
				stokesSingleOut_view[timeIdx, j] = holdVar

		writeDataShrunk(stokesSingleOut_view, dataLength, &outputLoc[0])

		#return (stokesSingleOut,) 
		"""
	free(hannWindow)