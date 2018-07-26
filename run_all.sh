#!/bin/bash

readonly GIT_REV="$(git rev-parse --short HEAD)"
readonly DATE="$(date '+%Y-%m-%d %H:%M:%S')"

JAVA_PATH="java"
MODE=""
REMOTE_ADDRESS=""
BIND_ADDRESS=""
RS_MODE="compat"

CVERBS_CMD="./src/CVerbsBench/build/bin/CVerbsBench"
JSOCKET_CMD=""
JSOR_CMD=""
LIBVMA_CMD=""
JVERBS_CMD=""

print_usage()
{
    printf "Usage: ./run_all.sh [OPTION...]
    Available options:
    -j, --java
        Set the path to your default JVM (default: 'java').
    -m, --mode
        Set the operating mode (server/client). This is a required option!
    -r, --remote
        Set the remote hostname. This is a required option when the program is running as a client!
    -a, --address
        Set the address to bind the local sockets to.
    -rs, --raw-statistics
        Set the way to get the infiniband performance counters to either 'mad' (requires root!) or 'compat' (default: 'compat').
    -h, --help
        Show this help message\n"
}


parse_args()
{
    while [ "${1}" != "" ]; do
        local arg=$1
        local val=$2

        case $arg in
            -j|--java)
            JAVA_PATH=$val
            ;;
            -m|--mode)
            MODE=$val
            ;;
            -r|--remote)
            REMOTE_ADDRESS=$val
            ;;
            -a|--address)
            BIND_ADDRESS=$val
            ;;
            -rs|--raw-statistics)
            RS_MODE=$val
            ;;
            -h|--help)
            print_usage
            exit 0
            ;;
            *)
            printf "Unknown option '${arg}'\n"
            print_usage
            exit 1
            ;;
        esac
        shift 2
    done

    if [ "${MODE}" != "server" ] && [ "${MODE}" != "client" ]; then
        printf "\e[91mInvalid mode '${MODE}'!\e[0m\n"
        exit 1
    fi

    if [ "${MODE}" = "client" ] && [ "${REMOTE_ADDRESS}" = "" ]; then
        printf "\e[91mMissing required parameter '--remote'!\e[0m\n"
        exit 1
    fi

    if [ "${RS_MODE}" != "mad" ] && [ "${RS_MODE}" != "compat" ]; then
        printf "\e[91mInvalid raw statistics mode '${RS_MODE}'!\e[0m\n"
        exit 1
    fi
}

gen_plot_file()
{
    local name=$1
    local xlabel=$2
    local ylabel=$3

    local plot="\
            FILES = system(\"ls -1 results/${name}/*.csv\")\n\
            LABELS = system(\"ls -1 results/${name}/*.csv | cut -d'/' -f3 | cut -d'.' -f1\")\n\
            \n\
            set title '${name}'\n\
            set xlabel '${xlabel}'\n\
            set ylabel '${ylabel}'\n\
            set grid\n\
            set xtics ('1' 1, '4' 3, '16' 5, '64' 7, '256' 9, '1K' 11, '4K' 13, '16K' 15, '64K' 17, '256K' 19, '1M' 21, '4M' 23, '16M' 25, '64M' 27, '256M' 29, '1G' 31)\n\
            set terminal svg\n\
            set datafile separator ','\n\
            set output 'results/${name}.svg'\n
            plot for [i=1:words(FILES)] word(FILES,i) using 0:1 title word(LABELS,i) with lines"

    mkdir -p "results"
    echo -e "${plot}" > "results/${name}.plot"
}

benchmark()
{
    local name="${1}"
    local cmd="${2}"
    local benchmark="${3}"
    local transport="${4}"
    local size="${5}"
    local count="${6}"
    local port="${7}"
    local jsor_buf_size="1048576"

    local params=("-v" "0" "-b" "${benchmark}" "-s" "${size}" "-c" "${count}" "-m" "${MODE}" "-rs" "${RS_MODE}")

    if [ "${MODE}" = "client" ]; then
        params[12]="-r"
        params[13]="${REMOTE_ADDRESS}"
    fi

    if [ "${BIND_ADDRESS}" != "" ]; then
        params[14]="-a"
        params[15]="${BIND_ADDRESS}"
    fi
    
    if [ "${transport}" != "" ]; then
        params[16]="-t"
        params[17]="${transport}"
    else
        transport="msg"
    fi

    if [ "${port}" != "" ]; then
        params[18]="-p"
        params[19]="${port}"
    fi
    
    printf "\e[92mRunning '${cmd} ${params[*]}'...\e[0m\n"

    local output=$(eval "${cmd} ${params[*]}")

    if [[ $output = *"ERROR"* ]]; then
        printf "${output}\n"
        printf "\e[91mBenchmark exited with an error!\e[0m\n"
        exit 1
    else
        printf "\e[92mBenchmark exited successful!\e[0m\n"
    fi

    if [ "${MODE}" = "server" ]; then
        mkdir -p "results/${benchmark}_${transport}_send_pkts_throughput/"
        mkdir -p "results/${benchmark}_${transport}_recv_pkts_throughput/"
        mkdir -p "results/${benchmark}_${transport}_combined_pkts_throughput/"
        mkdir -p "results/${benchmark}_${transport}_send_throughput/"
        mkdir -p "results/${benchmark}_${transport}_recv_throughput/"
        mkdir -p "results/${benchmark}_${transport}_combined_throughput/"
        mkdir -p "results/${benchmark}_${transport}_latency/"
        mkdir -p "results/${benchmark}_${transport}_send_overhead/"
        mkdir -p "results/${benchmark}_${transport}_recv_overhead/"
        mkdir -p "results/${benchmark}_${transport}_send_overhead_perc/"
        mkdir -p "results/${benchmark}_${transport}_recv_overhead_perc/"
        mkdir -p "results/${benchmark}_${transport}_send_raw_throughput/"
        mkdir -p "results/${benchmark}_${transport}_receive_raw_throughput/"
        mkdir -p "results/${benchmark}_${transport}_combined_raw_throughput/"
        
        local total_time=$(echo "${output}" | sed '1q;d')
        local total_data=$(echo "${output}" | sed '2q;d')
        local send_pkts_tp=$(echo "${output}" | sed '3q;d')
        local recv_pkts_tp=$(echo "${output}" | sed '4q;d')
        local combined_pkts_tp=$(echo "${output}" | sed '5q;d')
        local send_tp=$(echo "${output}" | sed '6q;d')
        local recv_tp=$(echo "${output}" | sed '7q;d')
        local combined_tp=$(echo "${output}" | sed '8q;d')
        local send_lat=$(echo "${output}" | sed '9q;d')
        local xmit_pkts=$(echo "${output}" | sed '10q;d')
        local rcv_pkts=$(echo "${output}" | sed '11q;d')
        local xmit_bytes=$(echo "${output}" | sed '12q;d')
        local rcv_bytes=$(echo "${output}" | sed '13q;d')
        local send_overhead=$(echo "${output}" | sed '14q;d')
        local send_overhead_perc=$(echo "${output}" | sed '15q;d')
        local recv_overhead=$(echo "${output}" | sed '16q;d')
        local recv_overhead_perc=$(echo "${output}" | sed '17q;d')
        local send_raw_tp=$(echo "${output}" | sed '18q;d')
        local recv_raw_tp=$(echo "${output}" | sed '19q;d')
        local combined_raw_tp=$(echo "${output}" | sed '20q;d')

        echo -e "${send_pkts_tp}" >> "results/${benchmark}_${transport}_send_pkts_throughput/${name}.csv"
        echo -e "${recv_pkts_tp}" >> "results/${benchmark}_${transport}_recv_pkts_throughput/${name}.csv"
        echo -e "${combined_pkts_tp}" >> "results/${benchmark}_${transport}_combined_pkts_throughput/${name}.csv"
        echo -e "${send_tp}" >> "results/${benchmark}_${transport}_send_throughput/${name}.csv"
        echo -e "${recv_tp}" >> "results/${benchmark}_${transport}_recv_throughput/${name}.csv"
        echo -e "${combined_tp}" >> "results/${benchmark}_${transport}_combined_throughput/${name}.csv"
        echo -e "${send_lat}" >> "results/${benchmark}_${transport}_latency/${name}.csv"
        echo -e "${send_overhead}" >> "results/${benchmark}_${transport}_send_overhead/${name}.csv"
        echo -e "${recv_overhead}" >> "results/${benchmark}_${transport}_recv_overhead/${name}.csv"
        echo -e "${send_overhead_perc}" >> "results/${benchmark}_${transport}_send_overhead_perc/${name}.csv"
        echo -e "${recv_overhead_perc}" >> "results/${benchmark}_${transport}_recv_overhead_perc/${name}.csv"
        echo -e "${send_raw_tp}" >> "results/${benchmark}_${transport}_send_raw_throughput/${name}.csv"
        echo -e "${recv_raw_tp}" >> "results/${benchmark}_${transport}_receive_raw_throughput/${name}.csv"
        echo -e "${combined_raw_tp}" >> "results/${benchmark}_${transport}_combined_raw_throughput/${name}.csv"
    else
        printf "\e[92m3...\e[0m"
        sleep 1s
        printf "\e[92m2...\e[0m"
        sleep 1s
        printf "\e[92m1...\e[0m"
        sleep 1s
        printf "\n"
    fi
}

run_benchmark_series()
{
    local name="${1}"
    local cmd="${2}"
    local benchmark="${3}"
    local transport="${4}"
    local jsor_buf_size="0"

    for i in `seq 0 20`; do
        local size=$((2**$i))
        local count=100000000
        
        if [ $i -ge 13 ]; then
            count=$((count/$((2**$(($i-12))))))
        fi
        
        benchmark "${name}" "${cmd}" "${benchmark}" "${transport}" "${size}" "${count}" "$((8000+$i))"
    done
}

wait()
{
    printf "Waiting 1 minute for ports to be available again...\n"
    sleep 60
}

printf "\e[94mRunning automatic benchmark script!\e[0m\n"
printf "\e[94mDate: ${DATE}, git ${GIT_REV}!\e[0m\n\n"

parse_args "$@"

printf "\e[94mUsing '${JAVA_PATH}' for IPoIB, libvma, JSOR and jVerbs!\e[0m\n\n"

JSOCKET_CMD="${JAVA_PATH} -Djava.net.preferIPv4Stack=true -jar src/JSocketBench/build/libs/JSocketBench.jar"
LIBVMA_CMD="sudo LD_PRELOAD=~/libvma.so.8.7.0 ${JAVA_PATH} -Djava.net.preferIPv4Stack=true -jar src/JSocketBench/build/libs/JSocketBench.jar"
JSOR_CMD="${JAVA_PATH} -Dcom.ibm.net.rdma.conf=src/JSocketBench/jsor_${MODE}.conf -Djava.net.preferIPv4Stack=true -jar src/JSocketBench/build/libs/JSocketBench.jar"
JVERBS_CMD="${JAVA_PATH} -Djava.net.preferIPv4Stack=true -jar src/JVerbsBench/build/libs/JVerbsBench.jar"

rm -rf "results"

run_benchmark_series "JVerbsBench" "${JVERBS_CMD}" "unidirectional" "rdma"
wait
run_benchmark_series "JVerbsBench" "${JVERBS_CMD}" "bidirectional" "rdma"
wait
run_benchmark_series "CVerbsBench" "${CVERBS_CMD}" "unidirectional" "rdma"
wait
run_benchmark_series "CVerbsBench" "${CVERBS_CMD}" "bidirectional" "rdma"
wait
run_benchmark_series "CVerbsBench" "${CVERBS_CMD}" "unidirectional" "msg"
wait
run_benchmark_series "CVerbsBench" "${CVERBS_CMD}" "bidirectional" "msg"
wait
run_benchmark_series "JSOR" "${JSOR_CMD}" "unidirectional"
wait
run_benchmark_series "libvma" "${LIBVMA_CMD}" "unidirectional"
wait
run_benchmark_series "libvma" "${LIBVMA_CMD}" "bidirectional"
wait
run_benchmark_series "JSocketBench" "${JSOCKET_CMD}" "unidirectional"
wait
run_benchmark_series "JSocketBench" "${JSOCKET_CMD}" "bidirectional"
wait
