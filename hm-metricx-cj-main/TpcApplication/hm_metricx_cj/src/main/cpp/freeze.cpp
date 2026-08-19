/*
 * Copyright (c) Huawei Technologies Co., Ltd. 2025-2025. All rights reserved.
 */

#include "common.h"
#include "crash.h"
#include "hidebug/hidebug.h"
#include "hilog/log.h"
#include <cstdio>
#include <cstdlib>
#include <cstdint>
#include <cstring>
#include <ctime>
#include <string>
#include <vector>

typedef const char *(*CollectExtraFreezeInfo)();
CollectExtraFreezeInfo cjCollectExtraFreezeInfo;

FILE *cpuUsageFile = nullptr;
FILE *extraInfoFile = nullptr;

std::string _ignoreFilePath;

const int FREEZE_TYPE = 3;
const unsigned int FREEZE_DOMAIN = 218108688;
const char *FreezeTag = "AppDfr";
const std::vector<std::string> FreezeTags = {"APP_INPUT_BLOCK", "NO_DRAW", "LIFECYCLE_TIMEOUT", "THREAD_BLOCK_6S",
                                             "SCREEN_ON_TIMEOUT", "SERVICE_TIMEOUT", "SERVICE_BLOCK"};

bool containFreezeTag(const std::vector<std::string> &msgTags, const std::string &msg)
{
    for (const std::string &tag : msgTags) {
        if (msg.find(tag) != std::string::npos) {
            return true;
        }
    }
    return false;
}

bool freezeCaught = false;
void collectFreezeInfo()
{
    if (isInCrash()) {
        auto fp = std::fopen(_ignoreFilePath.c_str(), "w+");
        std::fclose(fp);
        return;
    }
    auto extraInfo = cjCollectExtraFreezeInfo();
    if (extraInfoFile != nullptr) {
        fwrite(extraInfo, sizeof(char), strlen(extraInfo), extraInfoFile);
        fflush(extraInfoFile);
    }
    std::string saveStr = "";
    HiDebug_ThreadCpuUsagePtr usagePtr = OH_HiDebug_GetAppThreadCpuUsage();
    while (usagePtr != nullptr) {
        saveStr += std::to_string(usagePtr->threadId) + "," + std::to_string(usagePtr->cpuUsage) + ",";
        usagePtr = usagePtr->next;
    }
        
    if (cpuUsageFile != nullptr) {
        fwrite(saveStr.c_str(), sizeof(char), saveStr.size(), cpuUsageFile);
        fflush(cpuUsageFile);
    }
}

void FreezeHilogCallback(const LogType type, const LogLevel level, const unsigned int domain, const char *tag, const char *msg)
{
    if (freezeCaught) {
        return;
    }
    int typeValue = static_cast<int>(type);
    if (typeValue != FREEZE_TYPE) {
        return;
    }
    if (level != LOG_INFO) {
        return;
    }
    if (domain != FREEZE_DOMAIN) {
        return;
    }

    if(strcmp(tag, FreezeTag) != 0) {
        return;
    }

    std::string msgStr(msg);
    if (!containFreezeTag(FreezeTags, msgStr)) {
        return;
    }
    
    freezeCaught = true;
    collectFreezeInfo();
}

extern "C" int8_t registerFreezeHilogCallback(const char * ignoreFilePath, const char * cpuUsageFilePath,
                                        const char * extraInfoFilePath, CollectExtraFreezeInfo collectExtraFreezeInfo)
{
    _ignoreFilePath = ignoreFilePath;
    cpuUsageFile = std::fopen(cpuUsageFilePath, "w+");
    if (cpuUsageFile == NULL) {
        return FAIL;
    }
    extraInfoFile = std::fopen(extraInfoFilePath, "w+");
    if (extraInfoFile == NULL) {
        return FAIL;
    }
    cjCollectExtraFreezeInfo = collectExtraFreezeInfo;
    registerHilogCallback(FreezeHilogCallback);
    return SUCCESS;
}

extern "C" int8_t registerFreezeCallback(const char * ignoreFilePath, const char * cpuUsageFilePath,
                                        const char * extraInfoFilePath, CollectExtraFreezeInfo collectExtraFreezeInfo)
{
    _ignoreFilePath = ignoreFilePath;
    cpuUsageFile = std::fopen(cpuUsageFilePath, "w+");
    if (cpuUsageFile == NULL) {
        return FAIL;
    }
    extraInfoFile = std::fopen(extraInfoFilePath, "w+");
    if (extraInfoFile == NULL) {
        return FAIL;
    }
    cjCollectExtraFreezeInfo = collectExtraFreezeInfo;
    collectFreezeInfo();
    return SUCCESS;
}