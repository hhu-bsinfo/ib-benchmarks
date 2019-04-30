#!/bin/bash

LD_LIBRARY_PATH=$LD_LIBRARY_PATH:${HOME}

readonly SCRIPT_DIR="$( cd "$(dirname "${BASH_SOURCE[0]}")" && pwd )"

readonly NODES=($( < pbs_nodes ))
readonly SERVER="10.100.0.$(echo "${NODES[0]}" | sed -e "s/.hilbert.hpc.uni-duesseldorf.de//" | cut -c 8-)"
readonly CLIENT="10.100.0.$(echo "${NODES[1]}" | sed -e "s/.hilbert.hpc.uni-duesseldorf.de//" | cut -c 8-)"

readonly RESULTS_OUTPATH="${1}"
readonly BENCHMARK_PATH="${2}"
readonly JAVA_PATH="${3}"
readonly J9_JAVA_PATH="${4}"
readonly LIBVMA_PATH="${5}"

cd "${BENCHMARK_PATH}" || exit 1

if [ "${PBS_NODENUM}" -eq "0" ]; then
    echo "dummy" > "${RESULTS_OUTPATH}/server.log"
    ./run_all.sh -m "server" -a "${SERVER}" -rs compat -i "${J9_JAVA_PATH}" -j "${JAVA_PATH}" -l "${LIBVMA_PATH}" -o "${RESULTS_OUTPATH}" > "${RESULTS_OUTPATH}/server.log" 2>&1
elif [ "${PBS_NODENUM}" -eq "1" ]; then
    echo "dummy" > "${RESULTS_OUTPATH}/client.log"
    sleep 10 && ./run_all.sh -m client -r "${SERVER}" -a "${CLIENT}" -i "${J9_JAVA_PATH}" -j "${JAVA_PATH}" -l "${LIBVMA_PATH}" -o "${RESULTS_OUTPATH}" > "${RESULTS_OUTPATH}/client.log" 2>&1
fi

cd ~ || exit 1
