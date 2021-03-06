

all: reset submodules-local python-local

all-ucc: reset submodules-local python-ucc

reset:
	git reset --hard HEAD

all-global: submodules python

submodules-local:
	git submodule update --init --force --remote
	mkdir -p ~/.local/bin/
	cd mockHeader; make; cp ./mockHeader ~/.local/bin/
	cd cdmt; make cdmt_udp; cp ./cdmt_udp ~/.local/bin/

python-local:
	pip3 install setuptools cython astropy --user
	rm cyUdp2fil.c; exit 0
	python3 ./setup.py install --user
	chmod +x ./cli/*
	mkdir -p ~/.local/bin/
	cp ./cli/* ~/.local/bin/

python-ucc:
	pip3.8 install setuptools cython astropy --user
	rm cyUdp2fil.c; exit 0
	python3.8 ./setup.py install --user
	chmod +x ./cli/*
	mkdir -p ~/.local/bin/
	sed -i 's/python3/python3.8/' ./cli/*
	cp ./cli/* ~/.local/bin/


submodules:
	git submodule update --init --force --remote
	cd mockHeader; make; cp ./mockHeader /usr/local/bin/
	cd cdmt; make cdmt_udp; cp ./cdmt_udp /usr/local/bin/

python:
	pip3 install setuptools cython astropy
	rm cyUdp2fil.c; exit 0
	python3 ./setup.py install
	chmod +x ./cli/*
	cp ./cli/* /usr/local/bin/
