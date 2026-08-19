/*
 * Copyright (c) Huawei Technologies Co., Ltd. 2025-2025. All rights reserved.
 */

#ifndef TPCAPPLICATION_CRASH_H
#define TPCAPPLICATION_CRASH_H
#include "stdint.h"

extern "C" {
int8_t writeSystemLog(const char *pFilePath);
int8_t persistMemoryData(const char *mapPath, const char *memMallocPath, const char *parsedAddrPath,
                         const char *memPersistTimePath);
}
bool isInCrash();

#endif // TPCAPPLICATION_CRASH_H
