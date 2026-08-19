/*
 * Copyright (c) Huawei Technologies Co., Ltd. 2025-2025. All rights reserved.
 */

#include "netutil.h"
#include <string.h>
#include "netutil.h"

int parse_ipv6_port_from_sockaddr(const struct sockaddr *addr, char *ip, unsigned short *port) {
    const struct sockaddr_in6 *addr6;
    addr6 = reinterpret_cast<const struct sockaddr_in6 *>(addr);
    *port = ntohs(addr6->sin6_port);
    if (inet_ntop(AF_INET6, reinterpret_cast<const void *>(&addr6->sin6_addr), ip, INET6_ADDRSTRLEN)) {
        return 0;
    }
    return -1;
}

int parse_ipv4_port_from_sockaddr(const struct sockaddr *addr, char *ip, unsigned short *port) {
    const struct sockaddr_in *addr4;
    addr4 = reinterpret_cast<const struct sockaddr_in *>(addr);
    *port = ntohs(addr4->sin_port);
    strcpy(ip, "::ffff:");
    if (inet_ntop(AF_INET, reinterpret_cast<const void *>(&addr4->sin_addr), ip+7, INET_ADDRSTRLEN)) {
        return 0;
    }
    return -2;
}

int parse_ip_port_from_sockaddr(const struct sockaddr *addr, char *ip, unsigned short *port) {
    if (addr->sa_family == AF_INET6) {
        return parse_ipv6_port_from_sockaddr(addr, ip, port);
    } else if (addr->sa_family == AF_INET) {
        return parse_ipv4_port_from_sockaddr(addr, ip, port);
    }
    // ignore unix local socket etc.
    return -3;
}

