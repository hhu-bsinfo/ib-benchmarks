#!/bin/bash

readonly NODES=($( < pbs_nodes ))
readonly SERVER="10.100.0.$(echo "${NODES[0]}" | cut -c8-)"
readonly CLIENT="10.100.0.$(echo "${NODES[1]}" | cut -c8-)"

cd Projekte/Masterarbeit/ || exit 1

if [ "${PBS_NODENUM}" -eq "0" ]; then
    ./run_all.sh -m "server" -a "${SERVER}" -rs compat -j ~/ibm-java-x86_64-80/bin/java > ~/server.log
elif [ "${PBS_NODENUM}" -eq "1" ]; then
    sleep 10 && ./run_all.sh -m client -r "${SERVER}" -a "${CLIENT}" -j ~/ibm-java-x86_64-80/bin/java > ~/client.log
fi

cd ~  || exit 1