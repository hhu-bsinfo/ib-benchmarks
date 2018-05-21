/**
 * @file main.c
 * @author Fabian Ruhland, HHU
 * @date May 2018
 *
 * @brief Contains the benchmark's main-function.
 */

#include <stdio.h>
#include <string.h>
#include <stdbool.h>
#include <zconf.h>
#include "IbLib/log.h"
#include "IbLib/ib_perf_counter.h"
#include "IbLib/ib_perf_counter_compat.h"
#include "IbLib/ib_device.h"
#include "IbLib/ib_prot_dom.h"
#include "IbLib/ib_mem_reg.h"
#include "IbLib/ib_comp_queue.h"
#include "IbLib/ib_shared_recv_queue.h"
#include "IbLib/ib_queue_pair.h"
#include "IbLib/connection.h"
#include "threads.h"

void parse_args(int argc, char **argv);
void print_usage();
void print_results();

char *mode = NULL;
char *remote_hostname = NULL;
char *bind_address = NULL;
char *benchmark = "unidirectional";
char *transport = "msg";
char *perf_counter_mode = "off";
uint64_t buf_size = 1024;
uint64_t count = 1000000;
uint32_t queue_size = 100;
uint16_t port = 8888;

uint8_t verbosity = 4;

uint64_t *send_time_in_nanos = NULL;
uint64_t *recv_time_in_nanos = NULL;

ib_perf_counter perf_counter;
ib_perf_counter_compat perf_counter_compat;

/**
 * The main-function.
 */
int main(int argc, char **argv) {
    pthread_t send_thread = 0;
    pthread_t recv_thread = 0;

    ib_device device;
    ib_prot_dom prot_dom;
    ib_comp_queue send_cq;
    ib_comp_queue recv_cq;
    connection conn;

    parse_args(argc - 1, &argv[1]);

    // Check for root-priviliges.
    // Non-root users can only pin a small amount of memory.
    // This may not be enough, as infiniband resources need to be pinned.
    if(getuid() != 0) {
        LOG_WARN("MAIN", "Not running with root privileges. If any errors occur, try restarting as root!");
    }

    if(mode == NULL || (!strcmp(mode, "client") && remote_hostname == NULL)) {
        print_usage();
        LOG_ERROR_AND_EXIT("MAIN", "Missing required parameters!")
    }

    // Initialize infiniband resources
    init_device(&device);
    init_prot_dom(&prot_dom, &device, "BenchProtDom");
    init_comp_queue(&send_cq, &device, queue_size);
    init_comp_queue(&recv_cq, &device, queue_size);
    init_connection(&conn, &device, &prot_dom, &send_cq, &recv_cq, NULL, buf_size, queue_size);

    thread_params params = { &conn, count };

    // Connect to remote host
    if(!strcmp(mode, "server")) {
        connect_to_client(&conn, bind_address, port);
    } else if(!strcmp(mode, "client")) {
        connect_to_server(&conn, bind_address, remote_hostname, port);
    } else {
        LOG_ERROR_AND_EXIT("MAIN", "Invalid mode '%s'!", mode);
    }

    if(!strcmp(perf_counter_mode, "mad")) {
        init_perf_counter(&perf_counter, &device);
        reset_counters(&perf_counter);
    } else if(!strcmp(perf_counter_mode, "compat")) {
        init_perf_counter_compat(&perf_counter_compat, &device);
        reset_counters_compat(&perf_counter_compat);
    }

    // Start the benchmark
    if(!strcmp(benchmark, "unidirectional") && !strcmp(mode, "server")) {
        if(!strcmp(transport, "msg")) {
            pthread_create(&send_thread, NULL, (void *(*)(void *)) &msg_send_thread, &params);
        } else if(!strcmp(transport, "rdma")) {
            pthread_create(&send_thread, NULL, (void *(*)(void *)) &rdma_write_send_thread, &params);
        } else {
            LOG_ERROR_AND_EXIT("MAIN", "Invalid transport '%s'!", transport);
        }

        pthread_join(send_thread, (void **) &send_time_in_nanos);
    } else if(!strcmp(benchmark, "unidirectional") && !strcmp(mode, "client")) {
        if(!strcmp(transport, "msg")) {
            pthread_create(&recv_thread, NULL, (void *(*)(void *)) &msg_recv_thread, &params);
        } else if(!strcmp(transport, "rdma")) {
            pthread_create(&recv_thread, NULL, (void *(*)(void *)) &rdma_write_recv_thread, &params);
        } else {
            LOG_ERROR_AND_EXIT("MAIN", "Invalid transport '%s'!", transport);
        }

        pthread_join(recv_thread, (void **) &recv_time_in_nanos);
    } else if(!strcmp(benchmark, "bidirectional")) {
        if(!strcmp(transport, "msg")) {
            pthread_create(&send_thread, NULL, (void *(*)(void *)) &msg_send_thread, &params);
            pthread_create(&recv_thread, NULL, (void *(*)(void *)) &msg_recv_thread, &params);
        } else if(!strcmp(transport, "rdma")) {
            pthread_create(&send_thread, NULL, (void *(*)(void *)) &rdma_write_send_thread, &params);
            pthread_create(&recv_thread, NULL, (void *(*)(void *)) &rdma_write_recv_thread, &params);
        } else {
            LOG_ERROR_AND_EXIT("MAIN", "Invalid transport '%s'!", transport);
        }

        pthread_join(send_thread, (void **) &send_time_in_nanos);
        pthread_join(recv_thread, (void **) &recv_time_in_nanos);
    } else if(!strcmp(benchmark, "pingpong")) {
        if(!strcmp(mode, "server")) {
            pthread_create(&send_thread, NULL, (void *(*)(void *)) &pingpong_server_thread, &params);
        } else if(!strcmp(mode, "client")) {
            pthread_create(&send_thread, NULL, (void *(*)(void *)) &pingpong_client_thread, &params);
        }

        pthread_join(send_thread, (void **) &send_time_in_nanos);
    } else {
        LOG_ERROR_AND_EXIT("MAIN", "Invalid benchmark '%s'!", benchmark);
    }

    if(!strcmp(perf_counter_mode, "mad")) {
        refresh_counters(&perf_counter);
    } else if(!strcmp(perf_counter_mode, "compat")) {
        refresh_counters_compat(&perf_counter_compat);
    }

    // Destroy infiniband-resources
    close_connection(&conn);
    close_comp_queue(&send_cq);
    close_comp_queue(&recv_cq);
    close_prot_dom(&prot_dom);
    close_device(&device);

    // Print results
    if(!strcmp(mode, "server")) {
        print_results();
    } else if(!strcmp(mode, "client")) {
        printf("See results on server!\n");
    }

    if(!strcmp(perf_counter_mode, "mad")) {
        close_perf_counter(&perf_counter);
    } else if(!strcmp(perf_counter_mode, "compat")) {
        close_perf_counter_compat(&perf_counter_compat);
    }

    return 0;
}

/**
 * Parse the parameters, that are given by the user.
 */
void parse_args(int argc, char **argv) {
    for(uint32_t i = 0; i < argc; i++) {
        if(i == argc - 1) {
            print_usage();
            LOG_ERROR_AND_EXIT("MAIN", "Unable to parse options!");
        }

        if(!strcmp(argv[i], "-m") || !strcmp(argv[i], "--mode")) {
            mode = argv[++i];
        } else if(!strcmp(argv[i], "-r") || !strcmp(argv[i], "--remote")) {
            remote_hostname = argv[++i];
        } else if(!strcmp(argv[i], "-a") || !strcmp(argv[i], "--address")) {
            bind_address = argv[++i];
        } else if(!strcmp(argv[i], "-b") || !strcmp(argv[i], "--benchmark")) {
            benchmark = argv[++i];
        } else if(!strcmp(argv[i], "-t") || !strcmp(argv[i], "--transport")) {
            transport = argv[++i];
        } else if(!strcmp(argv[i], "-s") || !strcmp(argv[i], "--size")) {
            buf_size = strtoull(argv[++i], NULL, 10);
        } else if(!strcmp(argv[i], "-c") || !strcmp(argv[i], "--count")) {
            count = strtoull(argv[++i], NULL, 10);
        } else if(!strcmp(argv[i], "-q") || !strcmp(argv[i], "--qsize")) {
            queue_size = (uint32_t) strtol(argv[++i], NULL, 10);
        } else if(!strcmp(argv[i], "-p") || !strcmp(argv[i], "--port")) {
            port = (uint16_t) strtol(argv[++i], NULL, 10);
        } else if(!strcmp(argv[i], "-rs") || !strcmp(argv[i], "--raw-statistics")) {
            perf_counter_mode = argv[++i];
        } else if(!strcmp(argv[i], "-v") || !strcmp(argv[i], "--verbosity")) {
            verbosity = (uint8_t) strtol(argv[++i], NULL, 10);
        } else {
            print_usage();
            LOG_ERROR_AND_EXIT("MAIN", "Invalid option '%s'!", argv[i]);
        }
    }

    if(!strcmp(mode, "client")) {
        perf_counter_mode = "off";
    }
}

/**
 * Print the help message.
 */
void print_usage() {
    printf("Usage: ./CVerbsBench [OPTION...]\n"
           "Available options:\n"
           "-m, --mode\n"
           "    Set the operating mode (server/client). This is a required option!\n"
           "-r, --remote\n"
           "    Set the remote hostname. This is a required option when the program is running as a client!\n"
           "-a, --address\n"
           "    Set the address to bind the local socket to.\n"
           "-b, --benchmark\n"
           "    Set the benchmark to be executed. Available benchmarks are: "
           "'unidirectional', 'bidirectional' and 'pingpong' (Default: 'unidirectional').\n"
           "-t, --transport\n"
           "    Set the transport type. Available types are 'msg' and 'rdma' (Default: 'msg').\n"
           "-s, --size\n"
           "    Set the message size in bytes (Default: 1024).\n"
           "-c, --count\n"
           "    Set the amount of messages to be sent (Default: 1000000).\n"
           "-q, --qsize\n"
           "    Set the queue pair size (Default: 100).\n"
           "-p, --port\n"
           "    Set the TCP-port to be used for exchanging the infiniband connection information (Default: 8888).\n"
           "-rs, --raw-statistics\n"
           "    Show infiniband perfomance counters\n"
           "        'mad'    = Use libibmad to get performance counters (requires root-privileges!)\n"
           "        'compat' = Use filesystem to get performance counters\n"
           "        'off'    = Don't show performance counters (Default).\n"
           "-v, --verbosity\n"
           "    Set the verbosity level: 0 = Fatal errors and raw results,\n"
           "                             1 = Fatal errors formatted results,\n"
           "                             2 = All errors and formatted results,\n"
           "                             3 = All errors/warnings and formatted results,\n"
           "                             4 = All log messages and formatted results (Default).\n");
}

/**
 * Print the benchmark results.
 */
void print_results() {
    if(!strcmp(benchmark, "pingpong")) {
        uint64_t total_time = *send_time_in_nanos;
        uint64_t avg_latency = total_time / count;

        if(verbosity > 0) {
            printf("Results:\n");
            printf("  Total time: %.2Lf s\n", total_time / ((long double) 1000000000));
            printf("  Average request response latency: %.2Lf us\n", avg_latency / (long double) 1000);
        } else {
            printf("%Lf\n", total_time / ((long double) 1000000000));
            printf("%Lf\n", avg_latency / (long double) 1000);
        }
    } else {
        bool show_perf_counters = !strcmp(perf_counter_mode, "mad") || !strcmp(perf_counter_mode, "compat");

        uint64_t total_data = count * buf_size;
        uint64_t send_total_time = *send_time_in_nanos;
        uint64_t recv_total_time = !strcmp(benchmark, "unidirectional") ? 0 : *recv_time_in_nanos;

        uint64_t xmit_pkts = 0;
        uint64_t xmit_data_bytes = 0;
        uint64_t rcv_pkts = 0;
        uint64_t rcv_data_bytes = 0;

        if(!strcmp(perf_counter_mode, "mad")) {
            xmit_pkts = perf_counter.xmit_pkts;
            xmit_data_bytes = perf_counter.xmit_data_bytes;
            rcv_pkts = perf_counter.rcv_pkts;
            rcv_data_bytes = perf_counter.rcv_data_bytes;
        } else if(!strcmp(perf_counter_mode, "compat")) {
            xmit_pkts = perf_counter_compat.xmit_pkts;
            xmit_data_bytes = perf_counter_compat.xmit_data_bytes;
            rcv_pkts = perf_counter_compat.rcv_pkts;
            rcv_data_bytes = perf_counter_compat.rcv_data_bytes;
        }

        long double send_pkts_rate = (count / (send_total_time / ((long double) 1000000000)) / ((long double) 1000));

        long double recv_pkts_rate = recv_total_time == 0 ? 0 : (count / (recv_total_time / ((long double) 1000000000))
                / ((long double) 1000));

        long double send_avg_throughput_mib = total_data /
                (send_total_time / ((long double) 1000000000)) / ((long double) 1024) / ((long double) 1024);

        long double send_avg_throughput_mb = total_data /
                (send_total_time / ((long double) 1000000000)) / ((long double) 1000) / ((long double) 1000);

        long double recv_avg_throughput_mib = recv_total_time == 0 ? 0 : total_data /
                (recv_total_time / ((long double) 1000000000)) / ((long double) 1024) / ((long double) 1024);

        long double recv_avg_throughput_mb = recv_total_time == 0 ? 0 :total_data /
                (recv_total_time / ((long double) 1000000000)) / ((long double) 1000) / ((long double) 1000);

        long double send_avg_latency = send_total_time / (long double) count / (long double) 1000;

        // Even if we only send data, a few bytes will also be received, because of the RC-protocol,
        // so if recv_total_time is 0, we just set it to send_total_time,
        // so that the raw receive throughput can be calculated correctly.
        if (recv_total_time == 0) {
            recv_total_time = send_total_time;
        } else if (send_total_time == 0) {
            recv_total_time = 0;
        }

        long double send_avg_raw_throughput_mib = xmit_data_bytes / (send_total_time / ((long double) 1000000000)) /
                                                  ((long double) 1024) / ((long double) 1024);

        long double send_avg_raw_throughput_mb = xmit_data_bytes / (send_total_time / ((long double) 1000000000)) /
                                                 ((long double) 1000) / ((long double) 1000);

        long double recv_avg_raw_throughput_mib = rcv_data_bytes / (recv_total_time / ((long double) 1000000000)) /
                                                  ((long double) 1024) / ((long double) 1024);

        long double recv_avg_raw_throughput_mb = rcv_data_bytes / (recv_total_time / ((long double) 1000000000)) /
                                                 ((long double) 1000) / ((long double) 1000);

        long double send_overhead = 0;
        long double recv_overhead = 0;

        if(total_data < rcv_data_bytes) {
            recv_overhead = rcv_data_bytes - total_data;
        }

        if(total_data < xmit_data_bytes) {
            send_overhead = xmit_data_bytes - total_data;
        }

        long double send_overhead_percentage = send_overhead / (long double) total_data;
        long double recv_overhead_percentage = recv_overhead / (long double) total_data;

        if(verbosity > 0) {
            printf("Results:\n");
            printf("  Total time: %.2Lf s\n", send_total_time / ((long double) 1000000000));
            printf("  Total data: %.2Lf MiB (%.2Lf MB)\n", total_data / ((long double) 1024) / ((long double) 1024),
                   total_data / ((long double) 1000) / ((long double) 1000));
            printf("  Average sent packets per second:     %.2Lf kPkts/s\n", send_pkts_rate);
            printf("  Average recv packets per second:     %.2Lf kPkts/s\n", recv_pkts_rate);
            printf("  Average combined packets per second: %.2Lf kPkts/s\n", send_pkts_rate + recv_pkts_rate);
            printf("  Average send throughput:     %.2Lf MiB/s (%.2Lf MB/s)\n",
                   send_avg_throughput_mib, send_avg_throughput_mb);
            printf("  Average recv throughput:     %.2Lf MiB/s (%.2Lf MB/s)\n",
                   recv_avg_throughput_mib, recv_avg_throughput_mb);
            printf("  Average combined throughput: %.2Lf MiB/s (%.2Lf MB/s)\n",
                   send_avg_throughput_mib + recv_avg_throughput_mib, send_avg_throughput_mb + recv_avg_throughput_mb);
            printf("  Average send latency: %.2Lf us\n", send_avg_latency);

            if(show_perf_counters) {
                printf("\nRaw statistics:\n");
                printf("  Total packets sent: %ld\n", xmit_pkts);
                printf("  Total packets received %ld\n", rcv_pkts);
                printf("  Total data sent: %.2Lf MiB (%.2Lf MB)\n", xmit_data_bytes /
                                                                    ((long double) 1024) / ((long double) 1024),
                       xmit_data_bytes / ((long double) 1000) / ((long double) 1000));
                printf("  Total data received: %.2Lf MiB (%.2Lf MB)\n", rcv_data_bytes /
                                                                        ((long double) 1024) / ((long double) 1024),
                       rcv_data_bytes / ((long double) 1000) / ((long double) 1000));
                printf("  Send overhead: %.2Lf MiB (%.2Lf MB), %.2Lf%%\n", send_overhead /
                                                                ((long double) 1024) / ((long double) 1024),
                        send_overhead / ((long double) 1000) / ((long double) 1000), send_overhead_percentage * 100);
                printf("  Receive overhead: %.2Lf MiB (%.2Lf MB), %.2Lf%%\n", recv_overhead /
                                                                ((long double) 1024) / ((long double) 1024),
                       recv_overhead / ((long double) 1000) / ((long double) 1000), recv_overhead_percentage * 100);
                printf("  Average send throughput:     %.2Lf MiB/s (%.2Lf MB/s)\n",
                       send_avg_raw_throughput_mib, send_avg_raw_throughput_mb);
                printf("  Average recv throughput:     %.2Lf MiB/s (%.2Lf MB/s)\n",
                       recv_avg_raw_throughput_mib, recv_avg_raw_throughput_mb);
                printf("  Average combined throughput: %.2Lf MiB/s (%.2Lf MB/s)\n",
                       send_avg_raw_throughput_mib + recv_avg_raw_throughput_mib,
                       send_avg_raw_throughput_mb + recv_avg_raw_throughput_mb);
            }
        } else {
            send_total_time = *send_time_in_nanos;

            printf("%Lf\n", send_total_time / ((long double) 1000000000));
            printf("%Lf\n", total_data / ((long double) 1024) / ((long double) 1024));
            printf("%Lf\n", send_pkts_rate);
            printf("%Lf\n", recv_pkts_rate);
            printf("%Lf\n", send_pkts_rate + recv_pkts_rate);
            printf("%Lf\n", send_avg_throughput_mb);
            printf("%Lf\n", recv_avg_throughput_mb);
            printf("%Lf\n", send_avg_throughput_mb + recv_avg_throughput_mb);
            printf("%Lf\n", send_avg_latency);

            if(show_perf_counters) {
                printf("%ld\n", xmit_pkts);
                printf("%ld\n", rcv_pkts);
                printf("%Lf\n", xmit_data_bytes / ((long double) 1024) / ((long double) 1024));
                printf("%Lf\n", rcv_data_bytes / ((long double) 1024) / ((long double) 1024));
                printf("%Lf\n", send_overhead / ((long double) 1024) / ((long double) 1024) );
                printf("%Lf\n", send_overhead_percentage * 100);
                printf("%Lf\n", recv_overhead / ((long double) 1024) / ((long double) 1024) );
                printf("%Lf\n", recv_overhead_percentage * 100);
                printf("%Lf\n", send_avg_raw_throughput_mb);
                printf("%Lf\n", recv_avg_raw_throughput_mb);
                printf("%Lf\n", send_avg_raw_throughput_mb + recv_avg_raw_throughput_mb);
            }
        }
    }
}
