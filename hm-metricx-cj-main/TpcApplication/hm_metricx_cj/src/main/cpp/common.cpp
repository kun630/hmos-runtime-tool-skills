/*
 * Copyright (c) Huawei Technologies Co., Ltd. 2025-2025. All rights reserved.
 */

#include "common.h"
#include <fstream>
#include <vector>
#include <mutex>

bool isLogCallbackRegistered = false;
std::vector<LogCallback> logCallbacks;
std::mutex logCallbacksMutex;

void HilogCallback(const LogType type, const LogLevel level, const unsigned int domain, const char *tag,
                   const char *msg) {
    if (nullptr == tag || nullptr == msg) {
        return;
    }
    std::vector<LogCallback> callbacks;
    {
        std::lock_guard<std::mutex> lock(logCallbacksMutex);
        callbacks = logCallbacks;
    }
    for (const auto &callback : callbacks) {
        callback(type, level, domain, tag, msg);
    }
}

void registerHilogCallback(LogCallback logCallback) {
    {
        std::lock_guard<std::mutex> lock(logCallbacksMutex);
        logCallbacks.push_back(logCallback);
    }
    if (isLogCallbackRegistered) {
        return;
    }
    isLogCallbackRegistered = true;
    OH_LOG_SetCallback(HilogCallback);
}

std::string getLastLineEfficient(const std::string &filePath, char targetChar) {
    std::ifstream f(filePath, std::ios::ate);
    if (!f.is_open()) {
        return "";
    }
    char x;
    std::string line;
    std::streampos size = f.tellg();
    for (int var = 1; var <= size; var++) {
        f.seekg(-var, std::ios::end);
        f.get(x);
        if (x == 0) {
            continue;
        }
        if (x == '\n') {
            if (line.size() > 0 && line.find(targetChar) != std::string::npos) {
                return line;
            }
            line = "";
        } else {
            line = x + line;
        }
    }
    f.close();
    return line;
}

int64_t parseHexAddress(const std::string &hexStr) {
    if (hexStr.empty()) {
        return INT64_MAX;
    }
    try {
        return std::stoll(hexStr, nullptr, 16);
    } catch (...) {
        return INT64_MAX;
    }
}

bool writeFile(const char *filename, std::string str) {
    std::ofstream outfile(filename);
    if (!outfile.is_open()) {
        return false;
    }
    outfile << str;
    outfile.close();
    return true;
}
