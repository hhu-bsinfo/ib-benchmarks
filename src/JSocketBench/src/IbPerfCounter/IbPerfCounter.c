#include <stdbool.h>
#include "IbPerfCounter.h"
#include "IbLib/ib_device.h"
#include "IbLib/ib_perf_counter.h"
#include "IbLib/ib_perf_counter_compat.h"

uint8_t verbosity;

bool use_compat;
ib_device device;
ib_perf_counter perf_counter;
ib_perf_counter_compat perf_counter_compat;

JNIEXPORT jboolean JNICALL Java_IbPerfCounter_init(JNIEnv *env, jobject obj, jboolean compat, jint verbosity) {
    verbosity = (uint8_t) verbosity;
    use_compat = (bool) compat;

    init_device(&device);

    if(use_compat) {
        init_perf_counter_compat(&perf_counter_compat, &device);
    } else {
        init_perf_counter(&perf_counter, &device);
    }
}

JNIEXPORT void JNICALL Java_IbPerfCounter_resetCounters(JNIEnv *env, jobject obj) {
    if(use_compat) {
        reset_counters_compat(&perf_counter_compat);
    } else {
        reset_counters(&perf_counter);
    }
}

JNIEXPORT void JNICALL Java_IbPerfCounter_refreshCounters(JNIEnv *env, jobject obj) {
    if(use_compat) {
        refresh_counters_compat(&perf_counter_compat);
    } else {
        refresh_counters(&perf_counter);
    }
}

JNIEXPORT jlong JNICALL Java_IbPerfCounter_getXmitDataBytes(JNIEnv *env, jobject obj) {
    if(use_compat) {
        return perf_counter_compat.xmit_data_bytes;
    } else {
        return perf_counter.xmit_data_bytes;
    }
}

JNIEXPORT jlong JNICALL Java_IbPerfCounter_getRcvDataBytes(JNIEnv *env, jobject obj) {
    if(use_compat) {
        return perf_counter_compat.rcv_data_bytes;
    } else {
        return perf_counter.rcv_data_bytes;
    }
}

JNIEXPORT jlong JNICALL Java_IbPerfCounter_getXmitPkts(JNIEnv *env, jobject obj) {
    if(use_compat) {
        return perf_counter_compat.xmit_pkts;
    } else {
        return perf_counter.xmit_pkts;
    }
}

JNIEXPORT jlong JNICALL Java_IbPerfCounter_getRcvPkts(JNIEnv *env, jobject obj) {
    if(use_compat) {
        return perf_counter_compat.rcv_pkts;
    } else {
        return perf_counter.rcv_pkts;
    }
}