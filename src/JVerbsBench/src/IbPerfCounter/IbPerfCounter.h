#ifndef IBPERFCOUNTER_H
#define IBPERFCOUNTER_H

#define DEFAULT_QUERY_TIMEOUT 0
#define QUERY_BUF_SIZE 1536
#define RESET_BUF_SIZE 1024

#include <cstdint>
#include <iostream>
#include <infiniband/mad.h>

/**
 * Uses the MAD-library to read performance counters from an Infiniband-port.
 *
 * @author Fabian Ruhland, Fabian.Ruhland@hhu.de
 * @date May 2018
 */
class IbPerfCounter {

public:
    /**
     * Constructor.
     *
     * @param lid The port's local id
     * @param portNum The number, that the port has on its device.
     */
    explicit IbPerfCounter(uint16_t lid, uint8_t portNum);

    /**
     * Destructor.
     */
    ~IbPerfCounter();

    /**
     * Reset all MAD-counters.
     */
    void ResetCounters();

    /**
     * Query all MAD-counters from all ports and aggregate the results.
     * The resulting values will be saved in the counter variables.
     */
    void RefreshCounters();

    /**
     * Get the amount of transmitted data.
     */
    uint64_t GetXmitDataBytes() const {
        return m_xmitDataBytes;
    }

    /**
     * Get the amount of received data.
     */
    uint64_t GetRcvDataBytes() const {
        return m_rcvDataBytes;
    }

    /**
     * Get the amount of transmitted packets.
     */
    uint64_t GetXmitPkts() const {
        return m_xmitPkts;
    }

    /**
     * Get the amount of received packets.
     */
    uint64_t GetRcvPkts() const {
        return m_rcvPkts;
    }

private:
    /**
     * The lid of the port, that shall be monitored.
     */
    uint16_t m_lid;

    /**
     * The number, that the port has on its device.
     */
    uint8_t m_portNum;

    /**
     * The port's active link width.
     */
    uint8_t m_linkWidth;

    /**
     * Pointer to a mad-port. A port can be opened by calling mad_rpc_open_port().
     * A port must be opened before it is possible to query any data from the Infiniband device.
     */
    ibmad_port *m_madPort;

    /**
     * Contains information about an Infiniband device/port. This struct can be initialized by calling ib_portid_set().
     */
    ib_portid_t m_portId;

    /* Counter variables */

    uint64_t m_xmitDataBytes;
    uint64_t m_rcvDataBytes;
    uint64_t m_xmitPkts;
    uint64_t m_rcvPkts;
};

#endif
