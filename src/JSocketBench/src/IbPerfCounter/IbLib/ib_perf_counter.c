#include "ib_perf_counter.h"
#include "log.h"

void init_perf_counter(ib_perf_counter *perf_counter, ib_device *device) {
    LOG_INFO("PERF COUNTER", "Initializing performance counters...")

    uint8_t pmaQueryBuf[QUERY_BUF_SIZE];
    uint8_t smpQueryBuf[IB_SMP_DATA_SIZE];
    int mgmt_classes[3] = {IB_SMI_CLASS, IB_SA_CLASS, IB_PERFORMANCE_CLASS};

    memset(pmaQueryBuf, 0, sizeof(pmaQueryBuf));
    memset(smpQueryBuf, 0, sizeof(smpQueryBuf));

    perf_counter->device = device;

    // Open a MAD-port. mad_rpc_open_port takes the following parameters:
    //
    // dev_name: The name of the local device from which all queries will be sent.
    //           This seems to be optional, as passing a nullptr also works.
    // dev_port: This seems to be number of the local port from which the all queries will be sent.
    //           Passing a zero works fine. I guess, it then uses a default value.
    // mgmt_classes: I guess, this array is used to declare the fields, that we want to access.
    // num_classes: The amount of management-classes.
    perf_counter->mad_port = mad_rpc_open_port(NULL, 0, mgmt_classes, 3);

    if (perf_counter->mad_port == NULL) {
        LOG_ERROR_AND_EXIT("PERF COUNTER", "Failed to open MAD-port! (mad_rpc_open_port failed)");
    }

    // Once the MAD-port has been opened, we can use ib_portid_set to initialize portid.
    // It takes the following parameters:
    //
    // portid: A pointer to the ib_portid_t-struct, that shall be initialized.
    // lid: The device's local id.
    // qp: I guess, one can set this value to query only one specific queue pair. Setting it to 0 works fine for me.
    // qkey: Again, setting this to 0 works flawlessy.
    ib_portid_set(&perf_counter->portid, perf_counter->device->lid, 0, 0);

    LOG_INFO("PERF COUNTER", "Finished initializing performance counters!");
}

void reset_counters(ib_perf_counter *perf_counter) {
    char resetBuf[RESET_BUF_SIZE];
    memset(resetBuf, 0, sizeof(resetBuf));

    perf_counter->xmit_data_bytes = 0;
    perf_counter->rcv_data_bytes = 0;
    perf_counter->xmit_pkts = 0;
    perf_counter->rcv_pkts = 0;

    // Resetting the performance counters can be accomplished by calling performance_reset_via().
    // It takes the following parameters:
    //
    // rcvbuf: The function needs a buffer. I don't know what is written to it and what size it should have,
    //         but the perfquery-tool sets it to 1024 Bytes, so I just do the same.
    // dest: The ib_portid-struct.
    // port: The number of the port, whose counters shall be resetted.
    // mask: A bitmask, determining which counters shall be resetted. Setting it to 0xffffffff will reset all counters.
    // timeout: Setting the timeout to 0 works fine.
    // id: The class of counters that shall be resetted. IB_GSI_PORT_COUNTERS are the 32-bit performance counters
    //       and IB_GSI_PORT_COUNTERS_EXT are the 64-bit extended performance counters.
    // srcport: The MAD-port.
    if (!performance_reset_via(resetBuf, &perf_counter->portid, 1, 0xffffffff, DEFAULT_QUERY_TIMEOUT,
                               IB_GSI_PORT_COUNTERS, perf_counter->mad_port)) {
        mad_rpc_close_port(perf_counter->mad_port);
        LOG_ERROR_AND_EXIT("PERF COUNTER", "Failed to reset performance counters!");
    }

    if (!performance_reset_via(resetBuf, &perf_counter->portid, 1, 0xffffffff, DEFAULT_QUERY_TIMEOUT,
                               IB_GSI_PORT_COUNTERS_EXT, perf_counter->mad_port)) {
        mad_rpc_close_port(perf_counter->mad_port);
        LOG_ERROR_AND_EXIT("PERF COUNTER", "Failed to reset extended performance counters!");
    }
}

void refresh_counters(ib_perf_counter *perf_counter) {
    uint64_t value;
    uint8_t pmaQueryBuf[QUERY_BUF_SIZE];

    perf_counter->xmit_data_bytes = 0;
    perf_counter->rcv_data_bytes = 0;
    perf_counter->xmit_pkts = 0;
    perf_counter->rcv_pkts = 0;

    // Query the port's performance counters.
    //
    // Reading the performance counters works as follows:
    // 1. Call pma_query_via() to query the counters. Pass either IB_GSI_PORT_COUNTERS or IB_GSI_PORT_COUNTERS_EXT
    //    to read either the normal 32-bit or the extended 64-bit counters.
    // 2. Call mad_decode_field() for every counter we want to get. mad_decode_field() takes the following parameters:
    //
    //    buf: The buffer, that has been filled by pma_query_via().
    //    field: The counter, that we want to read.
    //    val: A pointer to the variable that the counter will be saved in. Make sure it has the correct size.

    // Get the extended 64-bit transmit- and receive-counters.
    memset(pmaQueryBuf, 0, sizeof(pmaQueryBuf));

    if (!pma_query_via(pmaQueryBuf, &perf_counter->portid, 1, 0, IB_GSI_PORT_COUNTERS_EXT, perf_counter->mad_port)) {
        mad_rpc_close_port(perf_counter->mad_port);
        LOG_ERROR_AND_EXIT("PERF COUNTER", "Failed to query extended performance counters!");
    }

    mad_decode_field(pmaQueryBuf, IB_PC_EXT_XMT_BYTES_F, &value);
    perf_counter->xmit_data_bytes += value * perf_counter->device->link_width;

    mad_decode_field(pmaQueryBuf, IB_PC_EXT_RCV_BYTES_F, &value);
    perf_counter->rcv_data_bytes += value * perf_counter->device->link_width;

    mad_decode_field(pmaQueryBuf, IB_PC_EXT_XMT_PKTS_F, &value);
    perf_counter->xmit_pkts += value;

    mad_decode_field(pmaQueryBuf, IB_PC_EXT_RCV_PKTS_F, &value);
    perf_counter->rcv_pkts += value;
}

void close_perf_counter(ib_perf_counter *perf_counter) {
    mad_rpc_close_port(perf_counter->mad_port);

    perf_counter->device = NULL;
    perf_counter->mad_port = NULL;
    perf_counter->xmit_data_bytes = 0;
    perf_counter->rcv_data_bytes = 0;
    perf_counter->xmit_pkts = 0;
    perf_counter->rcv_pkts = 0;

    LOG_INFO("PERF COUNTER", "Destroyed performance counters!");
}