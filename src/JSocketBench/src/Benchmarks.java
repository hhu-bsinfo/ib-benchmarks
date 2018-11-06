import java.io.IOException;

/**
 * Contains the benchmark functions.
 *
 * @author Fabian Ruhland, HHU
 * @date 2018
 */
public class Benchmarks {

    /**
     * Stores the time in nanosecons, that has been measured by a send benchmark.
     */
    private long sendTime = 0;

    /**
     * Stores the time in nanosecons, that has been measured by a receive benchmark.
     */
    private long recvTime = 0;

    /**
     * Start the send benchmark.
     *
     * The measured time in nanoseconds is stored in sendTime.
     */
    void sendBenchmark(Connection connection, long messageCount) {
        long startTime = 0, endTime = 0;

        Log.INFO("SEND THREAD", "Starting send thread! Sending %d messages.", messageCount);

        try {
            startTime = System.nanoTime();

            connection.sendMessages(messageCount);

            endTime = System.nanoTime();
        } catch (IOException e) {
            Log.ERROR_AND_EXIT("SEND THREAD", "An error occurred, while sending a message!" +
                    " Error: '%s'", e.getMessage());
        }

        Log.INFO("SEND THREAD", "Finished sending!");

        sendTime = endTime - startTime;

        Log.INFO("SEND THREAD", "Terminating thread...");
    }

    /**
     * Start the receive benchmark.
     *
     * The measured time in nanoseconds is stored in recvTime.
     */
    void recvBenchmark(Connection connection, long messageCount) {
        long startTime = 0, endTime = 0;

        Log.INFO("RECV THREAD", "Starting receive thread! Receiving %d messages.", messageCount);

        try {
            startTime = System.nanoTime();

            connection.recvMessages(messageCount);

            endTime = System.nanoTime();
        } catch (IOException e) {
            Log.ERROR_AND_EXIT("RECV THREAD", "An error occured, while receiving a message!" +
                    " Error: '%s'", e.getMessage());
        }

        Log.INFO("RECV THREAD", "Finished sending!");

        recvTime = endTime - startTime;

        Log.INFO("RECV THREAD", "Terminating thread...");
    }

    /**
     * Start the pingpong benchmark as server.
     *
     * The measured time in nanoseconds is stored in sendTime.
     */
    void pingPongBenchmarkServer(Connection connection, long messageCount) {
        long startTime = 0, endTime = 0;

        Log.INFO("SERVER THREAD", "Starting pingpong thread! Doing %d iterations.", messageCount);

        try {
            startTime = System.nanoTime();

            for (int i = 0; i < messageCount; i++) {
                connection.sendMessages(1);
                connection.recvMessages(1);
            }

            endTime = System.nanoTime();
        } catch(Exception e) {
            Log.ERROR_AND_EXIT("SERVER THREAD", "An error occurred, while sending or receiving a message!"
                    + "Error: '%s'", e.getMessage());
        }

        Log.INFO("SERVER THREAD","Finished pingpong benchmark!", messageCount);

        sendTime = endTime - startTime;

        Log.INFO("SERVER THREAD", "Terminating thread...", messageCount);
    }

    /**
     * Start the pingpong benchmark as client.
     *
     * The measured time in nanoseconds is stored in sendTime.
     */
    void pingPongBenchmarkClient(Connection connection, long messageCount) {
        long startTime = 0, endTime = 0;

        Log.INFO("CLIENT THREAD", "Starting pingpong thread! Doing %d iterations.", messageCount);

        try {
            startTime = System.nanoTime();

            for (int i = 0; i < messageCount; i++) {
                connection.recvMessages(1);
                connection.sendMessages(1);
            }

            endTime = System.nanoTime();
        } catch(Exception e) {
            Log.ERROR_AND_EXIT("CLIENT THREAD", "An error occurred, while sending or receiving a message!"
                    + "Error: '%s'", e.getMessage());
        }

        Log.INFO("CLIENT THREAD","Finished pingpong benchmark!", messageCount);

        sendTime = endTime - startTime;

        Log.INFO("CLIENT THREAD", "Terminating thread...", messageCount);
    }

    /**
     * Get the time, that has been measured by a send benchmark.
     */
    long getSendTime() {
        return sendTime;
    }

    /**
     * Get the time, that has been measured by a receive benchmark.
     */
    long getRecvTime() {
        return recvTime;
    }
}
