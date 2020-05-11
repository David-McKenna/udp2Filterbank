import argparse, os

def handleStrList(input):
	output = []
	for component in input.split(','):
		component = component.strip(' ')
		if ':' in component:
			component = component.split(':')
			component = list(range(int(component[0]), int(component[1]) + 1)) ## LOFAR counts the top subband as well, so add 1
		else:
			component = [int(component)]
		output = output+component

	if min(output) < 0 or max(output) > 511:
		raise RuntimeError("Invalid subband indexes.")

	output.sort()
	output = list(reversed(output))
	return output

def getFrequency(mode, subband):
	baseFreq = 100.0

	if mode == 5:
		freqOff = 100.

	elif mode == 6:
		freqOff = 160.
		baseFreq = 80.0

	elif mode == 7:
		freqOff = 200

	else:
		freqOff = 0

	# Sigproc need the center of band, not the bottom
	subband += 0.5

	frequency = ((baseFreq / 512 ) * (subband) + (freqOff))
	return frequency


baseChannelWidth = -0.1953125
if __name__ == '__main__':
	parser = argparse.ArgumentParser()

	parser.add_argument('-mode3', dest = 'm3', help = "Subbands for beamlets in mode 3", default = None)
	parser.add_argument('-mode5', dest = 'm5', help = "Subbands for beamlets in mode 5", default = None)
	parser.add_argument('-mode7', dest = 'm7', help = "Subbands for beamlets in mode 7", default = None)
	parser.add_argument('-channelisation', dest = 'chan', help = "Channelisation applied to dataset", default = 1, type = int)
	parser.add_argument('-outfile', dest = 'outfile', help = "Output file location", default = './frequencytable.txt')
	args = parser.parse_args()

	if os.path.exists(args.outfile):
		print("ERROR: File exists at output location. Exiting.")
		exit()

	modes = []
	freqs = []
	for mode, subbands in zip((7,5,3), [args.m7, args.m5, args.m3]):
		if subbands is not None:
			print(f"Parsing input for mode {mode}: {subbands}")
			modes.append(mode)
			subbands = handleStrList(subbands)
			print(f"Mode {mode} subbands: {subbands}")
			for sb in subbands:
				freqs.append(getFrequency(mode, sb))

	if int(args.chan) > 1:
		print(f"Applying channelisation of {args.chan} to frequencies")
		baseChannelWidth /= args.chan
		freqOld = freqs.copy()
		freqs = []

		for freq in freqOld:
			for offset in range(int(-args.chan / 2), int(args.chan / 2)):
				freqs.append(freq + offset * baseChannelWidth)

	strFreq = [str(freq) for freq in freqs]

	print(f"Parsed {len(freqs)} subbands across {len(modes)} modes, dumping output to {args.outfile}")

	with open(args.outfile, 'w') as refFile:
		refFile.writelines('\n'.join(strFreq))


	print(f"Frequencies successfully written to {args.outfile}")
