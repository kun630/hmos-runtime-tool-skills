/*
 * Copyright (c) Huawei Technologies Co., Ltd. 2025-2025. All rights reserved.
 * Modifications:
 * 1. Change the class name from LeakMonitor to MemoryMonitor.
 * 2. Delete the member variable thread_name of struct AllocRecord.
 * 3. Delete the ThreadInfo struct.
 * 4. MemoryMonitor adds member variable unique_backtrace and method SaveAllocRecordsToFile, ParseStackFrame, WriteAllocRecordToFile.
 * 5. MemoryMonitor deletes member variable memory_analyzer and method GetLeakAllocs, CurrentAllocIndex.
 * 6. Add hooking mmap, munmap.
 * 7. Modify the implementation of the following methods: MemoryMonitor::Install, MemoryMonitor::RegisterAlloc.
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

#define LOG_TAG "memory_monitor"
#include "memory_monitor.h"
#include "backtrace_64.h"
#include "hook_helper.h"
#include "xdl/xdl.h"
#include <functional>
#include <hilog/log.h>
#include <iostream>
#include <regex>
#include <sstream>
#include <sys/mman.h>
#include <sys/time.h>
#include <thread>

namespace kwai {
namespace memory_monitor {

#define WRAP(x) x##Monitor
#define HOOK(ret_type, function, ...) static ALWAYS_INLINE ret_type WRAP(function)(__VA_ARGS__)

// Define allocator proxies; aligned_alloc included in API 28 and valloc/pvalloc
// can ignore in LP64 So we can't proxy aligned_alloc/valloc/pvalloc.
HOOK(void, free, void *ptr) {
    free(ptr);
    if (ptr) {
        MemoryMonitor::GetInstance().UnregisterAlloc(reinterpret_cast<uintptr_t>(ptr));
    }
}

HOOK(void *, mmap, void *addr, size_t size, int prot, int flags, int fd, off_t offset) {
    auto result = mmap(addr, size, prot, flags, fd, offset);
    MemoryMonitor::GetInstance().OnMonitor(reinterpret_cast<intptr_t>(result), size);
    return result;
}

HOOK(int, munmap, void *addr, size_t size) {
    auto result = munmap(addr, size);
    MemoryMonitor::GetInstance().OnMonitor(reinterpret_cast<intptr_t>(addr), size);
    return result;
}

HOOK(void *, malloc, size_t size) {
    auto result = malloc(size);
    MemoryMonitor::GetInstance().OnMonitor(reinterpret_cast<intptr_t>(result), size);
    return result;
}

HOOK(void *, realloc, void *ptr, size_t size) {
    auto result = realloc(ptr, size);
    if (ptr != nullptr) {
        MemoryMonitor::GetInstance().UnregisterAlloc(reinterpret_cast<uintptr_t>(ptr));
    }
    MemoryMonitor::GetInstance().OnMonitor(reinterpret_cast<intptr_t>(result), size);
    return result;
}

HOOK(void *, calloc, size_t item_count, size_t item_size) {
    auto result = calloc(item_count, item_size);
    MemoryMonitor::GetInstance().OnMonitor(reinterpret_cast<intptr_t>(result), item_count * item_size);
    return result;
}

HOOK(void *, memalign, size_t alignment, size_t byte_count) {
    auto result = memalign(alignment, byte_count);
    MemoryMonitor::GetInstance().OnMonitor(reinterpret_cast<intptr_t>(result), byte_count);
    return result;
}

HOOK(int, posix_memalign, void **memptr, size_t alignment, size_t size) {
    auto result = posix_memalign(memptr, alignment, size);
    MemoryMonitor::GetInstance().OnMonitor(reinterpret_cast<intptr_t>(*memptr), size);
    return result;
}

MemoryMonitor &MemoryMonitor::GetInstance() {
    static MemoryMonitor leak_monitor;
    return leak_monitor;
}

void MemoryMonitor::SaveAllocRecordsToFile(const std::string &filename) {
    if (live_alloc_records_.Size() == 0) {
        OH_LOG_Print(LOG_APP, LOG_WARN, 0x00008, "hm_metricx_cj",
                     "MemoryMonitor::DumpLiveAllocRecordsToFile - live_alloc_records_ size is 0");
        return;
    }
    std::ofstream ofs(filename);
    if (!ofs.is_open()) {
        OH_LOG_Print(LOG_APP, LOG_WARN, 0x00008, "hm_metricx_cj",
                     "MemoryMonitor::DumpLiveAllocRecordsToFile - Failed to open file %s for writeing.",
                     filename.c_str());
        return;
    }
    size_t count = 0;
    auto predicate = [this, &ofs, &count](const std::shared_ptr<AllocRecord> &record) {
        try {
            WriteAllocRecordToFile(record, ofs);
            ++count;
            return true;
        } catch (const std::exception &e) {
            OH_LOG_Print(LOG_APP, LOG_WARN, 0x00008, "hm_metricx_cj",
                         "MemoryMonitor::DumpLiveAllocRecordsToFile - Error writing record %{public}zu %{public}s.",
                         count + 1, e.what());
            return false;
        }
    };
    live_alloc_records_.Dump(predicate);
    ofs.close();
}

void MemoryMonitor::WriteAllocRecordToFile(const std::shared_ptr<AllocRecord> &record, std::ofstream &ofs) {

    if (!record) {
        OH_LOG_Print(LOG_APP, LOG_WARN, 0x00008, "hm_metricx_cj",
                     "MemoryMonitor::WriteAllocRecordToFile - Failed as record is null");
        return;
    }

    std::ostringstream oss;
    oss << record->size;
    oss << " " << std::hex << (unsigned long)record->address << " ";
    for (size_t i = 0; i < record->num_backtraces; ++i) {
        if (i < kBacktraceSkipIndex) {
            continue;
        }
        oss << record->backtrace[i];
        if (i != record->num_backtraces - 1) {
            oss << ",";
        }
        unique_backtrace.insert(record->backtrace[i]);
    }
    oss << std::endl;
    ofs << oss.str();
}

std::string MemoryMonitor::ParseStackFrame(uintptr_t pc, void **dl_cache) {
    Dl_info info;
    std::ostringstream oss;

    if (0 == xdl_addr((void *)pc, &info, dl_cache) || (uintptr_t)info.dli_fbase > pc) {
        oss << std::hex << std::setfill('0') << std::setw(16) << pc << " " << std::hex << std::setfill('0')
            << std::setw(16) << pc << "  <unknown>\n";
    } else {
        if (NULL == info.dli_fname || '\0' == info.dli_fname[0]) {
            oss << std::hex << std::setfill('0') << std::setw(16) << pc << " " << std::hex << std::setfill('0')
                << std::setw(16) << (pc - (uintptr_t)info.dli_fbase) << "  <anonymous:" << (uintptr_t)info.dli_fbase
                << ">\n";
        } else {
            if (NULL == info.dli_sname || '\0' == info.dli_sname[0]) {
                oss << std::hex << std::setfill('0') << std::setw(16) << pc << " " << std::hex << std::setfill('0')
                    << std::setw(16) << (pc - (uintptr_t)info.dli_fbase) << "  " << info.dli_fname << "\n";
            } else {
                if (0 == (uintptr_t)info.dli_saddr || (uintptr_t)info.dli_saddr > pc) {
                    oss << std::hex << std::setfill('0') << std::setw(16) << pc << " " << std::hex << std::setfill('0')
                        << std::setw(16) << (pc - (uintptr_t)info.dli_fbase) << "  " << info.dli_fname << " ("
                        << info.dli_sname << ")\n";
                } else {
                    oss << std::hex << std::setfill('0') << std::setw(16) << pc << " " << std::hex << std::setfill('0')
                        << std::setw(16) << (pc - (uintptr_t)info.dli_fbase) << "  " << info.dli_fname << " ("
                        << info.dli_sname << "+" << (pc - (uintptr_t)info.dli_saddr) << ")\n";
                }
            }
        }
    }

    return oss.str();
}

bool MemoryMonitor::Install(std::vector<std::string> *selected_list, std::vector<std::string> *ignore_list) {


    // Reinstall can't hook again
    if (has_install_monitor_) {
        OH_LOG_Print(LOG_APP, LOG_WARN, 0x00008, "hm_metricx_cj", "MemoryMonitor::Install - already installed");
        return true;
    }

    std::vector<const std::string> register_pattern = {".*\\.so$"};
    std::vector<const std::string> ignore_pattern = {".*/libhm_metricx_cj.so$", ".*/libhilog_ndk.z.so$",
                                                     ".*/libstdx.encoding.so$", ".*/libhilog.so$"};

    if (ignore_list != nullptr) {
        for (std::string &item : *ignore_list) {
            ignore_pattern.push_back(".*/" + item + ".so$");
        }
    }
    if (selected_list != nullptr && !selected_list->empty()) {
        // only hook the so in selected list
        register_pattern.clear();
        for (std::string &item : *selected_list) {
            register_pattern.push_back("^/data/.*/" + item + ".so$");
        }
    }
    std::vector<std::pair<const std::string, void *const>> hook_entries = {
        std::make_pair("malloc", reinterpret_cast<void *>(WRAP(malloc))),
        std::make_pair("realloc", reinterpret_cast<void *>(WRAP(realloc))),
        std::make_pair("calloc", reinterpret_cast<void *>(WRAP(calloc))),
        std::make_pair("memalign", reinterpret_cast<void *>(WRAP(memalign))),
        std::make_pair("posix_memalign", reinterpret_cast<void *>(WRAP(posix_memalign))),
        std::make_pair("mmap", reinterpret_cast<void *>(WRAP(mmap))),
        std::make_pair("munmap", reinterpret_cast<void *>(WRAP(munmap))),
        std::make_pair("free", reinterpret_cast<void *>(WRAP(free)))};

    init_arm64_unwind();
    if (HookHelper::HookMethods(register_pattern, ignore_pattern, hook_entries)) {
        has_install_monitor_ = true;
        return true;
    }

    HookHelper::UnHookMethods();
    live_alloc_records_.Clear();
    OH_LOG_Print(LOG_APP, LOG_WARN, 0x00008, "hm_metricx_cj", "MemoryMonitor::Install - install failed");

    return false;
}

void MemoryMonitor::Uninstall() {
    has_install_monitor_ = false;
    HookHelper::UnHookMethods();
    live_alloc_records_.Clear();
}

void MemoryMonitor::SetMonitorThreshold(size_t threshold) { alloc_threshold_ = threshold; }


ALWAYS_INLINE void MemoryMonitor::RegisterAlloc(uintptr_t address, size_t size) {
    if (!address || !size) {
        return;
    }

    auto unwind_backtrace = [](uintptr_t *frames, uint32_t *frame_count) {
        *frame_count = unwind_backtrace_64(frames, kMaxBacktraceSize);
    };

    auto alloc_record = std::make_shared<AllocRecord>();
    alloc_record->address = address;
    alloc_record->size = size;
    alloc_record->index = alloc_index_++;
    unwind_backtrace(alloc_record->backtrace, &(alloc_record->num_backtraces));
    if (alloc_record->num_backtraces > kBacktraceSkipIndex) {
        live_alloc_records_.Put(address, std::move(alloc_record));
    }
}

ALWAYS_INLINE void MemoryMonitor::UnregisterAlloc(uintptr_t address) { live_alloc_records_.Erase(address); }

ALWAYS_INLINE void MemoryMonitor::OnMonitor(uintptr_t address, size_t size) {
    if (!has_install_monitor_ || !address || size < alloc_threshold_.load(std::memory_order_relaxed)) {
        return;
    }

    RegisterAlloc(address, size);
}
} // namespace memory_monitor
} // namespace kwai