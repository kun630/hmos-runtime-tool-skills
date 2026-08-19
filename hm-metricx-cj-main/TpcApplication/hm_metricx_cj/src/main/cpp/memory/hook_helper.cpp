/*
 * Copyright (c) Huawei Technologies Co., Ltd. 2025-2025. All rights reserved.
 * ModificationS:
 * 1. HookHelper adds public static method TryHook.
 * 2. HookHelper removes method Callback.
 * 3. Add function dlopen_hook and struct dl_extinfo.
 * 4. Modify implementation of method HookHelper::HookImpl.
 * 5. Replace log with hilog.
 * 
 * Copyright (c) 2021. Kwai, Inc. All rights reserved.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *         http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 *
 * Created by lbtrace on 2021.
 *
 */

#define LOG_TAG "hook_helper"
#include "hook_helper.h"
#include "xhook/xhook.h"
#include <hilog/log.h>

std::vector<const std::string> HookHelper::register_pattern_;
std::vector<const std::string> HookHelper::ignore_pattern_;
std::vector<std::pair<const std::string, void *const>> HookHelper::methods_;
pthread_mutex_t hook_mutex = PTHREAD_MUTEX_INITIALIZER;

typedef struct {
    int flag;
    int relro_fd;
    void *reserved_addr;
    size_t reserved_size;
} dl_extinfo;

void *(*dlopen_ext_origin)(const char *file, int mode, const char *space, const void *caller_addr,
                           const dl_extinfo *extinfo);

void *dlopen_hook(const char *file, int mode, const char *space, const void *caller_addr, const dl_extinfo *extinfo) {
    void *result = dlopen_ext_origin(file, mode, space, caller_addr, extinfo);
    if (strstr(file, "so") != NULL) {
        HookHelper::TryHook(file);
    }
    return result;
}

bool HookHelper::HookMethods(std::vector<const std::string> &register_pattern,
                             std::vector<const std::string> &ignore_pattern,
                             std::vector<std::pair<const std::string, void *const>> &methods) {
    if (register_pattern.empty() || methods.empty()) {
        OH_LOG_Print(LOG_APP, LOG_WARN, 0x00008, "hm_metricx_cj", "HookHelper::HookMethods - Nothing to hook");
        return false;
    }

    register_pattern_ = std::move(register_pattern);
    ignore_pattern_ = std::move(ignore_pattern);
    methods_ = std::move(methods);
    return HookImpl();
}

void HookHelper::UnHookMethods() {
    register_pattern_.clear();
    ignore_pattern_.clear();
    methods_.clear();
}

void HookHelper::TryHook(const char *filename) {
    pthread_mutex_lock(&hook_mutex);
    xhook_clear();
    for (auto &method : methods_) {
        if (xhook_register(filename, method.first.c_str(), method.second, nullptr) != EXIT_SUCCESS) {
            pthread_mutex_unlock(&hook_mutex);
            return;
        }
    }
    xhook_refresh(0);
    pthread_mutex_unlock(&hook_mutex);
}


bool HookHelper::HookImpl() {
    pthread_mutex_lock(&hook_mutex);
    xhook_clear();

    for (auto &pattern : register_pattern_) {
        for (auto &method : methods_) {
            if (xhook_register(pattern.c_str(), method.first.c_str(), method.second, nullptr) != EXIT_SUCCESS) {
                OH_LOG_Print(LOG_APP, LOG_WARN, 0x00008, "hm_metricx_cj",
                             "HookHelper::HookImpl - Failed to register hook for pattern: %s,method: %s",
                             pattern.c_str(), method.first.c_str());
                pthread_mutex_unlock(&hook_mutex);
                return false;
            }
        }
    }

    for (auto &pattern : ignore_pattern_) {
        for (auto &method : methods_) {
            if (xhook_ignore(pattern.c_str(), method.first.c_str()) != EXIT_SUCCESS) {
                OH_LOG_Print(LOG_APP, LOG_WARN, 0x00008, "hm_metricx_cj",
                             "HookHelper::HookImpl - Failed to ignore pattern: %s,method: %s", pattern.c_str(),
                             method.first.c_str());
                pthread_mutex_unlock(&hook_mutex);
                return false;
            }
        }
    }

    if (xhook_refresh(0) != 0) {
        OH_LOG_Print(LOG_APP, LOG_WARN, 0x00008, "hm_metricx_cj", "HookHelper::HookImpl - xhook_refresh failed");
        pthread_mutex_unlock(&hook_mutex);
        return false;
    }
    xhook_clear();
    if (xhook_register("ld-musl-aarch64.so.1", "dlopen_impl", (void *)dlopen_hook, (void **)(&dlopen_ext_origin)) !=
        EXIT_SUCCESS) {
        OH_LOG_Print(LOG_APP, LOG_WARN, 0x00008, "hm_metricx_cj", "HookHelper::HookImpl - register dlopen_impl failed");
        pthread_mutex_unlock(&hook_mutex);
        return false;
    }
    int ret = xhook_refresh(0);
    pthread_mutex_unlock(&hook_mutex);
    return ret == 0;
}