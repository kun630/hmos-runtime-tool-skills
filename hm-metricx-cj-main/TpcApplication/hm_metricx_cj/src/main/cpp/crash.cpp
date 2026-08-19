/*
 * Copyright (c) Huawei Technologies Co., Ltd. 2025-2025. All rights reserved.
 */

#include "crash.h"
#include "oom.h"
#include "common.h"
#include "memory/memory_monitor.h"
#include "xhook/xh_util.h"
#include <bundle/native_interface_bundle.h>
#include <cstdint>
#include <deque>
#include <filesystem>
#include <fstream>
#include <hilog/log.h>
#include <iostream>
#include <malloc.h>
#include <mutex>
#include <ostream>
#include <pthread.h>
#include <signal.h>
#include <sstream>
#include <stdexcept>
#include <stdlib.h>
#include <string.h>
#include <string>
#include <sys/eventfd.h>
#include <syscall.h>
#include <unistd.h>

using namespace kwai::memory_monitor;
typedef struct {
    int sigNum;
    struct sigaction oldact;
} SignalCrashInfo;

struct LogEntry {
    std::chrono::time_point<std::chrono::system_clock> now;
    LogType type;
    LogLevel level;
    unsigned int domain;
    std::string tag;
    std::string msg;
};

static pthread_mutex_t signalHandlerMutex = PTHREAD_MUTEX_INITIALIZER;

static sig_atomic_t inCrash = 0;

int initSuccess = 0;

static int globalCrashTid = 0;

typedef const char *(*CollectCrashInfo)();

CollectCrashInfo cjCollectCrashInfo;

typedef void (*Callback)(const char *, const char *, CollectCrashInfo, const char *, const char *, const char *);

Callback cjcb;

std::string persistentFilePath;

std::string persistentSystemLogFilePath;
std::string persistentLastNHilogFilePath;

std::string persistentMemMapFilePath;
std::string persistentMemMallocFilePath;
std::string persistentParsedAddrFilePath;
std::string memPersistTimePath;

long long memPersistTime = -1;

const char *levelChars = "DIWEF"; // 3->D, 4->I, 5->W, 6->E, 7->F

std::deque<LogEntry> systemLogMessages;
std::deque<LogEntry> hilogMessages;

std::mutex systemLogMessagesMutex;
std::mutex hilogMessagesMutex;

int64_t LASTN_HILOG_NUMBER = 0;
int64_t SYSTEM_LOG_NUMBER = 0;

std::string cjLimits;

static SignalCrashInfo signalCrashInfo[] = {{.sigNum = SIGABRT}, {.sigNum = SIGBUS},   {.sigNum = SIGFPE},
                                            {.sigNum = SIGILL},  {.sigNum = SIGSEGV},  {.sigNum = SIGTRAP},
                                            {.sigNum = SIGSYS},  {.sigNum = SIGSTKFLT}};

int RemoveSignalHandler() {
    int r = SUCCESS;
    size_t i;
    for (i = 0; i < sizeof(signalCrashInfo) / sizeof(signalCrashInfo[0]); i++) {
        if (0 != sigaction(signalCrashInfo[i].sigNum, &(signalCrashInfo[i].oldact), NULL)) {
            r = FAIL;
        }
    }
    return r;
}

static std::string readFile(std::string filePath) {
    if (std::__fs::filesystem::exists(filePath)) {
        std::ifstream file(filePath);
        if (file.is_open()) {
            std::string content((std::istreambuf_iterator<char>(file)), std::istreambuf_iterator<char>());
            return content;
        }
    }
    return "";
}

static std::string getVss(const std::string &s, char delimiter) {
    std::string token;
    std::istringstream tokenStream(s);
    if (std::getline(tokenStream, token, delimiter)) {
        return std::to_string(std::stoi(token) * 4);
    }
    return "";
}

void CrashSystemlogCallback(const LogType type, const LogLevel level, const unsigned int domain, const char *tag,
                            const char *msg) {
    int typeValue = static_cast<int>(type);
    if (typeValue != 3) {
        return;
    }

    // current time
    auto now = std::chrono::system_clock::now();

    LogEntry entry{};
    entry.now = now;
    entry.type = type;
    entry.level = level;
    entry.domain = domain;
    entry.tag = tag;
    entry.msg = msg;

    std::lock_guard<std::mutex> lock(systemLogMessagesMutex);
    if (systemLogMessages.size() >= SYSTEM_LOG_NUMBER) {
        systemLogMessages.pop_front();
    }
    systemLogMessages.emplace_back(entry);
}

void CrashLastNHilogCallback(const LogType type, const LogLevel level, const unsigned int domain, const char *tag,
                             const char *msg) {
    // current time
    auto now = std::chrono::system_clock::now();

    LogEntry entry{};
    entry.now = now;
    entry.type = type;
    entry.level = level;
    entry.domain = domain;
    entry.tag = tag;
    entry.msg = msg;

    std::lock_guard<std::mutex> lock(hilogMessagesMutex);
    if (hilogMessages.size() >= LASTN_HILOG_NUMBER) {
        hilogMessages.pop_front();
    }
    hilogMessages.emplace_back(entry);
}

extern "C" {
int8_t WriteSystemLog(const char *pFilePath);
int8_t WriteLastNHiLog(const char *pFilePath);
void MarkCrash();
}

bool startsWith(const std::string &str, const std::string &prefix) {
    return str.size() >= prefix.size() && str.substr(0, prefix.size()) == prefix;
}

static int signal_crash_queue(siginfo_t *si) {
    if (SIGABRT == si->si_signo || si->si_code <= 0) {
        if (0 != syscall(SYS_rt_tgsigqueueinfo, getpid(), gettid(), si->si_signo, si))
            return -1;
    }
    return 0;
}

static void CrashSignalHandler(int sig, siginfo_t *si, void *context) {
    if (initSuccess == 0) {
        return;
    }
    if (inCrash && globalCrashTid == gettid()) {
        _exit(1);
    }
    pthread_mutex_lock(&signalHandlerMutex);
    if (inCrash) {
        pthread_mutex_unlock(&signalHandlerMutex);
        _exit(1);
    }
    globalCrashTid = gettid();
    MarkCrash();
    if (std::__fs::filesystem::exists("/data/storage/el2/log/hiappevent/")) {
        for (const auto &entry : std::__fs::filesystem::directory_iterator("/data/storage/el2/log/hiappevent/")) {
            std::string fileName = entry.path().filename().string();
            if (startsWith(fileName, "APP_CRASH")) {
                std::__fs::filesystem::remove(entry.path());
            }
        }
    }
    std::string fds = "";
    if (std::__fs::filesystem::exists("/proc/self/fd")) {
        for (auto &entry : std::__fs::filesystem::directory_iterator("/proc/self/fd")) {
            auto path = entry.path();
            fds += path.string() + ",";
            try {
                fds += std::__fs::filesystem::canonical(path).string() + ",";
            } catch (const std::__fs::filesystem::filesystem_error &e) {
                fds += "unknown,";
            }
        }
    }
    std::string threads = readFile("/proc/self/tids");
    std::string smaps_rollup = readFile("/proc/self/smaps_rollup");
    std::string vss = "Vss:\t\t\t\t" + getVss(readFile("/proc/self/statm"), ' ') + " KB";
    std::string meminfo = smaps_rollup + "\n" + vss;
    cjcb(persistentFilePath.c_str(), cjLimits.c_str(), cjCollectCrashInfo, fds.c_str(), threads.c_str(),
         meminfo.c_str());
    WriteSystemLog(persistentSystemLogFilePath.c_str());
    persistMemoryData(persistentMemMapFilePath.c_str(), persistentMemMallocFilePath.c_str(),
                      persistentParsedAddrFilePath.c_str(), memPersistTimePath.c_str());
    WriteLastNHiLog(persistentLastNHilogFilePath.c_str());
    
    waitOOMDumping();
    
    RemoveSignalHandler();
    auto res = signal_crash_queue(si);
    pthread_mutex_unlock(&signalHandlerMutex);
    if (res != 0) {
        _exit(1);
    }
}

int8_t saveMemoryMapToFile(const char *pFilePath) {

    const std::string source = "/proc/self/maps";
    const std::string destination = pFilePath;

    std::ifstream src(source, std::ios::binary);
    std::ofstream dst(destination, std::ios::binary);

    if (!src.is_open() || !dst.is_open()) {
        OH_LOG_Print(LOG_APP, LOG_WARN, 0x00008, "hm_metricx_cj", "saveMemoryMapToFile - failed.");
        return FAIL;
    }
    dst << src.rdbuf();
    return SUCCESS;
}

std::string cParseStackFrame(const std::set<uintptr_t> &backtrace, int64_t maxAddr) {
    if (backtrace.empty()) {
        return "";
    }
    void *dl_cache = nullptr;
    std::ostringstream oss;
    auto &monitor = MemoryMonitor::GetInstance();
    for (const auto &addr : backtrace) {
        if (addr > maxAddr) {
            break;
        }
        std::string frame = monitor.ParseStackFrame(addr, &dl_cache);
        oss << frame;
    }
    return oss.str();
}

bool saveParsedAddressToFile(const char *parsedAddrPath, int64_t maxAddr) {

    const auto &backtrace = MemoryMonitor::GetInstance().unique_backtrace;
    if (backtrace.size() == 0) {
        OH_LOG_Print(LOG_APP, LOG_WARN, 0x00008, "hm_metricx_cj",
                     "saveParsedAddressToFile - unique_backtarce is empty");
        return false;
    }

    std::string parseResult = cParseStackFrame(backtrace, maxAddr);
    if (parseResult.empty()) {
        OH_LOG_Print(LOG_APP, LOG_WARN, 0x00008, "hm_metricx_cj",
                     "saveParsedAddressToFile - Failed to parse stack frame");
        return false;
    }
    std::ofstream ofs(parsedAddrPath);
    if (!ofs.is_open()) {
        OH_LOG_Print(LOG_APP, LOG_WARN, 0x00008, "hm_metricx_cj",
                     "saveParsedAddressToFile - Failed to open file '%s' for writing", parsedAddrPath);
        return false;
    }

    ofs << parseResult;
    ofs.close();
    return true;
}

std::string LogEntryToString(const LogEntry &entry) {
    // dateTime
    std::time_t currentTime = std::chrono::system_clock::to_time_t(entry.now);
    std::tm localTime = *std::localtime(&currentTime);

    // millisecond
    auto ms = std::chrono::duration_cast<std::chrono::milliseconds>(entry.now -
                                                                    std::chrono::system_clock::from_time_t(currentTime))
                  .count() %
              1000;
    // format time
    char timeBuffer[80];
    std::strftime(timeBuffer, sizeof(timeBuffer), "%m-%d %H:%M:%S", &localTime);
    std::ostringstream timeStream;
    timeStream << timeBuffer << "." << std::setw(3) << std::setfill('0') << ms;
    std::string formattedTime = timeStream.str();

    // format level
    char levelChar = '?';
    if (entry.level >= LOG_DEBUG && entry.level <= LOG_FATAL) {
        levelChar = levelChars[entry.level - LOG_DEBUG];
    }

    // format domain
    std::stringstream domainStream;
    domainStream << std::hex << std::uppercase << entry.domain;
    std::string hexDomain = domainStream.str();
    if (hexDomain.length() > 5) {
        hexDomain = hexDomain.substr(hexDomain.length() - 5);
    } else {
        while (hexDomain.length() < 5) {
            hexDomain = "0" + hexDomain;
        }
    }
    if (entry.type == 0) {
        hexDomain = "A" + hexDomain;
    } else if (entry.type == 3) {
        hexDomain = "C" + hexDomain;
    }

    std::string res = formattedTime + "  " + hexDomain + "/" + entry.tag + "  " + levelChar + " " + entry.msg;
    return res;
}

int64_t getMaxMapAddr(const std::string &filePath) {
    std::string lastLine = getLastLineEfficient(filePath, '-');
    if (lastLine.empty()) {
        return INT64_MAX;
    }
    // 数据格式：7ee516a000-7ee516c000 rw-p 00000000 00:00 0                              [anon:libark_tooling.so.bss]
    size_t dashPos = lastLine.find('-');
    std::string secondAddr = lastLine.substr(dashPos + 1);
    size_t spacePos = secondAddr.find(' ');
    if (spacePos != std::string::npos) {
        secondAddr = secondAddr.substr(0, spacePos);
    }
    return parseHexAddress(secondAddr);
}

bool isInCrash() { return inCrash == 1; }

extern "C" {
int8_t InitNativeSignalHandler(const char *pFilePath, const char *limits, CollectCrashInfo collectCrashInfo,
                               const char *pSystemLogFilePath, const char *pMemMapFilePath, const char *pMemMallocPath,
                               const char *parsedAddrPath, const char *pMemPersistTimePath,
                               const char *pLastNHilogFilePath, int64_t lastNHilogNumber, int64_t systemLogNumber,
                               Callback cb) {
    LASTN_HILOG_NUMBER = lastNHilogNumber;
    SYSTEM_LOG_NUMBER = systemLogNumber;
    struct sigaction act;
    memset(&act, 0, sizeof(act));
    sigfillset(&act.sa_mask);
    act.sa_sigaction = CrashSignalHandler;
    act.sa_flags = SA_RESTART | SA_SIGINFO | SA_ONSTACK;

    size_t i;
    for (i = 0; i < sizeof(signalCrashInfo) / sizeof(signalCrashInfo[0]); i++) {
        if (0 != sigaction(signalCrashInfo[i].sigNum, &act, &(signalCrashInfo[i].oldact))) {
            RemoveSignalHandler();
            return FAIL;
        }
    }
    initSuccess = 1;

    persistentFilePath = pFilePath;
    persistentSystemLogFilePath = pSystemLogFilePath;
    persistentMemMapFilePath = pMemMapFilePath;
    persistentMemMallocFilePath = pMemMallocPath;
    persistentParsedAddrFilePath = parsedAddrPath;
    memPersistTimePath = pMemPersistTimePath;
    persistentLastNHilogFilePath = pLastNHilogFilePath;
    cjLimits = limits;

    cjCollectCrashInfo = collectCrashInfo;
    cjcb = cb;
    return SUCCESS;
}

int8_t registerCrashSystemlogCallback() {
    registerHilogCallback(CrashSystemlogCallback);
    return SUCCESS;
}

int8_t registerCrashLastNHilogCallback() {
    registerHilogCallback(CrashLastNHilogCallback);
    return SUCCESS;
}

int8_t WriteFile(const char *filepath, const char *content) {
    std::ofstream file(filepath);
    try {
        if (!file.is_open()) {
            return FAIL;
        }
        file << content;
        file.close();
        return SUCCESS;
    } catch (const std::exception &e) {
        OH_LOG_Print(LOG_APP, LOG_WARN, 0x00008, "hm_metricx_cj", "hm-metricx-cj error: write %{public}s failed",
                     filepath);
    }
    if (file.is_open()) {
        file.close();
    }
    return FAIL;
}

int8_t WriteCrashJson(const char *content) { return WriteFile(persistentFilePath.c_str(), content); }

int8_t WriteSystemLog(const char *pFilePath) {
    std::ostringstream logStream;
    for (const auto &entry : systemLogMessages) {
        std::string entryString = LogEntryToString(entry);
        logStream << entryString << "\n";
    }
    return WriteFile(pFilePath, logStream.str().c_str());
}

int8_t WriteLastNHiLog(const char *pFilePath) {
    std::ostringstream logStream;
    for (const auto &entry : hilogMessages) {
        std::string entryString = LogEntryToString(entry);
        logStream << entryString << "\n";
    }
    return WriteFile(pFilePath, logStream.str().c_str());
}

int8_t installNativeMemoryMonitor() {
    if (!MemoryMonitor::GetInstance().Install(nullptr, nullptr)) {
        return -1;
    }
    return 0;
}

int8_t persistMemoryData(const char *mapPath, const char *memMallocPath, const char *parsedAddrPath,
                         const char *memPersistTimePath) {
    try {
        auto t1 = std::chrono::high_resolution_clock::now();
        MemoryMonitor::GetInstance().SaveAllocRecordsToFile(memMallocPath);
        saveMemoryMapToFile(mapPath);
        int64_t maxAddr = getMaxMapAddr(mapPath);
        saveParsedAddressToFile(parsedAddrPath, maxAddr);
        auto t2 = std::chrono::high_resolution_clock::now();
        memPersistTime = std::chrono::duration_cast<std::chrono::milliseconds>(t2 - t1).count();
        writeFile(memPersistTimePath, std::to_string(memPersistTime));
        return 0;
    } catch (const std::exception &e) {
        OH_LOG_Print(LOG_APP, LOG_WARN, 0x00008, "hm_metricx_cj", "persistMemoryData - exception: %s", e.what());
        return -1;
    }
}

bool IsSigCaught() { return xh_util_get_sig_caught() != 0; }

void ResetSigCaught() { xh_util_set_sig_caught(0); }

void MarkCrash() { inCrash = 1; }

}