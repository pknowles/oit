#!/bin/bash

EXE=./oit
OUT=results
TIME=$(date '+%Y%m%d_%H%M%S');

mkdir -p $OUT

#$EXE -r tests/lfb.xml 2>&1 > $OUT/log_lfb_$TIME.txt
#sleep 3
#mv benchmark.csv $OUT/lfb_$TIME.csv

$EXE -r tests/all.xml 2>&1 > $OUT/log_all_$TIME.txt
sleep 3
mv benchmark.csv $OUT/all_$TIME.csv

$EXE -r tests/coherent_oit.xml 2>&1 > $OUT/log_clfb_$TIME.txt
sleep 3
mv benchmark.csv $OUT/clfb_$TIME.csv
