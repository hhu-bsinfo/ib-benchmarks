#!/bin/bash

readonly GIT_VERSION="$(git describe --tags --abbrev=0 2>/dev/null)"
readonly GIT_BRANCH="$(git rev-parse --symbolic-full-name --abbrev-ref HEAD 2>/dev/null)"
readonly GIT_REV="$(git rev-parse --short HEAD 2>/dev/null)"
readonly DATE="$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null)"

JAVA_PATH="java"
J9_JAVA_PATH="java"
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
        Set the path to your default JVM, which will be used to run JSocketBench (default: 'java').
    -i, --ibm-java
        Set the path to your J9 JVM, which will be used to run JVerbsBench (default: 'java').
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
            -i|--ibm-java)
            J9_JAVA_PATH=$val
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

check_config()
{
    local java_version j9_java_valid j9_java_version libvma_soname libvma_version

    printf "\\e[92mChecking configuration...\\e[0m\\n\\n"
    
    java_version=$("${JAVA_PATH}/bin/java" -version 2>&1 | sed -n ';s/.* version "\(.*\)\.\(.*\)\..*"/\1\2/p;')
    j9_java_valid=$("${J9_JAVA_PATH}/bin/java" -version 2>&1 | grep "IBM J9 VM");
    j9_java_version=$("${J9_JAVA_PATH}/bin/java" -version 2>&1 | sed -n ';s/.* version "\(.*\)\.\(.*\)\..*"/\1\2/p;')
    libvma_soname=$(readelf -d "${LIBVMA_PATH}" | grep SONAME | sed -e 's/.*\[//' -e 's/\]//')
    libvma_version=$(echo "${libvma_soname}" | sed -e 's/libvma.so.//')

    if [ -z "${java_version}" ]; then
        printf "\\e[91m'%s' does not seem to be a valid java executable!\\e[0m\\n" "${JAVA_PATH}"
        exit 1 
    fi

    if [ -z "${j9_java_version}" ]; then
        printf "\\e[91m'%s' does not seem to be a valid java executable!\\e[0m\\n" "${J9_JAVA_PATH}"
        exit 1
    fi

    if [ -z "${j9_java_valid}" ]; then
        printf "\\e[91m'%s' does not seem to belong to a valid IBM J9 JVM!\\e[0m\\n" "${J9_JAVA_PATH}"
        exit 1
    fi

    if [ "${java_version}" -lt 18 ]; then
        printf "\\e[91m'%s' implements a version of java older than 1.8 (determined version %u)!\\e[0m\\n" "${JAVA_PATH}" "${java_version}"
        exit 1
    else
        printf "\\e[92mDefault JVM: '%s' - Determined version: %u --> [VALID]\\n" "${JAVA_PATH}" "${java_version}"
    fi

    if [ "${j9_java_version}" -lt 18 ]; then
        printf "\\e[91m'%s' implements a version of java older than 1.8 (determined version %u)!\\e[0m\\n" "${J9_JAVA_PATH}" "${j9_java_version}"
        exit 1
    else
        printf "\\e[92mIBM J9 JVM: '%s' - Determined version: %u --> [VALID]\\n" "${J9_JAVA_PATH}" "${j9_java_version}"
    fi

    if [[ ! "${libvma_soname}" =~ libvma.so ]]; then
        printf "\\e[91m'%s' is not a valid version of libvma!\\e[0m\\n" "${LIBVMA_PATH}"
        exit 1
    fi

    printf "\\e[92mlibvma: '%s' - soname: '%s' - Determined version: %u --> [VALID]\\n" "${LIBVMA_PATH}" "${libvma_soname}" "${libvma_version}"

    if [ "${libvma_version}" -lt 8 ]; then
        printf "\\e[93mIt seems like you are using an old version of libvma. Consider updating libvma for optimal performance and compatibility!\\e[0m\\n"
    fi

    printf "\\n\\e[92mConfiguration seems to be valid!\\e[0m\\n\\n"
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

    eval "${cmd} ${params[*]}" > ./${MODE}_tmp.log 2>&1 
  
    local output="$(cat ./${MODE}_tmp.log)"

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

perftest_benchmark() {
    local name="${1}"
    local outpath="${2}"
    local benchmark="${3}"
    local transport="${4}"
    local size="${5}"
    local count="${6}"
    local port="${7}"

    local params

    if [ "${MODE}" = "server" ]; then
        params=("-s" "${size}" "-n" "${count}" "-p" "${port}" "-I" "0")
    else
        params=("${REMOTE_ADDRESS}" "-s" "${size}" "-n" "${count}" "-p" "${port}" "-I" "0")
    fi

    if [ "${benchmark}" = "bidirectional" ]; then
        params+=("-b")
    fi

    printf "\\e[92mRunning '%s ${params[*]}'...\\e[0m\\n" "${name}"
    eval "${name} ${params[*]}" > "${MODE}_tmp.log" 2>&1

    if [ $? -eq 0 ]; then
        printf "\\e[92mBenchmark exited successful!\\e[0m\\n\\n"
    else
        printf "\\e[91mBenchmark exited with an error! See %s_tmp.log for further details.\\e[0m\\n\\n" "${MODE}"
        exit 1
    fi

    local results
    read -r -a results <<< $(cat "${MODE}_tmp.log" | tail -n 2 | head -n 1)

    if [ "${MODE}" = "server" ]; then
        mkdir -p "${outpath}/${benchmark}_${transport}_send_pkts_throughput/"
        mkdir -p "${outpath}/${benchmark}_${transport}_send_throughput/"

        echo -e "${results[3]}" >> "${outpath}/${benchmark}_${transport}_send_pkts_throughput/${name}.csv"
        echo -e "${results[4]}" >> "${outpath}/${benchmark}_${transport}_send_throughput/${name}.csv"
    else
        printf "\\e[92mWaiting for server to become ready...\\e[0m"
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

run_perftest_series()
{
    local name="${1}"
    local benchmark="${2}"
    local transport="${3}"

    for i in $(seq 0 20); do
        local size=$((2**i))
        local count=100000000
        
        if [ "${i}" -ge 13 ]; then
            count=$((count/$((2**$((i-12))))))
        fi
        
        perftest_benchmark "${name}" "results/1" "${benchmark}" "${transport}" "${size}" "${count}" "$((8000+i))"
        perftest_benchmark "${name}" "results/2" "${benchmark}" "${transport}" "${size}" "${count}" "$((8020+i))"
        perftest_benchmark "${name}" "results/3" "${benchmark}" "${transport}" "${size}" "${count}" "$((8040+i))"
    done
}

gen_plot_file()
{
    local path="${1}"
    local name="${2}"
    local xlabel="${3}"
    local ylabel="${4}"
    local logscale="${5}"
    local colors="${*:6}"

    local plot="\
            FILES = system(\"ls -1 ${name}/*.csv\")\\n\
            PACKET_FILES = system(\"ls -1 packets-throughput/*.csv\")\\n\
            LABELS = system(\"ls -1 ${name}/*.csv | cut -d'/' -f2 | cut -d'.' -f1\")\\n\
            COLORS = \"${colors}\"\
            \\n\
            set xlabel '${xlabel}'\\n\
            set grid\\n\
            set key above\\n\
            set xtics ('1' 0, '4' 2, '16' 4, '64' 6, '256' 8, '1K' 10, '4KiB' 12, '16KiB' 14, '64KiB' 16, '256KiB' 18, '1MiB' 20)\\n\
            set xrange [0:20]\\n\
            set ytics nomirror\\n\
            set datafile separator ','\\n\
            set terminal svg\\n\
            set output 'output/${name}.svg'\\n"

    if [ "${logscale}" == "true" ]; then
        plot+="set logscale y\\n"
    fi

    if [ "${name}" == "overhead" ]; then
        plot+="set ylabel '${ylabel}'\\n\
               plot for [i=1:words(FILES)] word(FILES,i) using 0:1:2:3 title word(LABELS,i) axes x1y1 with yerrorbars lt rgb word(COLORS,i) dt i pt i, \
                    for [i=1:words(FILES)] word(FILES,i) using 0:1 notitle axes x1y1 with lines lt rgb word(COLORS,i) dt i"
    elif [ "${name}" == "latency" ]; then
        plot+="set ylabel '${ylabel}'\\n\
               set y2label 'Messages [millions/s]'\\n\
               set y2tics\\n\
               plot for [i=1:words(FILES)] word(FILES,i) using 0:1:2:3 title word(LABELS,i) axes x1y1 with yerrorbars lt rgb word(COLORS,i) dt 1 pt i, \
                    for [i=1:words(FILES)] word(FILES,i) using 0:1 notitle axes x1y1 with lines lt rgb word(COLORS,i) dt 1, \
                    for [i=1:words(PACKET_FILES)] word(PACKET_FILES,i) using 0:1:2:3 notitle axes x1y2 with yerrorbars lt rgb word(COLORS,i) dt 1 pt i, \
                    for [i=1:words(PACKET_FILES)] word(PACKET_FILES,i) using 0:1 notitle axes x1y2 with lines lt rgb word(COLORS,i) dt 2"
    else
        plot+="set ylabel 'Messages [millions/s]'\\n\
               set y2label '${ylabel}'\\n\
               set y2tics\\n\
               plot for [i=1:words(FILES)] word(FILES,i) using 0:1:2:3 title word(LABELS,i) axes x1y2 with yerrorbars lt rgb word(COLORS,i) dt 1 pt i, \
                    for [i=1:words(FILES)] word(FILES,i) using 0:1 notitle axes x1y2 with lines lt rgb word(COLORS,i) dt 1, \
                    for [i=1:words(PACKET_FILES)] word(PACKET_FILES,i) using 0:1:2:3 notitle axes x1y1 with yerrorbars lt rgb word(COLORS,i) dt 1 pt i, \
                    for [i=1:words(PACKET_FILES)] word(PACKET_FILES,i) using 0:1 notitle axes x1y1 with lines lt rgb word(COLORS,i) dt 2"
    fi
    
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
    gen_plot_file "results/graphs/unidirectional/verbs" "latency" "Message size [Bytes]" "Latency [us]" "true" "red" "green" "blue"
    gen_plot_file "results/graphs/unidirectional/verbs" "throughput" "Message size [Bytes]" "Throughput [MB/s]" "false" "red" "green" "blue"
    gen_plot_file "results/graphs/unidirectional/verbs" "overhead" "Message size [Bytes]" "Overhead [%]" "true" "red" "green" "blue"
    gen_plot_file "results/graphs/unidirectional/sockets" "latency" "Message size [Bytes]" "Latency [us]" "true" "#8B008B" "#006400" "orange" "#191970"
    gen_plot_file "results/graphs/unidirectional/sockets" "throughput" "Message size [Bytes]" "Throughput [MB/s]" "false" "#8B008B" "#006400" "orange" "#191970"
    gen_plot_file "results/graphs/unidirectional/sockets" "overhead" "Message size [Bytes]" "Overhead [%]" "true" "#8B008B" "#006400" "orange" "#191970"
    gen_plot_file "results/graphs/unidirectional/mixed" "latency" "Message size [Bytes]" "Latency [us]" "true" "red" "orange" "true" "blue" "#191970"
    gen_plot_file "results/graphs/unidirectional/mixed" "throughput" "Message size [Bytes]" "Throughput [MB/s]" "false" "red" "orange" "blue" "#191970"

    gen_plot_file "results/graphs/bidirectional/verbs" "latency" "Message size [Bytes]" "Latency [us]" "true" "red" "green" "blue"
    gen_plot_file "results/graphs/bidirectional/verbs" "throughput" "Message size [Bytes]" "Throughput [MB/s]" "false" "red" "green" "blue"
    gen_plot_file "results/graphs/bidirectional/sockets" "latency" "Message size [Bytes]" "Latency [us]" "true" "#8B008B" "#006400" "orange" "#191970"
    gen_plot_file "results/graphs/bidirectional/sockets" "throughput" "Message size [Bytes]" "Throughput [MB/s]" "false" "#8B008B" "#006400" "orange" "#191970"
    gen_plot_file "results/graphs/bidirectional/mixed" "latency" "Message size [Bytes]" "Latency [us]" "true" "red" "orange" "blue" "#191970"
    gen_plot_file "results/graphs/bidirectional/mixed" "throughput" "Message size [Bytes]" "Throughput [MB/s]" "false" "red" "orange" "blue" "#191970"

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

    cp "results/sorted/unidirectional_msg_send_overhead_perc/CVerbsBench.csv" "results/graphs/unidirectional/verbs/overhead/CVerbsBench(msg).csv"
    cp "results/sorted/unidirectional_rdma_send_overhead_perc/CVerbsBench.csv" "results/graphs/unidirectional/verbs/overhead/CVerbsBench(rdma).csv"
    cp "results/sorted/unidirectional_rdma_send_overhead_perc/JVerbsBench.csv" "results/graphs/unidirectional/verbs/overhead/JVerbsBench(rdma).csv"

    cp "results/sorted/unidirectional_msg_latency/IPoIB.csv" "results/graphs/unidirectional/sockets/latency/IPoIB.csv"
    cp "results/sorted/unidirectional_rdma_latency/JSOR.csv" "results/graphs/unidirectional/sockets/latency/JSOR.csv"
    cp "results/sorted/unidirectional_rdma_latency/libvma.csv" "results/graphs/unidirectional/sockets/latency/libvma.csv"

    cp "results/sorted/unidirectional_msg_latency/IPoIB.csv" "results/graphs/unidirectional/sockets/throughput/IPoIB.csv"
    cp "results/sorted/unidirectional_rdma_latency/JSOR.csv" "results/graphs/unidirectional/sockets/throughput/JSOR.csv"
    cp "results/sorted/unidirectional_rdma_latency/libvma.csv" "results/graphs/unidirectional/sockets/throughput/libvma.csv"

    cp "results/sorted/unidirectional_msg_send_overhead_perc/IPoIB.csv" "results/graphs/unidirectional/overhead/packets-throughput/IPoIB.csv"
    cp "results/sorted/unidirectional_rdma_send_overhead_perc/JSOR.csv" "results/graphs/unidirectional/overhead/packets-throughput/JSOR.csv"
    cp "results/sorted/unidirectional_rdma_send_overhead_perc/libvma.csv" "results/graphs/unidirectional/overhead/packets-throughput/libvma.csv"

    cp "results/sorted/unidirectional_msg_latency/IPoIB.csv" "results/graphs/unidirectional/sockets/latency/IPoIB.csv"
    cp "results/sorted/unidirectional_rdma_latency/JSOR.csv" "results/graphs/unidirectional/sockets/latency/JSOR.csv"
    cp "results/sorted/unidirectional_rdma_latency/libvma.csv" "results/graphs/unidirectional/sockets/latency/libvma.csv"

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
check_config

printf "\\e[94mUsing '%s' for IPoIB and libvma!\\e[0m\\n" "${JAVA_PATH}"
printf "\\e[94mUsing '%s' for JSOR and jVerbs!\\e[0m\\n" "${J9_JAVA_PATH}"
printf "\\e[94mUsing '%s' for libvma!\\e[0m\\n\\n" "${LIBVMA_PATH}"

JSOCKET_CMD="${JAVA_PATH} -Djava.net.preferIPv4Stack=true -jar src/JSocketBench/build/libs/JSocketBench.jar"
LIBVMA_CMD="sudo LD_PRELOAD=${LIBVMA_PATH} ${JAVA_PATH} -Djava.net.preferIPv4Stack=true -jar src/JSocketBench/build/libs/JSocketBench.jar"
JSOR_CMD="IBM_JAVA_RDMA_SBUF_SIZE=1048576 IBM_JAVA_RDMA_RBUF_SIZE=1048576 ${J9_JAVA_PATH} -Dcom.ibm.net.rdma.conf=src/JSocketBench/jsor_${MODE}.conf -Djava.net.preferIPv4Stack=true -jar src/JSocketBench/build/libs/JSocketBench.jar"
JVERBS_CMD="${J9_JAVA_PATH} -Djava.net.preferIPv4Stack=true -jar src/JVerbsBench/build/libs/JVerbsBench.jar"

rm -rf "results"

run_perftest_series "ib_send_bw" "bidirectional" "msg"

#run_benchmark_series "CVerbsBench" "${CVERBS_CMD}" "unidirectional" "msg"
#run_benchmark_series "CVerbsBench" "${CVERBS_CMD}" "bidirectional" "msg"
#run_benchmark_series "CVerbsBench" "${CVERBS_CMD}" "unidirectional" "rdma"
#run_benchmark_series "CVerbsBench" "${CVERBS_CMD}" "bidirectional" "rdma"
#run_benchmark_series "JVerbsBench" "${JVERBS_CMD}" "unidirectional" "rdma"
#run_benchmark_series "JVerbsBench" "${JVERBS_CMD}" "bidirectional" "rdma"
#run_benchmark_series "JSOR" "${JSOR_CMD}" "unidirectional"
#run_benchmark_series "libvma" "${LIBVMA_CMD}" "unidirectional"
#run_benchmark_series "libvma" "${LIBVMA_CMD}" "bidirectional"
#run_benchmark_series "JSocketBench" "${JSOCKET_CMD}" "unidirectional"
#run_benchmark_series "JSocketBench" "${JSOCKET_CMD}" "bidirectional"

assemble_results