/**
 * @file ib_device.c
 * @author Fabian Ruhland, HHU
 * @date May 2018
 *
 * @brief Contains structs and functions to work with infiniband devices.
 */

#include <errno.h>
#include <string.h>
#include "ib_device.h"
#include "log.h"

void init_device(ib_device *device) {
    int num_devices = 0;
    struct ibv_device **dev_list = NULL;
    struct ibv_port_attr port_attr;

    // Get a list of all infiniband devices on the local host
    dev_list = ibv_get_device_list(&num_devices);

    if(dev_list == NULL) {
        LOG_ERROR_AND_EXIT("DEVICE", "Unable to retrieve device list! Error: %s", strerror(errno));
    }

    // Open an infiniband context for the first found device
    device->name = ibv_get_device_name(dev_list[0]);
    device->guid = ibv_get_device_guid(dev_list[0]);

    device->context = ibv_open_device(dev_list[0]);

    if(device->context == NULL) {
        LOG_ERROR_AND_EXIT("DEVICE", "Unable to open device %s, Guid: 0x%016lx! Error: %s",
                           device->name, device->guid, strerror(errno));
    }

    ibv_free_device_list(dev_list);

    // Query the first port on the device an get it's local id
    memset(&port_attr, 0, sizeof(struct ibv_port_attr));

    int result = ibv_query_port(device->context, 1, &port_attr);

    if(result != 0) {
        LOG_ERROR_AND_EXIT("DEVICE", "Unable to query port 1 of device %s! Error: %s", device->name, strerror(errno));
    }

    if(port_attr.lid == 0) {
        LOG_ERROR_AND_EXIT("DEVICE", "Port Lid of device %s is 0!", device->name);
    }

    device->lid = port_attr.lid;

    switch (port_attr.active_width) {
        case 1:
            device->link_width = 1;
            break;
        case 2:
            device->link_width = 4;
            break;
        case 4:
            device->link_width = 8;
            break;
        case 8:
            device->link_width = 12;
            break;
        default:
            device->link_width = 1;
            break;
    }

    LOG_INFO("DEVICE", "Opened device %s, Guid: 0x%016lx, Lid 0x%04x!", device->name, device->guid, device->lid);
}

void close_device(ib_device *device) {
    // Close the device context
    int result = ibv_close_device(device->context);

    if(result != 0) {
        LOG_ERROR_AND_EXIT("Unable to close device %s, Guid: 0x%016lx, Lid 0x%04x!",
                           device->name, device->guid, device->lid);
    }

    device->context = NULL;

    LOG_INFO("DEVICE", "Closed device %s, Guid: 0x%016lx, Lid 0x%04x!", device->name, device->guid, device->lid);
}