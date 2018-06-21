/**
 * Uses JNI-calls to read the performance counters of an infiniband device via the mad library.
 */
class IbPerfCounter {

    /**
     * Constructor.
     */
    IbPerfCounter() {
        Log.INFO("PERF COUNTER", "Initializing performance counters...");

        boolean result = init();

        if(!result) {
            Log.ERROR_AND_EXIT("PERF COUNTER", "Failed to initialize JNI-binding!");
        }

        Log.INFO("PERF COUNTER", "Finished initializing performance counters!");
    }

    /**
     * Initialize IbPerfCounterNative.
     */
    public native boolean init();

    /**
     * Reset all MAD-counters.
     */
    public native void resetCounters();

    /**
     * Query all MAD-counters from all ports and aggregate the results.
     * The resulting values will be saved in the counter variables.
     */
    public native void refreshCounters();

    /**
     * Get the amount of transmitted data.
     */
    public native long getXmitDataBytes();

    /**
     * Get the amount of received data.
     */
    public native long getRcvDataBytes();

    /**
     * Get the amount of transmitted packets.
     */
    public native long getXmitPkts();

    /**
     * Get the amount of received packets.
     */
    public native long getRcvPkts();
}
