/*
 * Copyright (c) Huawei Technologies Co., Ltd. 2025-2025. All rights reserved.
 */

#include "common.h"
#include "traffic.h"
#include "traffic/hook.h"
#include "traffic/data.h"
#include <cstdint>
#include <string>

extern "C" {
int8_t InitTrafficNativeHandler() {
    return hookSocket();
}

std::string urlData = "";
const char *getTrafficNativeData() {
    urlData = TrafficData::get().toString();
    return urlData.c_str();
}

int8_t clearTrafficNativeData() {
    TrafficData::get().clear();
    return SUCCESS;
}

}