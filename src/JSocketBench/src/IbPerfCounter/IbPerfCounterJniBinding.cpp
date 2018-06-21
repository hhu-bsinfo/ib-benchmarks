#include <cstdint>
#include <infiniband/verbs.h>
#include "IbPerfCounterJniBinding.h"
#include "IbPerfCounter.h"

IbPerfCounter *perfCounter = nullptr;

uint16_t getLid() {
    int numDevices = 0;
    ibv_device **deviceList = nullptr;
    ibv_context *context = nullptr;
    ibv_port_attr portAttributes;
    
    // Get a list of all infiniband devices on the local host
    deviceList = ibv_get_device_list(&numDevices);
    
    context = ibv_open_device(deviceList[0]);
    
    if(context == nullptr) {
        return 0;
    }
    
    ibv_free_device_list(deviceList);

    int result = ibv_query_port(context, 1, &portAttributes);
    
    if(result != 0) {
        return 0;
    }
    
    return portAttributes.lid;
}

JNIEXPORT jboolean JNICALL Java_IbPerfCounter_init (JNIEnv *, jobject) {
    uint16_t lid = getLid();
    
    if(lid == 0) {
        return false;
    }
    
    perfCounter = new IbPerfCounter(lid, 1);
    
    return true;
}

JNIEXPORT void JNICALL Java_IbPerfCounter_resetCounters (JNIEnv *, jobject) {
    perfCounter->ResetCounters();
}
  
JNIEXPORT void JNICALL Java_IbPerfCounter_refreshCounters (JNIEnv *, jobject) {
    perfCounter->RefreshCounters();
}
  
JNIEXPORT jlong JNICALL Java_IbPerfCounter_getXmitDataBytes (JNIEnv *, jobject) {
    return perfCounter->GetXmitDataBytes();
}

JNIEXPORT jlong JNICALL Java_IbPerfCounter_getRcvDataBytes (JNIEnv *, jobject) {
    return perfCounter->GetRcvDataBytes();
}
  
JNIEXPORT jlong JNICALL Java_IbPerfCounter_getXmitPkts (JNIEnv *, jobject) {
    return perfCounter->GetXmitPkts();
}
  
JNIEXPORT jlong JNICALL Java_IbPerfCounter_getRcvPkts (JNIEnv *, jobject) {
    return perfCounter->GetRcvPkts();
}
