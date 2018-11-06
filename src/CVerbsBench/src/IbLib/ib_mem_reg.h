/**
 * @file ib_mem_reg.h
 * @author Fabian Ruhland, HHU
 * @date May 2018
 *
 * @brief Contains structs and functions to work with memory regions.
 */

#ifndef IB_MEM_REG_H
#define IB_MEM_REG_H

#include <infiniband/verbs.h>

static uint32_t id_counter = 0;

/**
 * Structure, that wraps a memory region.
 */
typedef struct ib_mem_reg {
    struct ibv_mr *mr; /**< The memory region itself */

    uint32_t id; /**< Unique id, that is assigned automatically for every memory region */
    void *addr; /**< Pointer to the memory region's buffer */
    uint64_t size; /**< The size in bytes of the memory region's buffer */
    uint32_t lkey; /**< The memory region's local key */
    uint32_t rkey; /**< The memory region's remote key */
} ib_mem_reg;

/**
 * Initialize a memory region.
 *
 * After a memory region has been initialized, it can be registered by calling register_memory_region().
 *
 * @param mem_reg The memory region to be initialized
 * @param addr The buffer to be used as a memory region
 * @param size The buffer's size
 */
void init_mem_reg(ib_mem_reg *mem_reg, uint64_t size);

/**
 * Free the memory, that has been allocated by a given memory region.
 * 
 * The ib_mem_reg-struct will be useless after calling this function and can be freed.
 *
 * @param mem_reg The memory region to be destroyed
 */
void destroy_mem_reg(ib_mem_reg *mem_reg);

#endif