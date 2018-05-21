/**
 * @file connection.c
 * @author Fabian Ruhland, HHU
 * @date May 2018
 *
 * @brief Contains structs and functions to work with connections.
 */


#include <errno.h>
#include <string.h>
#include <unistd.h>
#include <arpa/inet.h>
#include <netdb.h>
#include <infiniband/verbs.h>
#include "connection.h"
#include "log.h"

void init_connection(connection* conn, ib_device *device, ib_prot_dom *prot_dom, ib_comp_queue *send_comp_queue,
                     ib_comp_queue *recv_comp_queue, ib_shared_recv_queue *recv_queue, uint64_t buf_size,
                     uint32_t queue_size) {
    LOG_INFO("CONNECTION", "Initializing connection...");

    conn->prot_dom = prot_dom;

    // Initialize queue pair
    conn->queue_pair = malloc(sizeof(ib_queue_pair));
    init_queue_pair(conn->queue_pair, prot_dom, send_comp_queue, recv_comp_queue, recv_queue, queue_size);

    conn->send_comp_queue = send_comp_queue;
    conn->recv_comp_queue = recv_comp_queue;

    // Initialize memory regions
    conn->send_mem_reg = malloc(sizeof(ib_mem_reg));
    init_mem_reg(conn->send_mem_reg, buf_size);

    conn->recv_mem_reg = malloc(sizeof(ib_mem_reg));
    init_mem_reg(conn->recv_mem_reg, buf_size);

    // Register memory regions
    register_memory_region(conn->prot_dom, conn->send_mem_reg);
    register_memory_region(conn->prot_dom, conn->recv_mem_reg);

    // Initialize scatter-gather elements
    conn->send_sge.addr = (uint64_t) conn->send_mem_reg->addr;
    conn->send_sge.length = (uint32_t) buf_size;
    conn->send_sge.lkey = conn->send_mem_reg->lkey;

    conn->recv_sge.addr = (uint64_t) conn->recv_mem_reg->addr;
    conn->recv_sge.length = (uint32_t) buf_size;
    conn->recv_sge.lkey = conn->recv_mem_reg->lkey;

    // Initialize work requests
    posix_memalign((void **) &conn->send_wrs, (size_t) getpagesize(), sizeof(struct ibv_send_wr) * queue_size);
    posix_memalign((void **) &conn->recv_wrs, (size_t) getpagesize(), sizeof(struct ibv_recv_wr) * queue_size);

    memset(conn->send_wrs, 0, sizeof(struct ibv_send_wr) * queue_size);
    memset(conn->recv_wrs, 0, sizeof(struct ibv_recv_wr) * queue_size);

    // Initialize the local connection information
    conn->local_conn_info.lid = device->lid;
    conn->local_conn_info.qpn = conn->queue_pair->qpn;
    conn->local_conn_info.rkey = conn->recv_mem_reg->rkey;
    conn->local_conn_info.remote_address = (uint64_t) conn->recv_mem_reg->addr;

    // Reset the remote connection information
    conn->remote_conn_info.lid = 0;
    conn->remote_conn_info.qpn = 0;
    conn->remote_conn_info.rkey = 0;
    conn->remote_conn_info.remote_address = 0;

    LOG_INFO("CONNECTION", "Finished initializing connection!");
}

void connect_to_server(connection *conn, const char *bind_address, const char *hostname, uint16_t port) {
    struct sockaddr_in server;
    struct hostent *he;
    char *ip_address;

    LOG_INFO("CONNECTION", "Connecting to server '%s'...", hostname);

    // Resolve hostname to an ip-address
    he = gethostbyname(hostname);

    if(he == NULL) {
        LOG_ERROR_AND_EXIT("CONNECTION", "Unable to resolve hostname '%s'", hostname);
    }

    ip_address = inet_ntoa(*((struct in_addr **)he->h_addr_list)[0]);

    LOG_INFO("CONNECTION", "Resolved IP-Address to '%s'", ip_address);

    // Set up the socket
    conn->remote_sockfd = socket(AF_INET, SOCK_STREAM, 0);

    if(conn->remote_sockfd == -1) {
        LOG_ERROR_AND_EXIT("CONNECTION", "Unable to open socket! Error: %s", strerror(errno));
    }

    setsockopt(conn->remote_sockfd, SOL_SOCKET, SO_REUSEADDR, NULL, 0);

    if(bind_address != NULL) {
        struct sockaddr_in local;

        local.sin_family = AF_INET;
        local.sin_addr.s_addr = inet_addr(bind_address);
        local.sin_port = 0;

        bind(conn->remote_sockfd, (struct sockaddr *) &local, sizeof(bind));
    }

    server.sin_family = AF_INET;
    server.sin_addr.s_addr = inet_addr(ip_address);
    server.sin_port = htons(port);

    // Connect to the server
    int ret = connect(conn->remote_sockfd, (struct sockaddr *) &server, sizeof(server));

    if(ret == -1) {
        LOG_ERROR_AND_EXIT("CONNECTION", "Unable to connect to server '%s'! Error: %s", hostname, strerror(errno));
    }

    LOG_INFO("CONNECTION", "Successfully established a TCP-connection to server '%s'!", hostname);

    // Exchange the infiniband connection information and set the queue to 'ready to send'
    __exchange_ib_connection_info(conn);

    set_qp_state_to_rtr(conn->queue_pair, conn->remote_conn_info.lid, conn->remote_conn_info.qpn);
    set_qp_state_to_rts(conn->queue_pair);
}

void connect_to_client(connection *conn, const char *bind_address, uint16_t port) {
    int sockfd;
    struct sockaddr_in server, client;

    LOG_INFO("CONNECTION", "Connecting to a client...");

    // Set up the socket
    sockfd = socket(AF_INET, SOCK_STREAM, 0);

    if(sockfd == -1) {
        LOG_ERROR_AND_EXIT("CONNECTION", "Unable to open socket! Error: %s", strerror(errno));
    }

    setsockopt(sockfd, SOL_SOCKET, SO_REUSEADDR, NULL, 0);

    server.sin_family = AF_INET;
    server.sin_addr.s_addr = bind_address == NULL ? INADDR_ANY : inet_addr(bind_address);
    server.sin_port = htons(port);

    int ret = bind(sockfd, (struct sockaddr *)&server, sizeof(server));

    if(ret == -1) {
        close(sockfd);
        LOG_ERROR_AND_EXIT("CONNECTION", "Unable to bind socket! Error: %s", strerror(errno));
    }

    LOG_INFO("CONNECTION", "Waiting for an incoming connection...");

    // Wait for a client to connect
    listen(sockfd, 1);

    int addr_len = sizeof(struct sockaddr_in);
    conn->remote_sockfd = accept(sockfd, (struct sockaddr *)&client, (socklen_t *) &addr_len);

    if(conn->remote_sockfd == -1) {
        close(sockfd);
        LOG_ERROR_AND_EXIT("CONNECTION", "Error while accepting an incoming connection! Error: %s", strerror(errno));
    }

    LOG_INFO("CONNECTION", "Successfully established a TCP-connection to a client!")

    // Exchange the infiniband connection information and set the queue to 'ready to send'
    __exchange_ib_connection_info(conn);

    close(sockfd);

    set_qp_state_to_rtr(conn->queue_pair, conn->remote_conn_info.lid, conn->remote_conn_info.qpn);
    set_qp_state_to_rts(conn->queue_pair);
}

void close_connection(connection *conn) {
    LOG_INFO("CONNECTION", "Closing connection...");

    // Free all resources
    deregister_memory_region(conn->prot_dom, conn->send_mem_reg);
    deregister_memory_region(conn->prot_dom, conn->recv_mem_reg);

    free(conn->send_mem_reg->addr);
    free(conn->recv_mem_reg->addr);

    free(conn->send_mem_reg);
    free(conn->recv_mem_reg);

    free(conn->send_wrs);
    free(conn->recv_wrs);

    close_queue_pair(conn->queue_pair);
    free(conn->queue_pair);

    close(conn->remote_sockfd);

    conn->prot_dom = NULL;
    conn->send_comp_queue = NULL;
    conn->recv_comp_queue = NULL;
    conn->queue_pair = NULL;
    conn->send_mem_reg = NULL;
    conn->recv_mem_reg = NULL;
    conn->send_wrs = NULL;
    conn->recv_wrs = NULL;
    conn->remote_sockfd = 0;

    LOG_INFO("CONNECTION", "Successfully closed connection!");
}

void msg_send(connection *conn, uint32_t amount) {
    struct ibv_send_wr *bad_wr;

    if(amount == 0) {
        return;
    }

    for(uint32_t i = 0; i < amount; i++) {
        conn->send_wrs[i].wr_id = 0; // An id can be assigned to each work request. As we don't use it,
                                     // we just set it to 0.
        conn->send_wrs[i].sg_list = &conn->send_sge; // The scatter-gather element, that points to our send buffer
        conn->send_wrs[i].num_sge = 1; // We only have a single scatter-gather-element per work request
        conn->send_wrs[i].opcode = IBV_WR_SEND; // Opcode for sending messages
        conn->send_wrs[i].send_flags = IBV_SEND_SIGNALED; // Generate a work completion for every work request
        conn->send_wrs[i].next = i < amount - 1 ? &conn->send_wrs[i + 1] : NULL; // Chain work requests, so we can post
                                                                                 // all at once
    }

    // Post the work requests to the send queue
    int ret = ibv_post_send(conn->queue_pair->qp, conn->send_wrs, &bad_wr);

    if(ret != 0) {
        LOG_ERROR_AND_EXIT("CONNECTION", "Error while posting send work requests! Error: %s", strerror(ret));
    }
}

void msg_recv(connection *conn, uint32_t amount) {
    struct ibv_recv_wr *bad_wr;

    if(amount == 0) {
        return;
    }

    for(uint32_t i = 0; i < amount; i++) {
        conn->recv_wrs[i].wr_id = 0; // An id can be assigned to each work request. As we don't use it,
                                     // we just set it to 0.
        conn->recv_wrs[i].sg_list = &conn->recv_sge; // The scatter-gather element, that points to our receive buffer
        conn->recv_wrs[i].num_sge = 1; // We only have a single scatter-gather-element per work request
        conn->recv_wrs[i].next = i < amount - 1 ? &conn->recv_wrs[i + 1] : NULL; // Chain work requests, so we can post
                                                                                 // all at once
    }

    // Post the work requests to the receive queue
    int ret = ibv_post_recv(conn->queue_pair->qp, conn->recv_wrs, &bad_wr);

    if(ret != 0) {
        LOG_ERROR_AND_EXIT("CONNECTION", "Error while posting receive work requests! Error: %s", strerror(ret));
    }
}

void rdma_write(connection *conn, uint32_t amount) {
    struct ibv_send_wr *bad_wr;

    if(amount == 0) {
        return;
    }

    for(uint32_t i = 0; i < amount; i++) {
        conn->send_wrs[i].wr_id = 0; // An id can be assigned to each work request. As we don't use it,
                                     // we just set it to 0.
        conn->send_wrs[i].sg_list = &conn->send_sge; // The scatter-gather element, that points to our send buffer
        conn->send_wrs[i].num_sge = 1; // We only have a single scatter-gather-element per work request
        conn->send_wrs[i].opcode = IBV_WR_RDMA_WRITE; // Opcode for writing via RDMA
        conn->send_wrs[i].send_flags = IBV_SEND_SIGNALED; // Generate a work completion for every work request
        conn->send_wrs[i].wr.rdma.remote_addr = conn->remote_conn_info.remote_address; // Address of the memory region
                                                                                       // on the remote host
        conn->send_wrs[i].wr.rdma.rkey = conn->remote_conn_info.rkey; // Remote key of the remote memory region
        conn->send_wrs[i].next = i < amount - 1 ? &conn->send_wrs[i + 1] : NULL; // Chain work requests, so we can post
                                                                                 // all at once
    }

    // Post the work requests to the send queue
    int ret = ibv_post_send(conn->queue_pair->qp, conn->send_wrs, &bad_wr);

    if(ret != 0) {
        LOG_ERROR_AND_EXIT("CONNECTION", "Error while posting rdma write work requests! Error: %s", strerror(ret));
    }
}

void __exchange_ib_connection_info(connection *conn) {
    char msg[sizeof("0000:00000000:00000000:0000000000000000")];

    LOG_INFO("CONNECTION", "Exchanging infiniband connection info...");

    // Create a string, which contains the local ib connection info
    sprintf(msg, "%04hx:%08x:%08x:%016lx", conn->local_conn_info.lid, conn->local_conn_info.qpn,
            conn->local_conn_info.rkey, conn->local_conn_info.remote_address);

    // Write the info-string
    if(write(conn->remote_sockfd, msg, sizeof(msg)) != sizeof(msg)) {
        LOG_ERROR_AND_EXIT("CONNECTION", "Error while sending the infiniband connection info!");
    }

    // Read the remote connection's info-string
    if(read(conn->remote_sockfd, msg, sizeof(msg)) != sizeof(msg)) {
        LOG_ERROR_AND_EXIT("CONNECTION", "Error while receiving the remote infiniband connection info!");
    }

    // Parse the received information string
    if(sscanf(msg, "%hx:%x:%x:%lx", &conn->remote_conn_info.lid, &conn->remote_conn_info.qpn,
              &conn->remote_conn_info.rkey, &conn->remote_conn_info.remote_address) != 4) {
        LOG_ERROR_AND_EXIT("CONNECTION", "Error while parsing the received infiniband connection info!")
    }

    LOG_INFO("CONNECTION", "Successfully exchanged infiniband connection info! Received Lid: 0x%04x, Qpn: 0x%08x, "
                           "Rkey: 0x%08x, Remote address: 0x%016lx", conn->remote_conn_info.lid,
             conn->remote_conn_info.qpn, conn->remote_conn_info.rkey, conn->remote_conn_info.remote_address);
}