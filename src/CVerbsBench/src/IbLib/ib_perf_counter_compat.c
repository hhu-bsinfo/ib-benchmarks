#include "ib_perf_counter_compat.h"
#include "log.h"

void init_perf_counter_compat(ib_perf_counter_compat *perf_counter, ib_device *device) {
    char path[512];

    LOG_INFO("PERF COUNTER", "Initializing performance counters...")

    snprintf(path, sizeof(path), "/sys/class/infiniband/%s/ports/1/counters/port_xmit_packets", device->name);
    perf_counter->files[0] = fopen(path, "r");

    snprintf(path, sizeof(path), "/sys/class/infiniband/%s/ports/1/counters/port_xmit_data", device->name);
    perf_counter->files[1] = fopen(path, "r");

    snprintf(path, sizeof(path), "/sys/class/infiniband/%s/ports/1/counters/port_rcv_packets", device->name);
    perf_counter->files[2] = fopen(path, "r");

    snprintf(path, sizeof(path), "/sys/class/infiniband/%s/ports/1/counters/port_rcv_data", device->name);
    perf_counter->files[3] = fopen(path, "r");

    for(uint32_t i = 0; i < 4; i++) {
        if(perf_counter->files[i] == NULL) {
            LOG_ERROR_AND_EXIT("PERF COUNTER", "Unable to open file! Error: %s", strerror(errno));
        }
    }

    reset_counters_compat(perf_counter);

    LOG_INFO("PERF COUNTER", "Finished initializing performance counters!");
}

void reset_counters_compat(ib_perf_counter_compat *perf_counter) {
    char buf[128];

    for(uint32_t i = 0; i < 4; i++) {
        fread(buf, 1, 128, perf_counter->files[i]);
        fseek(perf_counter->files[i], 0, SEEK_SET);
        perf_counter->base_values[i] = strtoull(buf, NULL, 10);
    }
}

void refresh_counters_compat(ib_perf_counter_compat *perf_counter) {
    char buf[128];

    fread(buf, 1, 128, perf_counter->files[0]);
    fseek(perf_counter->files[0], 0, SEEK_SET);
    perf_counter->xmit_pkts = strtoull(buf, NULL, 10) - perf_counter->base_values[0];

    fread(buf, 1, 128, perf_counter->files[1]);
    fseek(perf_counter->files[1], 0, SEEK_SET);
    perf_counter->xmit_data_bytes = (strtoull(buf, NULL, 10) - perf_counter->base_values[1]) * 4;

    fread(buf, 1, 128, perf_counter->files[2]);
    fseek(perf_counter->files[2], 0, SEEK_SET);
    perf_counter->rcv_pkts = strtoull(buf, NULL, 10) - perf_counter->base_values[2];

    fread(buf, 1, 128, perf_counter->files[3]);
    fseek(perf_counter->files[3], 0, SEEK_SET);
    perf_counter->rcv_data_bytes = (strtoull(buf, NULL, 10) - perf_counter->base_values[3]) * 4;
}

void close_perf_counter_compat(ib_perf_counter_compat *perf_counter) {
    for(uint32_t i = 0; i < 4; i++) {
        int32_t ret = fclose(perf_counter->files[i]);

        if(ret != 0) {
            LOG_WARN("PERF COUNTER", "Unable to close file! Error: %s", strerror(errno));
        }

        perf_counter->base_values[i] = 0;
    }

    perf_counter->xmit_data_bytes = 0;
    perf_counter->rcv_data_bytes = 0;
    perf_counter->xmit_pkts = 0;
    perf_counter->rcv_pkts = 0;

    LOG_INFO("PERF COUNTER", "Destroyed performance counters!");
}
