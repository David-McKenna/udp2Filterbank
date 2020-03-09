

all: submodules python-local


submodules:
	git submodule update --init --recursive
	cd mockHeader; make; cp ./mockHeader ../cli/

python-local:
	python3 ./setup.py install --user
