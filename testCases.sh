#!/bin/bash

errorCodes=("Success" \
			"Generic Failure" \
			"(g)Awk Version Failure" \
			"Insufficient Arguments" \
			"Error Parsing Arguments" \
			"File already Exists" \
			"Cannot Find mockHeader Command" \
			"Cannot Find zstd Command" \
			"Failed to Generate Sigproc Header" \
			"Cannot Find python wrapper Script" \
			"Cannot find cdmt_udp command" \
			"Error in wrapper script")


function wrapCall () {
	# $1 = Test Number
	
	printf "Running test \e[34m("$1") ${testName[$1]}\e[39m...\n"
	testCall "${testName[$1]}" "${testError[$1]}" $scriptName "${testArguments[$1]}"
	rm ./testCases/*
}


function testCall () {
	# $1 = Test Name
	# $2 = Expected Error Code
	# $3 = Test Executable
	# $4 = Test Arguments
	
	output=$(bash -c "$3 $4")
	execcode=$?
	if [ $execcode != $2 ]
	then
		printf "\n\n"
		echo "ERROR: ${output[@]}"
		notifyError $execcode $1 $2 "$4"
	fi
}

function notifyError () {
	# $1 = Error Code
	# $2 = Test Name
	# $3 = Expected Error
	# $4 = Arguments

	printf "Encountered unexpected error \e[93m"$1" (${errorCodes[$1]})\e[39m in test \e[93m"$2"\e[39m (expected error \e[93m"$3" (${errorCodes[$3]})\e[39m)\n\n\n"

	echo "Executed arguments: "$4
	rm ./testCases/*
	exit 1
}

scriptName=bf2fil.csh
testName=("standard" "standard-stokesI" "standard-alloptions" "4bit" "4bit-stokesI" "4bit-alloptions" "cdmt" "cdmt-alloptions" "cdmt-4bit" "cdmt-4bit-alloptions")

testArguments=("standard ./testData/udp_16130.ucc1.2020-03-26T10\:21\:00.000 20000 0.1 0.1 170.997 ./testCases/debug.fil" \
			   "standard ./testData/udp_16130.ucc1.2020-03-26T10\:21\:00.000 20000 0.1 0.1 170.997 ./testCases/debug.fil 1 0 8 16 16130 4 NULL 01:02:03.456 01:02:03.456" \
			   "standard ./testData/udp_16130.ucc1.2020-03-26T10\:21\:00.000 20000 0.1 0.1 170.997 ./testCases/debug.fil 1 1 1 16 16130 4 NULL 01:02:03.456 01:02:03.456" \
			   "4bit ./testData/udp_16130.ucc1.2020-03-26T10\:21\:00.000 20000 0.1 0.1 170.997 ./testCases/debug.fil" \
			   "4bit ./testData/udp_16130.ucc1.2020-03-26T10\:21\:00.000 20000 0.1 0.1 170.997 ./testCases/debug.fil  \1 0 8 1 16130 4 NULL 01:02:03.456 01:02:03.456" \
			   "4bit ./testData/udp_16130.ucc1.2020-03-26T10\:21\:00.000 20000 0.1 0.1 170.997 ./testCases/debug.fil  \1 1 1 1 16130 4 NULL 01:02:03.456 01:02:03.456" \
			   "cdmt ./testData/udp_16130.ucc1.2020-03-26T10\:21\:00.000 20000 0.1 0.1 170.997 ./testCases/debug.fil 10,10,10" \
			   "cdmt ./testData/udp_16130.ucc1.2020-03-26T10\:21\:00.000 20000 0.1 0.1 170.997 ./testCases/debug.fil 10,10,10 128 32 8 16130 4 NULL 01:02:03.456 01:02:03.456" \
			   "cdmt ./testData/udp_16130.ucc1.2020-03-26T10\:21\:00.000 20000 0.1 0.1 170.997 ./testCases/debug.fil 10,10,10 128 32 1 16130 4 NULL 01:02:03.456 01:02:03.456" \
			   "cdmt-4bit ./testData/udp_16130.ucc1.2020-03-26T10\:21\:00.000 20000 0.1 0.1 170.997 ./testCases/debug.fil 10,10,10" \
			   "cdmt-4bit ./testData/udp_16130.ucc1.2020-03-26T10\:21\:00.000 20000 0.1 0.1 170.997 ./testCases/debug.fil 10,10,10 256 16 1 16130 4 NULL 01:02:03.456 01:02:03.456")

testError=(0 0 0 0 0 0 0 1 0 0 0 0)




export ZSTD_AUTO=1
export ZSTD_CLEANUP=0
export CDMT_CLEANUP=1

mkdir -p ./testCases/
echo "Starting testing..."
if [[ -z $1 ]]
then
	for ((i=0;i<${#testName[@]};++i)); do
		wrapCall $i
	done
else 
	wrapCall $1
fi
printf "\n\n\e[32m\u2705\e[39m  Testing complete; no exits detected.\n"
