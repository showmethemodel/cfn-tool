.PHONY: build build-nocache install

SHELL   := /bin/bash
ORG     := showmethemodel
PROJECT := cfn-tools
TAG     := $(ORG)/$(PROJECT)
VERSION := 1.0.0

PREFIX  ?= /usr/local

# print variables (eg. make print-SHELL)
print-%:
	@echo '$*=$($*)'

build: $(DEPS)
	docker build -t $(TAG):$(VERSION) -t $(TAG):latest .

build-nocache: $(DEPS)
	docker build --no-cache -t $(TAG):$(VERSION) .

install: build
	cp bin/* $(PREFIX)/bin/
