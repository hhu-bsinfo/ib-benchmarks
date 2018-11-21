/**
 * @file threads.c
 * @author Fabian Ruhland, HHU
 * @date 2018
 *
 * @brief Contains thread-functions for sending and receiving data via infiniband.
 */

#define _GNU_SOURCE
#include <stdbool.h>
#include <string.h>
#include <IbLib/log.h>
#include <zconf.h>
#include "threads.h"
#include "timer.h"

/**
 * Return value of a send benchmark.
 *
 * The benchmark stores the measured time in this variable, after it has finished.
 * A pointer to this variable is then returned to the main-thread.
 */
uint64_t send_return_val = 0;

/**
 * Return value of a receive benchmark.
 *
 * The benchmark stores the measured time in this variable, after it has finished.
 * A pointer to this variable is then returned to the main-thread.
 */
uint64_t recv_return_val = 0;

/**
 * Return value of ping-pong benchmark (server).
 *
 * Holds msg_count measured times to determine average, min and max latencies as 
 * well as percentiles (e.g. 99th).
 */
uint64_t *send_return_vals = NULL;

void *msg_send_thread(thread_params *params) {
    connection *conn = params->conn;
    uint64_t msg_count = params->msg_count;

    uint32_t queue_size = conn->queue_pair->size;
    uint32_t pending_comps = 0;

    struct timespec start, end;

    LOG_INFO("SEND THREAD", "Starting send thread! Sending %ld messages to receiver with Lid 0x%04x and Qpn 0x%08x.",
             msg_count, conn->remote_conn_info.lid, conn->remote_conn_info.qpn);

    __pin_current_thread("SEND THREAD", 0);

    // Send start signal
    write(conn->remote_sockfd, "start", 6);

    clock_gettime(CLOCK_MONOTONIC_RAW, &start);

    while (msg_count > 0) {
        // Always post as much work requests as there are free places in the queue
        uint32_t batch_size = queue_size - pending_comps;

        if(batch_size > msg_count) {
            batch_size = (uint32_t) msg_count;
        }

        msg_send(conn, batch_size);

        pending_comps += batch_size;
        msg_count -= batch_size;

        // Poll only a single time
        // It is not recommended to poll the completion queue empty, as this mostly costs too much time, which would
        // better be spent posting new work requests
        pending_comps -= poll_completions(conn->send_comp_queue);
    }

    // At the end, poll the completion queue until it is empty
    while(pending_comps > 0) {
        pending_comps -= poll_completions(conn->send_comp_queue);
    }

    clock_gettime(CLOCK_MONOTONIC_RAW, &end);

    // Calculate result
    send_return_val = (uint64_t) (end.tv_sec * 1000000000 + end.tv_nsec -
                                  start.tv_sec * 1000000000 + start.tv_nsec);

    LOG_INFO("SEND THREAD", "Finished sending to receiver with Lid 0x%04x and Qpn 0x%08x!",
             conn->remote_conn_info.lid, conn->remote_conn_info.qpn)

    LOG_INFO("SEND THREAD", "Terminating thread...");

    return &send_return_val;
}

void *msg_recv_thread(thread_params *params) {
    connection *conn = params->conn;
    uint64_t msg_count = params->msg_count;

    uint32_t queue_size = conn->queue_pair->size;
    uint32_t pending_comps = 0;

    struct timespec start, end;

    LOG_INFO("RECV THREAD", "Starting receive thread! Receiving %ld messages from sender with Lid 0x%04x and "
                            "Qpn 0x%08x.", msg_count, conn->remote_conn_info.lid, conn->remote_conn_info.qpn);

    __pin_current_thread("RECV THREAD", 1);

    // Fill receive queue to avoid timeouts on sender side
    msg_recv(conn, queue_size);
    pending_comps = queue_size;
    msg_count -= pending_comps;

    // Wait for start signal
    char buf[6];
    do {
        read(conn->remote_sockfd, buf, 6);
    } while(strcmp(buf, "start") != 0);

    clock_gettime(CLOCK_MONOTONIC_RAW, &start);

    pending_comps -= poll_completions(conn->recv_comp_queue);

    while(msg_count > 0) {
        // Always post as much work requests as there are free places in the queue
        uint32_t batch_size = queue_size - pending_comps;

        if(batch_size > msg_count) {
            batch_size = (uint32_t) msg_count;
        }

        msg_recv(conn, batch_size);

        pending_comps += batch_size;
        msg_count -= batch_size;

        // Poll only a single time
        // It is not recommended to poll the completion queue empty, as this mostly costs too much time, which would
        // better be spent posting new work requests
        pending_comps -= poll_completions(conn->recv_comp_queue);
    }

    // At the end, poll the completion queue until it is empty
    while(pending_comps > 0) {
        pending_comps -= poll_completions(conn->recv_comp_queue);
    }

    clock_gettime(CLOCK_MONOTONIC_RAW, &end);

    recv_return_val = (uint64_t) (end.tv_sec * 1000000000 + end.tv_nsec -
                                  start.tv_sec * 1000000000 + start.tv_nsec);

    LOG_INFO("RECV THREAD", "Finished receiving from sender with Lid 0x%04x and Qpn 0x%08x!",
             conn->remote_conn_info.lid, conn->remote_conn_info.qpn)

    LOG_INFO("RECV THREAD", "Terminating thread...");

    return &recv_return_val;
}

void *rdma_write_send_thread(thread_params *params) {
    connection *conn = params->conn;
    uint64_t msg_count = params->msg_count;

    uint32_t queue_size = conn->queue_pair->size;
    uint32_t pending_comps = 0;

    struct timespec start, end;

    LOG_INFO("SEND THREAD", "Starting send thread! Sending %ld messages to receiver with Lid 0x%04x and Qpn 0x%08x.",
             msg_count, conn->remote_conn_info.lid, conn->remote_conn_info.qpn);

    __pin_current_thread("SEND THREAD", 0);

    // Send start signal
    write(conn->remote_sockfd, "start", 6);

    clock_gettime(CLOCK_MONOTONIC_RAW, &start);

    while (msg_count > 0) {
        // Always post as much work requests as there are free places in the queue
        uint32_t batch_size = queue_size - pending_comps;

        if(batch_size > msg_count) {
            batch_size = (uint32_t) msg_count;
        }

        rdma_write(conn, batch_size);

        pending_comps += batch_size;
        msg_count -= batch_size;

        // Poll only a single time
        // It is not recommended to poll the completion queue empty, as this mostly costs too much time, which would
        // better be spent posting new work requests
        pending_comps -= poll_completions(conn->send_comp_queue);
    }

    // At the end, poll the completion queue until it is empty
    while(pending_comps > 0) {
        pending_comps -= poll_completions(conn->send_comp_queue);
    }

    clock_gettime(CLOCK_MONOTONIC_RAW, &end);

    send_return_val = (uint64_t) (end.tv_sec * 1000000000 + end.tv_nsec -
                                  start.tv_sec * 1000000000 + start.tv_nsec);

    LOG_INFO("SEND THREAD", "Finished sending to receiver with Lid 0x%04x and Qpn 0x%08x!",
             conn->remote_conn_info.lid, conn->remote_conn_info.qpn)

    LOG_INFO("SEND THREAD", "Sending 'close'-command to remote!")

    write(conn->remote_sockfd, "close", 6);

    LOG_INFO("SEND THREAD", "Terminating thread...");

    return &send_return_val;
}

void *rdma_write_recv_thread(thread_params *params) {
    connection *conn = params->conn;
    uint64_t msg_count = params->msg_count;

    char buf[6];

    struct timespec start, end;

    LOG_INFO("RECV THREAD", "Starting receive thread! Receiving %ld messages from sender with Lid 0x%04x and "
                            "Qpn 0x%08x.", msg_count, conn->remote_conn_info.lid, conn->remote_conn_info.qpn);

    // Wait for the server to start writing via RDMA
    do {
        read(conn->remote_sockfd, buf, 6);
    } while(strcmp(buf, "start") != 0);

    clock_gettime(CLOCK_MONOTONIC_RAW, &start);

    // Wait until the server has finished writing via RDMA
    do {
        read(conn->remote_sockfd, buf, 6);
    } while(strcmp(buf, "close") != 0);

    clock_gettime(CLOCK_MONOTONIC_RAW, &end);

    // Calculate result
    recv_return_val = (uint64_t) (end.tv_sec * 1000000000 + end.tv_nsec -
                                  start.tv_sec * 1000000000 + start.tv_nsec);

    LOG_INFO("RECV THREAD", "Received 'close'-command from remote!");

    LOG_INFO("RECV THREAD", "Finished receiving from sender with Lid 0x%04x and Qpn 0x%08x!",
             conn->remote_conn_info.lid, conn->remote_conn_info.qpn)

    LOG_INFO("RECV THREAD", "Terminating thread...");

    return &recv_return_val;
}

void *pingpong_server_thread(thread_params *params) {
    connection *conn = params->conn;
    uint64_t msg_count = params->msg_count;

    uint32_t queue_size = conn->queue_pair->size;
    uint64_t msg_progress = 0;
    uint32_t polled = 0;

    // struct timespec start, end;
    uint64_t start;
    uint64_t end;

    // Free previously allocated memory
    if (send_return_vals) {
        free(send_return_vals);
    }

    // Allocate memory for recording the time of each message
    send_return_vals = (uint64_t*) malloc(sizeof(uint64_t) * msg_count);

    LOG_INFO("SERVER THREAD", "Starting pingpong server thread! Sending to and receiving from client with "
                              "Lid 0x%04x and Qpn 0x%08x.", conn->remote_conn_info.lid, conn->remote_conn_info.qpn);

    __pin_current_thread("SERVER THREAD", 0);

    // Fill receive queue to avoid HCA stalls
    msg_recv(conn, queue_size);

    // Send start signal
    write(conn->remote_sockfd, "start", 6);

    while(msg_count > 0) {
        start = timer_start();

        // Send a single message and wait until a work completion is generated
        msg_send(conn, 1);

        do {
            polled = poll_completions(conn->send_comp_queue);
        } while(polled == 0);

        do {
            polled = poll_completions(conn->recv_comp_queue);
        } while(polled == 0);

        // Add the used WR for recv back at the end of the cycle
        msg_recv(conn, 1);

        end = timer_end_strong();

        // Store recorded time for later
        send_return_vals[msg_progress++] = timer_calc_delta_ns(start, end);

        msg_count--;
    }

    LOG_INFO("SERVER THREAD", "Finished pingpong test with client with Lid 0x%04x and Qpn 0x%08x!",
             conn->remote_conn_info.lid, conn->remote_conn_info.qpn)

    LOG_INFO("SERVER THREAD", "Terminating thread...");

    return &send_return_vals;
}

void *pingpong_client_thread(thread_params *params) {
    connection *conn = params->conn;
    uint64_t msg_count = params->msg_count;

    uint32_t queue_size = conn->queue_pair->size;
    uint32_t polled = 0;

    struct timespec start, end;

    LOG_INFO("CLIENT THREAD", "Starting pingpong client thread! Sending to and receiving from server with "
                              "Lid 0x%04x and Qpn 0x%08x.", conn->remote_conn_info.lid, conn->remote_conn_info.qpn);

    __pin_current_thread("CLIENT THREAD", 0);

    // Fill receive queue to avoid HCA stalls
    msg_recv(conn, queue_size);

    // Wait for start signal
    char buf[6];
    do {
        read(conn->remote_sockfd, buf, 6);
    } while(strcmp(buf, "start") != 0);

    while(msg_count > 0) {
        do {
            polled = poll_completions(conn->recv_comp_queue);
        } while(polled == 0);

        // Send a single message and wait until a work completion is generated
        msg_send(conn, 1);

        // Add the used WR for recv back after posting new send WR
        msg_recv(conn, 1);

        do {
            polled = poll_completions(conn->send_comp_queue);
        } while(polled == 0);

        msg_count--;
    }

    LOG_INFO("CLIENT THREAD", "Finished pingpong test with server with Lid 0x%04x and Qpn 0x%08x!",
             conn->remote_conn_info.lid, conn->remote_conn_info.qpn)

    LOG_INFO("CLIENT THREAD", "Terminating thread...");

    return NULL;
}

void __pin_current_thread(const char *log_name, uint8_t cpu) {
    cpu_set_t cpuset;
    pthread_t thread = pthread_self();

    CPU_ZERO(&cpuset);
    CPU_SET(cpu, &cpuset);

    LOG_INFO(log_name, "Pinning thread to CPU %d!", cpu);

    int ret = pthread_setaffinity_np(thread, sizeof(cpu_set_t), &cpuset);

    if(ret != 0) {
        LOG_WARN(log_name, "Unable to pin thread to CPU %d! Error: %s", cpu, strerror(ret));
    }
}