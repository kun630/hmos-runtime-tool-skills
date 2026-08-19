/*
 * Copyright (c) Huawei Technologies Co., Ltd. 2025-2025. All rights reserved.
 */
package ohos_app_cangjie_hm_metricx_cj.freeze

import ohos_app_cangjie_hm_metricx_cj.util.*
import tpc.AbilityKit.kit_common.*
import tpc.AbilityKit.errorManager.*
import tpc.PerformanceAnalysisKit.hiAppEvent.*
import tpc.PerformanceAnalysisKit.hidebug.*
import tpc.AbilityKit.ApplicationContext
import tpc.AbilityKit.getRunningProcessInformation
import stdx.encoding.json.*
import std.fs.*
import std.collection.*
import ohos.hilog.Hilog
import tpc.CoreFileKit.fs.listFile
import tpc.CoreFileKit.fs.dup
import ohos.base.AppLog
import std.convert.*
import std.posix.getpid
import ohos.base.nativeLog
import ohos.base.ArrayLike
import std.sort.stableSort
import ohos.device_info.DeviceInfo

public class FreezeInfo {
    private var timestampValue: ?String = None
    private var pidValue: ?String = None
    private var exceptionValue: ?String = None
    private var hilogValue: ?String = None
    private var tidValue: ?String = None
    private var tnameValue: ?String = None
    private var extraInfoValue: ?JsonValue = None
    private var freezeLogPathValue: ?String = None
    //freezeExtLogPathValue
    private var freezeExtLogPathValue: ?String = None
    private var cpuThreadValue: ?HashMap<String, String> = None
    private var cpuValue: ?HashMap<String, String> = None
    private var stacktraceValue: ?ArrayList<String> = None
    private var rawFileValue: ?String = None
    //extRawFileValue
    private var extRawFileValue: ?String = None
    private var historyRawFilesValue: ?String = None

    public mut prop timestamp: ?String {
        get() {
            timestampValue
        }
        set(value) {
            timestampValue = value
        }
    }

    public mut prop pid: ?String {
        get() {
            pidValue
        }
        set(value) {
            pidValue = value
        }
    }

    public mut prop exception: ?String {
        get() {
            exceptionValue
        }
        set(value) {
            exceptionValue = value
        }
    }

    public mut prop hilog: ?String {
        get() {
            hilogValue
        }
        set(value) {
            hilogValue = value
        }
    }

    public mut prop tid: ?String {
        get() {
            tidValue
        }
        set(value) {
            tidValue = value
        }
    }

    public mut prop tname: ?String {
        get() {
            tnameValue
        }
        set(value) {
            tnameValue = value
        }
    }

    public mut prop extraInfo: ?JsonValue {
        get() {
            extraInfoValue
        }
        set(value) {
            extraInfoValue = value
        }
    }

    public mut prop freezeLogPath: ?String {
        get() {
            freezeLogPathValue
        }
        set(value) {
            freezeLogPathValue = value
        }
    }
    //freezeExtLogPath
    public mut prop freezeExtLogPath: ?String {
        get() {
            freezeExtLogPathValue
        }
        set(value) {
            freezeExtLogPathValue = value
        }
    }

    public mut prop cpuThread: ?HashMap<String, String> {
        get() {
            cpuThreadValue
        }
        set(value) {
            cpuThreadValue = value
        }
    }

    public mut prop cpu: ?HashMap<String, String> {
        get() {
            cpuValue
        }
        set(value) {
            cpuValue = value
        }
    }

    public mut prop stacktrace: ?ArrayList<String> {
        get() {
            stacktraceValue
        }
        set(value) {
            stacktraceValue = value
        }
    }

    public mut prop rawFile: ?String {
        get() {
            rawFileValue
        }
        set(value) {
            rawFileValue = value
        }
    }
    //extRawFile
    public mut prop extRawFile: ?String {
        get() {
            extRawFileValue
        }
        set(value) {
            extRawFileValue = value
        }
    }

    public mut prop historyRawFiles: ?String {
        get() {
            historyRawFilesValue
        }
        set(value) {
            historyRawFilesValue = value
        }
    }

    public func toString(): String {
        let jsonObj = JsonObject()
        if (timestampValue.isSome()) {
            jsonObj.put("timestamp", JsonString(timestampValue.getOrThrow()))
        }
        if (pidValue.isSome()) {
            jsonObj.put("pid", JsonString(pidValue.getOrThrow()))
        }
        if (exceptionValue.isSome()) {
            jsonObj.put("exception", JsonString(exceptionValue.getOrThrow()))
        }
        if (hilogValue.isSome()) {
            jsonObj.put("hilog", JsonString(hilogValue.getOrThrow()))
        }
        if (tidValue.isSome()) {
            jsonObj.put("tid", JsonString(tidValue.getOrThrow()))
        }
        if (tnameValue.isSome()) {
            jsonObj.put("tname", JsonString(tnameValue.getOrThrow()))
        }
        if (extraInfoValue.isSome()) {
            jsonObj.put("extraInfo", extraInfoValue.getOrThrow())
        }
        if (freezeLogPathValue.isSome()) {
            jsonObj.put("freezeLogPath", JsonString(freezeLogPathValue.getOrThrow()))
        }
        //freezeExtLogPathValue
        if (freezeExtLogPathValue.isSome()) {
            jsonObj.put("freezeExtLogPath", JsonString(freezeExtLogPathValue.getOrThrow()))
        }
        if (cpuThreadValue.isSome()) {
            jsonObj.put("cpuThread", map2json(cpuThreadValue.getOrThrow()))
        }
        if (cpuValue.isSome()) {
            jsonObj.put("cpu", map2json(cpuValue.getOrThrow()))
        }
        if (rawFileValue.isSome()) {
            jsonObj.put("rawFile", JsonString(rawFileValue.getOrThrow()))
        }
        //extRawFileValue
        if (extRawFileValue.isSome()) {
            jsonObj.put("freezeExtRawFile", JsonString(extRawFileValue.getOrThrow()))
        }
        if (stacktraceValue.isSome()) {
            let arrJson = ArrayList<JsonValue>()
            stacktraceValue
                .getOrThrow()
                .iterator()
                .forEach({
                    entry =>
                    arrJson.add(JsonValue.fromStr(JsonString(entry).toJsonString()))
                })
            jsonObj.put("stacktrace", JsonArray(arrJson))
        }
        if (let Some(v) <- historyRawFiles) {
            jsonObj.put("historyRawFiles", JsonString(v))
        }
        jsonObj.toString()
    }
}

private var freezeInited = false
private var iCollectFreezeInfo: () -> JsonValue = { => JsonValue.fromStr("{}") }

public func initFreezeHandler(
    applicationContext: ApplicationContext,
    collectFreezeInfo: () -> JsonValue,
    reportFreezeInfo: (freezeInfo: FreezeInfo) -> Unit,
    persistentDir: Path
): Unit {
    if (freezeInited) {
        return
    }
    let cleanFileRecordPath = persistentDir.join("cleanFileRecord.txt")
    cleanHistoryLogFiles({name => name.startsWith("APP_FREEZE")}, cleanFileRecordPath, "initFreezeHandler")
    iCollectFreezeInfo = collectFreezeInfo
    let cpuUsageFilePath = persistentDir.join("cpuUsageFreeze.txt")
    let cpuUsageBakFilePath = persistentDir.join("cpuUsageFreeze-bak.txt")
    renameFile(cpuUsageFilePath, cpuUsageBakFilePath)
    let extraInfoFilePath = persistentDir.join("extraInfoFreeze.json")
    let extraInfoBakFilePath = persistentDir.join("extraInfoFreeze-bak.json")
    renameFile(extraInfoFilePath, extraInfoBakFilePath)
    let ignoreFilePath = persistentDir.join("ignoreFreeze.txt")
    initFreezeWatcher(applicationContext, reportFreezeInfo, cpuUsageBakFilePath, extraInfoBakFilePath, cleanFileRecordPath, ignoreFilePath)
    if (DeviceInfo.sdkApiVersion >= 18) {
        onFreeze({ => freezeCallback(ignoreFilePath, cpuUsageFilePath, extraInfoFilePath)})
    } else {
        initHilogWatcher(ignoreFilePath, cpuUsageFilePath, extraInfoFilePath)
    }
    freezeInited = true
}

var reportFlag = false
private func freezeCallback(ignoreFilePath: Path, cpuUsageFilePath: Path, extraInfoFilePath: Path): Unit {
    if (!reportFlag) {
        collectFreezeInfo(ignoreFilePath, cpuUsageFilePath, extraInfoFilePath)
        reportFlag = true
    }
}

private func collectFreezeInfo(ignoreFilePath: Path, cpuUsageFilePath: Path, extraInfoFilePath: Path): Unit {
    unsafe {
        let cpuUsageFilePath = LibC.mallocCString(cpuUsageFilePath.toString())
        let extraInfoFilePath = LibC.mallocCString(extraInfoFilePath.toString())
        let ignoreFilePath = LibC.mallocCString(ignoreFilePath.toString())
        if (registerFreezeCallback(ignoreFilePath, cpuUsageFilePath, extraInfoFilePath, collectExtraFreezeInfo) != 0) {
            AppLog.warn("registerFreezeCallback failed.")
        }
        LibC.free(cpuUsageFilePath)
        LibC.free(extraInfoFilePath)
        LibC.free(ignoreFilePath)
    }
}

private func initFreezeWatcher(
    applicationContext: ApplicationContext,
    reportFreezeInfo: (freeezeInfo: FreezeInfo) -> Unit,
    cpuUsageFilePath: Path,
    extraInfoFilePath: Path,
    cleanFileRecordPath: Path,
    ignoreFilePath: Path
) {
    let watcher = Watcher(
        "freezeWatcher",
        appEventFilters: [AppEventFilter(OS, eventTypes: [FAULT], names: [APP_FREEZE])],
        onReceive: {
            domain: String, appEventGroups: Array<AppEventGroup> =>
            try {
                if (domain != OS) {
                    return
                }
                var shouldIgnore = false
                if (exists(ignoreFilePath)) {
                    shouldIgnore = true
                    deleteFile(ignoreFilePath)
                }
                let freezeInfo = FreezeInfo()
                if (exists(cpuUsageFilePath)) {
                    try {
                        if (freezeInfo.cpuThread.isNone()) {
                            let fileContent = String.fromUtf8(File.readFrom(cpuUsageFilePath))
                            freezeInfo.cpuThread = extractDataFromLog(fileContent)
                        }
                    } catch (e: Exception) {
                        AppLog.warn(e.toString())
                    }
                    deleteFile(cpuUsageFilePath)
                }
                else {
                    AppLog.warn("No persistent cpuUsage file.")
                }
                if (exists(extraInfoFilePath)) {
                    try {
                        if (freezeInfo.extraInfo.isNone()) {
                            let jsonObj = JsonValue.fromStr(String.fromUtf8(File.readFrom(extraInfoFilePath))).asObject()
                            freezeInfo.extraInfo = jsonObj.get("extraInfo")
                        }
                    } catch (e: Exception) {
                        AppLog.warn(e.toString())
                    }
                    deleteFile(extraInfoFilePath)
                }
                else {
                    AppLog.warn("No persistent extraInfo file.")
                }
                for (eventGroup in appEventGroups) {
                    if (eventGroup.name != APP_FREEZE) {
                        continue
                    }
                    for (eventInfo in eventGroup.appEventInfos) {
                        freezeInfo.timestamp = match (eventInfo.params.get("time")) {
                            case Some(value) => value.toString()
                            case _ => None
                        }
                        freezeInfo.pid = match (eventInfo.params.get("pid")) {
                            case Some(value) => value.toString()
                            case _ => None
                        }
                        freezeInfo.exception = match (eventInfo.params.get("exception")) {
                            case Some(value) => value.toString()
                            case _ => None
                        }
                        freezeInfo.hilog = match (eventInfo.params.get("hilog")) {
                            case Some(value) => hilogWordWrap(value.toString())
                            case _ => None
                        }

                        if (eventInfo.params.get("external_log").isNone()) {
                            freezeInfo.rawFile = "hm-metricx-cj freeze error: external_log is none"
                            continue
                        }
                        // Extract freeze log path from external_log param
                        let externalValue = eventInfo.params.get("external_log").getOrThrow()
                        var freezeLogPath: String = ""
                        var freezeExtLogPath: String = ""

                        // 统一按字符串处理
                        let extStr = externalValue.toString()

                        if (extStr.startsWith("[")) {
                            // 去掉 []
                            let inner = extStr.removePrefix("[").removeSuffix("]")
                            let parts = inner.split(",", removeEmpty: true)

                            freezeLogPath = match (parts.get(0)) {
                                case Some(v) => v
                                    .removePrefix(" ")
                                    .removePrefix("\"")
                                    .removeSuffix("\"")
                                case _ => ""
                            }

                            freezeExtLogPath = match (parts.get(1)) {
                                case Some(v) => v
                                    .removePrefix(" ")
                                    .removePrefix("\"")
                                    .removeSuffix("\"")
                                case _ => ""
                            }

                        } else {
                            freezeLogPath = extStr
                                .removePrefix("\"")
                                .removeSuffix("\"")
                        }

                        if (freezeLogPath.isEmpty() ) {
                            freezeInfo.rawFile = "hm-metricx-cj freeze error: freezeLogPath is empty"
                            freezeInfo.historyRawFiles = collectAndCleanHistoryLogFiles({name => name.startsWith("APP_FREEZE")},
                                cleanFileRecordPath, "initFreezeWatcher")
                            continue
                        }
                        if (!exists(freezeLogPath)) {
                            freezeInfo.rawFile = "hm-metricx-cj freeze error: freezeLogPath path ${freezeLogPath} does not exist"
                            continue
                        }
                        freezeInfo.freezeLogPath = freezeLogPath

                        if (!freezeExtLogPath.isEmpty()) {
                            freezeInfo.freezeExtLogPath = freezeExtLogPath
                        }
                        try {
                            freezeInfo.rawFile = readFile(Path(freezeLogPath), isReturnException: true)
                            let res = extractFromFreezeLog(freezeInfo.rawFile.getOrThrow())
                            deleteFile(freezeLogPath)
                            freezeInfo.tid = res[0]
                            freezeInfo.tname = res[1]
                            freezeInfo.stacktrace = res[2]
                            freezeInfo.cpu = res[3]
                            if (!freezeExtLogPath.isEmpty() && exists(freezeExtLogPath)) {
                                let content = readFile(Path(freezeExtLogPath), isReturnException: true)
                                if (!content.isEmpty()) {
                                    freezeInfo.extRawFile = content
                                }
                                deleteFile(freezeExtLogPath)
                            }
                        } catch (e: Exception) {
                            AppLog.warn(e.toString())
                        }
                    }
                }
                if (!shouldIgnore) {
                    reportFreezeInfo(freezeInfo)
                }
            } catch (e: Exception) {
                AppLog.warn("hm-metricx-cj freeze error: initFreezeWatcher error, " + e.toString())
            }
        }
    )
    addWatcher(watcher)
}

private func extractFromFreezeLog(content: String) {
    let lines = content.split("\n", removeEmpty: true)
    var tid: String = ""
    var tname: String = ""
    var cpuMap = HashMap<String, String>()
    var stacktrace = ArrayList<String>()

    var curLine: Int64 = -1
    for (i in 0..lines.size) {
        if (lines[i].startsWith("TID = ")) {
            tid = lines[i].removePrefix("TID = ")
            curLine = i
            break
        }
    }
    if (curLine == -1) {
        return (tid, tname, stacktrace, cpuMap)
    }

    let tidTag: String = "Tid:" + tid + ", Name:"
    for (i in curLine..lines.size) {
        if (lines[i].startsWith(tidTag)) {
            tname = lines[i].removePrefix(tidTag)
            curLine = i
            break
        }
    }
    curLine = curLine + 1
    for (i in curLine..lines.size) {
        if (!lines[i].startsWith("#")) {
            curLine = i
            break
        }
        stacktrace.add(lines[i])
    }
    let cpuTag = "Details of Processes:"
    for (i in curLine..lines.size) {
        if (lines[i].startsWith(cpuTag)) {
            curLine = i
            break
        }
    }
    curLine = curLine + 2
    for (i in curLine..lines.size) {
        let line = lines[i]
        if (!line.startsWith("  ")) {
            curLine = i
            break
        }
        let dataArray = line.split(" ", removeEmpty: true)
        cpuMap.add(dataArray[0], dataArray[1])
    }
    return (tid, tname, stacktrace, cpuMap)
}

private func extractDataFromLog(content: String): HashMap<String, String> {
    let cpuUsageMap = HashMap<String, String>()
    let cpuUsageStrs = content.split(",", removeEmpty: true)
    let cpuSize = cpuUsageStrs.size / 2
    for (i in 0..cpuSize) {
        cpuUsageMap.add(cpuUsageStrs[2 * i], cpuUsageStrs[2 * i + 1])
    }
    cpuUsageMap
}

foreign func registerFreezeHilogCallback(ignoreFilePath: CString, cpuUsageFilePath: CString, extraInfoFile: CString, cb: CFunc<() -> CString>): Int8
foreign func registerFreezeCallback(ignoreFilePath: CString, cpuUsageFilePath: CString, extraInfoFile: CString, cb: CFunc<() -> CString>): Int8

@C
func collectExtraFreezeInfo(): CString {
    let jsonObj = JsonObject()
    try {
        jsonObj.put("extraInfo", iCollectFreezeInfo())
    } catch (e: Exception) {
        AppLog.error(e.toString())
    }
    unsafe {
        let crashInfoCStr = LibC.mallocCString(jsonObj.toString())
        crashInfoCStr
    }
}

public func initHilogWatcher(ignoreFilePath: Path, cpuUsageFilePath: Path, extraInfoFilePath: Path): Unit {
    unsafe {
        let cpuUsageFilePath = LibC.mallocCString(cpuUsageFilePath.toString())
        let extraInfoFilePath = LibC.mallocCString(extraInfoFilePath.toString())
        let ignoreFilePath = LibC.mallocCString(ignoreFilePath.toString())
        if (registerFreezeHilogCallback(ignoreFilePath, cpuUsageFilePath, extraInfoFilePath, collectExtraFreezeInfo) != 0) {
            AppLog.warn("registerFreezeHilogCallback failed.")
        }
        LibC.free(cpuUsageFilePath)
        LibC.free(extraInfoFilePath)
        LibC.free(ignoreFilePath)
    }
}
