#!/bin/bash

rm -rf doc/
mkdir -p doc/CVerbsBench/
mkdir -p doc/JSocketBench/

doxygen src/CVerbsBench/doxygen.conf
doxygen src/JSocketBench/doxygen.conf

ln -s CVerbsBench/html/index.html doc/CVerbsBench.html
ln -s JSocketBench/html/index.html doc/JSocketBench.html
