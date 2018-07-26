/**
 * Uses JNI-calls to read the performance counters of an infiniband device via the mad library.
 */
class IbPerfCounter {

    /**
     * Constructor.
     */
    IbPerfCounter(boolean compat) {
        Log.INFO("PERF COUNTER", "Initializing performance counters...");

        System.loadLibrary("ibverbs");

        init(compat, Log.VERBOSITY);

        Log.INFO("PERF COUNTER", "Finished initializing performance counters!");
    }

    /**
     * Initialize IbPerfCounterNative.
     */
    public native boolean init(boolean compat, int verbosity);

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
