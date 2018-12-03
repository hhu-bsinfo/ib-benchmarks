import java.io.DataInputStream;
import java.io.DataOutputStream;
import java.io.EOFException;

/**
 * Contains the benchmarks.
 *
 * @author Fabian Ruhland, HHU
 * @date 2018
 */
class Benchmarks {

    /**
     * Send time in nanoseconds.
     */
    private long sendTime = 0;

    /**
     * Receive time in nanoseconds.
     */
    private long recvTime = 0;

    /**
     * Statistics measured
     */
    private Stats stats = null;

    /**
     * Start the send benchmark.
     *
     * The measured time in nanoseconds is stored in sendTime.
     *
     * @param connection The connection to use for the benchmark
     * @param msgCount The amount of message to send
     */
    void messageSendBenchmark(Connection connection, long msgCount) {
        long startTime = 0;
        long endTime = 0;

        int queueSize = connection.getQueueSize();
        int pendingComps = 0;

        Log.INFO("SEND THREAD", "Starting send thread! Sending %d messages.", msgCount);

        try {
            connection.getSocket().getOutputStream().write("start".getBytes());

            startTime = System.nanoTime();

            while(msgCount > 0) {
                // Get the amount of free places in the queue
                int batchSize = queueSize - pendingComps;

                // Post in batches of 10, so that Stateful Verbs Methods can be reused
                if(batchSize < 10) {
                    pendingComps -= connection.pollCompletionQueue(JVerbsWrapper.CqType.SEND_CQ);
                    continue;
                }

                if(batchSize > msgCount) {
                    batchSize = (int) msgCount;

                    connection.sendMessages(batchSize);

                    pendingComps += batchSize;
                    msgCount -= batchSize;
                } else {
                    int i = batchSize;

                    while(i >= 10) {
                        connection.sendMessages(10);
                        i -= 10;
                    }

                    pendingComps += batchSize - i;
                    msgCount -= batchSize - i;
                }

                // Poll only a single time
                // It is not recommended to poll the completion queue empty, as this mostly costs too much time,
                // which would better be spent posting new work requests
                pendingComps -= connection.pollCompletionQueue(JVerbsWrapper.CqType.SEND_CQ);
            }

            // At the end, poll the completion queue until it is empty
            while(pendingComps > 0) {
                pendingComps -= connection.pollCompletionQueue(JVerbsWrapper.CqType.SEND_CQ);
            }

            endTime = System.nanoTime();
        } catch(Exception e) {
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
     *
     * @param connection The connection to use for the benchmark
     * @param msgCount The amount of message to send
     */
    void messageRecvBenchmark(Connection connection, long msgCount) {
        long startTime = 0, endTime = 0;

        int queueSize = connection.getQueueSize();
        int pendingComps;

        Log.INFO("RECV THREAD", "Starting receive thread! Receiving %d messages.", msgCount);

        try {
            // Fill Receive Queue to avoid timeouts on sender side
            connection.recvMessages(queueSize);
            pendingComps = queueSize;
            msgCount -= queueSize;

            // Wait for start signal from server
            byte[] buf = new byte[5];
            DataInputStream stream = new DataInputStream(connection.getSocket().getInputStream());

            stream.readFully(buf);

            startTime = System.nanoTime();

            pendingComps -= connection.pollCompletionQueue(JVerbsWrapper.CqType.RECV_CQ);

            while(msgCount > 0) {
                // Get the amount of free places in the queue
                int batchSize = queueSize - pendingComps;

                // Post in batches of 10, so that Stateful Verbs Methods can be reused
                if(batchSize < 10) {
                    pendingComps -= connection.pollCompletionQueue(JVerbsWrapper.CqType.RECV_CQ);
                    continue;
                }

                if(batchSize > msgCount) {
                    batchSize = (int) msgCount;

                    connection.recvMessages(batchSize);

                    pendingComps += batchSize;
                    msgCount -= batchSize;
                } else {
                    int i = batchSize;

                    while(i >= 10) {
                        connection.recvMessages(10);
                        i -= 10;
                    }

                    pendingComps += batchSize - i;
                    msgCount -= batchSize - i;
                }

                // Poll only a single time
                // It is not recommended to poll the completion queue empty, as this mostly costs too much time,
                // which would better be spent posting new work requests
                pendingComps -= connection.pollCompletionQueue(JVerbsWrapper.CqType.RECV_CQ);
            }

            // At the end, poll the completion queue until it is empty
            while(pendingComps > 0) {
                pendingComps -= connection.pollCompletionQueue(JVerbsWrapper.CqType.RECV_CQ);
            }

            endTime = System.nanoTime();
        } catch (Exception e) {
            Log.ERROR_AND_EXIT("RECV THREAD", "An error occured, while receiving a message!" +
                    " Error: '%s'", e.getMessage());
        }

        Log.INFO("RECV THREAD", "Finished receiving!");

        recvTime = endTime - startTime;

        Log.INFO("RECV THREAD", "Terminating thread...");
    }

    /**
     * Start the rdma write benchmark.
     *
     * The measured time in nanoseconds is stored in sendTime.
     *
     * @param connection The connection to use for the benchmark
     * @param count The amount of writes to perform
     */
    void rdmaWriteActiveBenchmark(Connection connection, long count) {
        long startTime = 0;
        long endTime = 0;

        int queueSize = connection.getQueueSize();
        int pendingComps = 0;

        Log.INFO("SEND THREAD", "Starting send thread! Writing %d times.", count);

        try {
            startTime = System.nanoTime();

            while(count > 0) {
                // Get the amount of free places in the queue
                int batchSize = queueSize - pendingComps;

                // Post in batches of 10, so that Stateful Verbs Methods can be reused
                if(batchSize < 10) {
                    pendingComps -= connection.pollCompletionQueue(JVerbsWrapper.CqType.SEND_CQ);
                    continue;
                }

                if(batchSize > count) {
                    batchSize = (int) count;

                    connection.rdmaWrite(batchSize);

                    pendingComps += batchSize;
                    count -= batchSize;
                } else {
                    int i = batchSize;

                    while(i >= 10) {
                        connection.rdmaWrite(10);
                        i -= 10;
                    }

                    pendingComps += batchSize - i;
                    count -= batchSize - i;
                }

                // Poll only a single time
                // It is not recommended to poll the completion queue empty, as this mostly costs too much time,
                // which would better be spent posting new work requests
                pendingComps -= connection.pollCompletionQueue(JVerbsWrapper.CqType.SEND_CQ);
            }

            // At the end, poll the completion queue until it is empty
            while(pendingComps > 0) {
                pendingComps -= connection.pollCompletionQueue(JVerbsWrapper.CqType.SEND_CQ);
            }

            endTime = System.nanoTime();
        } catch(Exception e) {
            Log.ERROR_AND_EXIT("SEND THREAD", "An error occurred, while sending a message!" +
                    " Error: '%s'", e.getMessage());
        }

        Log.INFO("SEND THREAD", "Finished writing!");

        sendTime = endTime - startTime;

        Log.INFO("SEND THREAD", "Sending 'close'-command to remote host.");

        try {
            DataOutputStream outStream = new DataOutputStream(connection.getSocket().getOutputStream());

            outStream.write("close".getBytes());
        } catch (Exception e) {
            Log.ERROR_AND_EXIT("SEND THREAD", "An error occurred, while sending 'close'! Error: '%s'",
                    e.getMessage());
        }

        Log.INFO("SEND THREAD", "Terminating thread...");
    }

    /**
     * Start the rdma read benchmark.
     *
     * The measured time in nanoseconds is stored in sendTime.
     *
     * @param connection The connection to use for the benchmark
     * @param count The amount of read to perform
     */
    void rdmaReadActiveBenchmark(Connection connection, long count) {
        long startTime = 0;
        long endTime = 0;

        int queueSize = connection.getQueueSize();
        int pendingComps = 0;

        Log.INFO("SEND THREAD", "Starting send thread! Writing %d times.", count);

        try {
            startTime = System.nanoTime();

            while(count > 0) {
                // Get the amount of free places in the queue
                int batchSize = queueSize - pendingComps;

                // Post in batches of 10, so that Stateful Verbs Methods can be reused
                if(batchSize < 10) {
                    pendingComps -= connection.pollCompletionQueue(JVerbsWrapper.CqType.SEND_CQ);
                    continue;
                }

                if(batchSize > count) {
                    batchSize = (int) count;

                    connection.rdmaRead(batchSize);

                    pendingComps += batchSize;
                    count -= batchSize;
                } else {
                    int i = batchSize;

                    while(i >= 10) {
                        connection.rdmaRead(10);
                        i -= 10;
                    }

                    pendingComps += batchSize - i;
                    count -= batchSize - i;
                }

                // Poll only a single time
                // It is not recommended to poll the completion queue empty, as this mostly costs too much time,
                // which would better be spent posting new work requests
                pendingComps -= connection.pollCompletionQueue(JVerbsWrapper.CqType.SEND_CQ);
            }

            // At the end, poll the completion queue until it is empty
            while(pendingComps > 0) {
                pendingComps -= connection.pollCompletionQueue(JVerbsWrapper.CqType.SEND_CQ);
            }

            endTime = System.nanoTime();
        } catch(Exception e) {
            Log.ERROR_AND_EXIT("SEND THREAD", "An error occurred, while sending a message!" +
                    " Error: '%s'", e.getMessage());
        }

        Log.INFO("SEND THREAD", "Finished writing!");

        sendTime = endTime - startTime;

        Log.INFO("SEND THREAD", "Sending 'close'-command to remote host.");

        try {
            DataOutputStream outStream = new DataOutputStream(connection.getSocket().getOutputStream());

            outStream.write("close".getBytes());
        } catch (Exception e) {
            Log.ERROR_AND_EXIT("SEND THREAD", "An error occurred, while sending 'close'! Error: '%s'",
                    e.getMessage());
        }

        Log.INFO("SEND THREAD", "Terminating thread...");
    }

    /**
     * Start the rdma receive benchmark.
     *
     * The measured time in nanoseconds is stored in sendTime.
     *
     * @param connection The connection to use for the benchmark
     */
    void rdmaPassiveBenchmark(Connection connection) {
        long startTime = 0;
        long endTime = 0;

        byte[] buf = new byte[5];

        Log.INFO("RECV THREAD", "Starting receive thread!");

        startTime = System.nanoTime();

        try {
            DataInputStream inStream = new DataInputStream(connection.getSocket().getInputStream());

            inStream.readFully(buf);
        } catch (Exception e) {
            Log.ERROR_AND_EXIT("RECV THREAD", "An error occurred, while receiving 'close'! Error: '%s'",
                    e.getMessage());
        }

        endTime = System.nanoTime();

        Log.INFO("RECV THREAD", "Received 'close'-command from remote host!");

        Log.INFO("SEND THREAD", "Finished receiving!");

        recvTime = endTime - startTime;

        Log.INFO("RECV THREAD", "Terminating thread...");
    }

    /**
     * Start the pingpong benchmark as server
     *
     * The measured time in nanoseconds is stored in sendTime.
     *
     * @param connection The connection to use for the benchmarks
     * @param msgCount The amount of message to send and receive
     */
    void pingPongBenchmarkServer(Connection connection, long msgCount) {
        long startTime = 0;
        long endTime = 0;

        int polled;

        Log.INFO("SERVER THREAD", "Starting pingpong server thread!");

        stats = new Stats((int) msgCount);

        try {
            // Fill receive queue to avoid HCA stalls
            connection.recvMessages(connection.getQueueSize());

            startTime = System.nanoTime();

            while(msgCount > 0) {
                stats.start();

                // Send a single message and wait until a work completion is generated
                connection.sendMessages(1);

                do {
                    polled = connection.pollCompletionQueue(JVerbsWrapper.CqType.SEND_CQ);
                } while(polled == 0);

                do {
                    polled = connection.pollCompletionQueue(JVerbsWrapper.CqType.RECV_CQ);
                } while(polled == 0);

                // Add the used WR for recv back at the end of the cycle
                connection.recvMessages(1);

                stats.stop();

                msgCount--;
            }

            endTime = System.nanoTime();
        } catch(Exception e) {
            Log.ERROR_AND_EXIT("SERVER THREAD", "An error occurred, while sending or receiving a message!" +
                    " Error: '%s'", e.getMessage());
        }

        Log.INFO("SERVER THREAD", "Finished pingpong test!");

        sendTime = endTime - startTime;

        Log.INFO("SERVER THREAD", "Terminating thread...");
    }

    /**
     * Start the pingpong benchmark as client
     *
     * The measured time in nanoseconds is stored in sendTime.
     *
     * @param connection The connection to use for the benchmarks
     * @param msgCount The amount of message to send and receive
     */
    void pingPongBenchmarkClient(Connection connection, long msgCount) {
        long startTime = 0;
        long endTime = 0;

        int polled;

        Log.INFO("CLIENT THREAD", "Starting pingpong client thread!");

        try {
            // Fill receive queue to avoid HCA stalls
            connection.recvMessages(connection.getQueueSize());

            startTime = System.nanoTime();

            while(msgCount > 0) {
                do {
                    polled = connection.pollCompletionQueue(JVerbsWrapper.CqType.RECV_CQ);
                } while(polled == 0);

                // Send a single message and wait until a work completion is generated
                connection.sendMessages(1);

                // Add the used WR for recv back after posting new send WR
                connection.recvMessages(1);

                do {
                    polled = connection.pollCompletionQueue(JVerbsWrapper.CqType.SEND_CQ);
                } while(polled == 0);

                msgCount--;
            }

            endTime = System.nanoTime();
        } catch(Exception e) {
            Log.ERROR_AND_EXIT("CLIENT THREAD", "An error occurred, while sending or receiving a message!" +
                    " Error: '%s'", e.getMessage());
        }

        Log.INFO("CLIENT THREAD", "Finished pingpong test!");

        sendTime = endTime - startTime;

        Log.INFO("CLIENT THREAD", "Terminating thread...");
    }

    /**
     * Start the message benchmark as server
     *
     * The measured time in nanoseconds is stored in sendTime.
     *
     * @param connection The connection to use for the benchmarks
     * @param msgCount The amount of message to send and receive
     */
    void msgLatencyBenchmarkServer(Connection connection, long msgCount) {
        long startTime = 0;
        long endTime = 0;

        int polled;

        Log.INFO("SERVER THREAD", "Starting message latency server thread!");

        stats = new Stats((int) msgCount);

        try {
            connection.getSocket().getOutputStream().write("start".getBytes());

            startTime = System.nanoTime();

            while(msgCount > 0) {
                stats.start();

                // Send a single message and wait until a work completion is generated
                connection.sendMessages(1);

                do {
                    polled = connection.pollCompletionQueue(JVerbsWrapper.CqType.SEND_CQ);
                } while(polled == 0);

                stats.stop();

                msgCount--;
            }

            endTime = System.nanoTime();
        } catch(Exception e) {
            Log.ERROR_AND_EXIT("SERVER THREAD", "An error occurred, while sending or receiving a message!" +
                    " Error: '%s'", e.getMessage());
        }

        Log.INFO("SERVER THREAD", "Finished message latency test!");

        sendTime = endTime - startTime;

        Log.INFO("SERVER THREAD", "Terminating thread...");
    }

    /**
     * Start the message latency benchmark as client
     *
     * The measured time in nanoseconds is stored in sendTime.
     *
     * @param connection The connection to use for the benchmarks
     * @param msgCount The amount of message to send and receive
     */
    void msgLatencyBenchmarkClient(Connection connection, long msgCount) {
        long startTime = 0;
        long endTime = 0;

        int polled;
        int halfQueueSize = connection.getQueueSize() / 2;

        Log.INFO("CLIENT THREAD", "Starting message latency client thread!");

        try {
            // Fill receive queue to avoid HCA stalls
            connection.recvMessages(connection.getQueueSize());

            // Wait for start signal from server
            byte[] buf = new byte[5];
            DataInputStream stream = new DataInputStream(connection.getSocket().getInputStream());

            stream.readFully(buf);

            startTime = System.nanoTime();

            int batch = 0;

            while(msgCount > 0) {
                do {
                    polled = connection.pollCompletionQueue(JVerbsWrapper.CqType.RECV_CQ);
                } while(polled == 0);

                batch += polled;

                // Adding back single receive work requests seems to introduce a heavy
                // overhead slowing down sending on the remote side for some reason.
                // This is not a 1:1 copy of the c-verbs version but shouldn't matter for
                // the sending side as it still can't reach the performance of the
                // c-based implementation for whatever reason
                if (batch >= halfQueueSize) {
                    connection.recvMessages(halfQueueSize);
                    batch -= halfQueueSize;
                }

                msgCount -= polled;
            }

            endTime = System.nanoTime();
        } catch(Exception e) {
            Log.ERROR_AND_EXIT("CLIENT THREAD", "An error occurred, while sending or receiving a message!" +
                    " Error: '%s'", e.getMessage());
        }

        Log.INFO("CLIENT THREAD", "Finished message latency test!");

        sendTime = endTime - startTime;

        Log.INFO("CLIENT THREAD", "Terminating thread...");
    }

    /**
     * Start the RDMA write latency benchmark as server
     *
     * The measured time in nanoseconds is stored in sendTime.
     *
     * @param connection The connection to use for the benchmarks
     * @param msgCount The amount of message to send and receive
     */
    void rdmaWriteLatencyBenchmarkServer(Connection connection, long msgCount) {
        long startTime = 0;
        long endTime = 0;

        int polled;

        Log.INFO("SERVER THREAD", "Starting RDMA write latency server thread!");

        stats = new Stats((int) msgCount);

        try {
            startTime = System.nanoTime();

            while(msgCount > 0) {
                stats.start();

                // Send a single message and wait until a work completion is generated
                connection.rdmaWrite(1);

                do {
                    polled = connection.pollCompletionQueue(JVerbsWrapper.CqType.SEND_CQ);
                } while(polled == 0);

                stats.stop();

                msgCount--;
            }

            endTime = System.nanoTime();
        } catch(Exception e) {
            Log.ERROR_AND_EXIT("SERVER THREAD", "An error occurred, while sending or receiving a message!" +
                    " Error: '%s'", e.getMessage());
        }

        Log.INFO("SERVER THREAD", "Finished RDMA write latency test!");

        sendTime = endTime - startTime;

        Log.INFO("SEND THREAD", "Sending 'close'-command to remote host.");

        try {
            DataOutputStream outStream = new DataOutputStream(connection.getSocket().getOutputStream());

            outStream.write("close".getBytes());
        } catch (Exception e) {
            Log.ERROR_AND_EXIT("SEND THREAD", "An error occurred, while sending 'close'! Error: '%s'",
                    e.getMessage());
        }

        Log.INFO("SERVER THREAD", "Terminating thread...");
    }

    /**
     * Start the RDMA write latency benchmark as client
     *
     * The measured time in nanoseconds is stored in sendTime.
     *
     * @param connection The connection to use for the benchmarks
     * @param msgCount The amount of message to send and receive
     */
    void rdmaWriteLatencyBenchmarkClient(Connection connection, long msgCount) {
        long startTime = 0;
        long endTime = 0;

        int polled;
        byte[] buf = new byte[5];

        Log.INFO("CLIENT THREAD", "Starting RDMA write latency client thread!");

        startTime = System.nanoTime();

        try {
            DataInputStream inStream = new DataInputStream(connection.getSocket().getInputStream());

            inStream.readFully(buf);
        } catch (Exception e) {
            Log.ERROR_AND_EXIT("CLIENT THREAD", "An error occurred, while receiving 'close'! Error: '%s'",
                    e.getMessage());
        }

        endTime = System.nanoTime();

        Log.INFO("CLIENT THREAD", "Finished RDMA write latency test!");

        sendTime = endTime - startTime;

        Log.INFO("CLIENT THREAD", "Terminating thread...");
    }

    /**
     * Get the measured send time.
     */
    long getSendTime() {
        return sendTime;
    }

    /**
     * Get the measured receive time.
     */
    long getRecvTime() {
        return recvTime;
    }

    /**
     * Get the statistics measured
     */
    Stats getStatistics() {
        return stats;        
    }
}

