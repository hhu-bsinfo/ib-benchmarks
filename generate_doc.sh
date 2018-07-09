#!/bin/bash

rm -rf doc/
mkdir -p doc/CVerbsBench/
mkdir -p doc/JSocketBench/
mkdir -p doc/JVerbsBench/

doxygen src/CVerbsBench/doxygen.conf
doxygen src/JSocketBench/doxygen.conf
doxygen src/JVerbsBench/doxygen.conf

ln -s CVerbsBench/html/index.html doc/CVerbsBench.html
ln -s JSocketBench/html/index.html doc/JSocketBench.html
ln -s JVerbsBench/html/index.html doc/JVerbsBench.html
