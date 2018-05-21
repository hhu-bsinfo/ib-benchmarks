#!/bin/bash

rm -rf doc/
mkdir -p doc/CVerbsBench/

doxygen src/CVerbsBench/doxygen.conf
ln -s CVerbsBench/html/index.html doc/CVerbsBench.html
