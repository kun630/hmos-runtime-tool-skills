/*
 * Copyright (c) Huawei Technologies Co., Ltd. 2025-2025. All rights reserved.
 * Modifications:
 * 1. Change the class name from LeakMonitor to MemoryMonitor.
 * 2. Delete the member variable thread_name of struct AllocRecord.
 * 3. Delete the ThreadInfo struct.
 * 4. MemoryMonitor adds member variable unique_backtrace and method SaveAllocRecordsToFile, ParseStackFrame, WriteAllocRecordToFile.
 * 5. MemoryMonitor deletes member variable memory_analyzer and method GetLeakAllocs, CurrentAllocIndex.
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

#ifndef KOOM_NATIVE_OOM_SRC_MAIN_JNI_INCLUDE_LEAK_MONITOR_H_
#define KOOM_NATIVE_OOM_SRC_MAIN_JNI_INCLUDE_LEAK_MONITOR_H_


#include "constants.h"
#include "utils/concurrent_hash_map.h"
#include <fstream>
#include <set>
#include <vector>


namespace kwai {
namespace memory_monitor {
struct AllocRecord {
    uint64_t index;
    uint32_t size;
    intptr_t address;
    uint32_t num_backtraces;
    uintptr_t backtrace[kMaxBacktraceSize];
};

class MemoryMonitor {
public:
    static MemoryMonitor &GetInstance();
    std::set<uintptr_t> unique_backtrace;
    bool Install(std::vector<std::string> *selected_list, std::vector<std::string> *ignore_list);
    void Uninstall();
    void SetMonitorThreshold(size_t threshold);
    void OnMonitor(uintptr_t address, size_t size);
    void RegisterAlloc(uintptr_t address, size_t size);
    void UnregisterAlloc(uintptr_t address);
    void SaveAllocRecordsToFile(const std::string &filename);
    std::string ParseStackFrame(uintptr_t pc, void **dl_cache);
    void WriteAllocRecordToFile(const std::shared_ptr<AllocRecord> &record, std::ofstream &ofs);

private:
    MemoryMonitor()
        : alloc_index_(0), has_install_monitor_(false), live_alloc_records_(),
          alloc_threshold_(kDefaultAllocThreshold) {}
    ~MemoryMonitor() = default;
    MemoryMonitor(const MemoryMonitor &);
    MemoryMonitor &operator=(const MemoryMonitor &);
    ConcurrentHashMap<intptr_t, std::shared_ptr<AllocRecord>> live_alloc_records_;
    std::atomic<uint64_t> alloc_index_;
    std::atomic<bool> has_install_monitor_;
    std::atomic<size_t> alloc_threshold_;
};
} // namespace memory_monitor
} // namespace kwai
#endif // KOOM_NATIVE_OOM_SRC_MAIN_JNI_INCLUDE_LEAK_MONITOR_H_
