/**
 * @file ib_queue_pair.c
 * @author Fabian Ruhland, HHU
 * @date 2018
 *
 * @brief Contains structs and functions to work with queue pairs.
 */

#include <errno.h>
#include <string.h>
#include "ib_queue_pair.h"
#include "log.h"

void init_queue_pair(ib_queue_pair *queue_pair, ib_prot_dom *prot_dom, ib_comp_queue *send_comp_queue,
                     ib_comp_queue *recv_comp_queue, ib_shared_recv_queue *recv_queue, uint32_t size) {
    struct ibv_qp_init_attr init_attr;
    struct ibv_qp_attr attr;

    memset(&init_attr, 0, sizeof(init_attr));
    memset(&attr, 0, sizeof(attr));

    init_attr.send_cq = send_comp_queue->cq; // Set the send completion queue
    init_attr.recv_cq = recv_comp_queue->cq; // Set the receive completion queue
    init_attr.qp_type = IBV_QPT_RC; // Set the type to 'reliably connected'
    init_attr.cap.max_send_wr  = size; // Set the send queue's size
    init_attr.cap.max_send_sge = 1; // Set the maximum amount of scatter-gather elements per send work request

    if(recv_queue == NULL) {
        init_attr.cap.max_recv_wr = size; // Set the receive queue's size
        init_attr.cap.max_recv_sge = 1; // Set the maximum amount of scatter-gather elements per receive work request
    } else {
        init_attr.srq = recv_queue->srq; // Use a shared receive queue
    }

    // Create the queue pair
    queue_pair->qp = ibv_create_qp(prot_dom->pd, &init_attr);

    if(queue_pair->qp == NULL) {
        LOG_ERROR_AND_EXIT("QUEUE PAIR", "Unable to create queue pair with size %d", size);
    }

    queue_pair->size = size;
    queue_pair->qpn = queue_pair->qp->qp_num;

    LOG_INFO("QUEUE PAIR", "Created queue pair with size %d, Qpn: 0x%08x!", size, queue_pair->qpn);

    attr.qp_state        = IBV_QPS_INIT; // The desired queue pair state (init)
    attr.pkey_index      = 0; // Partition key index; not used by us
    attr.port_num        = 1; // We always use the first port of the device
    attr.qp_access_flags = IBV_ACCESS_LOCAL_WRITE | IBV_ACCESS_REMOTE_WRITE | IBV_ACCESS_REMOTE_READ;

    // Change the queue pair state to init
    int result = ibv_modify_qp(queue_pair->qp, &attr, IBV_QP_STATE      |
                                                      IBV_QP_PKEY_INDEX |
                                                      IBV_QP_PORT       |
                                                      IBV_QP_ACCESS_FLAGS);

    if(result != 0) {
        LOG_ERROR_AND_EXIT("QUEUE PAIR", "Unable to set qp state to IBV_QPS_INIT (Qpn: 0x%08x)! Error: %s",
                           queue_pair->qpn, strerror(errno));
    }

    LOG_INFO("QUEUE PAIR", "Changed qp state to IBV_QPS_INIT (Qpn: 0x%08x)!", queue_pair->qpn);
}

void set_qp_state_to_rtr(ib_queue_pair *queue_pair, uint16_t remote_lid, uint32_t remote_qpn) {
    struct ibv_qp_attr attr;

    memset(&attr, 0, sizeof(attr));

    attr.qp_state              = IBV_QPS_RTR; // The desired queue pair state (ready to receive)
    attr.path_mtu              = IBV_MTU_4096; // Maximum transmission unit
    attr.dest_qp_num           = remote_qpn; // The qpn of the remote queue pair
    attr.rq_psn                = 0; // Packet sequence number, must be the same on both sides
    attr.max_dest_rd_atomic    = 1; // Maximum number of outstanding atomic RDMA operations; not used by us
    attr.min_rnr_timer         = 1; // Minimum amount of time before sending a NACK to the sender; 0 = 0.01 ms

    attr.ah_attr.is_global     = 0; // Indicates, whether the remote host can be in another subnet
    attr.ah_attr.dlid          = remote_lid; // The local id of the remote port
    attr.ah_attr.sl            = 1; // Service level; not used by us
    attr.ah_attr.src_path_bits = 0; // Packets are sent with the port's lid ORed wit the src_path_bits;
                                    // Useful, when a port covers more than one lid
    attr.ah_attr.port_num      = 1; // We always use the first port of the device

    // Change the queue pair state to rtr
    int result = ibv_modify_qp(queue_pair->qp, &attr, IBV_QP_STATE              |
                                                      IBV_QP_AV                 |
                                                      IBV_QP_PATH_MTU           |
                                                      IBV_QP_DEST_QPN           |
                                                      IBV_QP_RQ_PSN             |
                                                      IBV_QP_MAX_DEST_RD_ATOMIC |
                                                      IBV_QP_MIN_RNR_TIMER);

    if(result != 0) {
        LOG_ERROR_AND_EXIT("QUEUE PAIR", "Unable to set qp state to IBV_QPS_RTR (Qpn: 0x%08x)! Error: %s",
                           queue_pair->qpn, strerror(errno))
    }

    LOG_INFO("QUEUE PAIR", "Changed qp state to IBV_QPS_RTR (Qpn: 0x%08x)!", queue_pair->qpn);
}

void set_qp_state_to_rts(ib_queue_pair *queue_pair) {
    struct ibv_qp_attr attr;

    memset(&attr, 0, sizeof(attr));

    attr.qp_state = IBV_QPS_RTS; // The desired queue pair state (ready to send)
    attr.sq_psn = 0; // Packet sequence number, must be the same on both sides
    attr.timeout = 1; // Minimum time to wait for an ACK or NACK from the remote queue pair; 1 = 8.192 us
    attr.retry_cnt = 3; // Maximum amount of retries after not receiving an ACK from the remote queue pair
    attr.rnr_retry = 6; // Maximum amount of retries after receiving a NACK from the remote queue pair
    attr.max_rd_atomic = 1; // Maximum number of outstanding atomic RDMA operations; not used by us

    int result = ibv_modify_qp(queue_pair->qp, &attr, IBV_QP_STATE     |
                                         IBV_QP_TIMEOUT                |
                                         IBV_QP_RETRY_CNT              |
                                         IBV_QP_RNR_RETRY              |
                                         IBV_QP_SQ_PSN                 |
                                         IBV_QP_MAX_QP_RD_ATOMIC);

    if(result != 0) {
        LOG_ERROR_AND_EXIT("QUEUE PAIR", "Unable to set qp state to IBV_QPS_RTS (Qpn: 0x%08x)! Error: %s",
                           queue_pair->qpn, strerror(errno))
    }

    LOG_INFO("QUEUE PAIR", "Changed qp state to IBV_QPS_RTS (Qpn: 0x%08x)!", queue_pair->qpn);
}

void close_queue_pair(ib_queue_pair *queue_pair) {
    // Destroy the queue pair
    int result = ibv_destroy_qp(queue_pair->qp);

    if(result != 0) {
        LOG_ERROR_AND_EXIT("QUEUE PAIR", "Unable to destroy queue pair with size %d!, Qpn: 0x%08x!", queue_pair->size,
                           queue_pair->qpn);
    }

    LOG_INFO("QUEUE PAIR", "Destroyed queue pair with size %d!, Qpn: 0x%08x!", queue_pair->size, queue_pair->qpn);

    queue_pair->qp = NULL;
    queue_pair->size = 0;
}
