

all: submodules-local python-local

all-global: submodules python

submodules-local:
	git submodule update --init --recursive
	cd mockHeader; make; cp ./mockHeader ~/.local/bin/

python-local:
	rm cyUdp2fil.c; exit 0
	python3 ./setup.py install --user
	chmod +x ./cli/*
	cp ./cli/* ~/.local/bin/

submodules:
	git submodule update --init --recursive
	cd mockHeader; make; cp ./mockHeader /usr/local/bin/

python:
	rm cyUdp2fil.c; exit 0
	python3 ./setup.py install
	chmod +x ./cli/*
	cp ./cli/* /usr/local/bin/
