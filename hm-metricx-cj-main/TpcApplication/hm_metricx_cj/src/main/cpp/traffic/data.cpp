/*
 * Copyright (c) Huawei Technologies Co., Ltd. 2025-2025. All rights reserved.
 */

#include "data.h"
#include "netdb.h"
#include "netutil.h"
#include "socket_info.h"
#include "sys/socket.h"
#include <unistd.h>

TrafficData& TrafficData::get() {
    static TrafficData instance;
    return instance;
}

TrafficData::TrafficData() { 
    this->g_rwlock = PTHREAD_RWLOCK_INITIALIZER;
}

TrafficData::~TrafficData() {
    clear();
    pthread_rwlock_destroy(&g_rwlock);
}

void TrafficData::onGetAddrInfo(const char *hostname, struct addrinfo *addr) {
    char ip_buf[INET6_ADDRSTRLEN + 1];
    unsigned short port;
    if (0 == parse_ip_port_from_sockaddr(addr->ai_addr, ip_buf, &port)) {
        if (strlen(ip_buf) > 0 && strlen(hostname) > 0) {
            pthread_rwlock_wrlock(&this->g_rwlock);
            ip_host_map.insert(std::pair<std::string, std::string>(ip_buf, hostname));
            pthread_rwlock_unlock(&this->g_rwlock);
        }
    }
}

void TrafficData::onConnect(int fd, const struct sockaddr *addr, socklen_t len) {
    char ip_buf[INET6_ADDRSTRLEN + 1];
    unsigned short port;

    int ret = parse_ip_port_from_sockaddr(addr, ip_buf, &port);
    if (ret == 0 && strlen(ip_buf) > 0 && 0 != strcmp(ip_buf, "::ffff:127.0.0.1")) {
        bindAddress(fd, ip_buf, port);
    }
}

void TrafficData::bindAddress(int fd, const char *ip_str, unsigned short port) {
    pthread_rwlock_wrlock(&this->g_rwlock);
    if (fd_sockinfo_map.size() >= MAX_SOCK_INFO_SIZE) {
        pthread_rwlock_unlock(&this->g_rwlock);
        return;
    }
    std::string host = "";
    if(nullptr != ip_str) {
        host = findHostByIp(ip_str);
    }
    
    SocketInfo *socketInfo = findSocketInfoByFd(fd);
    if (nullptr == socketInfo) {
        socketInfo = new SocketInfo(fd);
        fd_sockinfo_map[fd] = socketInfo;
    }

    if(nullptr != ip_str) {
        fd_sockinfo_map[fd]->setIp(ip_str);
        fd_sockinfo_map[fd]->setPort(port);
    }
    if (!host.empty()) {
        fd_sockinfo_map[fd]->setHost(host);
    }
    pthread_rwlock_unlock(&this->g_rwlock);
}

void TrafficData::onSend(int fd, size_t len) {
    pthread_rwlock_wrlock(&this->g_rwlock);
    SocketInfo *socketInfo = findSocketInfoByFd(fd);
    if (nullptr != socketInfo) {
        socketInfo->onSend(fd,len);
    }
    pthread_rwlock_unlock(&this->g_rwlock);
}

void TrafficData::onRecv(int fd, size_t len) {
    pthread_rwlock_wrlock(&this->g_rwlock);
    SocketInfo *socketInfo = findSocketInfoByFd(fd);
    if (nullptr != socketInfo) {
        socketInfo->onRecv(fd,len);
    }
    pthread_rwlock_unlock(&this->g_rwlock);
}

void TrafficData::onClose(int fd) {
    pthread_rwlock_wrlock(&this->g_rwlock);
    SocketInfo *socketInfo = findSocketInfoByFd(fd);
    
    pthread_rwlock_unlock(&this->g_rwlock);
}

std::string TrafficData::toString() {
    pthread_rwlock_wrlock(&this->g_rwlock);
    std::string res = "";
    for (auto it = fd_sockinfo_map.begin(); it != fd_sockinfo_map.end(); ++it) {
        if (it->second->getHost() != "null" && it->second->getSum() > 0) {
            res += it->second->toString() + ";";
        }
    }
    pthread_rwlock_unlock(&this->g_rwlock);
    return res;
}

void TrafficData::clear() {
    pthread_rwlock_wrlock(&this->g_rwlock);
    for (auto it = fd_sockinfo_map.begin(); it != fd_sockinfo_map.end(); ++it) {
        delete it->second;
        it->second = nullptr;
    }
    fd_sockinfo_map.clear();
    ip_host_map.clear();
    pthread_rwlock_unlock(&this->g_rwlock);
}

SocketInfo *TrafficData::findSocketInfoByFd(int fd) {
    SocketInfo *sockInfo = nullptr;
    auto it = fd_sockinfo_map.find(fd);
    if (it != fd_sockinfo_map.end()) {
        sockInfo = it->second;
    }
    return sockInfo;
}

std::string TrafficData::findHostByIp(const std::string &ip) {
    auto it = ip_host_map.find(ip);
    if (it != ip_host_map.end()) {
        return it->second;
    }
    return "";
}
