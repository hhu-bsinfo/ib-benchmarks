/**
 * @file threads.h
 * @author Fabian Ruhland, HHU
 * @date 2018
 *
 * @brief Contains thread-functions for sending and receiving data via infiniband.
 */

#ifndef THREADS_H
#define THREADS_H

#include <stdint.h>
#include <IbLib/connection.h>

/**
 * Parameters, that are passed to thread
 */
typedef struct thread_params {
    connection *conn; /**< The connection to use for sending/receiving */
    uint64_t msg_count; /**< The amount of messages to send/receive */
} thread_params;

/**
 * Send a specified amount of messages via a given connection and measures the time.
 *
 * @return The measured time in nanoseconds
 */
void *msg_send_thread(thread_params *params);

/**
 * Receive a specified amount of messages from a given connection and measures the time.
 *
 * @return The measured time in nanoseconds
 */
void *msg_recv_thread(thread_params *params);

/**
 * Write a buffer to a remote host via RDMA a specified amount of times and measures the time.
 *
 * @return The measured time in nanoseconds
 */
void *rdma_write_send_thread(thread_params *params);

/**
 * Wait for a remote host to finish writing via RDMA and measures the time.
 *
 * When the remote host starts writing, it sends 'start' via TCP and when it has finished, it sends 'close'.
 *
 * @return The measured time in nanoseconds
 */
void *rdma_write_recv_thread(thread_params *params);

/**
 * Server thread for the latency benchmark using messages.
 *
 * @return The measured time in nanoseconds.
 */
void *msg_lat_server_thread(thread_params *params);

/**
 * Client thread for the latency benchmark using messages.
 *
 * @return The measured time in nanoseconds.
 */
void *msg_lat_client_thread(thread_params *params);

/**
 * Server thread for the latency benchmark using RDMA writes.
 *
 * @return The measured time in nanoseconds.
 */
void *rdma_write_lat_server_thread(thread_params *params);

/**
 * Client thread for the latency benchmark using RDMA writes.
 *
 * @return The measured time in nanoseconds.
 */
void *rdma_write_lat_client_thread(thread_params *params);

/**
 * Server thread for the latency benchmark using RDMA reads.
 *
 * @return The measured time in nanoseconds.
 */
void *rdma_read_lat_server_thread(thread_params *params);

/**
 * Client thread for the latency benchmark using RDMA reads.
 *
 * @return The measured time in nanoseconds.
 */
void *rdma_read_lat_client_thread(thread_params *params);

/**
 * Server thread for the pingpong benchmark.
 *
 * @return The measured time in nanoseconds.
 */
void *pingpong_server_thread(thread_params *params);

/**
 * Client thread for the pingpong benchmark.
 *
 * @return The measured time in nanoseconds.
 */
void *pingpong_client_thread(thread_params *params);

/**
 * Set the affinity of the current thread to a single CPU.
 *
 * @param log_name The name to be used in log-entries, that are produced by this function
 * @param cpu The cpu to pin the current thread to
 */
void __pin_current_thread(const char *log_name, uint8_t cpu);

#endif