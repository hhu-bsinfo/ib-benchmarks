import com.ibm.disni.verbs.*;

import java.io.IOException;
import java.nio.ByteBuffer;
import java.util.HashMap;
import java.util.LinkedList;

/**
 * Wraps some of the Disni-functions and -classes.
 *
 * @author Fabian Ruhland, HHU
 * @date 2019
 */
class VerbsWrapper {

    /**
     * Size of the queue pair and completion queue.
     */
    private int queueSize;

    /**
     * Connection id for the connection to the remote host.
     *
     * Required to get the verbs context.
     */
    private RdmaCmId connectionId;

    /**
     * JVerbs context.
     */
    private IbvContext context;

    /**
     * The protection domain, in which all infiniband resources will be registered.
     */
    private IbvPd protDom;

    /**
     * Send Completion channel (Unused, but required for the creation of a completion queue).
     */
    private IbvCompChannel sendCompChannel;

    /**
     * Receive Completion channel (Unused, but required for the creation of a completion queue).
     */
    private IbvCompChannel recvCompChannel;

    /**
     * The send completion queue.
     */
    private IbvCQ sendCompQueue;

    /**
     * The receive completion queue.
     */
    private IbvCQ recvCompQueue;

    /**
     * The queue pair.
     */
    private IbvQP queuePair;

    /**
     * An array, which holds all work completions.
     */
    private IbvWC[] workComps;

    /**
     * Stateful Verbs Method for posting Send Work Requests.
     */
    private SVCPostSend postSendMethod;

    /**
     * Stateful Verbs Method for posting Receive Work Requests.
     */
    private SVCPostRecv postReceiveMethod;

    /**
     * Amount of last posted send work requests.
     */
    private int lastSend;

    /**
     * Amount of last posted receive work requests.
     */
    private int lastReceive;

    /**
     * Stateful Verbs Method for polling the send completion queue.
     */
    private SVCPollCq sendCqMethod;

    /**
     * Stateful Verbs Method for polling the receive completion queue.
     */
    private SVCPollCq recvCqMethod;

    /**
     * Used by Connection.pollCompletionQueue(JVerbsWrapper.CqType type) to determine whether
     * the send or the completion queue shall be polled.
     */
    enum CqType {
        SEND_CQ,    /**< Send completion queue */
        RECV_CQ     /**< Receive completion queue */
    }

    /**
     * Constructor.
     *
     * @param id The connection id, from which to get the context
     * @param queueSize Desired size of the queue pair and completion queue
     */
    VerbsWrapper(RdmaCmId id, int queueSize) throws Exception {
        this.queueSize = queueSize;

        // Get context
        this.connectionId = id;
        this.context = id.getVerbs();

        // Create protection domain
        protDom = context.allocPd();

        // Create send completion queue
        sendCompChannel = context.createCompChannel();
        sendCompQueue = context.createCQ(sendCompChannel, queueSize, 0);

        // Create receive completion queue
        recvCompChannel = context.createCompChannel();
        recvCompQueue = context.createCQ(recvCompChannel, queueSize, 0);

        // Create queue pair
        IbvQPInitAttr attr = new IbvQPInitAttr();
        attr.cap().setMax_recv_sge(1);
        attr.cap().setMax_recv_wr(queueSize);
        attr.cap().setMax_send_sge(1);
        attr.cap().setMax_send_wr(queueSize);
        attr.setQp_type(IbvQP.IBV_QPT_RC);
        attr.setSend_cq(sendCompQueue);
        attr.setRecv_cq(recvCompQueue);

        queuePair = id.createQP(protDom, attr);

        // Create work completion list
        workComps = new IbvWC[queueSize];

        for(int i = 0; i < this.workComps.length; i++) {
            this.workComps[i] = new IbvWC();
        }

        lastSend = -1;
        lastReceive = -1;
    }

    /**
     * Register a buffer as memory region.
     *
     * @param buffer The buffer to be registered
     *
     * @return The registered memory region
     */
    IbvMr registerMemoryRegion(ByteBuffer buffer) throws Exception {
        int accessFlags = IbvMr.IBV_ACCESS_LOCAL_WRITE  |
                IbvMr.IBV_ACCESS_REMOTE_WRITE |
                IbvMr.IBV_ACCESS_REMOTE_READ;

        return protDom.regMr(buffer, accessFlags).execute().free().getMr();
    }

    /**
     * Get a stateful verbs call, that posts a list of work requests to the send queue.
     *
     * @param sendWrs The list of work requests to be posted
     *
     * @return The stateful verbs call
     */
    SVCPostSend getPostSendMethod(LinkedList<IbvSendWR> sendWrs) throws IOException {
        if(lastSend != sendWrs.size()) {
            lastSend = sendWrs.size();

            if(postSendMethod != null) {
                postSendMethod.free();
            }

            postSendMethod = queuePair.postSend(sendWrs, null);
        }

        if(!postSendMethod.isValid()) {
            Log.ERROR_AND_EXIT("WRAPPER", "PostSendMethod invalid!");
        }

        return postSendMethod;
    }

    /**
     * Get a stateful verbs call, that posts a list of work requests to the recv queue.
     *
     * @param recvWrs The list of work requests to be posted
     *
     * @return The stateful verbs call
     */
    SVCPostRecv getPostReceiveMethod(LinkedList<IbvRecvWR> recvWrs) throws IOException {
        if(lastReceive != recvWrs.size()) {
            lastReceive = recvWrs.size();

            if(postReceiveMethod != null) {
                postReceiveMethod.free();
            }

            postReceiveMethod = queuePair.postRecv(recvWrs, null);
        }

        if(!postReceiveMethod.isValid()) {
            Log.ERROR_AND_EXIT("WRAPPER", "PostReceiveMethod invalid!");
        }

        return postReceiveMethod;
    }

    /**
     * Get a stateful verbs call, that can be used to poll the completion queue.
     *
     * @param type Whether to poll the send or the receive completion queue
     *
     * @return The stateful verbs call
     */
    SVCPollCq getPollCqMethod(CqType type) throws IOException {
        SVCPollCq pollCqMethod;

        if(type == CqType.SEND_CQ) {
            if(sendCqMethod == null) {
                sendCqMethod = sendCompQueue.poll(workComps, queueSize);
            }

            pollCqMethod = sendCqMethod;
        } else {
            if(recvCqMethod == null) {
                recvCqMethod = recvCompQueue.poll(workComps, queueSize);
            }

            pollCqMethod = recvCqMethod;
        }

        if (!pollCqMethod.isValid()) {
            Log.ERROR_AND_EXIT("WRAPPER", "PollCqMethod invalid!");
        }

        return pollCqMethod;
    }

    /**
     * Get the work completion array.
     *
     * Can be used to retrieve the work completion after the completion queue has been polled.
     *
     * @return The work completions
     */
    IbvWC[] getWorkCompletions() {
        return workComps;
    }

    /**
     * Destroy all JVerbs resources.
     */
    void destroy() throws Exception {
        postSendMethod.free();
        postSendMethod.free();
        sendCqMethod.free();
        recvCqMethod.free();

        sendCompQueue.destroyCQ();
        recvCompQueue.destroyCQ();
        sendCompChannel.destroyCompChannel();
        recvCompChannel.destroyCompChannel();
        connectionId.destroyQP();
        protDom.deallocPd();
    }
}
