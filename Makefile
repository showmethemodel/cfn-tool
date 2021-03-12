.PHONY: build build-impl build-nocache build-nocache-impl install

SHELL   := /bin/bash
ORG     := showmethemodel
PROJECT := cfn-tools
TAG     := $(ORG)/$(PROJECT)
VERSION := 1.0.0

PREFIX  ?= /usr/local

# print variables (eg. make print-SHELL)
print-%:
	@echo '$*=$($*)'

build: build-impl .build/cfn-tools.1

build-nocache: build-nocache-impl .build/cfn-tools.1

build-impl:
	docker build -t $(TAG):$(VERSION) -t $(TAG):latest .

build-nocache-impl: $(DEPS)
	docker build --no-cache -t $(TAG):$(VERSION) .

.build/cfn-tools.1: root/usr/share/man/man1/cfn-tools.1.ronn
	mkdir -p .build
	bin/cfn-tools -c 'cat /usr/share/man/man1/cfn-tools.1' > $@

install:
	cp bin/* $(PREFIX)/bin/
	cp .build/cfn-tools.1 $(PREFIX)/share/man/man1/cfn-tools.1
