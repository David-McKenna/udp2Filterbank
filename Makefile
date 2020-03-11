

all: submodules-local python-local

all-global: submodules python

submodules-local:
	git submodule update --init --recursive
	cd mockHeader; make; cp ./mockHeader ~/.local/bin/

python-local:
	rm cyUdp2fil.c; exit 0
	python3 ./setup.py install --user
	cp ./cli/* ~/.local/bin/

submodules:
	git submodule update --init --recursive
	cd mockHeader; make; cp ./mockHeader /usr/local/bin/

python:
	rm cyUdp2fil.c; exit 0
	python3 ./setup.py install
	cp ./cli/* /usr/local/bin/
