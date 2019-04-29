import com.ibm.disni.verbs.*;

import java.io.DataInputStream;
import java.io.DataOutputStream;
import java.io.IOException;
import java.net.InetSocketAddress;
import java.net.ServerSocket;
import java.net.Socket;
import java.nio.ByteBuffer;
import java.util.LinkedList;
import java.util.Objects;

/**
 * Connection to a remote host.
 *
 * This class allows connecting to either a server or a client and send messages to the remote host.
 *
 * @author Fabian Ruhland, HHU
 * @date 2019
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
    private RdmaEventChannel eventChannel;

    /**
     * Parameters for a jVerbs connection.
     */
    private RdmaConnParam connectionParams;

    /**
     * The connection id.
     */
    private RdmaCmId id;

    /**
     * The size of the queue pair and completion queue.
     */
    private int queueSize;

    /**
     * The memory region, that is used for sending.
     */
    private IbvMr sendRegion;

    /**
     * The memory region, that is used for receiving.
     */
    private IbvMr recvRegion;

    /**
     * Wraps some of the JVerbs-functions and -objects.
     */
    private VerbsWrapper wrapper;

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
    private LinkedList<IbvSge> sendSges;

    /**
     * List of scatter-gather elements used for receiving.
     */
    private LinkedList<IbvSge> recvSges;

    /**
     * Reusable send work requests.
     */
    private IbvSendWR[] sendWrs;

    /**
     * Reusable receive work requests.
     */
    private IbvRecvWR[] recvWrs;

    /**
     * List of send work requests.
     */
    private LinkedList<IbvSendWR> sendWrList;

    /**
     * List of receive work requests.
     */
    private LinkedList<IbvRecvWR> recvWrList;

    /**
     * Create a connection.
     *
     * @param bufSize The size to be used for sendBuf and recvBuf
     * @param queueSize The queue size to be used for the InfiniBand queue pairs
     */
    Connection(int bufSize, int queueSize) {
        Log.INFO("CONNECTION", "Creating connection...");

        this.sendBuf = ByteBuffer.allocateDirect(bufSize);
        this.recvBuf = ByteBuffer.allocateDirect(bufSize);

        this.connectionParams = new RdmaConnParam();

        try {
            this.connectionParams.setInitiator_depth((byte) 1);
            this.connectionParams.setResponder_resources((byte) 1);
            this.connectionParams.setRetry_count((byte) 3);
            this.connectionParams.setRnr_retry_count((byte) 3);
        } catch (IOException e) {
            Log.WARN("CONNETION", "");
        }

        this.queueSize = queueSize;

        this.sendSges = new LinkedList<>();
        this.recvSges = new LinkedList<>();

        this.sendWrs = new IbvSendWR[queueSize];
        this.recvWrs = new IbvRecvWR[queueSize];

        for(int i = 0; i < this.sendWrs.length; i++) {
            this.sendWrs[i] = new IbvSendWR();
        }

        for(int i = 0; i < this.sendWrs.length; i++) {
            this.recvWrs[i] = new IbvRecvWR();
        }

        this.sendWrList = new LinkedList<>();
        this.recvWrList = new LinkedList<>();

        try {
            this.eventChannel = RdmaEventChannel.createEventChannel();
        } catch (IOException e) {
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
        /*Log.INFO("CONNECTION", "Connecting to server '%s'...", hostname);

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

        Log.INFO("CONNECTION", "Successfully connected to remote host!");*/
    }

    /**
     * Connect to a remote client.
     *
     * @param bindAddress The address to bind the socket to (may be null, or empty string)
     * @param port The TCP-port to listen on
     */
    void connectToClient(String bindAddress, int port) {
        Log.INFO("CONNECTION", "Connecting to a client...");

        RdmaCmId serverId = null;
        ServerSocket serverSocket = null;

        try {
            serverId = eventChannel.createId(RdmaCm.RDMA_PS_TCP);
        } catch (Exception e) {
            Log.ERROR_AND_EXIT("Unable to create connection id! Error: %s", e.getMessage());
        }

        try {
            if (bindAddress == null || bindAddress.isEmpty()) {
                Objects.requireNonNull(serverId).bindAddr(new InetSocketAddress(port));
            } else {
                Objects.requireNonNull(serverId).bindAddr(new InetSocketAddress(bindAddress, port));
            }
        } catch (IOException | NullPointerException e) {
            Log.ERROR_AND_EXIT("CONNECTION", "Unable to bind address! Error: %s", e.getMessage());
        }

        Log.INFO("CONNECTION", "Waiting for an incoming connection...");

        try {
            Objects.requireNonNull(serverId).listen(0);

            RdmaCmEvent event = eventChannel.getCmEvent(-1);

            if(event.getEvent() != RdmaCmEvent.EventType.RDMA_CM_EVENT_CONNECT_REQUEST.ordinal()) {
                Log.ERROR_AND_EXIT("CONNECTION",
                        "Error while accepting an incoming connection! Error: Received wrong event type '%d'",
                        event.getEvent());
            }

            event.ackEvent();

            id = event.getConnIdPriv();
        } catch (Exception e) {
            Log.ERROR_AND_EXIT("CONNECTION", "Error while accepting an incoming connection! Error: %s",
                    e.getMessage());
        }

        Log.INFO("CONNECTION", "Received connection request!");

        try {
            wrapper = new VerbsWrapper(id, queueSize);

            sendRegion = wrapper.registerMemoryRegion(sendBuf);
            recvRegion = wrapper.registerMemoryRegion(recvBuf);

            IbvSge sendSge = new IbvSge();
            sendSge.setAddr(sendRegion.getAddr());
            sendSge.setLength(sendRegion.getLength());
            sendSge.setLkey(sendRegion.getLkey());
            sendSges.add(sendSge);

            IbvSge recvSge = new IbvSge();
            recvSge.setAddr(recvRegion.getAddr());
            recvSge.setLength(recvRegion.getLength());
            recvSge.setLkey(recvRegion.getLkey());
            recvSges.add(recvSge);

            id.accept(connectionParams);

            RdmaCmEvent event = eventChannel.getCmEvent(-1);

            if (event.getEvent() != RdmaCmEvent.EventType.RDMA_CM_EVENT_ESTABLISHED.ordinal()) {
                Log.ERROR_AND_EXIT("CONNECTION",
                        "Error while accepting an incoming connection! Error: Received wrong event type '%d'",
                        event.getEvent());
            }

            event.ackEvent();
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

    /**
     * Exchange the address and remote key of the receive memory regions with the remote host, so that rdma can be used.
     */
    private void exchangeRdmaInfo() {
        try {
            DataInputStream inputStream = new DataInputStream(socket.getInputStream());
            DataOutputStream outputStream = new DataOutputStream(socket.getOutputStream());

            byte[] outputBuf = String.format("%08x:%016x", recvRegion.getRkey(), recvRegion.getAddr()).getBytes();
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

            RdmaCmEvent event = eventChannel.getCmEvent(-1);

            if (event.getEvent() != RdmaCmEvent.EventType.RDMA_CM_EVENT_DISCONNECTED.ordinal()) {
                Log.WARN("CONNECTION", "Error while disconnecting! Error: Received wrong event type '%d'",
                        event.getEvent());
            }

            event.ackEvent();

            wrapper.destroy();

            id.disconnect();
            id.destroyId();

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
    void sendMessages(long msgCount) throws IOException {
        if(msgCount <= 0) {
            return;
        }

        sendWrList.clear();

        for(int i = 0; i < msgCount; i++) {
            sendWrs[i].setWr_id(1);
            sendWrs[i].setSg_list(sendSges);
            sendWrs[i].setOpcode(IbvSendWR.IBV_WR_SEND);
            sendWrs[i].setSend_flags(IbvSendWR.IBV_SEND_SIGNALED);

            sendWrList.add(sendWrs[i]);
        }

        SVCPostSend sendMethod = wrapper.getPostSendMethod(sendWrList);

        sendMethod.execute();
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
            recvWrs[i].setWr_id(1);
            recvWrs[i].setSg_list(recvSges);

            recvWrList.add(recvWrs[i]);
        }

        SVCPostRecv receiveMethod = wrapper.getPostReceiveMethod(recvWrList);

        receiveMethod.execute();
    }

    /**
     * Use RDMA to write a given amount of times to the remote host.
     *
     * @param count The amount of rdma writes to be performed
     */
    void rdmaWrite(long count) throws IOException {
        if(count <= 0) {
            return;
        }

        sendWrList.clear();

        for(int i = 0; i < count; i++) {
            sendWrs[i].setWr_id(1);
            sendWrs[i].setSg_list(sendSges);
            sendWrs[i].setOpcode(IbvSendWR.IBV_WR_RDMA_WRITE);
            sendWrs[i].setSend_flags(IbvSendWR.IBV_SEND_SIGNALED);
            sendWrs[i].getRdma().setRemote_addr(remoteAddress);
            sendWrs[i].getRdma().setRkey(remoteKey);

            sendWrList.add(sendWrs[i]);
        }

        SVCPostSend sendMethod = wrapper.getPostSendMethod(sendWrList);

        sendMethod.execute();
    }

    /**
     * Use RDMA to read a given amount of times from the remote host.
     *
     * @param count The amount of rdma reads to be performed
     */
    void rdmaRead(long count) throws IOException {
        if(count <= 0) {
            return;
        }

        sendWrList.clear();

        for(int i = 0; i < count; i++) {
            sendWrs[i].setWr_id(1);
            sendWrs[i].setSg_list(sendSges);
            sendWrs[i].setOpcode(IbvSendWR.IBV_WR_RDMA_READ);
            sendWrs[i].setSend_flags(IbvSendWR.IBV_SEND_SIGNALED);
            sendWrs[i].getRdma().setRemote_addr(remoteAddress);
            sendWrs[i].getRdma().setRkey(remoteKey);

            sendWrList.add(sendWrs[i]);
        }

        SVCPostSend sendMethod = wrapper.getPostSendMethod(sendWrList);

        sendMethod.execute();
    }

    /**
     * Poll completions from the completion queue.
     *
     * @return The amount of polled work completions
     */
    int pollCompletionQueue(VerbsWrapper.CqType type) throws IOException {
        SVCPollCq pollMethod = wrapper.getPollCqMethod(type);

        pollMethod.execute();

        int polled = pollMethod.getPolls();

        IbvWC[] workComps = wrapper.getWorkCompletions();

        for(int i = 0; i < polled; i++) {
            if(workComps[i].getStatus() != IbvWC.IbvWcStatus.IBV_WC_SUCCESS.ordinal()) {
                Log.ERROR_AND_EXIT("CONNECTION", "Work completion failed! Status: %d" +
                        workComps[i].getStatus());
            }
        }

        return polled;
    }

    /**
     * Get the queue size of the InfiniBand queue pairs.
     */
    int getQueueSize() {
        return queueSize;
    }

    /**
     * Get the socket, that is used to exchange the rdma parameters.
     */
    Socket getSocket() {
        return socket;
    }
}
