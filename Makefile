# OHMI ontology Makefile
# Jie Zheng
#
# This Makefile is used to build artifacts
# for the OHMI ontology.
#

### Configuration
#
# prologue:
# <http://clarkgrubb.com/makefile-style-guide#toc2>

MAKEFLAGS += --warn-undefined-variables
SHELL := bash
.SHELLFLAGS := -eu -o pipefail -c
.DEFAULT_GOAL := all
.DELETE_ON_ERROR:
.SUFFIXES:

### Definitions

SHELL   := /bin/bash
OBO     := http://purl.obolibrary.org/obo
OHMI  := $(OBO)/OHMI_
DEV     := $(OBO)/ohmi/dev
TODAY   := $(shell date +%Y-%m-%d)

### Directories
#
# This is a temporary place to put things.
build:
	mkdir -p $@


### ROBOT
#
# We use the official development version of ROBOT
# download the most recent build of ROBOT
build/robot.jar: | build
	@echo "Getting ROBOT" && \
	curl -L -o $@ https://github.com/ontodev/robot/releases/download/v1.2.0/robot.jar

ROBOT = java -jar build/robot.jar


### Imports
#
# Use Ontofox to import various modules.
#_build/import_%.owl: src/Ontofox-inputs/%_input.txt | build
#_	curl -s -F file=@$< -o $@ http://ontofox.hegroup.org/service.php

# Use ROBOT to ensure that serialization is consistent.
#_src/ontology/Ontofox_outputs/%_import.owl: build/import_%.owl
#_	$(ROBOT) convert -i build/$*_import.owl -o $@

#_IMPORT_FILES := $(wildcard src/ontology/import/import_*.owl)

#_.PHONY: imports
#_imports: $(IMPORT_FILES)


### Build
#
# Here we create a standalone OWL file appropriate for release.
# This involves merging, reasoning, annotating,
# and removing any remaining import declarations.
build/ohmi_merged.owl: src/ontology/ohmi-edit.owl | build/robot.jar
	@echo "Merging $< to $@" && \
	$(ROBOT) merge \
	--input $< \
	annotate \
	--ontology-iri "$(OBO)/ohmi/ohmi_merged.owl" \
	--version-iri "$(OBO)/ohmi/$(TODAY)/ohmi_merged.owl" \
	--annotation owl:versionInfo "$(TODAY)" \
	--output build/ohmi_merged.tmp.owl
	sed '/<owl:imports/d' build/ohmi_merged.tmp.owl > $@
	rm build/ohmi_merged.tmp.owl

ohmi.owl: build/ohmi_merged.owl | build/robot.jar
	$(ROBOT) reason \
	--input $< \
	--reasoner HermiT \
	annotate \
	--ontology-iri "$(OBO)/ohmi.owl" \
	--version-iri "$(OBO)/ohmi/$(TODAY)/ohmi.owl" \
	--annotation owl:versionInfo "$(TODAY)" \
	--output $@

test_report.tsv: build/ohmi_merged.owl
	$(ROBOT) report \
	--input $< \
        --fail-on none \
	--output $@

### Test
#
# Run main tests
MERGED_VIOLATION_QUERIES := $(wildcard src/sparql/*-violation.rq)

build/terms-report.csv: build/ohmi_merged.owl src/sparql/terms-report.rq | build
	$(ROBOT) query --input $< --select $(word 2,$^) $@

build/ohmi-previous-release.owl: | build
	curl -L -o $@ "http://purl.obolibrary.org/obo/ohmi.owl"

build/released-entities.tsv: build/ohmi-previous-release.owl src/sparql/get-ohmi-entities.rq | build/robot.jar
	$(ROBOT) query --input $< --select $(word 2,$^) $@

build/current-entities.tsv: build/ohmi_merged.owl src/sparql/get-ohmi-entities.rq | build/robot.jar
	$(ROBOT) query --input $< --select $(word 2,$^) $@

build/dropped-entities.tsv: build/released-entities.tsv build/current-entities.tsv
	comm -23 $^ > $@

# Run all validation queries and exit on error.
.PHONY: verify
verify: verify-merged verify-entities

# Run validation queries on ohmi_merged and exit on error.
.PHONY: verify-merged
verify-merged: build/ohmi_merged.owl $(MERGED_VIOLATION_QUERIES) | build/robot.jar
	$(ROBOT) verify --input $< --output-dir build \
	--queries $(MERGED_VIOLATION_QUERIES)

# Check if any entities have been dropped and exit on error.
.PHONY: verify-entities
verify-entities: build/dropped-entities.tsv
	@echo $(shell < $< wc -l) " ohmi IRIs have been dropped"
	@! test -s $<

# Run a Hermit reasoner to find inconsistencies
.PHONY: reason
reason: build/ohmi_merged.owl | build/robot.jar
	$(ROBOT) reason --input $< --reasoner HermiT

.PHONY: test
test: reason verify


### General/Users/jiezheng/Documents/ontology/ohmi
#
# Full build
.PHONY: all
all: test ohmi.owl build/terms-report.csv

# Remove generated files
.PHONY: clean
clean:
	rm -rf build

# Check for problems such as bad line-endings
.PHONY: check
check:
	src/scripts/check-line-endings.sh tsv

# Fix simple problems such as bad line-endings
.PHONY: fix
fix:
	src/scripts/fix-eol-all.sh
