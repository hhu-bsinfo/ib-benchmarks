/**
 * @file ib_device.h
 * @author Fabian Ruhland, HHU
 * @date 2018
 *
 * @brief Contains structs and functions to work with infiniband devices.
 */

#ifndef IB_DEVICE_H
#define IB_DEVICE_H

#include <infiniband/verbs.h>

/**
 * Structure, that wraps an infiniband device.
 */
typedef struct ib_device {
    struct ibv_context *context; /**< The device context */

    const char *name; /**< The device's name */
    uint64_t guid; /**< The device's global unique id */
    uint16_t lid; /**< The local id of the device's first port */
    uint8_t link_width; /**< The device's link width */
} ib_device;

/**
 * Initialize a device.
 *
 * The memory for the structure must already be allocated.
 * This function opens a context for the first device, that is found on the local host and queries it's first port for
 * it's local id.
 *
 * @param device The device to be initialized
 */
void init_device(ib_device *device);

/**
 * Destroy a device context.
 *
 * The ib_device-struct will be useless after calling this function and can be freed.
 *
 * @param device The device to be destroyed
 */
void close_device(ib_device *device);

#endif