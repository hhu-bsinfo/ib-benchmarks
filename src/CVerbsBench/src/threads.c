/**
 * @file threads.c
 * @author Fabian Ruhland, HHU
 * @date May 2018
 *
 * @brief Contains thread-functions for sending and receiving data via infiniband.
 */

#define _GNU_SOURCE
#include <stdbool.h>
#include <string.h>
#include <IbLib/log.h>
#include <zconf.h>
#include "threads.h"

uint64_t send_return_val = 0;
uint64_t recv_return_val = 0;

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