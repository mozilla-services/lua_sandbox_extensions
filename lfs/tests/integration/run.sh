#!/usr/bin/env bash
rm -rf output
mkdir -p load/input
mkdir -p load/analysis
mkdir -p load/output
hindsight_cli ../hindsight.cfg 7
rc=$?; if [[ $rc != 2 ]]; then exit $rc; fi
