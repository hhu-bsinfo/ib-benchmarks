/**
 * @file ib_perf_counter.h
 * @author Fabian Ruhland, HHU
 * @date June 2018
 *
 * @brief Uses the ibmad library to read performance counters from an infiniband device.
 *
 * Requires root! If you don't have root-privileges, use ib_perf_counter_compat.
 */

#ifndef IB_PERF_COUNTER_H
#define IB_PERF_COUNTER_H

/**
 * Default timeout-value to be used for SMP-/PMA-querys.
 */
#define DEFAULT_QUERY_TIMEOUT 0

/**
 * Buffer size to be used for SMP-/PMA-querys.
 */
#define QUERY_BUF_SIZE 1536

/**
 * Buffer size to be used for reset-querys.
 */
#define RESET_BUF_SIZE 1024

#include <stdint.h>
#include <infiniband/mad.h>
#include "ib_device.h"

/**
 * Contains the performance counters.
 */
typedef struct ib_perf_counter {
    ib_device *device; /**< The infiniband device */

    struct ibmad_port *mad_port; /**< The mad-port, that is used to query the performance counters */
    ib_portid_t portid; /**< The id of the port, which will be queried */

    uint64_t xmit_data_bytes; /**< The amount of sent packets since the last counter reset */
    uint64_t rcv_data_bytes; /**< The amount of sent bytes since the last counter reset */
    uint64_t xmit_pkts; /**< The amount of received packets since the last counter reset */
    uint64_t rcv_pkts; /**< The amount of received bytes since the last counter reset */
} ib_perf_counter;

/**
 * Initialize an ib_perf_counter struct.
 *
 * The memory for the structure must already be allocated.
 * This function opens a mad-port to monitor the first port of the specified device.
 *
 * @param perf_counter The ib_perf_counter struct to be initialized
 * @param device The device to be monitored
 */
void init_perf_counter(ib_perf_counter *perf_counter, ib_device *device);

/**
 * Reset all MAD-counters.
 */
void reset_counters(ib_perf_counter *perf_counter);

/**
 * Query all MAD-counters from all ports and aggregate the results.
 * The resulting values will be saved in the counter variables.
 */
void refresh_counters(ib_perf_counter *perf_counter);

/**
 * Destroy an ib_perf_counter struct and close the opened mad-port.
 *
 * The perf_counter-struct will be useless after calling this function and can be freed.
 *
 * @param perf_counter The ib_perf_counter struct to be destroyed
 */
void close_perf_counter(ib_perf_counter *perf_counter);

#endif
