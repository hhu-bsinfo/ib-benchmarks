#!/bin/bash

readonly SCRIPT_DIR="$( cd "$(dirname "${BASH_SOURCE[0]}")" && pwd )"

readonly SERVER="10.0.0.65"
readonly CLIENT="10.0.0.66"

cd $SCRIPT_DIR
source ./settings.conf

if [ "${1}" = "server" ]; then
    echo "Building..."
    ./build_all.sh -m build -i "${J9_JAVA_PATH}" -j "${JAVA_PATH}"

    echo "Running as server"
    ./run_all.sh -m "server" -a "${SERVER}" -rs compat -i "${J9_JAVA_PATH}" -j "${JAVA_PATH}" -l "${LIBVMA_PATH}" # > ./server.log 2>&1
elif [ "${1}" = "client" ]; then
    echo "Running as client"
    sleep 10 && ./run_all.sh -m client -r "${SERVER}" -a "${CLIENT}" -i "${J9_JAVA_PATH}" -j "${JAVA_PATH}" -l "${LIBVMA_PATH}" #> ./client.log 2>&1
else
    echo "Usage: ${0} <type server/client>"
    exit 1
fi
