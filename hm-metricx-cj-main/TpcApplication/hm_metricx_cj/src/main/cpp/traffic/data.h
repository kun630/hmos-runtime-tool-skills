/*
 * Copyright (c) Huawei Technologies Co., Ltd. 2025-2025. All rights reserved.
 */

#ifndef TPCAPPLICATION_TRAFFIC_DATA_H
#define TPCAPPLICATION_TRAFFIC_DATA_H

#include "socket_info.h"
#include "sys/socket.h"
#include <unordered_set>

#define MAX_SOCK_INFO_SIZE 1024

class TrafficData {
public:
    static TrafficData &get();
    void onGetAddrInfo(const char *hostname, struct addrinfo *addr);
    void onConnect(int fd, const struct sockaddr *addr, socklen_t len);
    void onSend(int fd, size_t len);
    void onRecv(int fd, size_t len);
    void onClose(int fd);
    std::string toString();
    void clear();
    
    TrafficData(const TrafficData &) = delete;
    TrafficData &operator=(const TrafficData &) = delete;
private:
    TrafficData();
    ~TrafficData();
    void bindAddress(int fd, const char *address_str, unsigned short port);
    SocketInfo *findSocketInfoByFd(int fd);
    std::string findHostByIp(const std::string &ip);

    pthread_rwlock_t g_rwlock;
    std::unordered_map<int, SocketInfo *> fd_sockinfo_map;
    std::unordered_map<std::string, std::string> ip_host_map;
};

#endif // TPCAPPLICATION_TRAFFIC_DATA_H
