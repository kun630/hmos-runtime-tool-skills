/*
 * Copyright (c) Huawei Technologies Co., Ltd. 2025-2025. All rights reserved.
 */

#include "oom.h"
#include "common.h"
#include "xhook/xh_elf.h"
#include "xhook/xhook.h"
#include <KOOM/kwai_linker/elf_reader.h>
#include <cstdio>
#include <dlfcn.h>
#include <fcntl.h>
#include <fstream>
#include <hilog/log.h>
#include <inttypes.h>
#include <iostream>
#include <link.h>
#include <stdarg.h>
#include <string.h>
#include <string>
#include <sys/mman.h>
#include <sys/syscall.h>
#include <sys/types.h>
#include <unistd.h>
#include <sys/wait.h>
#include <chrono>
#include <thread>
#include "memory/hook_helper.h"

#define PAGE_SHIFT 12
#define PAGE_SIZE (1UL << PAGE_SHIFT)
#define PAGE_MASK (~(PAGE_SIZE - 1))
#define PAGE_START(addr) ((addr) & PAGE_MASK)
#define PAGE_END(addr) (PAGE_START(addr + sizeof(uintptr_t) - 1) + PAGE_SIZE)
#define PAGE_COVER(addr) (PAGE_END(addr) - PAGE_START(addr))

const char *cj_runtime = "libcangjie-runtime.so";

uintptr_t gBaseAddr = 0;

char *oomFile;

FILE *gFp;

bool isInitOOMHandler = false;
bool isOOMDumping = false;

std::string dumpFilePathStr = "";

typedef struct {
    long long total;
    long long stw;
    long long fork;
    long long dump;
} DumpTime;

DumpTime dumpTime = {0, 0, 0, 0};

class MutatorManager {
public:
    MutatorManager() {}
    ~MutatorManager() {}

    MutatorManager(const MutatorManager &) = delete;
    MutatorManager(MutatorManager &&) = delete;
    MutatorManager &operator=(const MutatorManager &) = delete;
    MutatorManager &operator=(MutatorManager &&) = delete;

    static MutatorManager &Instance() noexcept;

    void StopTheWorld(bool syncGCPhase, uint8_t phase);
    void StartTheWorld() noexcept;
};

MutatorManager &(*initMutatorManager)();

void (*stopTheWorld)(MutatorManager *, bool, uint8_t);

void (*startTheWorld)(MutatorManager *);

static void Noop(bool syncGCPhase, uint8_t phase) {}

int replaceFunc(uintptr_t baseAddr, uintptr_t offset, void *newFunc) {
    uintptr_t addr = baseAddr + offset;

    int res = mprotect((void *)PAGE_START(addr), PAGE_COVER(addr), PROT_READ | PROT_WRITE);

    if (res != 0) {
        return errno;
    }

    *(void **)addr = newFunc;

    __builtin___clear_cache((char *)PAGE_START(addr), (char *)PAGE_END(addr));

    return 0;
}

static FILE *Fopen(const char *filename, const char *mode) {
    if (!oomFile || std::strcmp(oomFile, filename) != 0) {
        return fopen(filename, mode);
    }
    isOOMDumping = true;
    auto t1 = std::chrono::high_resolution_clock::now();
    MutatorManager &mutatorManager = initMutatorManager();
    stopTheWorld(&mutatorManager, false, 1);
    auto t2 = std::chrono::high_resolution_clock::now();
    pid_t pid = fork();
    auto t3 = std::chrono::high_resolution_clock::now();
    if (pid == 0) {
        pthread_mutex_lock(&hook_mutex);
        xhook_clear();
        xhook_register(cj_runtime, "_ZN12MapleRuntime14MutatorManager12StopTheWorldEbNS_7GCPhaseE", (void *)Noop, nullptr);
        xhook_refresh(0);
        pthread_mutex_unlock(&hook_mutex);
        //replaceFunc(gBaseAddr, 0x11a440, (void *)Noop);
        FILE *fp = fopen(filename, mode);
        gFp = fp;
        return fp;
    } else {
        startTheWorld(&mutatorManager);
        int status;
        if (waitpid(pid, &status, 0) == -1) {
            OH_LOG_Print(LOG_APP, LOG_WARN, 0x00008, "hm_metricx_cj", "waitpid error: no child process or other reasons");
        }
        if (errno == EINTR) {
            OH_LOG_Print(LOG_APP, LOG_WARN, 0x00008, "hm_metricx_cj", "waitpid error: interrupted system call");
        }
        if (!WIFEXITED(status)) {
            OH_LOG_Print(LOG_APP, LOG_WARN, 0x00008, "hm_metricx_cj",
                         "waitpid error: child process %{public}d exited with status %{public}d, terminated by signal %{public}d",
                         pid, WEXITSTATUS(status), WTERMSIG(status));
        }
        auto t4 = std::chrono::high_resolution_clock::now();
        auto total = std::chrono::duration_cast<std::chrono::milliseconds>(t4 - t1).count();
        auto d1 = std::chrono::duration_cast<std::chrono::milliseconds>(t2 - t1).count();
        auto d2 = std::chrono::duration_cast<std::chrono::milliseconds>(t3 - t2).count();
        auto d3 = std::chrono::duration_cast<std::chrono::milliseconds>(t4 - t3).count();
        OH_LOG_Print(LOG_APP, LOG_WARN, 0x00008, "hm_metricx_cj", "dump time: total: %{public}lld ms, stw: %{public}lld ms, fork: %{public}lld ms, dump: %{public}lld ms",
                     total, d1, d2, d3);
        dumpTime = {total, d1, d2, d3};
        isOOMDumping = false;
        return nullptr;
    }
}

static int Fclose(FILE *fp) {
    int res = fclose(fp);
    if (gFp == fp) {
        _exit(0);
    }
    return res;
}

extern "C" __attribute__((weak)) int dl_iterate_phdr(int (*)(struct dl_phdr_info *, size_t, void *), void *);

struct dl_iterate_data {
    dl_phdr_info info_;
};

int dl_iterate_phdr_wrapper(int (*__callback)(struct dl_phdr_info *, size_t, void *), void *__data) {
    if (dl_iterate_phdr) {
        return dl_iterate_phdr(__callback, __data);
    }
    return 0;
}

static int dl_iterate_callback(dl_phdr_info *info, size_t size, void *data) {
    auto target = reinterpret_cast<dl_iterate_data *>(data);
    if (info->dlpi_addr != 0 && strstr(info->dlpi_name, target->info_.dlpi_name)) {
        target->info_.dlpi_name = info->dlpi_name;
        target->info_.dlpi_addr = info->dlpi_addr;
        target->info_.dlpi_phdr = info->dlpi_phdr;
        target->info_.dlpi_phnum = info->dlpi_phnum;
        return 1;
    }
    return 0;
}

void *Dlopen(const char *libName, int flags) {
    auto *data = new dl_iterate_data();
    data->info_.dlpi_name = libName;
    dl_iterate_phdr_wrapper(dl_iterate_callback, data);
    return data;
}

int Dlclose(void *handle) {
    delete (dl_iterate_data *)handle;
    return 0;
}

void *Dlsym(void *handle, const char *name) {
    if (!handle) {
        return nullptr;
    }

    auto *data = (dl_iterate_data *)handle;
    if (!data->info_.dlpi_name || data->info_.dlpi_name[0] != '/') {
        return nullptr;
    }

    kwai::linker::ElfReader elf_reader(std::make_shared<kwai::linker::FileElfWrapper>(data->info_.dlpi_name));
    if (!elf_reader.Init()) {
        return nullptr;
    }
    return elf_reader.LookupSymbol(name, data->info_.dlpi_addr, true);
}

void waitOOMDumping() {
    if (!isInitOOMHandler) {
        return;
    }
    const auto TIMEOUT = std::chrono::milliseconds(500);
    while (true) {
        std::this_thread::sleep_for(TIMEOUT);
        if (isOOMDumping) {
            continue;
        } else {
            std::ofstream ofs(dumpFilePathStr);
            if (ofs.is_open()) {
                ofs << "dump time: total: " << dumpTime.total 
                    << " ms, stw: " << dumpTime.stw 
                    << " ms, fork: " << dumpTime.fork 
                    << " ms, dump: " << dumpTime.dump << " ms";
                ofs.close();
            }
            break;
        }
    }
}

extern "C" {
int8_t InitOOMHandler(const char *targetFile, const char *dumpTimePath) {
    
    dumpFilePathStr = dumpTimePath;
    
    char line[512];
    FILE *fp;
    uintptr_t baseAddr = 0;

    if (NULL == (fp = fopen("/proc/self/maps", "r"))) {
        return FAIL;
    }

    while (fgets(line, sizeof(line), fp)) {
        if (NULL != strstr(line, cj_runtime) &&
            sscanf(line, "%" PRIxPTR "-%*lx %*4s 00000000", &baseAddr) == 1) {
            break;
        }
    }
    fclose(fp);
    
    pthread_mutex_lock(&hook_mutex);
    xhook_clear();
    if (xhook_register(cj_runtime, "fopen", (void *)Fopen, nullptr) != EXIT_SUCCESS) {
        pthread_mutex_unlock(&hook_mutex);
        return FAIL;
    }
    if (xhook_register(cj_runtime, "fclose", (void *)Fclose, nullptr) != EXIT_SUCCESS) {
        pthread_mutex_unlock(&hook_mutex);
        return FAIL;
    }
    if (xhook_refresh(0) != 0) {
        pthread_mutex_unlock(&hook_mutex);
        return FAIL;
    }
    pthread_mutex_unlock(&hook_mutex);

    void *handle = Dlopen(cj_runtime, RTLD_NOW);
    if (!handle) {
        return FAIL;
    }

    stopTheWorld = (void (*)(MutatorManager *, bool, uint8_t))Dlsym(
        handle, "_ZN12MapleRuntime14MutatorManager12StopTheWorldEbNS_7GCPhaseE");
    if (!stopTheWorld) {
        Dlclose(handle);
        return FAIL;
    }

    startTheWorld = (void (*)(MutatorManager *))Dlsym(handle, "_ZN12MapleRuntime14MutatorManager13StartTheWorldEv");
    if (!startTheWorld) {
        Dlclose(handle);
        return FAIL;
    }

    initMutatorManager = (MutatorManager & (*)()) Dlsym(handle, "_ZN12MapleRuntime14MutatorManager8InstanceEv");
    if (!initMutatorManager) {
        Dlclose(handle);
        return FAIL;
    }

    gBaseAddr = baseAddr;
    auto targetFileLen = strlen(targetFile);
    oomFile = new char[targetFileLen + 1];
    strncpy(oomFile, targetFile, targetFileLen);
    oomFile[targetFileLen] = '\0';
    
    isInitOOMHandler = true;
    return SUCCESS;
}

bool IsOOMDumping() {
    return isOOMDumping;
}

DumpTime GetDumpTime() {
    return dumpTime;
}
}