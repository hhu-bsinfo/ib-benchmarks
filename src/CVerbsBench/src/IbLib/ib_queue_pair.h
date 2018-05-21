/**
 * @file ib_queue_pair.h
 * @author Fabian Ruhland, HHU
 * @date May 2018
 *
 * @brief Contains structs and functions to work with queue pairs.
 */

#ifndef IB_QUEUE_PAIR_H
#define IB_QUEUE_PAIR_H

#include <infiniband/verbs.h>
#include "ib_prot_dom.h"
#include "ib_comp_queue.h"
#include "ib_shared_recv_queue.h"

/**
 * Structure, that wraps a queue pair.
 */
typedef struct ib_queue_pair {
    struct ibv_qp *qp; /**< The queue pair itself */

    uint32_t qpn; /**< The queue pair number */
    uint32_t size; /**< The queue size */
} ib_queue_pair;

/**
 * Initialize a queue pair.
 * The state of the queue pair will be set to IBV_QPS_INIT.
 *
 * The memory for the structure must already be allocated.
 *
 * @param queue_pair The queue pair to be initialized
 * @param prot_dom The protection domain, in which the queue pair shall be created
 * @param send_comp_queue The send completion queue (may be the same as send_comp_queue)
 * @param recv_comp_queue The receive completion queue (may be the same as send_comp_queue)
 * @param recv_queue The shared receive queue (may be NULL, if no shared receive queue shall be used)
 * @param size The queue size
 */
void init_queue_pair(ib_queue_pair *queue_pair, ib_prot_dom *prot_dom, ib_comp_queue *send_comp_queue,
                     ib_comp_queue *recv_comp_queue, ib_shared_recv_queue *recv_queue, uint32_t size);

/**
 * Change the state of a queue pair to IBV_QPS_RTR (Ready to receive).
 * Afterwards, the queue pair can receive messages from a remote queue pair.
 *
 * @param queue_pair The queue pair
 * @param remote_lid The remote queue pair's lid
 * @param remote_qpn The remote queue pair's qpn
 */
void set_qp_state_to_rtr(ib_queue_pair *queue_pair, uint16_t remote_lid, uint32_t remote_qpn);

/**
 * Change the state of a queue pair to IBV_QPS_RTS (Ready to send).
 * Afterwards, the queue pair can send messages to a remote queue pair.
 *
 * @param queue_pair The queue pair
 */
void set_qp_state_to_rts(ib_queue_pair *queue_pair);

/**
 * Destroy a queue pair.
 *
 * The ib_queue_pair-struct will be useless after calling this function and can be freed.
 *
 * @param queue_pair The queue pair to be destroyed
 */
void close_queue_pair(ib_queue_pair *queue_pair);

#endif