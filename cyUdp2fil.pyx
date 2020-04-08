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


# Import fftw3 functions (fftw3f for floating point precision)
cdef extern from "fftw3.h" nogil:
	cdef int fftwf_init_threads();
	cdef void fftwf_plan_with_nthreads(int nthreads)
	cdef void fftwf_cleanup_threads();

	ctypedef DTYPE_t_2 fftwf_complex[2]
	ctypedef struct fftwf_plan:
		pass

	cdef fftwf_plan fftwf_plan_dft_1d(int N, fftwf_complex *inVar, fftwf_complex *outVar, int direction, unsigned char flags)
	cdef void fftwf_execute(const fftwf_plan plan)
	cdef void *fftwf_malloc(size_t size)
	cdef void fftwf_destroy_plan(fftwf_plan plan)
	cdef void fftwf_free(fftwf_complex[2] arr)
	cdef unsigned char FFTW_ESTIMATE = 1U << 6

fftwf_init_threads()


# Define our stokes functions for different forms / precisions
cdef DTYPE_t_2 stokesI(unsigned char Xr, unsigned char Xi, unsigned char Yr, unsigned char Yi) nogil:
	return <DTYPE_t_2> ((Xr * Xr) + (Yr * Yr) + (Xi * Xi) + (Yi * Yi))

cdef DTYPE_t_2 stokesIf(DTYPE_t_2 Xr, DTYPE_t_2 Xi, DTYPE_t_2 Yr, DTYPE_t_2 Yi) nogil:
	return <DTYPE_t_2> ((Xr * Xr) + (Yr * Yr) + (Xi * Xi) + (Yi * Yi))


cdef DTYPE_t_2 stokesV(unsigned char Xr, unsigned char Xi, unsigned char Yr, unsigned char Yi) nogil:
	return <DTYPE_t_2> (2 * ((Xr * Yi) + (-1 * Xi * Yr)))

cdef DTYPE_t_2 stokesVf(DTYPE_t_2 Xr, DTYPE_t_2 Xi, DTYPE_t_2 Yr, DTYPE_t_2 Yi) nogil:
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

cdef void writeData(DTYPE_t_2[:, :, ::1] dataSet, long long dataLength, char outputLoc[], char outputLoc2[]) nogil:
	printf("Passing Stokes I data to writer...\n")
	writeDataShrunk(dataSet[0], dataLength / 2, outputLoc)

	printf("Passing Stokes V data to writer...\n")
	writeDataShrunk(dataSet[1], dataLength / 2, outputLoc2)




# Main read function: handles getting all data from disk into memory.
cpdef void readFile(char* fileLoc, char* portPattern, int ports, int threadCount, long long readStart, long long readLength, unsigned char stokesIT, unsigned char stokesVT, int timeDecimation, int freqDecimation, char* outputLoc):
	printf("\nVerifiyng input parameters...\n\n")
	ports = max(1, ports)

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
		if readLength < 0:
			printf("\033[5;31m\xf0\x9f\x9b\x91	FATAL ERROR: Calculated readLength is negative (%lld), exiting early.\033[0m\n", readLength)
			exit(1)
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


	# Assume our output location is less than 1k characters long...
	cdef char[1024] outputF
	cdef char[1024] outputF2
	cdef char[1000] outputLocCopy

	if outputLoc == b"":
		sprintf(outputLocCopy, "%s.tmp.fil", fileLoc)
	else:
		sprintf(outputLocCopy, "%s", outputLoc)

	if stokesIT and stokesVT:
		sprintf(outputF, "%s_stokesI.fil", outputLocCopy)
		sprintf(outputF2, "%s_stokesV.fil", outputLocCopy)
		printf("Data will be saved to %s and %s once processing is finished.\n\n", outputF, outputF2)
	else:
		sprintf(outputF, "%s", outputLocCopy)
		printf("Data will be saved to %s once processing is finished.\n\n", outputF)



	# fileData is free'd in this function
	processData(fileData, ports, threadCount, packetCount, stokesIT, stokesVT, timeDecimation, freqDecimation, outputF, outputF2)

cdef void processData(DTYPE_t_1* fileData, int ports, int threadCount, long packetCount, unsigned char stokesIT, unsigned char stokesVT, int timeDecimation, int freqDecimation, char* outputLoc, char* outputLoc2):

	# Initialise all variables.
	cdef object t1, t2

	cdef unsigned char Xr, Xi, Yr, Yi

	freqDecimation = max(freqDecimation, 1) # Sanitise input

	cdef int j, k, kSet, l, offsetIdx, idx1, idx2, combinedSteps
	cdef int rawBeamletCount = 122
	cdef int beamletCount = rawBeamletCount * ports
	cdef int scans = 16
	cdef int filterbankIdx = 0
	cdef int filterbankLim = freqDecimation - 1
	cdef int fftOffset = freqDecimation // 2
	cdef int mirror = 0
	cdef int port, beamletBase

	#cdef DTYPE_t_2 *hannWindow = <DTYPE_t_2*>malloc(sizeof(DTYPE_t_2) * freqDecimation)
	cdef DTYPE_t_2 pi = np.pi

	cdef long i, iSet, baseOffset, beamletIdx, __
	cdef long udpPacketLength = 7824
	cdef long udpHeaderLength = 16
	cdef long timeIdx = 0
	cdef long timeSteps = packetCount * scans

	cdef long long dataLength = int(packetCount * (beamletCount) * (float(scans) / float(timeDecimation)) * (stokesIT + stokesVT)) # freqDecimation has a 1:1 transfer between time/freq, so no effect on output size.

	cdef fftwf_complex *inVarX
	cdef fftwf_complex *outVarX
	cdef fftwf_plan fftPlanX

	cdef fftwf_complex *inVarY
	cdef fftwf_complex *outVarY
	cdef fftwf_plan fftPlanY

	#cdef unsigned char* progressArr = <unsigned char*> calloc(beamletCount, sizeof(unsigned char))

	printf("Output expected to be %lld bytes long, from %ld packets and %d modes.\n", dataLength * sizeof(DTYPE_t_2), packetCount, stokesIT + stokesVT)
	printf("Allocating memory for processing operations...\n")


	# Initialise memory for our data, setup memviews
	# Cython requires empties be setup if we are going to define a variable,
	# 	so file 1 element arrays for the unused shape.
	structuredFileData = np.zeros((beamletCount, packetCount * scans,  4), dtype = DTYPE_1)

	if stokesVT + stokesIT == 1:
		stokesSingleData = np.zeros((packetCount * scans // freqDecimation, beamletCount * freqDecimation), dtype = DTYPE_2)
		stokesSingleOut = np.zeros((packetCount * scans // timeDecimation // freqDecimation, beamletCount * freqDecimation), dtype = DTYPE_2)

		stokesDualData = np.zeros((1,1,1), dtype = DTYPE_2)
		stokesDualOut = np.zeros((1,1,1), dtype = DTYPE_2)
	else:
		stokesDualData = np.zeros((2, packetCount * scans // freqDecimation, beamletCount * freqDecimation), dtype = DTYPE_2)
		stokesDualOut = np.zeros((2, packetCount * scans // timeDecimation // freqDecimation, beamletCount * freqDecimation), dtype = DTYPE_2)

		stokesSingleData = np.zeros((1,1), dtype = DTYPE_2)
		stokesSingleOut = np.zeros((1,1), dtype = DTYPE_2)
	
	cdef DTYPE_t_1[:, :, ::1] structuredFileData_view = structuredFileData
	cdef DTYPE_t_2[:, ::1] stokesSingle_view = stokesSingleData
	cdef DTYPE_t_2[:, :, ::1] stokesDual_view = stokesDualData
	cdef DTYPE_t_2[:, ::1] stokesSingleOut_view = stokesSingleOut
	cdef DTYPE_t_2[:, :, ::1] stokesDualOut_view = stokesDualOut



	# Initialise FFTW operations and memory 
	if freqDecimation > 1:
		# Spread each fft over only 1 thread, but thread safe
		fftwf_plan_with_nthreads(1)

	cdef fftwf_complex **inVarXArr = <fftwf_complex**>malloc(beamletCount * sizeof(fftwf_complex *))
	cdef fftwf_complex **outVarXArr = <fftwf_complex**>malloc(beamletCount * sizeof(fftwf_complex *))
	cdef fftwf_plan *fftPlanXArr = <fftwf_plan*> malloc(beamletCount * sizeof(fftwf_plan *))

	for i in range(beamletCount):
		inVarXArr[i] = <fftwf_complex*> fftwf_malloc(sizeof(fftwf_complex) * freqDecimation);
		outVarXArr[i] = <fftwf_complex*> fftwf_malloc(sizeof(fftwf_complex) * freqDecimation);
		fftPlanXArr[i] =  <fftwf_plan> fftwf_plan_dft_1d(freqDecimation, inVarXArr[i], outVarXArr[i], -1, FFTW_ESTIMATE)


	cdef fftwf_complex **inVarYArr = <fftwf_complex**>malloc(beamletCount * sizeof(fftwf_complex *))
	cdef fftwf_complex **outVarYArr =<fftwf_complex**> malloc(beamletCount * sizeof(fftwf_complex *))
	cdef fftwf_plan *fftPlanYArr =  <fftwf_plan*> malloc(beamletCount * sizeof(fftwf_plan *))

	for i in range(beamletCount):
		inVarYArr[i] = <fftwf_complex*> fftwf_malloc(sizeof(fftwf_complex) * freqDecimation);
		outVarYArr[i] = <fftwf_complex*> fftwf_malloc(sizeof(fftwf_complex) * freqDecimation);
		fftPlanYArr[i] = <fftwf_plan> fftwf_plan_dft_1d(freqDecimation, inVarYArr[i], outVarYArr[i], -1, FFTW_ESTIMATE)


	# Change the memory from time continuous to beam continuous
	# This is simply to make my life easier while creating this script.
	printf("\n\nRestructuring the dataset in memory...\n")

	for port in range(ports):
		for i in prange(packetCount, nogil = True, schedule = 'guided', num_threads = threadCount):
			baseOffset = udpPacketLength * (packetCount * port) + udpPacketLength * i + udpHeaderLength
			beamletBase = beamletCount - (rawBeamletCount * port)

			for j in range(rawBeamletCount):
				beamletIdx = baseOffset + j * scans * 4
				for k in range(scans):
					# Filterbank expects the frequency to be reversed compared to input flow
					kSet = k * 4
					timeIdx = i * scans + k
					structuredFileData_view[beamletBase - 1 - j][timeIdx][0] += fileData[beamletIdx + kSet] # Xr
					structuredFileData_view[beamletBase - 1 - j][timeIdx][1] += fileData[beamletIdx + kSet + 1] # Xi
					structuredFileData_view[beamletBase - 1 - j][timeIdx][2] += fileData[beamletIdx + kSet + 2] # Yr
					structuredFileData_view[beamletBase - 1 - j][timeIdx][3] += fileData[beamletIdx + kSet + 3] # Yi

	# Release the raw data.
	printf("Releasing raw file data...\n")
	free(fileData)


	# Initialise the Hann window
	#for i in range(freqDecimation):
	#	hannWindow[i] = pow(sin(pi * i / freqDecimation), 2)


	# Being actually processing data
	printf("\n\n\nBegining processing...\n\n")
	if stokesVT and stokesIT:
		printf("Processing Stokes I and Stokes V...\n")
		t1 = time.time()


		# Handle the frequency/time tradeoff
		if freqDecimation > 1:
			printf("Begining Stokes formation and channelisation process...\n")
			for j in prange(beamletCount, nogil = True, schedule = 'guided', num_threads = threadCount):
				
				#progressArr[j] = 1
				#progress(progressArr, beamletCount, 0)
				
				filterbankIdx = 0
				filterbankLim = freqDecimation - 1
				timeIdx = 0

				inVarX = inVarXArr[j]
				inVarY = inVarYArr[j]
				outVarX = outVarXArr[j]
				outVarY = outVarYArr[j]
				fftPlanX = fftPlanXArr[j]
				fftPlanY = fftPlanYArr[j]


				for i in range(timeSteps):
					# Data structure reminder
					#Xr = structuredFileData_view[j][i][0]
					#Xi = structuredFileData_view[j][i][1]
					#Yr = structuredFileData_view[j][i][2]
					#Yi = structuredFileData_view[j][i][3]

					inVarX[filterbankIdx][0] = structuredFileData_view[j][i][0] #* hannWindow[filterbankIdx]
					inVarX[filterbankIdx][1] = structuredFileData_view[j][i][1] #* hannWindow[filterbankIdx]
					inVarY[filterbankIdx][0] = structuredFileData_view[j][i][2] #* hannWindow[filterbankIdx]
					inVarY[filterbankIdx][1] = structuredFileData_view[j][i][3] #* hannWindow[filterbankIdx]

					if filterbankIdx == filterbankLim:
						filterbankIdx = 0
						fftwf_execute(fftPlanX)
						fftwf_execute(fftPlanY)

						for l in range(fftOffset):
							# Stored values are frequency reversed, FFT shifted
							offsetIdx = l + fftOffset
							idx1 = fftOffset - 1 - l
							idx2 = freqDecimation - 1 - l
							stokesDual_view[0][timeIdx][j * freqDecimation + l] = stokesIf(outVarX[idx1][0], outVarX[idx1][1], outVarY[idx1][0], outVarY[idx1][1])
							stokesDual_view[0][timeIdx][j * freqDecimation + offsetIdx] = stokesIf(outVarX[idx2][0], outVarX[idx2][1], outVarY[idx2][0], outVarY[idx2][1])
							stokesDual_view[1][timeIdx][j * freqDecimation + l] = stokesVf(outVarX[idx1][0], outVarX[idx1][1], outVarY[idx1][0], outVarY[idx1][1])
							stokesDual_view[1][timeIdx][j * freqDecimation + offsetIdx] = stokesVf(outVarX[idx2][0], outVarX[idx2][1], outVarY[idx2][0], outVarY[idx2][1])
						

						timeIdx = timeIdx + 1
					else:
						filterbankIdx = filterbankIdx + 1

				# Cleanup fftw memory objects
				#progressArr[j] = 2
				#progress(progressArr, beamletCount, 0)
				
				printf("Beam %d processing completed.\n", j)

				fftwf_destroy_plan(fftPlanX)
				fftwf_destroy_plan(fftPlanY)
				fftwf_free(inVarX)
				fftwf_free(inVarY)
				fftwf_free(outVarX)
				fftwf_free(outVarY)

			#time.sleep(1)
			#progress(progressArr, beamletCount, 1)
			printf(".\nChannelisation complete, cleaning up FFTW artefacts...\n")
			fftwf_cleanup_threads()
		else:
			# Just process the Stokes values if we aren't doing a frequency trade off
			printf("Forming Stokes parameters...\n")
			for j in prange(beamletCount, nogil = True, schedule = 'guided', num_threads = threadCount):
				
				#progressArr[j] = 1
				#progress(progressArr, beamletCount, 0)
				
				for i in range(timeSteps):
					stokesDual_view[0][i][j] = stokesI(structuredFileData_view[j][i][0], structuredFileData_view[j][i][1], structuredFileData_view[j][i][2], structuredFileData_view[j][i][3])
					stokesDual_view[1][i][j] = stokesV(structuredFileData_view[j][i][0], structuredFileData_view[j][i][1], structuredFileData_view[j][i][2], structuredFileData_view[j][i][3])
				
				#progressArr[j] = 2
				#progress(progressArr, beamletCount, 0)
				printf("Beam %d processing completed.\n", j)
			#time.sleep(1)
			#progress(progressArr, beamletCount, 1)
			printf(".\nStokes parameter formation complete.\n")
		# Account for reduced time steps from frequency trade offs
		timeSteps /= freqDecimation

		# Sum over time if we are decimating the data
		if timeDecimation > 1:
			printf("\n\nBegining time decimation...\n")
			for j in prange(beamletCount * freqDecimation, nogil = True, schedule = 'guided', num_threads = threadCount):
				
				#progressArr[j] = 1
				#progress(progressArr, beamletCount, 0)
				
				timeIdx = 0
				combinedSteps = 1
				for i in range(timeSteps):
					stokesDualOut_view[0][timeIdx][j] = stokesDualOut_view[0][timeIdx][j] + stokesDual_view[0][i][j]
					stokesDualOut_view[1][timeIdx][j] = stokesDualOut_view[1][timeIdx][j] + stokesDual_view[1][i][j]

					if combinedSteps == timeDecimation:
						combinedSteps = 1 
						timeIdx = timeIdx + 1
					else:
						combinedSteps = combinedSteps + 1
				
				#progressArr[j] = 2
				#progress(progressArr, beamletCount, 0)
				printf("Beam %d processing completed.\n", j)

			#time.sleep(1)
			#progress(progressArr, beamletCount, 1)
			printf(".\nTime decimation complete.\n")

		else:
			stokesDualOut_view = stokesDual_view

		t2 = time.time()
		print("This took {:.2f} seconds, each sample taking {:f} seconds to process.".format(t2 - t1, (t2 - t1) / stokesDualData.size / 2))

		t1 = time.time()
		# Write the results to disk
		printf("Writing results to disk...\n")
		writeData(stokesDualOut_view, dataLength, &outputLoc[0], &outputLoc2[0])

	else:

		# Select our Stokes function
		if stokesIT:
			stokesFunc = stokesI
			stokesFFunc = stokesIf
			printf("Processing Stokes I...\n")
		elif stokesVT:
			stokesFunc = stokesV
			stokesFFunc = stokesVf
			printf("Processing Stokes V...\n")
		else:
			printf("No Stokes Method Selected; exiting.")
			return

		t1 = time.time()

		# Handle the frequency/time tradeoff. Speedup from splitting up the stokes I/V combined method is noticable.
		if freqDecimation > 1:
			printf("Begining Stokes formation and channelisation process...\n")
			for j in prange(beamletCount, nogil = True, schedule = 'guided', num_threads = threadCount):
				
				#progressArr[j] = 1
				#progress(progressArr, beamletCount, 0)

				filterbankIdx = 0
				filterbankLim = freqDecimation - 1
				timeIdx = 0

				inVarX = inVarXArr[j]
				inVarY = inVarYArr[j]
				outVarX = outVarXArr[j]
				outVarY = outVarYArr[j]
				fftPlanX = fftPlanXArr[j]
				fftPlanY = fftPlanYArr[j]

				for i in range(timeSteps):
					# Data structure reminder
					#Xr = structuredFileData_view[j][i][0]
					#Xi = structuredFileData_view[j][i][1]
					#Yr = structuredFileData_view[j][i][2]
					#Yi = structuredFileData_view[j][i][3]

					inVarX[filterbankIdx][0] = structuredFileData_view[j][i][0] #* hannWindow[filterbankIdx]
					inVarX[filterbankIdx][1] = structuredFileData_view[j][i][1] #* hannWindow[filterbankIdx]
					inVarY[filterbankIdx][0] = structuredFileData_view[j][i][2] #* hannWindow[filterbankIdx]
					inVarY[filterbankIdx][1] = structuredFileData_view[j][i][3] #* hannWindow[filterbankIdx]

					if filterbankIdx == filterbankLim:
						filterbankIdx = 0
						fftwf_execute(fftPlanX)
						fftwf_execute(fftPlanY)

						for l in range(fftOffset):
							# Stored values are frequency reversed, FFT shifted
							offsetIdx = l + fftOffset
							idx1 = fftOffset - 1 - l
							idx2 = freqDecimation - 1 - l
							stokesSingle_view[timeIdx][j * freqDecimation + l] = stokesFFunc(outVarX[idx1][0], outVarX[idx1][1], outVarY[idx1][0], outVarY[idx1][1])
							stokesSingle_view[timeIdx][j * freqDecimation + offsetIdx] = stokesFFunc(outVarX[idx2][0], outVarX[idx2][1], outVarY[idx2][0], outVarY[idx2][1])
						

						timeIdx = timeIdx + 1
					else:
						filterbankIdx = filterbankIdx + 1

				# Cleanup fftw memory objects on a per-beam basis
				#progressArr[j] = 2
				#progress(progressArr, beamletCount, 0)

				printf("Beam %d processing completed.\n", j)

				fftwf_destroy_plan(fftPlanX)
				fftwf_destroy_plan(fftPlanY)
				fftwf_free(inVarX)
				fftwf_free(inVarY)
				fftwf_free(outVarX)
				fftwf_free(outVarY)
			
			time.sleep(1)
			#progress(progressArr, beamletCount, 1)
			printf(".\nChannelisation complete, cleaning up FFTW artefacts...\n")
			
			fftwf_cleanup_threads()

		else:
			# Just process the Stokes value if we aren't doing a frequency trade off
			printf("Forming Stokes parameters...\n")
			for j in prange(beamletCount, nogil = True, schedule = 'guided', num_threads = threadCount):
				
				#progressArr[j] = 1
				#progress(progressArr, beamletCount, 0)
				
				for i in range(timeSteps):
					stokesSingle_view[i][j] = stokesFunc(structuredFileData_view[j][i][0], structuredFileData_view[j][i][1], structuredFileData_view[j][i][2], structuredFileData_view[j][i][3])
				
				#progressArr[j] = 2
				#progress(progressArr, beamletCount, 0)
				#
				printf("Beam %d processing completed.\n", j)
			#time.sleep(1)
			#progress(progressArr, beamletCount, 1)
			printf(".\nStokes parameter formation complete.\n")

		# Account for reduced time steps from frequency trade offs
		timeSteps /= freqDecimation

		# Sum over time if we are decimating the data
		if timeDecimation > 1:
			printf("\n\nBegining time decimation...\n")
			for j in prange(beamletCount * freqDecimation, nogil = True, schedule = 'guided', num_threads = threadCount):
				
				#progressArr[j] = 1
				#progress(progressArr, beamletCount, 0)
				
				timeIdx = 0
				combinedSteps = 1
				for i in range(timeSteps):
					stokesSingleOut_view[timeIdx][j] = stokesSingleOut_view[timeIdx][j] + stokesSingle_view[i][j]

					if combinedSteps == timeDecimation:
						combinedSteps = 1 
						timeIdx = timeIdx + 1
					else:
						combinedSteps = combinedSteps + 1
				
				#progressArr[j] = 2
				#progress(progressArr, beamletCount, 0)
				printf("Beam %d processing completed.\n", j)
			#time.sleep(1)
			#progress(progressArr, beamletCount, 1)
			printf(".\nTime decimation complete.\n")

		else:
			stokesSingleOut_view = stokesSingle_view

		t2 = time.time()
		print("This took {:.2f} seconds, each sample taking {:} seconds to process.".format(t2 - t1, (t2 - t1) / stokesSingleData.size))

		t1 = time.time()
		# Write the results to disk.
		printf("\n\nWriting results to disk...\n")
		writeDataShrunk(stokesSingleOut_view, dataLength, &outputLoc[0])

	t2 = time.time()
	print("This took {:.2f} seconds, giving a write speed of {:.2f}MB/s".format(t2 - t1, dataLength * 4 / 1024 / 1024 / (t2 - t1)))


	# Cleanup the allocated memory / fftw remnants
	# Memviews are handled by the Python GC (unfortunatly, can't empty them early)
	#free(hannWindow)
	free(inVarXArr)
	free(inVarYArr)
	free(outVarXArr)
	free(outVarYArr)
	free(fftPlanXArr)
	free(fftPlanYArr)

"""
cdef int progress(unsigned char * progressArr, int itersCount) nogil:
	
	cdef int i;
	cdef int compCounter;
	cdef int workCounter;
	for i in range(itersCount):
		if i % 4 == 0:
			printf("\n")
		if (progressArr[i] == 2):
			printf("%03d: \033[42mCompleted.\033[49m\t\t", i)
			counter += 1
		elif (progressArr[i] == 1):
			printf("%03d: \033[44mWorking...\033[49m\t\t", i)


	progressArr[beamletCount + 1] = 0
	printf("\n\n\n")
	if (counter == itersCount):
		free(progressArr)
		progressArr = <unsigned char*> calloc(beamletCount + 1, sizeof(unsigned char))
		return 1

	return 0
"""