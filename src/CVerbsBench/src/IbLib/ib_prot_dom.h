/**
 * @file ib_prot_dom.h
 * @author Fabian Ruhland, HHU
 * @date 2018
 *
 * @brief Contains structs and functions to work with protection domains.
 */

#ifndef IB_PROT_DOM_H
#define IB_PROT_DOM_H

#include <infiniband/verbs.h>
#include "ib_device.h"
#include "ib_mem_reg.h"

/**
 * Structure, that wraps a protection domain.
 */
typedef struct ib_prot_dom {
    struct ibv_pd *pd; /**< The protection domain itself */

    char name[33]; /**< The domain's name (shown in log entries) */
    uint32_t num_regions; /**< The amount of registered memory regions */
} ib_prot_dom;

/**
 * Initialize a protection domain.
 *
 * The memory for the structure must already be allocated.
 *
 * @param prot_dom The protection domain to be intialized
 * @param device The local infiniband device
 * @param name A short name (32 characters at max) describing the domain (shown in log entries).
 */
void init_prot_dom(ib_prot_dom *prot_dom, ib_device *device, const char *name);

/**
 * Register a memory region a protection domain.
 *
 * @param prot_dom The protection domain
 * @param mem_reg The memory region to be registered
 */
void register_memory_region(ib_prot_dom *prot_dom, ib_mem_reg *mem_reg);

/**
 * Deregister a memory region from a protection domain.
 *
 * @param prot_dom The protection domain
 * @param mem_reg The memory region to be deregistered
 */
void deregister_memory_region(ib_prot_dom *prot_dom, ib_mem_reg *mem_reg);

/**
 * Destroy a protection domain.
 *
 * The ib_prot_dom-struct will be useless after calling this function and can be freed.
 *
 * @param prot_dom The protection domain to be destroyed
 */
void close_prot_dom(ib_prot_dom *prot_dom);

#endif