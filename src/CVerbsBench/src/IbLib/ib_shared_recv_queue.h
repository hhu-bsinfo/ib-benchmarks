/**
 * @file ib_shared_recv_queue.h
 * @author Fabian Ruhland, HHU
 * @date 2018
 *
 * @brief Contains structs and functions to work with shared receive queues.
 */

#ifndef IB_SHARED_RECV_QUEUE_H
#define IB_SHARED_RECV_QUEUE_H

#include <infiniband/verbs.h>
#include "ib_prot_dom.h"

/**
 * Structure, that wraps a shared receive queue.
 */
typedef struct ib_shared_recv_queue {
    struct ibv_srq *srq; /**< The shared receive queue itself */

    uint32_t size; /**< The queue size */
} ib_shared_recv_queue;

/**
 * Initialize a shared receive queue.
 *
 * The memory for the structure must already be allocated.
 *
 * @param recv_queue The shared receive queue to be initialized
 * @param prot_dom The protection domain, in which the shared receive queue shall be created
 * @param size The queue size
 */
void init_shared_recv_queue(ib_shared_recv_queue *recv_queue, ib_prot_dom *prot_dom, uint32_t size);

/**
 * Destroy a shared receive queue pair.
 *
 * The ib_shared_recv_queue-struct will be useless after calling this function and can be freed.
 *
 * @param recv_queue The shared receive queue to be destroyed
 */
void close_shared_recv_queue(ib_shared_recv_queue *recv_queue);

#endif