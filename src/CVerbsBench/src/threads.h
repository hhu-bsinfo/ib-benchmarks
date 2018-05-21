/**
 * @file threads.h
 * @author Fabian Ruhland, HHU
 * @date May 2018
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
 * Set the affinity of the current thread to a single CPU.
 *
 * @param log_name The name to be used in log-entries, that are produced by this function
 * @param cpu The cpu to pin the current thread to
 */
void __pin_current_thread(const char *log_name, uint8_t cpu);

#endif