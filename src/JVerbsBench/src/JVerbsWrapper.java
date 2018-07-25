import com.ibm.net.rdma.jverbs.cm.*;
import com.ibm.net.rdma.jverbs.verbs.*;
import java.nio.ByteBuffer;
import java.util.HashMap;
import java.util.LinkedList;

/**
 * Wraps some of the JVerbs-functions and -classes.
 */
class JVerbsWrapper {

    /**
     * Size of the queue pair and completion queue.
     */
    private int queueSize;

    /**
     * Connection id for the connection to the remote host.
     *
     * Required to get the verbs context.
     */
    private ConnectionId connectionId;

    /**
     * JVerbs context.
     */
    private VerbsContext context;

    /**
     * The protection domain, in which all infiniband resources will be registered.
     */
    private ProtectionDomain protDom;

    /**
     * Completion channel (Unused, but required for the creation of a completion queue).
     */
    private CompletionChannel compChannel;

    /**
     * The completion queue.
     */
    private CompletionQueue compQueue;

    /**
     * The queue pair.
     */
    private QueuePair queuePair;

    /**
     * An array, which holds all work completions.
     */
    private WorkCompletion[] workComps;

    /**
     * Holds a PollCQMethod for every thread, that calls getPollCqMethod().
     *
     * PollCQMethod is a stateful verbs call. Stateful verbs calls can be reused, once they are initialized.
     *
     * Apparently, stateful verbs calls are NOT thread-safe. In my tests, I found out, that the benchmark crashes when
     * two threads use the same stateful verbs call.
     */
    private HashMap<Long, PollCQMethod> pollCqMethodMap;

    /**
     * Constructor.
     *
     * @param id The connection id, from which to get the context
     * @param queueSize Desired size of the queue pair and completion queue
     */
    JVerbsWrapper(ConnectionId id, int queueSize) throws Exception {
        this.queueSize = queueSize;

        // Get context
        this.connectionId = id;
        this.context = id.getVerbsContext();

        // Create protection domain
        protDom = context.allocProtectionDomain();

        // Create completion queue
        compChannel = context.createCompletionChannel();
        compQueue = context.createCompletionQueue(compChannel, queueSize, 0);

        // Create queue pair
        QueuePairInitAttribute attr = new QueuePairInitAttribute();
        attr.getCap().setMaxReceiveSge(1);
        attr.getCap().setMaxReceiveWorkRequest(queueSize);
        attr.getCap().setMaxSendSge(1);
        attr.getCap().setMaxSendWorkRequest(queueSize);
        attr.setQueuePairType(QueuePair.Type.IBV_QPT_RC);
        attr.setSendCompletionQueue(compQueue);
        attr.setReceiveCompletionQueue(compQueue);

        queuePair = id.createQueuePair(protDom, attr);

        // Create work completion list
        workComps = new WorkCompletion[queueSize];

        for(int i = 0; i < this.workComps.length; i++) {
            this.workComps[i] = new WorkCompletion();
        }

        pollCqMethodMap = new HashMap<>();
    }

    /**
     * Register a buffer as memory region.
     *
     * @param buffer The buffer to be registered
     *
     * @return The registered memory region
     */
    MemoryRegion registerMemoryRegion(ByteBuffer buffer) throws Exception {
        int accessFlags = MemoryRegion.IBV_ACCESS_LOCAL_WRITE  |
                          MemoryRegion.IBV_ACCESS_REMOTE_WRITE |
                          MemoryRegion.IBV_ACCESS_REMOTE_READ;

        return protDom.registerMemoryRegion(buffer, accessFlags).execute().getMemoryRegion();
    }

    /**
     * Deregister a memory region.
     *
     * @param region The region to be deregistered
     */
    void deregisterMemoryRegion(MemoryRegion region) throws Exception {
        protDom.deregisterMemoryRegion(region).execute();
    }

    /**
     * Get a stateful verbs call, that posts a list of work requests to the send queue.
     *
     * @param sendWrs The list of work requests to be posted
     *
     * @return The stateful verbs call
     */
    PostSendMethod getPostSendMethod(LinkedList<SendWorkRequest> sendWrs) throws Exception {
        PostSendMethod postSendMethod = queuePair.preparePostSend(sendWrs);

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
    PostReceiveMethod getPostReceiveMethod(LinkedList<ReceiveWorkRequest> recvWrs) throws Exception {
        PostReceiveMethod postReceiveMethod = queuePair.preparePostReceive(recvWrs);

        if(!postReceiveMethod.isValid()) {
            Log.ERROR_AND_EXIT("WRAPPER", "PostSendMethod invalid!");
        }

        return postReceiveMethod;
    }

    /**
     * Get a stateful verbs call, that can be used to poll the completion queue.
     *
     * @return The stateful verbs call
     */
    PollCQMethod getPollCqMethod() throws Exception {
        long threadId = Thread.currentThread().getId();

        if(!pollCqMethodMap.containsKey(threadId)) {
            pollCqMethodMap.put(threadId, compQueue.pollCQ(workComps, queueSize));
        }

        PollCQMethod pollCqMethod = pollCqMethodMap.get(threadId);

        if (!pollCqMethod.isValid()) {
            Log.ERROR_AND_EXIT("WRAPPER", "SendPollCqMethod invalid!");
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
    WorkCompletion[] getWorkCompletions() {
        return workComps;
    }

    /**
     * Destroy all JVerbs resources.
     */
    void destroy() throws Exception {
        for(PollCQMethod pollCqMethod : pollCqMethodMap.values()) {
            pollCqMethod.free();
        }

        pollCqMethodMap.clear();

        context.destroyCompletionQueue(compQueue);
        context.destroyCompletionChannel(compChannel);
        connectionId.destroyQueuePair();
        context.deallocProtectionDomain(protDom);
    }
}
