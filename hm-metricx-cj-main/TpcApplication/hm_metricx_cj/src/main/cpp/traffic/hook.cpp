/*
 * Copyright (c) Huawei Technologies Co., Ltd. 2025-2025. All rights reserved.
 */

#include "hook.h"
#include "common.h"
#include "traffic/netutil.h"
#include "traffic/data.h"
#include "netdb.h"
#include "sys/socket.h"
#include "sys/stat.h"
#include "xhook/xh_elf.h"
#include "xhook/xhook.h"
#include "memory/hook_helper.h"
#include <cstdint>
#include <iomanip>
#include <iostream>
#include <sstream>
#include <sys/time.h>
#include <thread>
#include <unistd.h>

bool is_socketfd(int fd) {
    if (fd < 0) {
        return false;
    }
    int error;
    socklen_t len = sizeof(error);
    int result = getsockopt(fd, SOL_SOCKET, SO_TYPE, &error, &len);
    return (result == 0);
}

int (*old_getaddrinfo)(const char *node, const char *service,
                       const struct addrinfo *hints, struct addrinfo **res);
int new_getaddrinfo(const char *node, const char *service,
                   const struct addrinfo *hints, struct addrinfo **res) {
    int ret = old_getaddrinfo(node, service, hints, res);
    if (ret == 0) {
        TrafficData::get().onGetAddrInfo(node, (*res));
    }
    return ret;
}

int (*old_connect)(int sockfd, const struct sockaddr *addr, socklen_t addrlen);
int new_connect(int sockfd, const struct sockaddr *addr, socklen_t addrlen) {
    int ret = old_connect(sockfd, addr, addrlen);
    // For non-blocking sockets, connect() returns -1 and sets errno to EINPROGRESS 
    // to indicate that the connection operation is now in progress.
    if (ret == 0 || errno == EINPROGRESS) {
        TrafficData::get().onConnect(sockfd, addr, addrlen);
    }
    return ret;
}

ssize_t (*old_send)(int sockfd, const void *buf, size_t len, int flags);
ssize_t new_send(int sockfd, const void *buf, size_t len, int flags) {
    ssize_t ret = old_send(sockfd, buf, len, flags);
    if (ret > 0) {
        TrafficData::get().onSend(sockfd, ret);
    }
    return ret;
}

ssize_t (*old_recv)(int sockfd, void *buf, size_t len, int flags);
ssize_t new_recv(int sockfd, void *buf, size_t len, int flags) {
    ssize_t ret = old_recv(sockfd, buf, len, flags);
    if (ret > 0) {
        TrafficData::get().onRecv(sockfd, ret);
    }
    return ret;
}

ssize_t (*old_sendto)(int sockfd, const void *buf, size_t len, int flags,
                      const struct sockaddr *dest_addr, socklen_t addrlen);
ssize_t new_sendto(int sockfd, const void *buf, size_t len, int flags,
                   const struct sockaddr *dest_addr, socklen_t addrlen) {
    ssize_t ret = old_sendto(sockfd, buf, len, flags, dest_addr, addrlen);
    if (ret > 0) {
        TrafficData::get().onSend(sockfd, ret);
    }
    return ret;
}

ssize_t (*old_recvfrom)(int sockfd, void *buf, size_t len, int flags, 
                        struct sockaddr *src_addr, socklen_t *addrlen);
ssize_t new_recvfrom(int sockfd, void *buf, size_t len, int flags, 
                     struct sockaddr *src_addr, socklen_t *addrlen) {
    ssize_t ret = old_recvfrom(sockfd, buf, len, flags, src_addr, addrlen);
    if (ret > 0) {
        TrafficData::get().onRecv(sockfd, ret);
    }
    return ret;
}

ssize_t (*old_send_chk)(int sockfd, const void *buf, size_t len, size_t buflen, int flags);
ssize_t new_send_chk(int sockfd, const void *buf, size_t len, size_t buflen, int flags) {
    ssize_t ret = old_send_chk(sockfd, buf, len, buflen, flags);
    if (ret > 0) {
        TrafficData::get().onSend(sockfd, ret);
    }
    return ret;
}
ssize_t (*old_recv_chk)(int sockfd, void *buf, size_t len, size_t buflen, int flags);
ssize_t new_recv_chk(int sockfd, void *buf, size_t len, size_t buflen, int flags) {
    ssize_t ret = old_recv_chk(sockfd, buf, len, buflen, flags);
    if (ret > 0) {
        TrafficData::get().onRecv(sockfd, ret);
    }
    return ret;
}

ssize_t (*old_sendto_chk)(int sockfd, const void *buf, size_t len, size_t buflen, int flags,
                          const struct sockaddr *dest_addr, socklen_t addrlen);
ssize_t new_sendto_chk(int sockfd, const void *buf, size_t len, size_t buflen, int flags,
                       const struct sockaddr *dest_addr, socklen_t addrlen) {
    ssize_t ret = old_sendto_chk(sockfd, buf, len, buflen, flags, dest_addr, addrlen);
    if (ret > 0) {
        TrafficData::get().onSend(sockfd, ret);
    }
    return ret;
}

ssize_t (*old_recvfrom_chk)(int sockfd, void *buf, size_t len, size_t buflen, int flags,
                            struct sockaddr *src_addr, socklen_t *addrlen);
ssize_t new_recvfrom_chk(int sockfd, void *buf, size_t len, size_t buflen, int flags, 
                         struct sockaddr *src_addr, socklen_t *addrlen) {
    ssize_t ret = old_recvfrom_chk(sockfd, buf, len, buflen, flags, src_addr, addrlen);
    if (ret > 0) {
        TrafficData::get().onRecv(sockfd, ret);
    }
    return ret;
}

ssize_t (*old_sendmsg)(int sockfd, const struct msghdr *msg, int flags);
ssize_t new_sendmsg(int sockfd, const struct msghdr *msg, int flags) {
    ssize_t ret = old_sendmsg(sockfd, msg, flags);
    if (ret > 0) {
        TrafficData::get().onSend(sockfd, ret);
    }
    return ret;
}

ssize_t (*old_recvmsg)(int sockfd, struct msghdr *msg, int flags);
ssize_t new_recvmsg(int sockfd, struct msghdr *msg, int flags) {
    ssize_t ret = old_recvmsg(sockfd, msg, flags);
    if (ret > 0) {
        TrafficData::get().onRecv(sockfd, ret);
    }
    return ret;
}

ssize_t (*old_write)(int fd, const void *buf, size_t count);
ssize_t new_write(int fd, const void *buf, size_t count) {
    ssize_t ret = old_write(fd, buf, count);
    if (ret > 0) {
        bool fd_type = is_socketfd(fd);
        if (fd_type) {
            TrafficData::get().onSend(fd, ret);
        }
    }
    return ret;
}

ssize_t (*old_read)(int fd, void *buf, size_t count);
ssize_t new_read(int fd, void *buf, size_t count) {
    ssize_t ret = old_read(fd, buf, count);
    if (ret > 0) {
        bool fd_type = is_socketfd(fd);
        if (fd_type) {
            TrafficData::get().onRecv(fd, ret);
        }
    }
    return ret;
}

int hookSocket() {
    pthread_mutex_lock(&hook_mutex);
    xhook_clear();
    
    int hook_status = 0;
    std::vector<const std::string> register_patterns = {
        ".*\\.so$"
    };
    std::vector<std::pair<const std::string, void *const>> methods_new = {
        std::make_pair("getaddrinfo", reinterpret_cast<void *>(new_getaddrinfo)),
        std::make_pair("connect", reinterpret_cast<void *>(new_connect)),
        std::make_pair("send", reinterpret_cast<void *>(new_send)),
        std::make_pair("recv", reinterpret_cast<void *>(new_recv)),
        std::make_pair("sendto", reinterpret_cast<void *>(new_sendto)),
        std::make_pair("recvfrom", reinterpret_cast<void *>(new_recvfrom)),
        std::make_pair("sendmsg", reinterpret_cast<void *>(new_sendmsg)),
        std::make_pair("recvmsg", reinterpret_cast<void *>(new_recvmsg)),
        std::make_pair("write", reinterpret_cast<void *>(new_write)),
        std::make_pair("read", reinterpret_cast<void *>(new_read)),
        std::make_pair("__send_chk", reinterpret_cast<void *>(new_send_chk)),
        std::make_pair("__recv_chk", reinterpret_cast<void *>(new_recv_chk)),
        std::make_pair("__sendto_chk", reinterpret_cast<void *>(new_sendto_chk)),
        std::make_pair("__recvfrom_chk", reinterpret_cast<void *>(new_recvfrom_chk))
    };
    std::vector<void **const> methods_old = {
        reinterpret_cast<void **>(&old_getaddrinfo),
        reinterpret_cast<void **>(&old_connect),
        reinterpret_cast<void **>(&old_send),
        reinterpret_cast<void **>(&old_recv),
        reinterpret_cast<void **>(&old_sendto),
        reinterpret_cast<void **>(&old_recvfrom),
        reinterpret_cast<void **>(&old_sendmsg),
        reinterpret_cast<void **>(&old_recvmsg),
        reinterpret_cast<void **>(&old_write),
        reinterpret_cast<void **>(&old_read),
        reinterpret_cast<void **>(&old_send_chk),
        reinterpret_cast<void **>(&old_recv_chk),
        reinterpret_cast<void **>(&old_sendto_chk),
        reinterpret_cast<void **>(&old_recvfrom_chk)
    };

    for (auto &pattern : register_patterns) {
        for (size_t i = 0; i < methods_new.size(); ++i) {
            hook_status = xhook_register(pattern.c_str(), methods_new[i].first.c_str(), methods_new[i].second, methods_old[i]);
            if (EXIT_SUCCESS != hook_status) {
                OH_LOG_Print(LOG_APP, LOG_WARN, 0x00008, "hm_metricx_cj",
                             "Traffic-hookSocket - Failed to register pattern: %{public}s, method: %{public}s",
                             pattern.c_str(), methods_new[i].first.c_str());
                pthread_mutex_unlock(&hook_mutex);
                return FAIL;
            }
        }
    }

    std::vector<const std::string> ignore_patterns = {
        // self
        ".*libhm_metricx_cj\\.so$", ".*libohos_app_cangjie_hm_metricx_cj.*\\.so$",
        // __recv_chk: triggered when button is clicked
        ".*libmmi-client.z\\.so$",
        // sendto: triggered when app is started
        ".*libhisysevent.z\\.so$",
        ".*/libhilog_ndk.z.so$",
        ".*/libstdx.encoding.so$",
        ".*/libhilog.so$"
    };

    for (auto &pattern : ignore_patterns) {
        hook_status = xhook_ignore(pattern.c_str(), nullptr);
        if (EXIT_SUCCESS != hook_status)
        {
            OH_LOG_Print(LOG_APP, LOG_WARN, 0x00008, "hm_metricx_cj",
                        "Traffic-hookSocket - Failed to ignore pattern: %{public}s", pattern.c_str());
            pthread_mutex_unlock(&hook_mutex);
            return FAIL;
        }
    }
    
    if (xhook_refresh(0) != 0) {
        pthread_mutex_unlock(&hook_mutex);
        return FAIL;
    }
    pthread_mutex_unlock(&hook_mutex);
    return SUCCESS;
}