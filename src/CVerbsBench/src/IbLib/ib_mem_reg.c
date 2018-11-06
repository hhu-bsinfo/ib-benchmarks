/**
 * @file ib_mem_reg.c
 * @author Fabian Ruhland, HHU
 * @date 2018
 *
 * @brief Contains structs and functions to work with memory regions.
 */


#include <stdlib.h>
#include "ib_mem_reg.h"
#include "log.h"

void init_mem_reg(ib_mem_reg *mem_reg, uint64_t size) {
    mem_reg->id = id_counter++;

    // Allocate space for the memory region
    mem_reg->addr = malloc(size);
    mem_reg->size = size;

    LOG_INFO("MEMORY REGION", "Allocated %ld bytes of space for memory region with id %d at address 0x%016lx!",
             mem_reg->size, mem_reg->id, (uint64_t) mem_reg->addr);
}

void destroy_mem_reg(ib_mem_reg *mem_reg) {
    free(mem_reg->addr);

    LOG_INFO("MEMORY REGION", "Freed memory region with id %d at address 0x%016lx, size %ld!",
             mem_reg->id, (uint64_t) mem_reg->addr, mem_reg->size);

    mem_reg->id = 0;
    mem_reg->addr = NULL;
    mem_reg->size = 0;
}