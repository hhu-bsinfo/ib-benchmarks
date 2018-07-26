import com.ibm.net.rdma.jverbs.cm.*;
import com.ibm.net.rdma.jverbs.verbs.*;

import java.io.DataInputStream;
import java.io.DataOutput;
import java.io.DataOutputStream;
import java.io.IOException;
import java.net.InetSocketAddress;
import java.net.ServerSocket;
import java.net.Socket;
import java.nio.ByteBuffer;
import java.util.LinkedList;
import java.util.Objects;
import java.util.StringTokenizer;

/**
 * Connection to a remote host.
 *
 * This class allows connecting to either a server or a client and send messages to the remote host.
 */
class Connection {

    /**
     * The send buffer.
     */
    private ByteBuffer sendBuf;

    /**
     * The receive buffer.
     */
    private ByteBuffer recvBuf;

    /**
     * The TCP-socket, that is used to exchange data with the remote host.
     */
    private Socket socket;

    /**
     * The jVerbs event channel.
     */
    private EventChannel eventChannel;

    /**
     * Parameters for a jVerbs connection.
     */
    private ConnectionParameter connectionParams;

    /**
     * The jVerbs connection id.
     */
    private ConnectionId id;

    /**
     * The size of the queue pair and completion queue.
     */
    private int queueSize;

    /**
     * The memory region, that is used for sending.
     */
    private MemoryRegion sendRegion;

    /**
     * The memory region, that is used for receiving.
     */
    private MemoryRegion recvRegion;

    /**
     * Wraps some of the JVerbs-functions and -objects.
     */
    private JVerbsWrapper wrapper;

    /**
     * The key of the remote host's receive memory region.
     */
    private int remoteKey;

    /**
     * The address of the remote host's receive memory region.
     */
    private long remoteAddress;

    /**
     * List of scatter-gather elements used for sending.
     */
    private LinkedList<ScatterGatherElement> sendSges;

    /**
     * List of scatter-gather elements used for receiving.
     */
    private LinkedList<ScatterGatherElement> recvSges;

    /**
     * Reusable send work requests.
     */
    private SendWorkRequest[] sendWrs;

    /**
     * Reusable receive work requests.
     */
    private ReceiveWorkRequest[] recvWrs;

    /**
     * List of send work requests.
     */
    private LinkedList<SendWorkRequest> sendWrList;

    /**
     * List of receive work requests.
     */
    private LinkedList<ReceiveWorkRequest> recvWrList;

    Connection(int bufSize, int queueSize) {
        Log.INFO("CONNECTION", "Creating connection...");

        this.sendBuf = ByteBuffer.allocateDirect(bufSize);
        this.recvBuf = ByteBuffer.allocateDirect(bufSize);

        this.connectionParams = new ConnectionParameter();
        this.connectionParams.setInitiatorDepth(1);
        this.connectionParams.setResponderResources(1);
        this.connectionParams.setRetryCount(7);

        this.queueSize = queueSize;

        this.sendSges = new LinkedList<>();
        this.recvSges = new LinkedList<>();

        this.sendWrs = new SendWorkRequest[queueSize];
        this.recvWrs = new ReceiveWorkRequest[queueSize];

        for(int i = 0; i < this.sendWrs.length; i++) {
            this.sendWrs[i] = new SendWorkRequest();
        }

        for(int i = 0; i < this.sendWrs.length; i++) {
            this.recvWrs[i] = new ReceiveWorkRequest();
        }

        this.sendWrList = new LinkedList<>();
        this.recvWrList = new LinkedList<>();

        try {
            this.eventChannel = EventChannel.createEventChannel();
        } catch (Exception e) {
            Log.ERROR_AND_EXIT("Unable to create event channel! Error: %s", e.getMessage());
        }

        Log.INFO("CONNECTION", "Finished creating connection!");
    }

    /**
     * Connect to a remote server.
     *
     * @param bindAddress The address to bind the socket to (may be null, or empty string)
     * @param hostname The server's hostname
     * @param port The TCP-port
     */
    void connectToServer(String bindAddress, String hostname, int port) {
        Log.INFO("CONNECTION", "Connecting to server '%s'...", hostname);

        // Create connection id
        try {
            id = ConnectionId.create(eventChannel, PortSpace.RDMA_PS_TCP);
        } catch (Exception e) {
            Log.ERROR_AND_EXIT("Unable to create connection id! Error: %s", e.getMessage());
        }

        // Resolve address
        try {
            if (bindAddress == null || bindAddress.isEmpty()) {
                id.resolveAddress(new InetSocketAddress(port), new InetSocketAddress(hostname, port), 5000);
            } else {
                id.resolveAddress(new InetSocketAddress(bindAddress, port),
                        new InetSocketAddress(hostname, port), 5000);
            }

            ConnectionEvent event = eventChannel.getConnectionEvent(-1);

            if(event.getEventType() != ConnectionEvent.EventType.RDMA_CM_EVENT_ADDR_RESOLVED) {
                Log.ERROR_AND_EXIT("CONNECTION",
                        "Unable to resolve address! Error: Received wrong event type '%s'", event.getEventType());
            }

            eventChannel.ackConnectionEvent(event);
        } catch (Exception e) {
            Log.ERROR_AND_EXIT("CONNECTION", "Unable to resolve address! Error: %s", e.getMessage());
        }

        Log.INFO("CONNECTION", "Successfully resolved address!");

        // Resolve route
        try {
            id.resolveRoute(5000);

            ConnectionEvent event = eventChannel.getConnectionEvent(-1);

            if(event.getEventType() != ConnectionEvent.EventType.RDMA_CM_EVENT_ROUTE_RESOLVED) {
                Log.ERROR_AND_EXIT("CONNECTION",
                        "Unable to resolve address! Error: Received wrong event type '%s'", event.getEventType());
            }

            eventChannel.ackConnectionEvent(event);
        } catch (Exception e) {
            Log.ERROR_AND_EXIT("CONNECTION", "Unable to resolve route! Error: %s", e.getMessage());
        }

        Log.INFO("CONNECTION", "Successfully resolved route!");

        // Establish connection
        try {
            wrapper = new JVerbsWrapper(id, queueSize);

            sendRegion = wrapper.registerMemoryRegion(sendBuf);
            recvRegion = wrapper.registerMemoryRegion(recvBuf);

            ScatterGatherElement sendSge = new ScatterGatherElement();
            sendSge.setAddress(sendRegion.getAddress());
            sendSge.setLength(sendRegion.getLength());
            sendSge.setLocalKey(sendRegion.getLocalKey());
            sendSges.add(sendSge);

            ScatterGatherElement recvSge = new ScatterGatherElement();
            recvSge.setAddress(recvRegion.getAddress());
            recvSge.setLength(recvRegion.getLength());
            recvSge.setLocalKey(recvRegion.getLocalKey());
            recvSges.add(recvSge);

            id.connect(connectionParams);

            ConnectionEvent event = eventChannel.getConnectionEvent(-1);

            if(event.getEventType() != ConnectionEvent.EventType.RDMA_CM_EVENT_ESTABLISHED) {
                Log.ERROR_AND_EXIT("CONNECTION",
                        "Unable to connect to remote host! Error: Received wrong event type '%s'",
                        event.getEventType());
            }

            eventChannel.ackConnectionEvent(event);
        } catch (Exception e) {
            Log.ERROR_AND_EXIT("CONNECTION", "Unable to connect to remote host! Error: %s", e.getMessage());
        }

        try {
            Thread.sleep(1000);
            socket = new Socket();

            if(bindAddress == null || bindAddress.isEmpty()) {
                socket.bind(new InetSocketAddress(port));
            } else {
                socket.bind(new InetSocketAddress(bindAddress, port));
            }

            socket.connect(new InetSocketAddress(hostname, port));
        } catch (Exception e) {
            Log.ERROR_AND_EXIT("CONNECTION", "Unable to open socket! Error: %s", e.getMessage());
        }

        exchangeRdmaInfo();

        Log.INFO("CONNECTION", "Successfully connected to remote host!");
    }

    /**
     * Connect to a remote client.
     *
     * @param bindAddress The address to bind the socket to (may be null, or empty string)
     * @param port The TCP-port to listen on
     */
    void connectToClient(String bindAddress, int port) {
        Log.INFO("CONNECTION", "Connecting to a client...");

        ConnectionId serverId = null;
        ServerSocket serverSocket = null;

        try {
            serverId = ConnectionId.create(eventChannel, PortSpace.RDMA_PS_TCP);
        } catch (Exception e) {
            Log.ERROR_AND_EXIT("Unable to create connection id! Error: %s", e.getMessage());
        }

        try {
            if (bindAddress == null || bindAddress.isEmpty()) {
                Objects.requireNonNull(serverId).bindAddress(new InetSocketAddress(port));
            } else {
                Objects.requireNonNull(serverId).bindAddress(new InetSocketAddress(bindAddress, port));
            }
        } catch (Exception e) {
            Log.ERROR_AND_EXIT("CONNECTION", "Unable to bind address! Error: %s", e.getMessage());
        }

        Log.INFO("CONNECTION", "Waiting for an incoming connection...");

        try {
            Objects.requireNonNull(serverId).listen(0);

            ConnectionEvent event = eventChannel.getConnectionEvent(-1);

            if(event.getEventType() != ConnectionEvent.EventType.RDMA_CM_EVENT_CONNECT_REQUEST) {
                Log.ERROR_AND_EXIT("CONNECTION",
                        "Error while accepting an incoming connection! Error: Received wrong event type '%s'",
                        event.getEventType());
            }

            eventChannel.ackConnectionEvent(event);

            id = event.getConnectionId();
        } catch (Exception e) {
            Log.ERROR_AND_EXIT("CONNECTION", "Error while accepting an incoming connection! Error: %s",
                    e.getMessage());
        }

        Log.INFO("CONNECTION", "Received connection request!");

        try {
            wrapper = new JVerbsWrapper(id, queueSize);

            sendRegion = wrapper.registerMemoryRegion(sendBuf);
            recvRegion = wrapper.registerMemoryRegion(recvBuf);

            ScatterGatherElement sendSge = new ScatterGatherElement();
            sendSge.setAddress(sendRegion.getAddress());
            sendSge.setLength(sendRegion.getLength());
            sendSge.setLocalKey(sendRegion.getLocalKey());
            sendSges.add(sendSge);

            ScatterGatherElement recvSge = new ScatterGatherElement();
            recvSge.setAddress(recvRegion.getAddress());
            recvSge.setLength(recvRegion.getLength());
            recvSge.setLocalKey(recvRegion.getLocalKey());
            recvSges.add(recvSge);

            id.accept(connectionParams);

            ConnectionEvent event = eventChannel.getConnectionEvent(-1);

            if (event.getEventType() != ConnectionEvent.EventType.RDMA_CM_EVENT_ESTABLISHED) {
                Log.ERROR_AND_EXIT("CONNECTION",
                        "Error while accepting an incoming connection! Error: Received wrong event type '%s'",
                        event.getEventType());
            }

            eventChannel.ackConnectionEvent(event);
        } catch(Exception e) {
            Log.ERROR_AND_EXIT("CONNECTION",
                    "Error while accepting an incoming connection! Error: Received wrong event type '%s'",
                    e.getMessage());
        }

        try {
            serverSocket = new ServerSocket();

            if(bindAddress == null || bindAddress.isEmpty()) {
                serverSocket.bind(new InetSocketAddress(port));
            } else {
                serverSocket.bind(new InetSocketAddress(bindAddress, port));
            }

            socket = Objects.requireNonNull(serverSocket).accept();
        } catch (Exception e) {
            Log.ERROR_AND_EXIT("CONNECTION", "Error while accepting an incoming connection! Error: %s",
                    e.getMessage());
        }

        exchangeRdmaInfo();

        Log.INFO("CONNECTION", "Successfully established a connection to a client!");
    }

    private void exchangeRdmaInfo() {
        try {
            DataInputStream inputStream = new DataInputStream(socket.getInputStream());
            DataOutputStream outputStream = new DataOutputStream(socket.getOutputStream());

            byte[] outputBuf = String.format("%08x:%016x", recvRegion.getRemoteKey(), recvRegion.getAddress()).getBytes();
            byte[] inputBuf = new byte[outputBuf.length];

            outputStream.write(outputBuf);
            inputStream.readFully(inputBuf);

            String[] data = new String(inputBuf).split(":");

            remoteKey = Integer.parseUnsignedInt(data[0], 16);
            remoteAddress = Long.parseUnsignedLong(data[1], 16);

            Log.INFO("CONNECTION", "Successfully exchanged rdma information with the remote host! " +
                    "Received: 0x%08x, 0x%016x", remoteKey, remoteAddress);
        } catch(Exception e) {
            Log.ERROR_AND_EXIT("CONNECTION",
                    "Unable to exchange rdma information with the remote host! Error: %s", e.getMessage());
        }
    }

    /**
     * Disconnect from the remote host.
     */
    void close() {
        Log.INFO("CONNECTION", "Closing connection...");

        try {
            socket.close();

            id.disconnect();

            ConnectionEvent event = eventChannel.getConnectionEvent(-1);

            if (event.getEventType() != ConnectionEvent.EventType.RDMA_CM_EVENT_DISCONNECTED) {
                Log.WARN("CONNECTION", "Error while disconnecting! Error: Received wrong event type '%s'",
                        event.getEventType());
            }

            eventChannel.ackConnectionEvent(event);

            wrapper.deregisterMemoryRegion(sendRegion);
            wrapper.deregisterMemoryRegion(recvRegion);
            wrapper.destroy();

            id.destroy();
            eventChannel.destroyEventChannel();
        } catch (Exception e) {
            Log.WARN("CONNECTION", "Unable to close connection! Error: %s", e.getMessage());

            return;
        }

        Log.INFO("CONNECTION", "Successfully closed connection!");
    }

    /**
     * Send a specified amount of messages to the remote host.
     *
     * @param msgCount The amount of messages to be sent
     *
     * @throws Exception DataOutputStream.write() may throw an Exception
     */
    void sendMessages(long msgCount) throws Exception {
        if(msgCount <= 0) {
            return;
        }

        sendWrList.clear();

        for(int i = 0; i < msgCount; i++) {
            sendWrs[i].setWorkRequestId(1);
            sendWrs[i].setSgeList(sendSges);
            sendWrs[i].setOpcode(SendWorkRequest.Opcode.IBV_WR_SEND);
            sendWrs[i].setSendFlags(SendWorkRequest.IBV_SEND_SIGNALED);

            sendWrList.add(sendWrs[i]);
        }

        PostSendMethod sendMethod = wrapper.getPostSendMethod(sendWrList);

        sendMethod.execute();

        if(!sendMethod.isSuccess()) {
            Log.ERROR_AND_EXIT("CONNECTION", "PostSendMethod failed!");
        }

        sendMethod.free();
    }

    /**
     * Receive a specified amount of messages from the remote host.
     *
     * @param msgCount The amount of messages to be sent
     */
    void recvMessages(long msgCount) throws Exception {
        if(msgCount <= 0) {
            return;
        }

        recvWrList.clear();

        for(int i = 0; i < msgCount; i++) {
            recvWrs[i].setWorkRequestId(1);
            recvWrs[i].setSgeList(recvSges);

            recvWrList.add(recvWrs[i]);
        }

        PostReceiveMethod receiveMethod = wrapper.getPostReceiveMethod(recvWrList);

        receiveMethod.execute();

        if(!receiveMethod.isSuccess()) {
            Log.ERROR_AND_EXIT("CONNECTION", "PostReceiveMethod failed!");
        }

        receiveMethod.free();
    }

    /**
     * Use RDMA to write a given amount of times to the remote host.
     *
     * @param count The amount of rdma writes to be performed
     */
    void rdmaWrite(long count) throws Exception {
        if(count <= 0) {
            return;
        }

        sendWrList.clear();

        for(int i = 0; i < count; i++) {
            sendWrs[i].setWorkRequestId(1);
            sendWrs[i].setSgeList(sendSges);
            sendWrs[i].setOpcode(SendWorkRequest.Opcode.IBV_WR_RDMA_WRITE);
            sendWrs[i].setSendFlags(SendWorkRequest.IBV_SEND_SIGNALED);
            sendWrs[i].getRdma().setRemoteAddress(remoteAddress);
            sendWrs[i].getRdma().setRemoteKey(remoteKey);

            sendWrList.add(sendWrs[i]);
        }

        PostSendMethod sendMethod = wrapper.getPostSendMethod(sendWrList);

        sendMethod.execute();

        if(!sendMethod.isSuccess()) {
            Log.ERROR_AND_EXIT("CONNECTION", "PostSendMethod failed!");
        }
    }

    /**
     * Poll completions from the completion queue.
     *
     * @return The amount of polled work completions
     */
    int pollCompletionQueue() throws Exception {
        PollCQMethod pollMethod = wrapper.getPollCqMethod();

        pollMethod.execute();

        if(!pollMethod.isSuccess()) {
            Log.ERROR_AND_EXIT("CONNECTION", "PollCQMethod failed!");
        }

        int polled = pollMethod.getPolls();

        WorkCompletion[] workComps = wrapper.getWorkCompletions();

        for(int i = 0; i < polled; i++) {
            if(workComps[i].getStatus() != WorkCompletion.Status.IBV_WC_SUCCESS) {
                Log.ERROR_AND_EXIT("CONNECTION", "Work completion failed! Status: " +
                        workComps[i].getStatus());
            }
        }

        return polled;
    }

    int getQueueSize() {
        return queueSize;
    }

    Socket getSocket() {
        return socket;
    }
}
