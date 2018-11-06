/**
 * @file ib_prot_dom.c
 * @author Fabian Ruhland, HHU
 * @date 2018
 *
 * @brief Contains structs and functions to work with protection domains.
 */

#include <errno.h>
#include <string.h>
#include "ib_prot_dom.h"
#include "log.h"

void init_prot_dom(ib_prot_dom *prot_dom, ib_device *device, const char *name) {
    // Allocate the protection domain
    prot_dom->pd = ibv_alloc_pd(device->context);

    if(prot_dom->pd == NULL) {
        LOG_ERROR_AND_EXIT("PROTECTION DOMAIN", "Unable to allocate protection domain '%s'! Error: %s",
                           name, strerror(errno));
    }

    memcpy(prot_dom->name, name, strlen(name) > 32 ? 33 : strlen(name) + 1);
    prot_dom->num_regions = 0;

    LOG_INFO("PROTECTION DOMAIN", "Allocated protection domain '%s'!", prot_dom->name);
}

void register_memory_region(ib_prot_dom *prot_dom, ib_mem_reg *mem_reg) {
    // Register the given memory region in the protection domain
    mem_reg->mr = ibv_reg_mr(prot_dom->pd, mem_reg->addr, mem_reg->size,
            IBV_ACCESS_LOCAL_WRITE | IBV_ACCESS_REMOTE_WRITE);

    if(mem_reg->mr == NULL) {
        LOG_ERROR_AND_EXIT("PROTECTION DOMAIN", "%s: Unable to register memory region at Address 0x%016lx, "
                                                "size %ld Bytes!", prot_dom->name, (uint64_t) mem_reg->addr,
                           mem_reg->size);
    }

    mem_reg->lkey = mem_reg->mr->lkey;
    mem_reg->rkey = mem_reg->mr->rkey;

    prot_dom->num_regions++;

    LOG_INFO("PROTECTION DOMAIN", "%s: Registered memory region with id %d at Address 0x%016lx, Lkey: 0x%08x, Rkey: 0x%08x, "
                                  "size: %ld Bytes! Total regions registered: %d.", prot_dom->name, mem_reg->id,
             (uint64_t) mem_reg->addr, mem_reg->lkey, mem_reg->rkey, mem_reg->size, prot_dom->num_regions);
}

void deregister_memory_region(ib_prot_dom *prot_dom, ib_mem_reg *mem_reg) {
    // Deregister the memory region from the protection domain
    int result = ibv_dereg_mr(mem_reg->mr);

    if(result != 0) {
        LOG_ERROR_AND_EXIT("PROTECTION DOMAIN", "%s: Unable to deregister memory region withd id %d at Address 0x%016lx, "
                                                "Lkey: 0x%08x, Rkey: 0x%08x, size: %ld Bytes! "
                                                "Total regions registered: %d.", prot_dom->name, mem_reg->id,
                           (uint64_t) mem_reg->addr, mem_reg->lkey, mem_reg->rkey, mem_reg->size,
                           prot_dom->num_regions);
    }

    prot_dom->num_regions--;

    LOG_INFO("PROTECTION DOMAIN", "%s: Deregistered memory region with id %d at Address 0x%016lx, Lkey: 0x%08x, "
                                  "Rkey: 0x%08x, size: %ld Bytes!", prot_dom->name, mem_reg->id,
             (uint64_t) mem_reg->addr, mem_reg->lkey, mem_reg->rkey, mem_reg->size);

    mem_reg->addr = NULL;
    mem_reg->size = 0;
    mem_reg->lkey = 0;
    mem_reg->rkey = 0;
}

void close_prot_dom(ib_prot_dom *prot_dom) {
    // Deallocate the protection domain
    int result = ibv_dealloc_pd(prot_dom->pd);

    if(result != 0) {
        LOG_ERROR_AND_EXIT("PROTECTION DOMAIN", "Unable to deallocate protection domain '%s'! Error: %s",
                           prot_dom->name, strerror(errno));
    }

    LOG_INFO("PROTECTION DOMAIN", "Deallocated protection domain '%s'!", prot_dom->name);

    prot_dom->pd = NULL;
    prot_dom->num_regions = 0;
    memset(prot_dom->name, 0, sizeof(char));
}