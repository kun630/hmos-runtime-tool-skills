/*
 * Copyright (c) Huawei Technologies Co., Ltd. 2025-2025. All rights reserved.
 */

#ifndef TPCAPPLICATION_TRAFFIC_NETUTIL_H
#define TPCAPPLICATION_TRAFFIC_NETUTIL_H

#include <arpa/inet.h>

int parse_ip_port_from_sockaddr(const struct sockaddr *addr, char* ip, unsigned short* port);

#endif //TPCAPPLICATION_TRAFFIC_NETUTIL_H
