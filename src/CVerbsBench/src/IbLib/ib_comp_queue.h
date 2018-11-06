/**
 * @file ib_comp_queue.h
 * @author Fabian Ruhland, HHU
 * @date 2018
 *
 * @brief Contains structs and functions to work with completion queues.
 */

#ifndef IB_COMP_QUEUE_H
#define IB_COMP_QUEUE_H

#include <infiniband/verbs.h>
#include "ib_device.h"

/**
 * Structure, that wraps a completion queue.
 */
typedef struct ib_comp_queue {
    struct ibv_cq *cq; /**< The completion queue itself */
    struct ibv_wc *work_comps; /**< Pointer to work completions, to be used with ibv_poll_cq(). */

    uint32_t size; /**< The completion queue's size. */
} ib_comp_queue;

/**
 * Initialize a completion queue.
 *
 * The memory for the structure must already be allocated.
 *
 * @param comp_queue The completion queue to be initialized
 * @param device The local infiniband device
 * @param size The desired queue size
 */
void init_comp_queue(ib_comp_queue *comp_queue, ib_device *device, uint32_t size);

/**
 * Poll completions from a completion queue.
 *
 * This function calls ibv_poll_cq() only once.
 *
 * @param comp_queue The completion queue to be polled
 *
 * @return The amount of polled work completions
 */
uint32_t poll_completions(ib_comp_queue *comp_queue);

/**
 * Destroy a completion queue.
 *
 * The ib_comp_queue-struct will be useless after calling this function and can be freed.
 *
 * @param comp_queue The completion queue to be destroyed
 */
void close_comp_queue(ib_comp_queue *comp_queue);

#endif