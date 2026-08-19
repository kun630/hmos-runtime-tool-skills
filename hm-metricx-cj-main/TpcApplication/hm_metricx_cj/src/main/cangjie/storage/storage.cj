/*
 * Copyright (c) Huawei Technologies Co., Ltd. 2025-2025. All rights reserved.
 */
package ohos_app_cangjie_hm_metricx_cj.storage

import stdx.encoding.json.*
import std.core.*
import std.fs.{Directory, Path, exists, FileInfo}
import std.collection.{TreeSet, ArrayList}
import tpc.CoreFileKit.storageStatistics.*
import tpc.CoreFileKit.fs.*
import tpc.AbilityKit.kit_common.*
import tpc.AbilityKit.bundleManager.*

public class StorageInfo {
    public var appSize: ?Int64 = None
    public var cacheSize: ?Int64 = None
    public var dataSize: ?Int64 = None
    public var totalSize: ?Int64 = None
    public var topStorageFileList = ArrayList<StorageFileInfo>()
    public var exceptionDirList = ArrayList<StorageFileInfo>()

    public init() {}

    public func toString(): String {
        let jsonObj = JsonObject()
        if (let Some(v) <- appSize) {
            jsonObj.put("appSize", JsonString(v.toString()))
        }
        if (let Some(v) <- dataSize) {
            jsonObj.put("dataSize", JsonString(v.toString()))
        }
        if (let Some(v) <- cacheSize) {
            jsonObj.put("cacheSize", JsonString(v.toString()))
        }
        if (let Some(v) <- totalSize) {
            jsonObj.put("totalSize", JsonString(v.toString()))
        }
        if (!topStorageFileList.isEmpty()) {
            jsonObj.put("topStorageFileList", JsonString(topStorageFileList.toString()))
        }
        if (!exceptionDirList.isEmpty()) {
            jsonObj.put("exceptionDirList", JsonString(exceptionDirList.toString()))
        }
        jsonObj.toString()
    }
}

public class StorageFileInfo <: Comparable<StorageFileInfo> & ToString {
    public let path: String
    public let size: Int64
    public var subfileList = TreeSet<StorageFileInfo>()
    public let isDir: Bool

    public init(f: FileInfo, isDir: Bool) {
        this.path = f.path.toString()
        this.size = f.size
        this.isDir = isDir
    }

    public init(path: String, size: Int64, isDir: Bool) {
        this.path = path
        this.size = size
        this.isDir = isDir
    }

    public func compare(f: StorageFileInfo) {
        if (this.size > f.size) {
            return Ordering.LT
        } else if (this.size < f.size) {
            return Ordering.GT
        }
        if (this.path < f.path) {
            return Ordering.LT
        } else if (this.path > f.path) {
            return Ordering.GT
        }
        return Ordering.EQ
    }

    public func toString(): String {
        let jsonObj = JsonObject()
        jsonObj.put("path", JsonString(path))
        jsonObj.put("size", JsonString(size.toString()))
        if (isDir) {
            jsonObj.put("subfileList", JsonString(subfileList.toString()))
        }
        jsonObj.toString().replace("\\\"", "\"").replace("\"[", "[").replace("]\"", "]")
    }
}

var reportStorageInfoCallback: (storageInfo: StorageInfo) -> Unit = {info: StorageInfo =>}
var sizeLimitValue: ?Int64 = None
var dirSizeLimitValue: ?Int64 = None
var reportTopNumValue: Int64 = 5
public func reportAppStorageInfo(): Unit {
    getCurrentBundleStats(
        {
            err, data => if (err.isNone()) {
                if (data.isSome()) {
                    let storageInfo = StorageInfo()
                    storageInfo.appSize = data.getOrThrow().appSize
                    storageInfo.dataSize = data.getOrThrow().dataSize
                    storageInfo.cacheSize = data.getOrThrow().cacheSize
                    if (storageInfo.appSize.isSome() && storageInfo.dataSize.isSome()) {
                        storageInfo.totalSize = storageInfo.appSize.getOrThrow() + storageInfo.dataSize.getOrThrow()
                    }

                    let allAppStorageFiles = TreeSet<StorageFileInfo>()
                    let allAppStorageDirs = TreeSet<StorageFileInfo>()

                    if (sizeLimitValue.isSome()) {
                        if (storageInfo.totalSize.getOrThrow() > sizeLimitValue.getOrThrow()) {
                            let storagePathList = getAllStoragePath()
                            let allStorageInfoList = ArrayList<StorageFileInfo>()
                            for (storagePath in storagePathList) {
                                if (!exists(storagePath)) {
                                    continue
                                }
                                let fileInfo = FileInfo(storagePath)
                                let storageDirInfo = getAllStorage(fileInfo, allAppStorageFiles)
                                allStorageInfoList.add(storageDirInfo)
                                if (dirSizeLimitValue.isSome()) {
                                    getDirsOverLimit(storageDirInfo, dirSizeLimitValue.getOrThrow(), allAppStorageDirs)
                                }
                            }
                            reportTopNFile(allAppStorageFiles, storageInfo.topStorageFileList, reportTopNumValue)
                            reportTopNFile(allAppStorageDirs, storageInfo.exceptionDirList, reportTopNumValue)
                        }
                    }
                    reportStorageInfoCallback(storageInfo)
                }
            }
        })
}

public func reportTopNFile(fileList: TreeSet<StorageFileInfo>, resultList: ArrayList<StorageFileInfo>, reportTopNum: Int64): Unit {
    var count: Int64 = 0
    for (storageFileInfo in fileList) {
        resultList.add(storageFileInfo)
        count++
        if (count == reportTopNum) {
            break
        }
    }
}

public func getDirsOverLimit(f: StorageFileInfo, dirLimitSize: Int64, dirSet: TreeSet<StorageFileInfo>): Unit {
    //Find the smallest folder level that exceeds the size limit
    let subfilePathList = f.subfileList
    var reportFlag = true
    if (f.size <= dirLimitSize) {
        return
    }
    for (subfile in subfilePathList) {
        if (!subfile.isDir) {
            continue
        }
        if (subfile.size > dirLimitSize) {
            getDirsOverLimit(subfile, dirLimitSize, dirSet)
            reportFlag = false
        }
    }
    if (reportFlag) {
        dirSet.add(f)
    }
}

public func getAllStoragePath(): ArrayList<String> {
    //Get storage path according to official documentation: https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/app-fs-space-statistics
    let storagePathList = ArrayList<String>(["/data/storage/el1/bundle",
        "/data/storage/el2/sharefiles",
        "/data/storage/el2/distributedfiles"])
    for (i in 1..6) {
        storagePathList.add("/data/storage/el${i}/base")
        storagePathList.add("/data/storage/el${i}/database")
    }
    storagePathList
}

public func getAllStorage(f: FileInfo, fileSet: TreeSet<StorageFileInfo>): StorageFileInfo {
    if (f.size <= 0) {
        return StorageFileInfo(f.path.toString(), 0, true)
    }
    let storageFilesList = TreeSet<StorageFileInfo>()
    var size = 0
    let fileList = Directory.readFrom(f.path)
    for (file in fileList) {
        if (file.isDirectory()) {
            let childStorageFileInfo = getAllStorage(file, fileSet)
            size += childStorageFileInfo.size
            storageFilesList.add(childStorageFileInfo)
        } else {
            let fileInfo = StorageFileInfo(file, false)
            fileSet.add(fileInfo)
            storageFilesList.add(fileInfo)
            size += fileInfo.size
        }
    }
    let parentStorageFileInfo = StorageFileInfo(f.path.toString(), size, true)
    parentStorageFileInfo.subfileList = storageFilesList
    parentStorageFileInfo
}

public func initStorageHandler(
    reportStorageInfo: (storageInfo: StorageInfo) -> Unit,
    sizeLimit!: Int64,
    dirSizeLimit!: Int64,
    reportTopNum!: Int64 = 5): Unit {
    sizeLimitValue = sizeLimit
    dirSizeLimitValue = dirSizeLimit
    reportTopNumValue = reportTopNum
    reportStorageInfoCallback = reportStorageInfo
}
