/**
 * @file ib_comp_queue.c
 * @author Fabian Ruhland, HHU
 * @date May 2018
 *
 * @brief Contains structs and functions to work with completion queues.
 */

#include <errno.h>
#include <string.h>
#include <zconf.h>
#include "ib_comp_queue.h"
#include "log.h"

void init_comp_queue(ib_comp_queue *comp_queue, ib_device *device, uint32_t size) {
    // Create completion queue
    comp_queue->cq = ibv_create_cq(device->context, size, NULL, NULL, 0);

    if(comp_queue->cq == NULL) {
        LOG_ERROR_AND_EXIT("COMPLETION QUEUE", "Unable to create completion queue with size %d!", size);
    }

    // Allocate space for work completions
    posix_memalign((void **) &comp_queue->work_comps, (size_t) getpagesize(), sizeof(struct ibv_wc) * size);

    comp_queue->size = size;

    LOG_INFO("COMPLETION QUEUE", "Created completion queue with size %d!", comp_queue->size);
}

uint32_t poll_completions(ib_comp_queue *comp_queue) {
    // Poll work completions from the completion queue
    int ret = ibv_poll_cq(comp_queue->cq, comp_queue->size, comp_queue->work_comps);

    if(ret < 0) {
        LOG_ERROR_AND_EXIT("COMPLETION QUEUE", "Error while polling completions! Error: %s", strerror(errno));
    }

    // Iterate through all polled completions an check for errors
    for(uint32_t i = 0; i < ret; i++) {
        if(comp_queue->work_comps[i].status != IBV_WC_SUCCESS) {
            switch (comp_queue->work_comps[i].status) {
                case IBV_WC_LOC_LEN_ERR:
                LOG_ERROR_AND_EXIT("COMPLETION QUEUE", "Failed work completion! Error: IBV_WC_LOC_LEN_ERR - "
                                                       "The memory region is too small to hold the received message");
                case IBV_WC_LOC_QP_OP_ERR:
                LOG_ERROR_AND_EXIT("COMPLETION QUEUE", "Failed work completion! Error: IBV_WC_LOC_QP_OP_ERR - "
                                                       "Internal queue pair consistency error");
                case IBV_WC_LOC_EEC_OP_ERR:
                LOG_ERROR_AND_EXIT("COMPLETION QUEUE", "Failed work completion! Error: IBV_WC_LOC_EEC_OP_ERR - "
                                                       "Local EE context operation error");
                case IBV_WC_LOC_PROT_ERR:
                LOG_ERROR_AND_EXIT("COMPLETION QUEUE", "Failed work completion! Error: IBV_WC_LOC_PROT_ERR - "
                                                       "Local protection error. The posted buffer is not registered as"
                                                       "a memory region");
                case IBV_WC_WR_FLUSH_ERR:
                LOG_ERROR_AND_EXIT("COMPLETION QUEUE", "Failed work completion! Error: IBV_WC_WR_FLUSH_ERR - "
                                                       "Work request flush error. The queue pair went into the error "
                                                       "state before processing all work requests");
                case IBV_WC_MW_BIND_ERR:
                LOG_ERROR_AND_EXIT("COMPLETION QUEUE", "Failed work completion! Error: IBV_WC_MW_BIND_ERR - "
                                                       "Unable to bind a memory window to the memory region");
                case IBV_WC_BAD_RESP_ERR:
                LOG_ERROR_AND_EXIT("COMPLETION QUEUE", "Failed work completion! Error: IBV_WC_BAD_RESP_ERR - "
                                                       "Bad response error");
                case IBV_WC_LOC_ACCESS_ERR:
                LOG_ERROR_AND_EXIT("COMPLETION QUEUE", "Failed work completion! Error: IBV_WC_LOC_ACCESS_ERR - "
                                                       "Local access error. A protection error occured on a local "
                                                       "data buffer");
                case IBV_WC_REM_INV_REQ_ERR:
                LOG_ERROR_AND_EXIT("COMPLETION QUEUE", "Failed work completion! Error: IBV_WC_REM_INV_REQ_ERR - "
                                                       "Remote invalid request error. Invalid message detected");
                case IBV_WC_REM_ACCESS_ERR:
                LOG_ERROR_AND_EXIT("COMPLETION QUEUE", "Failed work completion! Error: IBV_WC_REM_ACCESS_ERR - "
                                                       "Remote access error. Protection error on remote");
                case IBV_WC_REM_OP_ERR:
                LOG_ERROR_AND_EXIT("COMPLETION QUEUE", "Failed work completion! Error: IBV_WC_REM_OP_ERR - "
                                                       "Remote operation error. Remote is unable to complete "
                                                       "operation");
                case IBV_WC_RETRY_EXC_ERR:
                LOG_ERROR_AND_EXIT("COMPLETION QUEUE", "Failed work completion! Error: IBV_WC_RETRY_EXC_ERR - "
                                                       "Retry counter exceeded without receiving ACK/NAK from remote");
                case IBV_WC_RNR_RETRY_EXC_ERR:
                LOG_ERROR_AND_EXIT("COMPLETION QUEUE", "Failed work completion! Error: IBV_WC_RNR_RETRY_EXC_ERR - "
                                                       "RNR Retry counter exceeded");
                case IBV_WC_LOC_RDD_VIOL_ERR:
                LOG_ERROR_AND_EXIT("COMPLETION QUEUE", "Failed work completion! Error: IBV_WC_LOC_RDD_VIOL_ERR - "
                                                       "Local RDD violation error");
                case IBV_WC_REM_INV_RD_REQ_ERR:
                LOG_ERROR_AND_EXIT("COMPLETION QUEUE", "Failed work completion! Error: IBV_WC_REM_INV_RD_REQ_ERR - "
                                                       "Remote invalid RD request");
                case IBV_WC_REM_ABORT_ERR:
                LOG_ERROR_AND_EXIT("COMPLETION QUEUE", "Failed work completion! Error: IBV_WC_REM_ABORT_ERR - "
                                                       "Remote aborted error");
                case IBV_WC_INV_EECN_ERR:
                LOG_ERROR_AND_EXIT("COMPLETION QUEUE", "Failed work completion! Error: IBV_WC_INV_EECN_ERR - "
                                                       "Invalid EE context number");
                case IBV_WC_INV_EEC_STATE_ERR:
                LOG_ERROR_AND_EXIT("COMPLETION QUEUE", "Failed work completion! Error: IBV_WC_INV_EEC_STATE_ERR - "
                                                       "Invalid EE context stat error");
                case IBV_WC_FATAL_ERR:
                LOG_ERROR_AND_EXIT("COMPLETION QUEUE", "Failed work completion! Error: IBV_WC_FATAL_ERR - "
                                                       "Fatal error");
                case IBV_WC_RESP_TIMEOUT_ERR:
                LOG_ERROR_AND_EXIT("COMPLETION QUEUE", "Failed work completion! Error: IBV_WC_RESP_TIMEOUT_ERR - "
                                                       "Response timeout error");
                case IBV_WC_GENERAL_ERR:
                LOG_ERROR_AND_EXIT("COMPLETION QUEUE", "Failed work completion! Error: IBV_WC_GENERAL_ERR - "
                                                       "General error");
                default:
                    LOG_ERROR_AND_EXIT("COMPLETION QUEUE", "Failed work completion! Error: Unknown error");
            }
        }
    }

    return (uint32_t) ret;
}

void close_comp_queue(ib_comp_queue *comp_queue) {
    // Destroy the completion queue
    int result = ibv_destroy_cq(comp_queue->cq);

    if(result != 0) {
        LOG_ERROR_AND_EXIT("COMPLETION QUEUE", "Unable to destroy completion queue with size %d!", comp_queue->size);
    }

    free(comp_queue->work_comps);

    LOG_INFO("COMPLETION QUEUE", "Destroyed completion queue with size %d!", comp_queue->size);

    comp_queue->cq = NULL;
    comp_queue->work_comps = NULL;
    comp_queue->size = 0;
}