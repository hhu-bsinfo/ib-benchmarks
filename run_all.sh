#!/bin/bash

readonly GIT_VERSION="$(git describe --tags --abbrev=0 2>/dev/null)"
readonly GIT_BRANCH="$(git rev-parse --symbolic-full-name --abbrev-ref HEAD 2>/dev/null)"
readonly GIT_REV="$(git rev-parse --short HEAD 2>/dev/null)"
readonly DATE="$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null)"

JAVA_PATH="java"
LIBVMA_PATH="libvma.so"
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
    -l, --libvma
        Set the path to the libvma shared object file (default 'libvma.so').
    -m, --mode
        Set the operating mode (server/client). This is a required option!
    -r, --remote
        Set the remote hostname. This is a required option when the program is running as a client!
    -a, --address
        Set the address to bind the local sockets to.
    -rs, --raw-statistics
        Set the way to get the infiniband performance counters to either 'mad' (requires root!) or 'compat' (default: 'compat').
    -h, --help
        Show this help message\\n"
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
            -l|--libvma)
            LIBVMA_PATH=$val
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
            printf "Unknown option '%s'\\n" "${arg}"
            print_usage
            exit 1
            ;;
        esac
        shift 2
    done

    if [ "${MODE}" != "server" ] && [ "${MODE}" != "client" ]; then
        printf "\\e[91mInvalid mode '%s'!\\e[0m\\n" "${arg}"
        exit 1
    fi

    if [ "${MODE}" = "client" ] && [ "${REMOTE_ADDRESS}" = "" ]; then
        printf "\\e[91mMissing required parameter '--remote'!\\e[0m\\n"
        exit 1
    fi

    if [ "${RS_MODE}" != "mad" ] && [ "${RS_MODE}" != "compat" ]; then
        printf "\\e[91mInvalid raw statistics mode '%s'!\\e[0m\\n" "${RS_MODE}"
        exit 1
    fi
}

benchmark()
{
    local name="${1}"
    local outpath="${2}"
    local cmd="${3}"
    local benchmark="${4}"
    local transport="${5}"
    local size="${6}"
    local count="${7}"
    local port="${8}"

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
    
    printf "\\e[92mRunning '%s ${params[*]}'...\\e[0m\\n" "${cmd}"

    local output;
    output=$(eval "${cmd} ${params[*]}")

    if [[ $output = *"ERROR"* ]]; then
        printf "%s\\n" "${output}"
        printf "\\e[91mBenchmark exited with an error!\\e[0m\\n\\n"
        exit 1
    else
        printf "\\e[92mBenchmark exited successful!\\e[0m\\n\\n"
    fi

    if [ "${MODE}" = "server" ]; then
        mkdir -p "${outpath}/${benchmark}_${transport}_send_pkts_throughput/"
        mkdir -p "${outpath}/${benchmark}_${transport}_recv_pkts_throughput/"
        mkdir -p "${outpath}/${benchmark}_${transport}_combined_pkts_throughput/"
        mkdir -p "${outpath}/${benchmark}_${transport}_send_throughput/"
        mkdir -p "${outpath}/${benchmark}_${transport}_recv_throughput/"
        mkdir -p "${outpath}/${benchmark}_${transport}_combined_throughput/"
        mkdir -p "${outpath}/${benchmark}_${transport}_latency/"
        mkdir -p "${outpath}/${benchmark}_${transport}_send_overhead/"
        mkdir -p "${outpath}/${benchmark}_${transport}_recv_overhead/"
        mkdir -p "${outpath}/${benchmark}_${transport}_send_overhead_perc/"
        mkdir -p "${outpath}/${benchmark}_${transport}_recv_overhead_perc/"
        mkdir -p "${outpath}/${benchmark}_${transport}_send_raw_throughput/"
        mkdir -p "${outpath}/${benchmark}_${transport}_receive_raw_throughput/"
        mkdir -p "${outpath}/${benchmark}_${transport}_combined_raw_throughput/"
        
        local send_pkts_tp recv_pkts_tp combined_pkts_tp send_tp recv_tp combined_tp send_lat send_overhead;
        local send_overhead_perc recv_overhead recv_overhead_perc send_raw_tp recv_raw_tp combined_raw_tp;

        send_pkts_tp=$(echo "${output}" | sed '3q;d')
        recv_pkts_tp=$(echo "${output}" | sed '4q;d')
        combined_pkts_tp=$(echo "${output}" | sed '5q;d')
        send_tp=$(echo "${output}" | sed '6q;d')
        recv_tp=$(echo "${output}" | sed '7q;d')
        combined_tp=$(echo "${output}" | sed '8q;d')
        send_lat=$(echo "${output}" | sed '9q;d')
        send_overhead=$(echo "${output}" | sed '14q;d')
        send_overhead_perc=$(echo "${output}" | sed '15q;d')
        recv_overhead=$(echo "${output}" | sed '16q;d')
        recv_overhead_perc=$(echo "${output}" | sed '17q;d')
        send_raw_tp=$(echo "${output}" | sed '18q;d')
        recv_raw_tp=$(echo "${output}" | sed '19q;d')
        combined_raw_tp=$(echo "${output}" | sed '20q;d')

        echo -e "${send_pkts_tp}" >> "${outpath}/${benchmark}_${transport}_send_pkts_throughput/${name}.csv"
        echo -e "${recv_pkts_tp}" >> "${outpath}/${benchmark}_${transport}_recv_pkts_throughput/${name}.csv"
        echo -e "${combined_pkts_tp}" >> "${outpath}/${benchmark}_${transport}_combined_pkts_throughput/${name}.csv"
        echo -e "${send_tp}" >> "${outpath}/${benchmark}_${transport}_send_throughput/${name}.csv"
        echo -e "${recv_tp}" >> "${outpath}/${benchmark}_${transport}_recv_throughput/${name}.csv"
        echo -e "${combined_tp}" >> "${outpath}/${benchmark}_${transport}_combined_throughput/${name}.csv"
        echo -e "${send_lat}" >> "${outpath}/${benchmark}_${transport}_latency/${name}.csv"
        echo -e "${send_overhead}" >> "${outpath}/${benchmark}_${transport}_send_overhead/${name}.csv"
        echo -e "${recv_overhead}" >> "${outpath}/${benchmark}_${transport}_recv_overhead/${name}.csv"
        echo -e "${send_overhead_perc}" >> "${outpath}/${benchmark}_${transport}_send_overhead_perc/${name}.csv"
        echo -e "${recv_overhead_perc}" >> "${outpath}/${benchmark}_${transport}_recv_overhead_perc/${name}.csv"
        echo -e "${send_raw_tp}" >> "${outpath}/${benchmark}_${transport}_send_raw_throughput/${name}.csv"
        echo -e "${recv_raw_tp}" >> "${outpath}/${benchmark}_${transport}_receive_raw_throughput/${name}.csv"
        echo -e "${combined_raw_tp}" >> "${outpath}/${benchmark}_${transport}_combined_raw_throughput/${name}.csv"
    else
        printf "\\e[92mWaiting for server to become ready... \\e[0m"
        printf "\\e[92m3...\\e[0m"
        sleep 1s
        printf "\\e[92m2...\\e[0m"
        sleep 1s
        printf "\\e[92m1...\\e[0m"
        sleep 1s
        printf "\\n"
    fi
}

wait()
{
    printf "\\e[94mWaiting 1 minute for ports to be available again...\\e[0m\\n\\n"
    sleep 60
}

run_benchmark_series()
{
    local name="${1}"
    local cmd="${2}"
    local benchmark="${3}"
    local transport="${4}"

    for i in $(seq 0 20); do
        local size=$((2**i))
        local count=100000000
        
        if [ "${i}" -ge 13 ]; then
            count=$((count/$((2**$((i-12))))))
        fi
        
        benchmark "${name}" "results/1" "${cmd}" "${benchmark}" "${transport}" "${size}" "${count}" "$((8000+i))"
        benchmark "${name}" "results/2" "${cmd}" "${benchmark}" "${transport}" "${size}" "${count}" "$((8020+i))"
        benchmark "${name}" "results/3" "${cmd}" "${benchmark}" "${transport}" "${size}" "${count}" "$((8040+i))"
    done

    wait
}

gen_plot_file()
{
    local path="${1}"
    local name="${2}"
    local xlabel="${3}"
    local ylabel="${4}"
    local colors="${*:6}"

    local plot="\
            FILES = system(\"ls -1 ${name}/*.csv\")\\n\
            PACKET_FILES = system(\"ls -1 packets-throughput/*.csv\")\\n\
            LABELS = system(\"ls -1 ${name}/*.csv | cut -d'/' -f2 | cut -d'.' -f1\")\\n\
            COLORS = \"${colors}\"\
            \\n\
            set xlabel '${xlabel}'\\n\
            set ylabel 'Messages [millions/s]'\\n\
            set y2label '${ylabel}'\\n\
            set grid\\n\
            set key above\\n\
            set xtics ('1' 0, '4' 2, '16' 4, '64' 6, '256' 8, '1K' 10, '4KiB' 12, '16KiB' 14, '64KiB' 16, '256KiB' 18, '1MiB' 20)\\n\
            set xrange [0:20]\\n\
            set ytics nomirror\\n\
            set y2tics\\n\
            set datafile separator ','\\n\
            set terminal svg\\n\
            set output 'output/${name}.svg'
            plot for [i=1:words(FILES)] word(FILES,i) using 0:1:2:3 title word(LABELS,i) axes x1y2 with yerrorbars lt rgb word(COLORS,i) dt 1 pt i, \
                 for [i=1:words(FILES)] word(FILES,i) using 0:1 notitle axes x1y2 with lines lt rgb word(COLORS,i) dt 1, \
                 for [i=1:words(PACKET_FILES)] word(PACKET_FILES,i) using 0:1:2:3 notitle axes x1y1 with yerrorbars lt rgb word(COLORS,i) dt 1 pt i, \
                 for [i=1:words(PACKET_FILES)] word(PACKET_FILES,i) using 0:1 notitle axes x1y1 with lines lt rgb word(COLORS,i) dt 2"
    
    if [ ! -d "${path}/output" ]; then
        mkdir -p "${path}/output"
    fi

    if [ ! -d "${path}/packets-throughput" ]; then
        mkdir -p "${path}/packets-throughput"
    fi

    mkdir -p "${path}/${name}"
    echo -e "${plot}" > "${path}/${name}.plot"
}

sort_csv_values()
{
    mkdir -p "results/sorted/"

    for folder in results/1/*; do
        for file in "${folder}"/*; do
            for i in $(seq 0 20); do
                local subpath first second third sorted

                subpath=$(basename "${folder}")/$(basename "${file}")

                first=$(sed "$((i+1))q;d" < "results/1/${subpath}")
                second=$(sed "$((i+1))q;d" < "results/2/${subpath}")
                third=$(sed "$((i+1))q;d" < "results/3/${subpath}")

                sorted=$(echo -e "${first}\\n${second}\\n${third}" | sort -n)

                first=$(echo "${sorted}" | sed '1q;d')
                second=$(echo "${sorted}" | sed '2q;d')
                third=$(echo "${sorted}" | sed '3q;d')

                if [ ! -d "results/sorted/$(basename "${folder}")" ]; then
                    mkdir -p "results/sorted/$(basename "${folder}")"
                fi

                if [ ! -f "results/sorted/${subpath}" ]; then
                    touch "results/sorted/${subpath}"
                fi

                echo "${second},${first},${third}" >> "results/sorted/${subpath}"
            done
        done
    done
}

assemble_results()
{
    gen_plot_file "results/graphs/unidirectional/verbs" "latency" "Message size [Bytes]" "Latency [us]" "red" "green" "blue"
    gen_plot_file "results/graphs/unidirectional/verbs" "throughput" "Message size [Bytes]" "Throughput [MB/s]" "red" "green" "blue"
    gen_plot_file "results/graphs/unidirectional/sockets" "latency" "Message size [Bytes]" "Latency [us]" "#8B008B" "#006400" "orange" "#191970"
    gen_plot_file "results/graphs/unidirectional/sockets" "throughput" "Message size [Bytes]" "Throughput [MB/s]" "#8B008B" "#006400" "orange" "#191970"
    gen_plot_file "results/graphs/unidirectional/mixed" "latency" "Message size [Bytes]" "Latency [us]" "red" "orange" "blue" "#191970"
    gen_plot_file "results/graphs/unidirectional/mixed" "throughput" "Message size [Bytes]" "Throughput [MB/s]" "red" "orange" "blue" "#191970"

    gen_plot_file "results/graphs/bidirectional/verbs" "latency" "Message size [Bytes]" "Latency [us]" "red" "green" "blue"
    gen_plot_file "results/graphs/bidirectional/verbs" "throughput" "Message size [Bytes]" "Throughput [MB/s]" "red" "green" "blue"
    gen_plot_file "results/graphs/bidirectional/sockets" "latency" "Message size [Bytes]" "Latency [us]" "#8B008B" "#006400" "orange" "#191970"
    gen_plot_file "results/graphs/bidirectional/sockets" "throughput" "Message size [Bytes]" "Throughput [MB/s]" "#8B008B" "#006400" "orange" "#191970"
    gen_plot_file "results/graphs/bidirectional/mixed" "latency" "Message size [Bytes]" "Latency [us]" "red" "orange" "blue" "#191970"
    gen_plot_file "results/graphs/bidirectional/mixed" "throughput" "Message size [Bytes]" "Throughput [MB/s]" "red" "orange" "blue" "#191970"

    sort_csv_values

    cp "results/sorted/unidirectional_msg_latency/CVerbsBench.csv" "results/graphs/unidirectional/verbs/latency/CVerbsBench(msg).csv"
    cp "results/sorted/unidirectional_rdma_latency/CVerbsBench.csv" "results/graphs/unidirectional/verbs/latency/CVerbsBench(rdma).csv"
    cp "results/sorted/unidirectional_rdma_latency/JVerbsBench.csv" "results/graphs/unidirectional/verbs/latency/JVerbsBench(rdma).csv"

    cp "results/sorted/unidirectional_msg_send_throughput/CVerbsBench.csv" "results/graphs/unidirectional/verbs/throughput/CVerbsBench(msg).csv"
    cp "results/sorted/unidirectional_rdma_send_throughput/CVerbsBench.csv" "results/graphs/unidirectional/verbs/throughput/CVerbsBench(rdma).csv"
    cp "results/sorted/unidirectional_rdma_send_throughput/JVerbsBench.csv" "results/graphs/unidirectional/verbs/throughput/JVerbsBench(rdma).csv"

    cp "results/sorted/unidirectional_msg_send_pkts_throughput/CVerbsBench.csv" "results/graphs/unidirectional/verbs/packets-throughput/CVerbsBench(msg).csv"
    cp "results/sorted/unidirectional_rdma_send_pkts_throughput/CVerbsBench.csv" "results/graphs/unidirectional/verbs/packets-throughput/CVerbsBench(rdma).csv"
    cp "results/sorted/unidirectional_rdma_send_pkts_throughput/JVerbsBench.csv" "results/graphs/unidirectional/verbs/packets-throughput/JVerbsBench(rdma).csv"

    cp "results/sorted/unidirectional_msg_latency/IPoIB.csv" "results/graphs/unidirectional/sockets/latency/IPoIB.csv"
    cp "results/sorted/unidirectional_rdma_latency/JSOR.csv" "results/graphs/unidirectional/sockets/latency/JSOR.csv"
    cp "results/sorted/unidirectional_rdma_latency/libvma.csv" "results/graphs/unidirectional/sockets/latency/libvma.csv"

    cp "results/sorted/unidirectional_msg_latency/IPoIB.csv" "results/graphs/unidirectional/sockets/throughput/IPoIB.csv"
    cp "results/sorted/unidirectional_rdma_latency/JSOR.csv" "results/graphs/unidirectional/sockets/throughput/JSOR.csv"
    cp "results/sorted/unidirectional_rdma_latency/libvma.csv" "results/graphs/unidirectional/sockets/throughput/libvma.csv"

    cp "results/sorted/unidirectional_msg_latency/IPoIB.csv" "results/graphs/unidirectional/sockets/packets-throughput/IPoIB.csv"
    cp "results/sorted/unidirectional_rdma_latency/JSOR.csv" "results/graphs/unidirectional/sockets/packets-throughput/JSOR.csv"
    cp "results/sorted/unidirectional_rdma_latency/libvma.csv" "results/graphs/unidirectional/sockets/packets-throughput/libvma.csv"

    cp "results/sorted/unidirectional_msg_latency/CVerbsBench.csv" "results/graphs/unidirectional/mixed/latency/CVerbsBench(msg).csv"
    cp "results/sorted/unidirectional_rdma_latency/JVerbsBench.csv" "results/graphs/unidirectional/mixed/latency/JVerbsBench(rdma).csv"
    cp "results/sorted/unidirectional_rdma_latency/JSOR.csv" "results/graphs/unidirectional/mixed/latency/JSOR.csv"
    cp "results/sorted/unidirectional_rdma_latency/libvma.csv" "results/graphs/unidirectional/mixed/latency/libvma.csv"

    cp "results/sorted/unidirectional_msg_latency/CVerbsBench.csv" "results/graphs/unidirectional/mixed/throughput/CVerbsBench(msg).csv"
    cp "results/sorted/unidirectional_rdma_latency/JVerbsBench.csv" "results/graphs/unidirectional/mixed/throughput/JVerbsBench(rdma).csv"
    cp "results/sorted/unidirectional_rdma_latency/JSOR.csv" "results/graphs/unidirectional/mixed/throughput/JSOR.csv"
    cp "results/sorted/unidirectional_rdma_latency/libvma.csv" "results/graphs/unidirectional/mixed/throughput/libvma.csv"

    cp "results/sorted/unidirectional_msg_latency/CVerbsBench.csv" "results/graphs/unidirectional/mixed/packets-throughput/CVerbsBench(msg).csv"
    cp "results/sorted/unidirectional_rdma_latency/JVerbsBench.csv" "results/graphs/unidirectional/mixed/packets-throughput/JVerbsBench(rdma).csv"
    cp "results/sorted/unidirectional_rdma_latency/JSOR.csv" "results/graphs/unidirectional/mixed/packets-throughput/JSOR.csv"
    cp "results/sorted/unidirectional_rdma_latency/libvma.csv" "results/graphs/unidirectional/mixed/packets-throughput/libvma.csv"

    cp "results/sorted/bidirectional_msg_latency/CVerbsBench.csv" "results/graphs/bidirectional/verbs/latency/CVerbsBench(msg).csv"
    cp "results/sorted/bidirectional_rdma_latency/CVerbsBench.csv" "results/graphs/bidirectional/verbs/latency/CVerbsBench(rdma).csv"
    cp "results/sorted/bidirectional_rdma_latency/JVerbsBench.csv" "results/graphs/bidirectional/verbs/latency/JVerbsBench(rdma).csv"

    cp "results/sorted/bidirectional_msg_send_throughput/CVerbsBench.csv" "results/graphs/bidirectional/verbs/throughput/CVerbsBench(msg).csv"
    cp "results/sorted/bidirectional_rdma_send_throughput/CVerbsBench.csv" "results/graphs/bidirectional/verbs/throughput/CVerbsBench(rdma).csv"
    cp "results/sorted/bidirectional_rdma_send_throughput/JVerbsBench.csv" "results/graphs/bidirectional/verbs/throughput/JVerbsBench(rdma).csv"

    cp "results/sorted/bidirectional_msg_send_pkts_throughput/CVerbsBench.csv" "results/graphs/bidirectional/verbs/packets-throughput/CVerbsBench(msg).csv"
    cp "results/sorted/bidirectional_rdma_send_pkts_throughput/CVerbsBench.csv" "results/graphs/bidirectional/verbs/packets-throughput/CVerbsBench(rdma).csv"
    cp "results/sorted/bidirectional_rdma_send_pkts_throughput/JVerbsBench.csv" "results/graphs/bidirectional/verbs/packets-throughput/JVerbsBench(rdma).csv"

    cp "results/sorted/bidirectional_msg_latency/IPoIB.csv" "results/graphs/bidirectional/sockets/latency/IPoIB.csv"
    cp "results/sorted/bidirectional_rdma_latency/JSOR.csv" "results/graphs/bidirectional/sockets/latency/JSOR.csv"
    cp "results/sorted/bidirectional_rdma_latency/libvma.csv" "results/graphs/bidirectional/sockets/latency/libvma.csv"

    cp "results/sorted/bidirectional_msg_latency/IPoIB.csv" "results/graphs/bidirectional/sockets/throughput/IPoIB.csv"
    cp "results/sorted/bidirectional_rdma_latency/JSOR.csv" "results/graphs/bidirectional/sockets/throughput/JSOR.csv"
    cp "results/sorted/bidirectional_rdma_latency/libvma.csv" "results/graphs/bidirectional/sockets/throughput/libvma.csv"

    cp "results/sorted/bidirectional_msg_latency/IPoIB.csv" "results/graphs/bidirectional/sockets/packets-throughput/IPoIB.csv"
    cp "results/sorted/bidirectional_rdma_latency/JSOR.csv" "results/graphs/bidirectional/sockets/packets-throughput/JSOR.csv"
    cp "results/sorted/bidirectional_rdma_latency/libvma.csv" "results/graphs/bidirectional/sockets/packets-throughput/libvma.csv"

    cp "results/sorted/bidirectional_msg_latency/CVerbsBench.csv" "results/graphs/bidirectional/mixed/latency/CVerbsBench(msg).csv"
    cp "results/sorted/bidirectional_rdma_latency/JVerbsBench.csv" "results/graphs/bidirectional/mixed/latency/JVerbsBench(rdma).csv"
    cp "results/sorted/bidirectional_rdma_latency/JSOR.csv" "results/graphs/bidirectional/mixed/latency/JSOR.csv"
    cp "results/sorted/bidirectional_rdma_latency/libvma.csv" "results/graphs/bidirectional/mixed/latency/libvma.csv"

    cp "results/sorted/bidirectional_msg_latency/CVerbsBench.csv" "results/graphs/bidirectional/mixed/throughput/CVerbsBench(msg).csv"
    cp "results/sorted/bidirectional_rdma_latency/JVerbsBench.csv" "results/graphs/bidirectional/mixed/throughput/JVerbsBench(rdma).csv"
    cp "results/sorted/bidirectional_rdma_latency/JSOR.csv" "results/graphs/bidirectional/mixed/throughput/JSOR.csv"
    cp "results/sorted/bidirectional_rdma_latency/libvma.csv" "results/graphs/bidirectional/mixed/throughput/libvma.csv"

    cp "results/sorted/bidirectional_msg_latency/CVerbsBench.csv" "results/graphs/bidirectional/mixed/packets-throughput/CVerbsBench(msg).csv"
    cp "results/sorted/bidirectional_rdma_latency/JVerbsBench.csv" "results/graphs/bidirectional/mixed/packets-throughput/JVerbsBench(rdma).csv"
    cp "results/sorted/bidirectional_rdma_latency/JSOR.csv" "results/graphs/bidirectional/mixed/packets-throughput/JSOR.csv"
    cp "results/sorted/bidirectional_rdma_latency/libvma.csv" "results/graphs/bidirectional/mixed/packets-throughput/libvma.csv"
}

printf "\\e[94mRunning automatic benchmark script!\\e[0m\\n"
printf "\\e[94mversion: %s(%s) - git %s, date: %s!\\e[0m\\n\\n" "${GIT_VERSION}" "${GIT_BRANCH}" "${GIT_REV}" "${DATE}"

parse_args "$@"

printf "\\e[94mUsing '%s' for IPoIB, libvma, JSOR and jVerbs!\\e[0m\\n" "${JAVA_PATH}"
printf "\\e[94mUsing '%s' for libvma!\\e[0m\\n\\n" "${LIBVMA_PATH}"

JSOCKET_CMD="${JAVA_PATH} -Djava.net.preferIPv4Stack=true -jar src/JSocketBench/build/libs/JSocketBench.jar"
LIBVMA_CMD="sudo LD_PRELOAD=${LIBVMA_PATH} ${JAVA_PATH} -Djava.net.preferIPv4Stack=true -jar src/JSocketBench/build/libs/JSocketBench.jar"
JSOR_CMD="IBM_JAVA_RDMA_SBUF_SIZE=1048576 IBM_JAVA_RDMA_RBUF_SIZE=1048576 ${JAVA_PATH} -Dcom.ibm.net.rdma.conf=src/JSocketBench/jsor_${MODE}.conf -Djava.net.preferIPv4Stack=true -jar src/JSocketBench/build/libs/JSocketBench.jar"
JVERBS_CMD="${JAVA_PATH} -Djava.net.preferIPv4Stack=true -jar src/JVerbsBench/build/libs/JVerbsBench.jar"

rm -rf "results"

run_benchmark_series "CVerbsBench" "${CVERBS_CMD}" "unidirectional" "msg"
run_benchmark_series "CVerbsBench" "${CVERBS_CMD}" "bidirectional" "msg"
run_benchmark_series "CVerbsBench" "${CVERBS_CMD}" "unidirectional" "rdma"
run_benchmark_series "CVerbsBench" "${CVERBS_CMD}" "bidirectional" "rdma"
run_benchmark_series "JVerbsBench" "${JVERBS_CMD}" "unidirectional" "rdma"
run_benchmark_series "JVerbsBench" "${JVERBS_CMD}" "bidirectional" "rdma"
run_benchmark_series "JSOR" "${JSOR_CMD}" "unidirectional"
run_benchmark_series "libvma" "${LIBVMA_CMD}" "unidirectional"
run_benchmark_series "libvma" "${LIBVMA_CMD}" "bidirectional"
run_benchmark_series "JSocketBench" "${JSOCKET_CMD}" "unidirectional"
run_benchmark_series "JSocketBench" "${JSOCKET_CMD}" "bidirectional"

assemble_results