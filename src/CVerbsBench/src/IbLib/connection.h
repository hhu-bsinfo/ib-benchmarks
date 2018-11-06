/**
 * @file connection.h
 * @author Fabian Ruhland, HHU
 * @date 2018
 *
 * @brief Contains structs and functions to work with connections.
 */

#ifndef CONNECTION_H
#define CONNECTION_H

#include "ib_queue_pair.h"

/**
 * Information about a host.
 *
 * Every host creates an instance of this struct and fills it with it's local information.
 * These information are then send to a remote host via TCP.
 */
typedef struct ib_connection_info {
    uint16_t lid; /**< The host's local id */
    uint32_t qpn; /**< The host's queue pair number */

    uint32_t rkey; /**< The remote key of a memory region in the host's memory (only relevant for RDMA) */
    uint64_t remote_address; /**< The address of the memory region that the remote key belongs to
                              *   (only relevant for RDMA) */
} ib_connection_info;

/**
 * Structure for a connection with a remote host.
 *
 * A connection always has a single queue pair, which gets connected with a remote queue pair.
 * It also has pointers to a memory region for sending and another one for receiving messages.
 * It is possible to use a shared receive queue and to use the same completion queue for multiple connections.
 */
typedef struct connection {
    int remote_sockfd; /**< TCP-socket, that is used to exchange the infiniband connection information */

    ib_prot_dom *prot_dom; /**< The protection domain, in which the queue pair and the memory regions are created */
    ib_comp_queue *send_comp_queue; /**< The completion queue for send work requests */
    ib_comp_queue *recv_comp_queue; /**< The completion queue for receive work requests */

    ib_queue_pair *queue_pair; /**< The queue pair, that is used to send and receive messages */

    ib_mem_reg *send_mem_reg; /**< The memory region, that contains the send buffer */
    ib_mem_reg *recv_mem_reg; /**< The memory region, that contains the receive buffer */

    struct ibv_sge send_sge; /**< The scatter-gather element, that is used for sending messages */
    struct ibv_sge recv_sge; /**< The scatter-gather element, that is used for receiving messages */

    struct ibv_send_wr* send_wrs; /**< Send work requests, that are (re-)used by msg_send() and rdma_write() */
    struct ibv_recv_wr* recv_wrs; /**< Receive work requests, that are (re-)used by msg_recv() */

    ib_connection_info local_conn_info; /**< Infiniband connection information about the local host */
    ib_connection_info remote_conn_info; /**< Infiniband connection information about the remote host */
} connection;

/**
 * Initialize a connection.
 *
 * The memory for the structure must already be allocated.
 * device, prot_dom, send_comp_queue, recv_comp_queue must point to valid and already initialized
 * structs; recv_queue may also be NULL, if no shared receive queue shall be used.
 *
 * This function will create a queue pair and register two memory regions in the given protection domain.
 * Always call close_connection() to ensure that these will be deallocated!
 *
 * @param conn The connection to be initialized
 * @param device The local infiniband device
 * @param prot_dom The protection domain, where the infiniband resources shall be allocated
 * @param send_comp_queue The completion queue for send requests (may be the same as recv_comp_queue)
 * @param recv_comp_queue The completion queue for receive requests (may be the same as send_comp_queue)
 * @param recv_queue The shared receive queue (may be NULL, if no shared receive queue shall be used)
 * @param buf_size The size in bytes to be used for the send- and receive-buffers
 * @param queue_size The size to be used for the queue pair
 */
void init_connection(connection *conn, ib_device *device, ib_prot_dom *prot_dom, ib_comp_queue *send_comp_queue,
                     ib_comp_queue *recv_comp_queue, ib_shared_recv_queue *recv_queue, uint64_t buf_size,
                     uint32_t queue_size);

/**
 * Connect to a remote server.
 *
 * The infiniband connection information will be exchanged via TCP.
 * After that, the local queue pair will be connected to the remote queue pair.
 *
 * @param conn The connection to be connected
 * @param bind_address The address to bind the socket to (may be null, or empty string)
 * @param hostname The remote's hostname
 * @param port The port to use for TCP-communication
 */
void connect_to_server(connection *conn, const char *bind_address, const char *hostname, uint16_t port);

/**
 * Connect to a remote client.
 *
 * This function will wait for a client to connect via TCP and then exchange the infiniband connection information.
 * After that, the local queue pair will be connected to the remote queue pair.
 *
 * @param conn The connection to be connected
 * @param bind_address The address to bind the socket to (may be null, or empty string)
 * @param port The port to use for TCP-communication
 */
void connect_to_client(connection *conn, const char *bind_address, uint16_t port);

/**
 * Disconnect from a remote host and free the resources, that have been allocated by init_connection().
 *
 * The connection-struct will be useless after calling this function and can be freed.
 *
 * @param conn The connection to be disconnected
 */
void close_connection(connection *conn);

/**
 * Send a specified amount of messages via a given connection.
 *
 * The work requests all use the same memory region. They get linked together, so that only a single call of
 * ibv_post_send() is necessary. Each work request has IBV_SEND_SIGNAL set, so that a work completion will be created
 * for every sent message.
 *
 * @param conn The connection
 * @param amount The amount of messages to be sent
 */
void msg_send(connection *conn, uint32_t amount);

/**
 * Receive a specified amount of messages from a given connection.
 *
 * The work requests all use the same memory region. They get linked together, so that only a single call of
 * ibv_post_recv() is necessary.
 *
 * @param conn The connection
 * @param amount The amount of messages to be received.
 */
void msg_recv(connection *conn, uint32_t amount);

/**
 * Use RDMA to write a given amount of times to a remote host via a given connection.
 *
 * The work requests all use the same memory region. They get linked together, so that only a single call of
 * ibv_post_send() is necessary. Each work request has IBV_SEND_SIGNAL set, so that a work completion will be created
 * for every sent message.
 *
 * @param conn The connection
 * @param amount The amount of rdma writes to be performed.
 */
void rdma_write(connection *conn, uint32_t amount);

/**
 * Exchange the infiniband connection information with a remote host.
 *
 * This function is called only by connect_to_server() and connect_to_client().
 *
 * @param conn The connection
 */
void __exchange_ib_connection_info(connection *conn);

#endif