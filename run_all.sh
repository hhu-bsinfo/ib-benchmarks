#!/bin/bash

readonly GIT_VERSION="$(git describe --tags --abbrev=0 2>/dev/null)"
readonly GIT_BRANCH="$(git rev-parse --symbolic-full-name --abbrev-ref HEAD 2>/dev/null)"
readonly GIT_REV="$(git rev-parse --short HEAD 2>/dev/null)"
readonly DATE="$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null)"

RESULTS_OUTPATH="results"
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
            -o|--output)
            RESULTS_OUTPATH=$val
            ;;
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
            LOG_ERROR "Unknown option '%s'" "${arg}"
            print_usage
            exit 1
            ;;
        esac
        shift 2
    done

    if [ "${MODE}" != "server" ] && [ "${MODE}" != "client" ]; then
        LOG_ERROR_AND_EXIT "Invalid mode '%s'!" "${arg}"
    fi

    if [ "${MODE}" = "client" ] && [ "${REMOTE_ADDRESS}" = "" ]; then
        LOG_ERROR_AND_EXIT "Missing required parameter '--remote'!"
    fi

    if [ "${RS_MODE}" != "mad" ] && [ "${RS_MODE}" != "compat" ]; then
        LOG_ERROR_AND_EXIT "Invalid raw statistics mode '%s'!" "${RS_MODE}"
    fi
}

check_config()
{
    local java_version j9_java_valid j9_java_version libvma_soname libvma_version

    LOG_INFO "Checking configuration..."
    
    java_version=$("${JAVA_PATH}/bin/java" -version 2>&1 | sed -n ';s/.* version "\(.*\)\.\(.*\)\..*"/\1\2/p;')
    j9_java_valid=$("${J9_JAVA_PATH}/bin/java" -version 2>&1 | grep "IBM J9 VM");
    j9_java_version=$("${J9_JAVA_PATH}/bin/java" -version 2>&1 | sed -n ';s/.* version "\(.*\)\.\(.*\)\..*"/\1\2/p;')
    libvma_soname=$(readelf -d "${LIBVMA_PATH}" | grep SONAME | sed -e 's/.*\[//' -e 's/\]//')
    libvma_version=$(echo "${libvma_soname}" | sed -e 's/libvma.so.//')

    if [ -z "${java_version}" ]; then
        LOG_ERROR_AND_EXIT "'%s' does not seem to be a valid java executable!" "${JAVA_PATH}"
    fi

    if [ -z "${j9_java_version}" ]; then
        LOG_ERROR_AND_EXIT "'%s' does not seem to be a valid java executable!" "${J9_JAVA_PATH}"
    fi

    if [ -z "${j9_java_valid}" ]; then
        LOG_ERROR_AND_EXIT "'%s' does not seem to belong to a valid IBM J9 JVM!" "${J9_JAVA_PATH}"
    fi

    if [ "${java_version}" -lt 18 ]; then
        LOG_ERROR_AND_EXIT "'%s' implements a version of java older than 1.8 (determined version %u)!" "${JAVA_PATH}" "${java_version}"
    else
        LOG_INFO "Default JVM: '%s' - Determined version: %u --> [VALID]" "${JAVA_PATH}" "${java_version}"
    fi

    if [ "${j9_java_version}" -lt 18 ]; then
        LOG_ERROR_AND_EXIT "'%s' implements a version of java older than 1.8 (determined version %u)!" "${J9_JAVA_PATH}" "${j9_java_version}"
    else
        LOG_INFO "IBM J9 JVM: '%s' - Determined version: %u --> [VALID]" "${J9_JAVA_PATH}" "${j9_java_version}"
    fi

    if [[ ! "${libvma_soname}" =~ libvma.so ]]; then
        LOG_ERROR_AND_EXIT "'%s' is not a valid version of libvma!" "${LIBVMA_PATH}"
    fi

    LOG_INFO "libvma: '%s' - soname: '%s' - Determined version: %u --> [VALID]" "${LIBVMA_PATH}" "${libvma_soname}" "${libvma_version}"

    if [ "${libvma_version}" -lt 8 ]; then
        LOG_WARN "It seems like you are using an old version of libvma. Consider updating libvma for optimal performance and compatibility!"
    fi

    LOG_INFO "Configuration seems to be valid!"
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
    
    LOG_INFO "Running '%s ${params[*]}'..." "${cmd}"

    # Keep log output files of all benchmarks
    mkdir -p "${outpath}/logfiles"

    local logfile="${outpath}/logfiles/${name}_${benchmark}_${transport}_${size}_${MODE}.log"
    touch $logfile

    eval "${cmd} ${params[*]}" > $logfile 2>&1

    local output="$(cat $logfile)"

    if [[ $output = *"ERROR"* ]]; then
        printf "%s" "${output}"
        LOG_ERROR_AND_EXIT "Benchmark exited with an error!"
    else
        LOG_INFO "Benchmark exited successfully!\\n"
    fi

    # Consider latency for pingpong only
    if [ "${MODE}" = "server" ] && { [ "${benchmark}" = "pingpong" ] || [ "${benchmark}" = "latency" ]; } ; then
        mkdir -p "${outpath}/${benchmark}_lat_avg/"
        mkdir -p "${outpath}/${benchmark}_lat_min/"
        mkdir -p "${outpath}/${benchmark}_lat_max/"
        mkdir -p "${outpath}/${benchmark}_lat_95/"
        mkdir -p "${outpath}/${benchmark}_lat_99/"
        mkdir -p "${outpath}/${benchmark}_lat_999/"
        mkdir -p "${outpath}/${benchmark}_lat_9999/"
        mkdir -p "${outpath}/${benchmark}_tp_pkt_send/"

        mkdir -p "${outpath}/${benchmark}_overhead_send/"
        mkdir -p "${outpath}/${benchmark}_overhead_recv/"
        mkdir -p "${outpath}/${benchmark}_overhead_perc_send/"
        mkdir -p "${outpath}/${benchmark}_overhead_perc_recv/"
        mkdir -p "${outpath}/${benchmark}_tp_raw_send/"
        mkdir -p "${outpath}/${benchmark}_tp_raw_recv/"
        mkdir -p "${outpath}/${benchmark}_tp_raw_combined/"
        
        local avg_lat min_lat max_lat lat_95 lat_99 lat_999 lat_9999 pkts_tp;
        local send_overhead send_overhead_perc recv_overhead recv_overhead_perc;

        avg_lat=$(echo "${output}" | sed '2q;d')
        min_lat=$(echo "${output}" | sed '3q;d')
        max_lat=$(echo "${output}" | sed '4q;d')
        lat_95=$(echo "${output}" | sed '5q;d')
        lat_99=$(echo "${output}" | sed '6q;d')
        lat_999=$(echo "${output}" | sed '7q;d')
        lat_9999=$(echo "${output}" | sed '8q;d')
        pkts_tp=$(echo "${output}" | sed '9q;d')

        send_overhead=$(echo "${output}" | sed '14q;d')
        send_overhead_perc=$(echo "${output}" | sed '15q;d')
        recv_overhead=$(echo "${output}" | sed '16q;d')
        recv_overhead_perc=$(echo "${output}" | sed '17q;d')
        send_raw_tp=$(echo "${output}" | sed '18q;d')
        recv_raw_tp=$(echo "${output}" | sed '19q;d')
        combined_raw_tp=$(echo "${output}" | sed '20q;d')

        echo -e "${avg_lat}" >> "${outpath}/${benchmark}_lat_avg/${name}(${transport}).csv"
        echo -e "${min_lat}" >> "${outpath}/${benchmark}_lat_min/${name}(${transport}).csv"
        echo -e "${max_lat}" >> "${outpath}/${benchmark}_lat_max/${name}(${transport}).csv"
        echo -e "${lat_95}" >> "${outpath}/${benchmark}_lat_95/${name}(${transport}).csv"
        echo -e "${lat_99}" >> "${outpath}/${benchmark}_lat_99/${name}(${transport}).csv"
        echo -e "${lat_999}" >> "${outpath}/${benchmark}_lat_999/${name}(${transport}).csv"
        echo -e "${lat_9999}" >> "${outpath}/${benchmark}_lat_9999/${name}(${transport}).csv"
        echo -e "${pkts_tp}" >> "${outpath}/${benchmark}_tp_pkt_send/${name}(${transport}).csv"

        echo -e "${send_overhead}" >> "${outpath}/${benchmark}_overhead_send/${name}(${transport}).csv"
        echo -e "${recv_overhead}" >> "${outpath}/${benchmark}_overhead_recv/${name}(${transport}).csv"
        echo -e "${send_overhead_perc}" >> "${outpath}/${benchmark}_overhead_perc_send/${name}(${transport}).csv"
        echo -e "${recv_overhead_perc}" >> "${outpath}/${benchmark}_overhead_perc_recv/${name}(${transport}).csv"
        echo -e "${send_raw_tp}" >> "${outpath}/${benchmark}_tp_raw_send/${name}(${transport}).csv"
        echo -e "${recv_raw_tp}" >> "${outpath}/${benchmark}_tp_raw_recv/${name}(${transport}).csv"
        echo -e "${combined_raw_tp}" >> "${outpath}/${benchmark}_tp_raw_combined/${name}(${transport}).csv"
    # Throughput on all other benchmarks
    elif [ "${MODE}" = "server" ]; then
        mkdir -p "${outpath}/${benchmark}_tp_pkt_send/"
        mkdir -p "${outpath}/${benchmark}_tp_pkt_recv/"
        mkdir -p "${outpath}/${benchmark}_tp_pkt_combined/"
        mkdir -p "${outpath}/${benchmark}_tp_data_send/"
        mkdir -p "${outpath}/${benchmark}_tp_data_recv/"
        mkdir -p "${outpath}/${benchmark}_tp_data_combined/"

        mkdir -p "${outpath}/${benchmark}_overhead_send/"
        mkdir -p "${outpath}/${benchmark}_overhead_recv/"
        mkdir -p "${outpath}/${benchmark}_overhead_perc_send/"
        mkdir -p "${outpath}/${benchmark}_overhead_perc_recv/"
        mkdir -p "${outpath}/${benchmark}_tp_raw_send/"
        mkdir -p "${outpath}/${benchmark}_tp_raw_recv/"
        mkdir -p "${outpath}/${benchmark}_tp_raw_combined/"
        
        local send_pkts_tp recv_pkts_tp combined_pkts_tp send_tp recv_tp combined_tp send_lat;
        local send_overhead send_overhead_perc recv_overhead recv_overhead_perc;
        local send_raw_tp recv_raw_tp combined_raw_tp;

        send_pkts_tp=$(echo "${output}" | sed '3q;d')
        recv_pkts_tp=$(echo "${output}" | sed '4q;d')
        combined_pkts_tp=$(echo "${output}" | sed '5q;d')
        send_tp=$(echo "${output}" | sed '6q;d')
        recv_tp=$(echo "${output}" | sed '7q;d')
        combined_tp=$(echo "${output}" | sed '8q;d')

        send_overhead=$(echo "${output}" | sed '13q;d')
        send_overhead_perc=$(echo "${output}" | sed '14q;d')
        recv_overhead=$(echo "${output}" | sed '15q;d')
        recv_overhead_perc=$(echo "${output}" | sed '16q;d')
        send_raw_tp=$(echo "${output}" | sed '17q;d')
        recv_raw_tp=$(echo "${output}" | sed '18q;d')
        combined_raw_tp=$(echo "${output}" | sed '19q;d')

        echo -e "${send_pkts_tp}" >> "${outpath}/${benchmark}_tp_pkt_send/${name}(${transport}).csv"
        echo -e "${recv_pkts_tp}" >> "${outpath}/${benchmark}_tp_pkt_recv/${name}(${transport}).csv"
        echo -e "${combined_pkts_tp}" >> "${outpath}/${benchmark}_tp_pkt_combined/${name}(${transport}).csv"
        echo -e "${send_tp}" >> "${outpath}/${benchmark}_tp_data_send/${name}(${transport}).csv"
        echo -e "${recv_tp}" >> "${outpath}/${benchmark}_tp_data_recv/${name}(${transport}).csv"
        echo -e "${combined_tp}" >> "${outpath}/${benchmark}_tp_data_combined/${name}(${transport}).csv"

        echo -e "${send_overhead}" >> "${outpath}/${benchmark}_overhead_send/${name}(${transport}).csv"
        echo -e "${recv_overhead}" >> "${outpath}/${benchmark}_overhead_recv/${name}(${transport}).csv"
        echo -e "${send_overhead_perc}" >> "${outpath}/${benchmark}_overhead_perc_send/${name}(${transport}).csv"
        echo -e "${recv_overhead_perc}" >> "${outpath}/${benchmark}_overhead_perc_recv/${name}(${transport}).csv"
        echo -e "${send_raw_tp}" >> "${outpath}/${benchmark}_tp_raw_send/${name}(${transport}).csv"
        echo -e "${recv_raw_tp}" >> "${outpath}/${benchmark}_tp_raw_recv/${name}(${transport}).csv"
        echo -e "${combined_raw_tp}" >> "${outpath}/${benchmark}_tp_raw_combined/${name}(${transport}).csv"
    else
        LOG_INFO "Waiting for server to become ready..."
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

    # Keep log output files of all benchmarks
    mkdir -p "${outpath}/logfiles"

    local logfile="${outpath}/logfiles/${name}_${benchmark}_${transport}_${size}_${MODE}.log"

    LOG_INFO "Running 'sudo %s ${params[*]}'..." "${name}"
    eval "sudo ${name} ${params[*]}" > "$logfile" 2>&1

    if [ $? -eq 0 ]; then
        LOG_INFO "Benchmark exited successfully!\\n"
    else
        LOG_ERROR_AND_EXIT "Benchmark exited with an error! See %s_tmp.log for further details." "${MODE}"
    fi

    local results
    read -r -a results <<< $(cat "$logfile" | tail -n 2 | head -n 1)

    if [ "${MODE}" = "server" ]; then
        if [ "${benchmark}" = "latency" ]; then
            mkdir -p "${outpath}/${benchmark}_lat_min/"
            mkdir -p "${outpath}/${benchmark}_lat_max/"
            mkdir -p "${outpath}/${benchmark}_lat_avg/"

            echo -e "${results[2]}" >> "${outpath}/${benchmark}_lat_min/${name}(${transport}).csv"
            echo -e "${results[3]}" >> "${outpath}/${benchmark}_lat_max/${name}(${transport}).csv"
            echo -e "${results[4]}" >> "${outpath}/${benchmark}_lat_avg/${name}(${transport}).csv"
        else
            mkdir -p "${outpath}/${benchmark}_tp_pkt_send/"
            mkdir -p "${outpath}/${benchmark}_tp_data_send/"

            echo -e "${results[3]}" >> "${outpath}/${benchmark}_tp_data_send/${name}(${transport}).csv"
            echo -e "${results[4]}" >> "${outpath}/${benchmark}_tp_pkt_send/${name}(${transport}).csv"
        fi
    else
        LOG_INFO "Waiting for server to become ready..."
        printf "\\e[92m3...\\e[0m"
        sleep 1s
        printf "\\e[92m2...\\e[0m"
        sleep 1s
        printf "\\e[92m1...\\e[0m"
        sleep 1s
        printf "\\n"
    fi
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

        # For some currently unknown reason, jverbs msg uni and bidirectional is very slow. 
        # Reduce number of messages to avoid running for days.
        if [ "$name" = "JVerbsBench" ] && [ "$transport" = "msg" ]; then
            if [ "$benchmark" = "unidirectional" ] || [ "$benchmark" = "bidirectional" ]; then
                count=1000000
            fi
        fi 

        # Reduce message count to avoid unncessary long running benchmarks
        if [ "$benchmark" = "pingpong" ] || [ "$benchmark" = "latency" ]; then
            count=10000000
        fi
        
        if [ "${i}" -ge 13 ]; then
            count=$((count/$((2**$((i-12))))))
        fi
        
        benchmark "${name}" "$RESULTS_OUTPATH/1" "${cmd}" "${benchmark}" "${transport}" "${size}" "${count}" "$((8000+i))"
        benchmark "${name}" "$RESULTS_OUTPATH/2" "${cmd}" "${benchmark}" "${transport}" "${size}" "${count}" "$((8021+i))"
        benchmark "${name}" "$RESULTS_OUTPATH/3" "${cmd}" "${benchmark}" "${transport}" "${size}" "${count}" "$((8042+i))"
    done
}

run_perftest_series()
{
    local name="${1}"
    local benchmark="${2}"
    local transport="${3}"

    for i in $(seq 0 20); do
        local size=$((2**i))
        local count=100000000

        # Reduce message count to avoid unncessary long running benchmarks
        if [ "$benchmark" = "latency" ]; then
            count=10000000
        fi
        
        if [ "${i}" -ge 13 ]; then
            count=$((count/$((2**$((i-12))))))
        fi
        
        perftest_benchmark "${name}" "$RESULTS_OUTPATH/1" "${benchmark}" "${transport}" "${size}" "${count}" "$((8000+i))"
        perftest_benchmark "${name}" "$RESULTS_OUTPATH/2" "${benchmark}" "${transport}" "${size}" "${count}" "$((8021+i))"
        perftest_benchmark "${name}" "$RESULTS_OUTPATH/3" "${benchmark}" "${transport}" "${size}" "${count}" "$((8042+i))"
    done
}

gen_plot_file()
{
    local plot_name="${1}"
    local benchmark="${2}"
    local values_name_y1="${3}"
    local values_name_y2="${4}"
    local filter_files="${5}"
    local xlabel="${6}"
    local y1label="${7}"
    local y2label="${8}"
    local logscale="${9}"
    local colors="${*:10}"

    local plot="\
            FILES = system(\"ls -1 ../merged/${benchmark}_${values_name_y1}/*.csv | grep -E \\\"${filter_files}\\\"\")\\n\
            PACKET_FILES = system(\"ls -1 ../merged/${benchmark}_${values_name_y2}/*.csv | grep -E \\\"${filter_files}\\\"\")\\n\
            LABELS = system(\"ls -1 ../merged/${benchmark}_${values_name_y1}/*.csv | xargs -n 1 basename | cut -d'.' -f1 | grep -E \\\"${filter_files}\\\"\")\\n\
            COLORS = \"${colors}\"\
            \\n\
            set xlabel '${xlabel}'\\n\
            set grid\\n\
            set key above\\n\
            set xtics ('1' 0, '4' 2, '16' 4, '64' 6, '256' 8, '1K' 10, '4K' 12, '16K' 14, '64K' 16, '256K' 18, '1MB' 20)\\n\
            set xrange [0:20]\\n\
            set ytics nomirror\\n\
            set datafile separator ','\\n\
            set terminal pdf\\n\
            set output 'output/${plot_name}_${benchmark}.pdf'\\n"

    # Don't plot y2 on overhead plots
    if [ "${name}" == "overhead" ]; then
        plot+="set ylabel '${y1label}'\\n\
               plot for [i=1:words(FILES)] word(FILES,i) using 0:1:2:3 title word(LABELS,i) axes x1y1 with yerrorbars lt rgb word(COLORS,i) dt i pt i, \
                    for [i=1:words(FILES)] word(FILES,i) using 0:1 notitle axes x1y1 with lines lt rgb word(COLORS,i) dt i"
    else
        if [ "${name}" = "latency" ] || [ "${name}" = "pingpong" ]; then
            plot+="set logscale y\\n"
            plot+="set ylabel '${y1label}'\\n\
                   set y2label '${y2label}'\\n\
                   set y2tics\\n\
                   plot for [i=1:words(FILES)] word(FILES,i) using 0:1:2:3 title word(LABELS,i) axes x1y1 with yerrorbars lt rgb word(COLORS,i) dt 1 pt i, \
                        for [i=1:words(FILES)] word(FILES,i) using 0:1 notitle axes x1y1 with lines lt rgb word(COLORS,i) dt 1, \
                        for [i=1:words(PACKET_FILES)] word(PACKET_FILES,i) using 0:1:2:3 notitle axes x1y2 with yerrorbars lt rgb word(COLORS,i) dt 1 pt i, \
                        for [i=1:words(PACKET_FILES)] word(PACKET_FILES,i) using 0:1 notitle axes x1y2 with lines lt rgb word(COLORS,i) dt 2"
        else
            plot+="set ylabel '${y1label}'\\n\
                   set y2label '${y2label}'\\n\
                   set y2tics\\n\
                   plot for [i=1:words(FILES)] word(FILES,i) using 0:1:2:3 title word(LABELS,i) axes x1y2 with yerrorbars lt rgb word(COLORS,i) dt 1 pt i, \
                        for [i=1:words(FILES)] word(FILES,i) using 0:1 notitle axes x1y2 with lines lt rgb word(COLORS,i) dt 1, \
                        for [i=1:words(PACKET_FILES)] word(PACKET_FILES,i) using 0:1:2:3 notitle axes x1y1 with yerrorbars lt rgb word(COLORS,i) dt 1 pt i, \
                        for [i=1:words(PACKET_FILES)] word(PACKET_FILES,i) using 0:1 notitle axes x1y1 with lines lt rgb word(COLORS,i) dt 2"
        fi
    fi
    
    if [ ! -d "$RESULTS_OUTPATH/plot/scripts" ]; then
        mkdir -p "$RESULTS_OUTPATH/plot/scripts"
    fi

    echo -e "${plot}" > "$RESULTS_OUTPATH/plot/scripts/${plot_name}.plot"
}

values_min()
{
    printf "%s\n" "${@:1}" | sort -g | head -n1
}

values_max()
{
    printf "%s\n" "${@:1}" | sort -gr | head -n1
}

values_avg()
{
    echo "${@:1}" | tr " " '\n' | awk '{sum+=$1};END{printf "%f", sum/NR}'
}

generate_merged_values_benchmark_runs()
{
    mkdir -p "$RESULTS_OUTPATH/merged/"

    for folder in $RESULTS_OUTPATH/1/*; do
        # Skip logfile folder
        if [ "$(basename $folder)" = "logfiles" ]; then
            continue
        fi

        for file in "${folder}"/*; do
            for i in $(seq 0 20); do
                local subpath first second third sorted

                subpath=$(basename "${folder}")/$(basename "${file}")

                first=$(sed "$((i+1))q;d" < "$RESULTS_OUTPATH/1/${subpath}")
                second=$(sed "$((i+1))q;d" < "$RESULTS_OUTPATH/2/${subpath}")
                third=$(sed "$((i+1))q;d" < "$RESULTS_OUTPATH/3/${subpath}")

                # In order to display error bars in gnuplot correctly, we have
                # to provide the minimum, maximum and average values
                min=$(values_min $first $second $third)
                max=$(values_max $first $second $third)
                avg=$(values_avg $first $second $third)

                if [ ! -d "$RESULTS_OUTPATH/merged/$(basename "${folder}")" ]; then
                    mkdir -p "$RESULTS_OUTPATH/merged/$(basename "${folder}")"
                fi

                if [ ! -f "$RESULTS_OUTPATH/merged/${subpath}" ]; then
                    touch "$RESULTS_OUTPATH/merged/${subpath}"
                fi

                echo "${avg},${min},${max}" >> "$RESULTS_OUTPATH/merged/${subpath}"
            done
        done
    done
}

assemble_results()
{
    LOG_INFO "Assembling results..."

    generate_merged_values_benchmark_runs

    # Notes on determining the (worst case) raw overhead:
    # Some libraries (e.g. libvma, IPoIB) use very aggressive aggregation (up to ~1000 messages)
    # on one way non blocking data transfers (e.g. uni/bi-directional throughput or uni-directional
    # latency). Fundamentally, this is good as it reduces the overhead for such communication patterns
    # significantly. However, to determine the (worst case) per paket overhead, we have to do this
    # on a pingpong type benchmark which eliminates any kind of implicit aggregation.

    gen_plot_file "verbs_tp_uni" "unidirectional" "tp_data_send" "tp_pkt_send" "ib_send_bw|ib_write_bw|CVerbsBench|JVerbsBench" "Message size [Bytes]" "Messages [mmps]" "Throughput [MB/s]" "#001b7837" "#007fbf7b" "#00762a83" "#00af8dc3" "#00e7d4e8" "red" "green" "blue"
    gen_plot_file "verbs_tp_bi" "bidirectional" "tp_data_combined" "tp_pkt_combined" "ib_send_bw|ib_write_bw|CVerbsBench|JVerbsBench" "Message size [Bytes]" "Messages [mmps]" "Throughput [MB/s]" "#001b7837" "#007fbf7b" "#00762a83" "#00af8dc3" "#00e7d4e8" "red" "green" "blue"
    gen_plot_file "verbs_pp_avg" "pingpong" "lat_avg" "tp_pkt_send" "CVerbsBench|JVerbsBench" "Message size [Bytes]" "Latency [us]" "Messages [mmps]" "#001b7837" "#007fbf7b" "#00762a83" "#00af8dc3" "#00e7d4e8" "red" "green" "blue"
    gen_plot_file "verbs_pp_999" "pingpong" "lat_999" "tp_pkt_send" "CVerbsBench|JVerbsBench" "Message size [Bytes]" "Latency [us]" "Messages [mmps]" "#001b7837" "#007fbf7b" "#00762a83" "#00af8dc3" "#00e7d4e8" "red" "green" "blue"
    gen_plot_file "verbs_lat_avg" "latency" "lat_avg" "tp_pkt_send" "ib_send_lat|ib_write_lat|CVerbsBench|JVerbsBench" "Message size [Bytes]" "Latency [us]" "Messages [mmps]" "#001b7837" "#007fbf7b" "#00762a83" "#00af8dc3" "#00e7d4e8" "red" "green" "blue"
    gen_plot_file "verbs_lat_999" "latency" "lat_999" "tp_pkt_send" "ib_send_lat|ib_write_lat|CVerbsBench|JVerbsBench" "Message size [Bytes]" "Latency [us]" "Messages [mmps]" "#001b7837" "#007fbf7b" "#00762a83" "#00af8dc3" "#00e7d4e8" "red" "green" "blue"

    gen_plot_file "sockets_tp_uni" "unidirectional" "tp_data_send" "tp_pkt_send" "JSOR|libvma|JSocketBench" "Message size [Bytes]" "Messages [mmps]" "Throughput [MB/s]" "#001b7837" "#007fbf7b" "#00762a83" "#00af8dc3" "#00e7d4e8" "red" "green" "blue"
    gen_plot_file "sockets_tp_bi" "bidirectional" "tp_data_combined" "tp_pkt_combined" "JSOR|libvma|JSocketBench" "Message size [Bytes]" "Messages [mmps]" "Throughput [MB/s]" "#001b7837" "#007fbf7b" "#00762a83" "#00af8dc3" "#00e7d4e8" "red" "green" "blue"

    gen_plot_file "sockets_pp_avg" "pingpong" "lat_avg" "tp_pkt_send" "JSOR|libvma|JSocketBench" "Message size [Bytes]" "Latency [us]" "Messages [mmps]" "#001b7837" "#007fbf7b" "#00762a83" "#00af8dc3" "#00e7d4e8" "red" "green" "blue"
    gen_plot_file "sockets_pp_999" "pingpong" "lat_999" "tp_pkt_send" "JSOR|libvma|JSocketBench" "Message size [Bytes]" "Latency [us]" "Messages [mmps]" "#001b7837" "#007fbf7b" "#00762a83" "#00af8dc3" "#00e7d4e8" "red" "green" "blue"
    gen_plot_file "sockets_lat_avg" "latency" "lat_avg" "tp_pkt_send" "JSOR|libvma|JSocketBench" "Message size [Bytes]" "Latency [us]" "Messages [mmps]" "#001b7837" "#007fbf7b" "#00762a83" "#00af8dc3" "#00e7d4e8" "red" "green" "blue"
    gen_plot_file "sockets_lat_999" "latency" "lat_999" "tp_pkt_send" "JSOR|libvma|JSocketBench" "Message size [Bytes]" "Latency [us]" "Messages [mmps]" "#001b7837" "#007fbf7b" "#00762a83" "#00af8dc3" "#00e7d4e8" "red" "green" "blue"

    gen_plot_file "sockets_lat_999" "latency" "lat_999" "tp_pkt_send" "JSOR|libvma|JSocketBench" "Message size [Bytes]" "Latency [us]" "Messages [mmps]" "#001b7837" "#007fbf7b" "#00762a83" "#00af8dc3" "#00e7d4e8" "red" "green" "blue"

    gen_plot_file "all_tp_uni" "unidirectional" "tp_data_send" "tp_pkt_send" "ib_send_bw|ib_write_bw|CVerbsBench|JVerbsBench|JSOR|libvma|JSocketBench" "Message size [Bytes]" "Messages [mmps]" "Throughput [MB/s]" "#001b7837" "#007fbf7b" "#00762a83" "#00af8dc3" "#00e7d4e8"
    gen_plot_file "all_tp_uni" "bidirectional" "tp_data_combined" "tp_pkt_combined" "ib_send_bw|ib_write_bw|CVerbsBench|JVerbsBench|JSOR|libvma|JSocketBench" "Message size [Bytes]" "Messages [mmps]" "Throughput [MB/s]" "#001b7837" "#007fbf7b" "#00762a83" "#00af8dc3" "#00e7d4e8"

    gen_plot_file "all_pp_avg" "pingpong" "lat_avg" "tp_pkt_send" "CVerbsBench|JVerbsBench|JSOR|libvma|JSocketBench" "Message size [Bytes]" "Latency [us]" "Messages [mmps]" "#001b7837" "#007fbf7b" "#00762a83" "#00af8dc3" "#00e7d4e8"
    gen_plot_file "all_pp_999" "pingpong" "lat_999" "tp_pkt_send" "CVerbsBench|JVerbsBench|JSOR|libvma|JSocketBench" "Message size [Bytes]" "Latency [us]" "Messages [mmps]" "#001b7837" "#007fbf7b" "#00762a83" "#00af8dc3" "#00e7d4e8"
    gen_plot_file "all_lat_avg" "latency" "lat_avg" "tp_pkt_send" "ib_send_lat|ib_write_lat|CVerbsBench|JVerbsBench|JSOR|libvma|JSocketBench" "Message size [Bytes]" "Latency [us]" "Messages [mmps]" "#001b7837" "#007fbf7b" "#00762a83" "#00af8dc3" "#00e7d4e8"
    gen_plot_file "all_lat_999" "latency" "lat_999" "tp_pkt_send" "ib_send_lat|ib_write_lat|CVerbsBench|JVerbsBench|JSOR|libvma|JSocketBench" "Message size [Bytes]" "Latency [us]" "Messages [mmps]" "#001b7837" "#007fbf7b" "#00762a83" "#00af8dc3" "#00e7d4e8"
}

plot_all()
{
    LOG_INFO "Generating plots..."

    if [ ! -d "$RESULTS_OUTPATH/plot/output" ]; then
        mkdir -p "$RESULTS_OUTPATH/plot/output"
    fi

    cd $RESULTS_OUTPATH/plot

    for file in scripts/*; do
        gnuplot "$file" 
    done

    cd ../..
}

##################################################################
# Main entry point
##################################################################

# Use this switch to execute the post processing of the results (e.g. from a cluster) only
#PROCESS_RESULTS_ONLY="1"

source log.sh

LOG_INFO "Running automatic benchmark script!"
LOG_INFO "version: %s(%s) - git %s, date: %s!" "${GIT_VERSION}" "${GIT_BRANCH}" "${GIT_REV}" "${DATE}"

printf "\\n"

if [ "$PROCESS_RESULTS_ONLY" != "1" ]; then
    parse_args "$@"
    check_config
fi

printf "\\n"

LOG_INFO "Using '%s' for IPoIB and libvma!" "${JAVA_PATH}"
LOG_INFO "Using '%s' for JSOR and jVerbs!" "${J9_JAVA_PATH}"
LOG_INFO "Using '%s' for libvma!" "${LIBVMA_PATH}"

printf "\\n"

JSOCKET_CMD="${JAVA_PATH}/bin/java -Djava.net.preferIPv4Stack=true -jar src/JSocketBench/build/libs/JSocketBench.jar"
# VMA_TRACELEVEL: 0-6 debug output level (set to 0 to have results only printed)
LIBVMA_CMD="sudo VMA_TRACELEVEL=0 LD_PRELOAD=${LIBVMA_PATH} ${JAVA_PATH}/bin/java -Djava.net.preferIPv4Stack=true -jar src/JSocketBench/build/libs/JSocketBench.jar"
JSOR_CMD="IBM_JAVA_RDMA_SBUF_SIZE=1048576 IBM_JAVA_RDMA_RBUF_SIZE=1048576 ${J9_JAVA_PATH}/bin/java -Dcom.ibm.net.rdma.conf=src/JSocketBench/jsor_${MODE}.conf -Djava.net.preferIPv4Stack=true -jar src/JSocketBench/build/libs/JSocketBench.jar"
JVERBS_CMD="${J9_JAVA_PATH}/bin/java -Djava.net.preferIPv4Stack=true -jar src/JVerbsBench/build/libs/JVerbsBench.jar"

##################################################################
# Benchmarks
##################################################################

if [ "$PROCESS_RESULTS_ONLY" != "1" ]; then
    # ib perf tools included in OFED package
    run_perftest_series "ib_send_bw" "unidirectional" "msg"
    run_perftest_series "ib_send_bw" "bidirectional" "msg"
    run_perftest_series "ib_write_bw" "unidirectional" "rdma"
    run_perftest_series "ib_write_bw" "bidirectional" "rdma"
    run_perftest_series "ib_send_lat" "latency" "msg"
    run_perftest_series "ib_write_lat" "latency" "rdma"

    # libverbs (native C)
    run_benchmark_series "CVerbsBench" "${CVERBS_CMD}" "unidirectional" "msg"
    run_benchmark_series "CVerbsBench" "${CVERBS_CMD}" "bidirectional" "msg"
    run_benchmark_series "CVerbsBench" "${CVERBS_CMD}" "unidirectional" "rdma"
    run_benchmark_series "CVerbsBench" "${CVERBS_CMD}" "bidirectional" "rdma"
    run_benchmark_series "CVerbsBench" "${CVERBS_CMD}" "unidirectional" "rdmar"
    run_benchmark_series "CVerbsBench" "${CVERBS_CMD}" "bidirectional" "rdmar"
    run_benchmark_series "CVerbsBench" "${CVERBS_CMD}" "pingpong" "msg"
    run_benchmark_series "CVerbsBench" "${CVERBS_CMD}" "latency" "msg"
    run_benchmark_series "CVerbsBench" "${CVERBS_CMD}" "latency" "rdma"
    run_benchmark_series "CVerbsBench" "${CVERBS_CMD}" "latency" "rdmar"

    # jVerbs (IBM JVM)
    run_benchmark_series "JVerbsBench" "${JVERBS_CMD}" "unidirectional" "msg"
    run_benchmark_series "JVerbsBench" "${JVERBS_CMD}" "bidirectional" "msg"
    run_benchmark_series "JVerbsBench" "${JVERBS_CMD}" "unidirectional" "rdma"
    run_benchmark_series "JVerbsBench" "${JVERBS_CMD}" "bidirectional" "rdma"
    run_benchmark_series "JVerbsBench" "${JVERBS_CMD}" "unidirectional" "rdmar"
    run_benchmark_series "JVerbsBench" "${JVERBS_CMD}" "bidirectional" "rdmar"
    run_benchmark_series "JVerbsBench" "${JVERBS_CMD}" "pingpong" "msg"
    run_benchmark_series "JVerbsBench" "${JVERBS_CMD}" "latency" "msg"
    run_benchmark_series "JVerbsBench" "${JVERBS_CMD}" "latency" "rdma"
    run_benchmark_series "JVerbsBench" "${JVERBS_CMD}" "latency" "rdmar"

    # JSOR (IBM JVM)
    run_benchmark_series "JSOR" "${JSOR_CMD}" "unidirectional"
    # bidirectional missing: errors on small packages, does not terminate with large packages
    run_benchmark_series "JSOR" "${JSOR_CMD}" "pingpong"
    run_benchmark_series "JSOR" "${JSOR_CMD}" "latency"

    # libvma library
    run_benchmark_series "libvma" "${LIBVMA_CMD}" "unidirectional"
    run_benchmark_series "libvma" "${LIBVMA_CMD}" "bidirectional"
    run_benchmark_series "libvma" "${LIBVMA_CMD}" "pingpong"
    run_benchmark_series "libvma" "${LIBVMA_CMD}" "latency"

    # IPoIB using normal Java sockets
    run_benchmark_series "JSocketBench" "${JSOCKET_CMD}" "unidirectional"
    run_benchmark_series "JSocketBench" "${JSOCKET_CMD}" "bidirectional"
    run_benchmark_series "JSocketBench" "${JSOCKET_CMD}" "pingpong"
    run_benchmark_series "JSocketBench" "${JSOCKET_CMD}" "latency"
else
    LOG_INFO "Skipping benchmarks, processing results only"
fi

##################################################################
# Post processing results
##################################################################

assemble_results
plot_all
