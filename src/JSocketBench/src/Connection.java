import java.io.*;
import java.net.*;
import java.util.Objects;

/**
 * TCP-connection to a remote host.
 *
 * This class allows connecting to either a server or a client and send messages to the remote host.
 */
class Connection {

    /**
     * The send buffer.
     */
    private byte[] sendBuf;

    /**
     * The receive buffer.
     */
    private byte[] recvBuf;

    /**
     * The TCP-socket, that is used to exchange data with the remote host.
     */
    private Socket socket;

    /**
     * The socket's output stream.
     */
    private DataOutputStream outputStream;

    /**
     * The socket's input stream.
     */
    private DataInputStream inputStream;

    /**
     * Create a connection.
     *
     * @param bufSize The size to be used for sendBuf and recvBuf
     */
    Connection(int bufSize) {
        Log.INFO("CONNECTION", "Creating connection...");

        sendBuf = new byte[bufSize];
        recvBuf = new byte[bufSize];

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

        try {
            socket = new Socket();

            if(bindAddress == null || bindAddress.isEmpty()) {
                socket.bind(new InetSocketAddress(port));
            } else {
                socket.bind(new InetSocketAddress(bindAddress, port));
            }

            socket.connect(new InetSocketAddress(hostname, port));
        } catch (IOException e) {
            Log.ERROR_AND_EXIT("CONNECTION", "Unable to open socket! Error: %s", e.getMessage());
        }

        try {
            inputStream = new DataInputStream(socket.getInputStream());
            outputStream = new DataOutputStream(socket.getOutputStream());
        } catch (IOException e) {
            Log.ERROR_AND_EXIT("CONNECTION", "Unable to open data streams! Error: %s", e.getMessage());
        }

        Log.INFO("CONNECTION", "Successfully established a TCP-connection to server '%s'!", hostname);
    }

    /**
     * Connect to a remote client.
     *
     * @param bindAddress The address to bind the socket to (may be null, or empty string)
     * @param port The TCP-port to listen on
     */
    void connectToClient(String bindAddress, int port) {
        ServerSocket serverSocket = null;

        Log.INFO("CONNECTION", "Connecting to a client...");

        try {
            serverSocket = new ServerSocket();

            if(bindAddress == null || bindAddress.isEmpty()) {
                serverSocket.bind(new InetSocketAddress(port));
            } else {
                serverSocket.bind(new InetSocketAddress(bindAddress, port));
            }
        } catch (IOException e) {
            Log.ERROR_AND_EXIT("CONNECTION", "Unable to open socket! Error: %s", e.getMessage());
        }



        Log.INFO("CONNECTION", "Waiting for an incoming connection...");

        try {
            socket = Objects.requireNonNull(serverSocket).accept();
        } catch (Exception e) {
            Log.ERROR_AND_EXIT("CONNECTION", "Error while accepting an incoming connection! Error: %s",
                    e.getMessage());
        }

        try {
            inputStream = new DataInputStream(socket.getInputStream());
            outputStream = new DataOutputStream(socket.getOutputStream());
        } catch (IOException e) {
            Log.ERROR_AND_EXIT("CONNECTION", "Unable to open data streams! Error: %s", e.getMessage());
        }

        Log.INFO("CONNECTION", "Successfully established a TCP-connection to a client!");
    }

    /**
     * Disconnect from the remote host.
     */
    void close() {
        Log.INFO("CONNECTION", "Closing connection...");

        try {
            Thread.sleep(1000);

            outputStream.close();
            inputStream.close();
            socket.close();
        } catch (Exception e) {
            Log.WARN("CONNECTION", "Unable to close socket! Errors: %s", e.getMessage());
        }

        Log.INFO("CONNECTION", "Successfully closed connection!");
    }

    /**
     * Send a specified amount of messages to the remote host.
     *
     * @param msgCount The amount of messages to be sent
     *
     * @throws IOException DataOutputStream.write() may throw an IOException
     */
    void sendMessages(long msgCount) throws IOException {
        for(int i = 0; i < msgCount; i++) {
            outputStream.write(sendBuf);
        }

        outputStream.flush();
        socket.getOutputStream().flush();
    }

    /**
     * Receive a specified amount of messages from the remote host.
     *
     * @param msgCount The amount of messages to be sent
     *
     * @throws IOException DataOutputStream.write() may throw an IOException
     */
    void recvMessages(long msgCount) throws IOException {
        for(int i = 0; i < msgCount; i++) {
            inputStream.readFully(recvBuf);
        }
    }
}
