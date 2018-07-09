#include "IbPerfCounter.h"

IbPerfCounter::IbPerfCounter(uint16_t lid, uint8_t portNum) : m_lid(lid),
                                                            m_portNum(portNum),
                                                            m_linkWidth(0),
                                                            m_madPort(nullptr),
                                                            m_portId({0}),
                                                            m_xmitDataBytes(0),
                                                            m_rcvDataBytes(0),
                                                            m_xmitPkts(0),
                                                            m_rcvPkts(0)
{
    uint8_t pmaQueryBuf[QUERY_BUF_SIZE];
    uint8_t smpQueryBuf[IB_SMP_DATA_SIZE];
    int mgmt_classes[3] = {IB_SMI_CLASS, IB_SA_CLASS, IB_PERFORMANCE_CLASS};

    memset(pmaQueryBuf, 0, sizeof(pmaQueryBuf));
    memset(smpQueryBuf, 0, sizeof(smpQueryBuf));

    // Open a MAD-port. mad_rpc_open_port takes the following parameters:
    //
    // dev_name: The name of the local device from which all queries will be sent.
    //           This seems to be optional, as passing a nullptr also works.
    // dev_port: This seems to be number of the local port from which the all queries will be sent.
    //           Passing a zero works fine. I guess, it then uses a default value.
    // mgmt_classes: I guess, this array is used to declare the fields, that we want to access.
    // num_classes: The amount of management-classes.
    m_madPort = mad_rpc_open_port(nullptr, 0, mgmt_classes, 3);

    if (m_madPort == nullptr) {
        throw std::runtime_error("MAD: Failed to open port! (mad_rpc_open_port failed)");
    }

    // Once the MAD-port has been opened, we can use ib_portid_set to initialize m_portId.
    // It takes the following parameters:
    //
    // portid: A pointer to the ib_portid_t-struct, that shall be initialized.
    // lid: The device's local id.
    // qp: I guess, one can set this value to query only one specific queue pair. Setting it to 0 works fine for me.
    // qkey: Again, setting this to 0 works flawlessy.
    ib_portid_set(&m_portId, m_lid, 0, 0);

    // Query the Subnet Management Agent for device-information. We do this to get the port's link width.
    // This function works similar to pma_query_via() (see above).
    if (!smp_query_via(smpQueryBuf, &m_portId, IB_ATTR_PORT_INFO, 0, 0, m_madPort)) {
        mad_rpc_close_port(m_madPort);
        throw std::runtime_error("MAD: Failed to query device information! (smp_query_via failed)");
    }

    mad_decode_field(smpQueryBuf, IB_PORT_LINK_WIDTH_ACTIVE_F, &m_linkWidth);

    switch (m_linkWidth) {
        case 1:
            m_linkWidth = 1;
            break;
        case 2:
            m_linkWidth = 4;
            break;
        case 4:
            m_linkWidth = 8;
            break;
        case 8:
            m_linkWidth = 12;
            break;
        default:
            m_linkWidth = 1;
            break;
    }
}

IbPerfCounter::~IbPerfCounter() {
    // Close the MAD-port.
    mad_rpc_close_port(m_madPort);
}

void IbPerfCounter::ResetCounters() {
    char resetBuf[RESET_BUF_SIZE];
    memset(resetBuf, 0, sizeof(resetBuf));

    m_xmitDataBytes = 0;
    m_rcvDataBytes = 0;
    m_xmitPkts = 0;
    m_rcvPkts = 0;

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
    if (!performance_reset_via(resetBuf, &m_portId, m_portNum, 0xffffffff, DEFAULT_QUERY_TIMEOUT,
                               IB_GSI_PORT_COUNTERS, m_madPort)) {
        mad_rpc_close_port(m_madPort);
        throw std::runtime_error("Failed to reset performance counters!");
    }

    if (!performance_reset_via(resetBuf, &m_portId, m_portNum, 0xffffffff, DEFAULT_QUERY_TIMEOUT,
                               IB_GSI_PORT_COUNTERS_EXT, m_madPort)) {
        mad_rpc_close_port(m_madPort);
        throw std::runtime_error("Failed to reset extended performance counters!");
    }
}

void IbPerfCounter::RefreshCounters() {
    uint64_t value;
    uint8_t pmaQueryBuf[QUERY_BUF_SIZE];

    m_xmitDataBytes = 0;
    m_rcvDataBytes = 0;
    m_xmitPkts = 0;
    m_rcvPkts = 0;

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

    if (!pma_query_via(pmaQueryBuf, &m_portId, m_portNum, 0, IB_GSI_PORT_COUNTERS_EXT, m_madPort)) {
        mad_rpc_close_port(m_madPort);
        throw std::runtime_error("Failed to query extended performance counters!");
    }

    mad_decode_field(pmaQueryBuf, IB_PC_EXT_XMT_BYTES_F, &value);
    m_xmitDataBytes += value * m_linkWidth;

    mad_decode_field(pmaQueryBuf, IB_PC_EXT_RCV_BYTES_F, &value);
    m_rcvDataBytes += value * m_linkWidth;

    mad_decode_field(pmaQueryBuf, IB_PC_EXT_XMT_PKTS_F, &value);
    m_xmitPkts += value;

    mad_decode_field(pmaQueryBuf, IB_PC_EXT_RCV_PKTS_F, &value);
    m_rcvPkts += value;
}