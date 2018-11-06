/**
 * @file ib_perf_counter.h
 * @author Fabian Ruhland, HHU
 * @date July 2018
 *
 * @brief Reads the performance counters of an infiniband device from the filesystem.
 *
 * There is a file for each performance counter in "/sys/class/infiniband/<device-name>/ports/<port-number>/counters/".
 * This implementation reads the the counters from these files, instead of using the ibmad library, thus, it does not
 * require root-privileges.
 */

#ifndef IB_PERF_COUNTER_COMPAT_H
#define IB_PERF_COUNTER_COMPAT_H

#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include "ib_device.h"

/**
 * Contains the performance counters.
 */
typedef struct ib_perf_counter_compat {
    ib_device *device; /**< The infiniband device */

    FILE *files[4]; /**< The file descriptors for each performance counter */
    uint64_t base_values[4]; /**< The initial counter values */

    uint64_t xmit_data_bytes; /**< The amount of sent packets since the last counter reset */
    uint64_t rcv_data_bytes; /**< The amount of sent bytes since the last counter reset */
    uint64_t xmit_pkts; /**< The amount of received packets since the last counter reset */
    uint64_t rcv_pkts; /**< The amount of received bytes since the last counter reset */
} ib_perf_counter_compat;

/**
 * Initialize an ib_perf_counter_compat struct.
 *
 * The memory for the structure must already be allocated.
 * This function opens a mad-port to monitor the first port of the specified device.
 *
 * @param perf_counter The ib_perf_counter struct to be initialized
 * @param device The device to be monitored
 */
void init_perf_counter_compat(ib_perf_counter_compat *perf_counter, ib_device *device);

/**
 * Reset all performance counters.
 */
void reset_counters_compat(ib_perf_counter_compat *perf_counter);

/**
 * Query all performance counters from all ports and aggregate the results.
 * The resulting values will be saved in the counter variables.
 */
void refresh_counters_compat(ib_perf_counter_compat *perf_counter);

/**
 * Destroy an ib_perf_counter_compat struct and close the opened mad-port.
 *
 * The perf_counter_compat-struct will be useless after calling this function and can be freed.
 *
 * @param perf_counter The ib_perf_counter_compat struct to be destroyed
 */
void close_perf_counter_compat(ib_perf_counter_compat *perf_counter);

#endif
