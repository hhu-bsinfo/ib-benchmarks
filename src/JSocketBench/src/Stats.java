import java.util.Arrays;
import java.util.Collections;
import java.util.List;

/**
 * Statistics class to measure time.
 *
 * @author Stefan Nothaas, HHU
 * @date 2018
 */
public class Stats {
    private long[] times;
    private int pos;

    private long tmpTime;

    /**
     * Constructor
     * 
     * @param size Total number of measurements to record.
     */
    public Stats(int size) {
        times = new long[size];
        pos = 0;
    }

    /**
     * Start measuring time.
     */
    public void start() {
        tmpTime = System.nanoTime();
    }

    /**
     * Stop measuring time (must be preceeded by a call to start).
     */
    public void stop() {
        times[pos++] = System.nanoTime() - tmpTime;
    }
    
    /**
     * Sort all currently available measurements in ascending order.
     */
    public void sortAscending() {
        Arrays.sort(times);
    }

    /**
     * Get the lowest time in us.
     * 
     * @return Time in us.
     */
    public double getMinUs() {
        return times[0] / 1000.0;
    }

    /**
     * Get the highest time in us.
     * 
     * @return Time in us.
     */
    public double getMaxUs() {
        return times[0] / 1000.0;
    }


    /**
     * Get the average time in us.
     * 
     * @return Time in us.
     */
    public double getAvgUs() {
        double tmp = 0;

        for (int i = 0; i < pos; i++) {
            tmp += times[i] / 1000.0;
        }

        return tmp / pos;
    }

    /**
     * Get the Xth percentiles value (Stats object must be sorted).
     * 
     * @return Value in us.
     */
    public double getPercentilesUs(float perc) {
        if (perc < 0.0 || perc > 1.0) {
            return -1;
        }

        return times[(int) Math.ceil(perc * pos) - 1] / 1000.0;
    }
}