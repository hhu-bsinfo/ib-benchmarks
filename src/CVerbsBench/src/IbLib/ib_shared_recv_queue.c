/**
 * @file ib_shared_recv_queue.c
 * @author Fabian Ruhland, HHU
 * @date May 2018
 *
 * @brief Contains structs and functions to work with shared receive queues.
 */

#include <errno.h>
#include <string.h>
#include "ib_shared_recv_queue.h"
#include "log.h"

void init_shared_recv_queue(ib_shared_recv_queue *recv_queue, ib_prot_dom *prot_dom, uint32_t size) {
    struct ibv_srq_init_attr attr;

    attr.attr.max_wr = size;
    attr.attr.max_sge = 1;

    // Create the shared receive queue
    recv_queue->srq = ibv_create_srq(prot_dom->pd, &attr);

    if(recv_queue->srq == NULL) {
        LOG_ERROR_AND_EXIT("SHARED RECEIVE QUEUE", "Unable to create shared receive queue with size %d!", size);
    }

    recv_queue->size = size;

    LOG_INFO ("SHARED RECEIVE QUEUE", "Created shared receive queue with size %d!", size);
}

void close_shared_recv_queue(ib_shared_recv_queue *recv_queue) {
    // Destroy the shared receive queue
    int result = ibv_destroy_srq(recv_queue->srq);

    if(result != 0) {
        LOG_ERROR_AND_EXIT("SHARED RECEIVE QUEUE", "Unable to destroy shared receive queue with size %d",
                           recv_queue->size);
    }

    LOG_INFO ("SHARED RECEIVE QUEUE", "Destroyed shared receive queue with size %d!", recv_queue->size);

    recv_queue->size = 0;
}