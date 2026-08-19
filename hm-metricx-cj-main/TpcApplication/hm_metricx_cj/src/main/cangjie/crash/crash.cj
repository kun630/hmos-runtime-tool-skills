/*
 * Copyright (c) Huawei Technologies Co., Ltd. 2025-2025. All rights reserved.
 * Co-Author: AI
 */
package ohos_app_cangjie_hm_metricx_cj.crash

import ohos_app_cangjie_hm_metricx_cj.util.*
import tpc.PerformanceAnalysisKit.hiAppEvent.*
import tpc.AbilityKit.ApplicationContext
import std.fs.*
import std.collection.*
import ohos.base.AppLog
import std.convert.*
import std.env.*
import ohos.ability.ErrorManager
import ohos.ability.ErrorObserver
import stdx.compress.zlib.*
import stdx.encoding.json.*
import std.time.*
import std.sync.*
import std.io.*
import std.unicode.UnicodeStringExtension
import std.convert.*
import std.sort.*

public class CrashCallbacks {
    public var collectCrashInfo: Option<() -> JsonValue> = None
    public var reportCrashInfo: (CrashInfo) -> Unit

    public init(collectCrashInfo!: Option<() -> JsonValue> = None, reportCrashInfo!: (CrashInfo) -> Unit) {
        this.collectCrashInfo = collectCrashInfo
        this.reportCrashInfo = reportCrashInfo
    }
}

public class CrashConfig {
    public var memMonitor: Option<CMemMonitorConfig> = None
    public var lastNHilogNumber: Int64 = 1000
    public var systemLogNumber: Int64 = 1000

    public init(memMonitor!: Option<CMemMonitorConfig> = None, lastNHilogNumber!: Int64 = 1000, systemLogNumber!: Int64 = 1000) {
        this.memMonitor = memMonitor
        this.lastNHilogNumber = lastNHilogNumber
        this.systemLogNumber = systemLogNumber
    }
}

public class CrashInfo {
    private var languageValue: ?String = None
    private var meminfoValue: ?String = None
    private var timestampValue: ?String = None
    private var pidValue: ?String = None
    private var pnameValue: ?String = None
    private var stacktraceValue: ?String = None
    private var hilogValue: ?String = None
    private var tidValue: ?String = None
    private var tnameValue: ?String = None
    private var fdsValue: ?HashMap<String, String> = None
    private var limitsValue: ?String = None
    private var threadsValue: ?String = None
    private var extraInfoValue: ?JsonValue = None
    private var crashLogPathValue: ?String = None
    private var dumpOnOOMPathValue: ?String = None
    private var appVersionValue: ?String = None
    private var rawFileValue: ?String = None
    private var systemLogValue: ?String = None
    private var lastNHilogValue: ?String = None
    private var dumpTimeValue: ?String = None
    private var historyRawFilesValue: ?String = None
    private var nativeMemDetailValue: ?String = None
    private var memPersistTimeValue: ?String = None
    private var rawheapResourceTypeValue: ?String = None
    private var rawheapMemoryLimitValue: ?String = None
    private var rawheapCurrentMemoryValue: ?String = None
    private var rawheapExternalLogsValue: ?String = None
    private var rawheapFilePathValue: ?String = "/data/log/reliability/resource_leak/memory_leak"

    public mut prop language: ?String {
        get() { languageValue }
        set(value) { languageValue = value }
    }

    public mut prop meminfo: ?String {
        get() { meminfoValue }
        set(value) { meminfoValue = value }
    }

    public mut prop timestamp: ?String {
        get() { timestampValue }
        set(value) { timestampValue = value }
    }

    public mut prop pid: ?String {
        get() { pidValue }
        set(value) { pidValue = value }
    }

    public mut prop pname: ?String {
        get() { pnameValue }
        set(value) { pnameValue = value }
    }

    public mut prop stacktrace: ?String {
        get() { stacktraceValue }
        set(value) { stacktraceValue = value }
    }

    public mut prop hilog: ?String {
        get() { hilogValue }
        set(value) { hilogValue = value }
    }

    public mut prop tid: ?String {
        get() { tidValue }
        set(value) { tidValue = value }
    }

    public mut prop tname: ?String {
        get() { tnameValue }
        set(value) { tnameValue = value }
    }

    public mut prop fds: ?HashMap<String, String> {
        get() { fdsValue }
        set(value) { fdsValue = value }
    }

    public mut prop limits: ?String {
        get() { limitsValue }
        set(value) { limitsValue = value }
    }

    public mut prop threads: ?String {
        get() { threadsValue }
        set(value) { threadsValue = value }
    }

    public mut prop crashLogPath: ?String {
        get() { crashLogPathValue }
        set(value) { crashLogPathValue = value }
    }

    public mut prop extraInfo: ?JsonValue {
        get() { extraInfoValue }
        set(value) { extraInfoValue = value }
    }

    public mut prop dumpOnOOMPath: ?String {
        get() { dumpOnOOMPathValue }
        set(value) { dumpOnOOMPathValue = value }
    }

    public mut prop appVersion: ?String {
        get() { appVersionValue }
        set(value) { appVersionValue = value }
    }

    public mut prop rawFile: ?String {
        get() { rawFileValue }
        set(value) { rawFileValue = value }
    }

    public mut prop systemLog: ?String {
        get() { systemLogValue }
        set(value) { systemLogValue = value }
    }

    public mut prop lastNHilog: ?String {
        get() { lastNHilogValue }
        set(value) { lastNHilogValue = value }
    }

    public mut prop dumpTime: ?String {
        get() { dumpTimeValue }
        set(value) { dumpTimeValue = value }
    }

    public mut prop historyRawFiles: ?String {
        get() { historyRawFilesValue }
        set(value) { historyRawFilesValue = value }
    }

    public mut prop nativeMemDetail: ?String {
        get() { nativeMemDetailValue }
        set(value) { nativeMemDetailValue = value }
    }

    public mut prop memPersistTime: ?String {
        get() {
            memPersistTimeValue
        }
        set(value) {
            memPersistTimeValue = value
        }
    }

    public mut prop rawheapResourceType: ?String {
        get() {
            rawheapResourceTypeValue
        }
        set(value) {
            rawheapResourceTypeValue = value
        }
    }

    public mut prop rawheapMemoryLimit: ?String {
        get() {
            rawheapMemoryLimitValue
        }
        set(value) {
            rawheapMemoryLimitValue = value
        }
    }

    public mut prop rawheapCurrentMemory: ?String {
        get() {
            rawheapCurrentMemoryValue
        }
        set(value) {
            rawheapCurrentMemoryValue = value
        }
    }

    public mut prop rawheapExternalLogs: ?String {
        get() {
            rawheapExternalLogsValue
        }
        set(value) {
            rawheapExternalLogsValue = value
        }
    }

    public mut prop rawheapFilePath: ?String {
        get() {
            rawheapFilePathValue
        }
        set(value) {
            rawheapFilePathValue = value
        }
    }

    public func toString(): String {
        let jsonObj = JsonObject()
        if (let Some(v) <- languageValue) {
            jsonObj.put("language", JsonString(v))
        }
        if (let Some(v) <- meminfoValue) {
            jsonObj.put("meminfo", JsonString(v))
        }
        if (let Some(v) <- timestampValue) {
            jsonObj.put("timestamp", JsonString(v))
        }
        if (let Some(v) <- pidValue) {
            jsonObj.put("pid", JsonString(v))
        }
        if (let Some(v) <- pnameValue) {
            jsonObj.put("pname", JsonString(v))
        }
        if (let Some(v) <- stacktraceValue) {
            jsonObj.put("stacktrace", JsonString(v))
        }
        if (let Some(v) <- hilogValue) {
            jsonObj.put("hilog", JsonString(v))
        }
        if (let Some(v) <- tidValue) {
            jsonObj.put("tid", JsonString(v))
        }
        if (let Some(v) <- tnameValue) {
            jsonObj.put("tname", JsonString(v))
        }
        if (let Some(v) <- fdsValue) {
            jsonObj.put("fds", map2json(v))
        }
        if (let Some(v) <- limitsValue) {
            jsonObj.put("limits", JsonString(v))
        }
        if (let Some(v) <- threadsValue) {
            jsonObj.put("threads", JsonString(v))
        }
        if (let Some(v) <- extraInfoValue) {
            jsonObj.put("extraInfo", v)
        }
        if (let Some(v) <- crashLogPathValue) {
            jsonObj.put("crashLogPath", JsonString(v))
        }
        if (let Some(v) <- dumpOnOOMPathValue) {
            jsonObj.put("dumpOnOOMPath", JsonString(v))
        }
        if (let Some(v) <- appVersionValue) {
            jsonObj.put("appVersion", JsonString(v))
        }
        if (let Some(v) <- rawFileValue) {
            jsonObj.put("rawFile", JsonString(v))
        }
        if (let Some(v) <- systemLogValue) {
            jsonObj.put("systemLog", JsonString(v))
        }
        if (let Some(v) <- lastNHilogValue) {
            jsonObj.put("lastNHilog", JsonString(v))
        }
        if (let Some(v) <- dumpTimeValue) {
            jsonObj.put("dumpTime", JsonString(v))
        }
        if (let Some(v) <- historyRawFiles) {
            jsonObj.put("historyRawFiles", JsonString(v))
        }
        if (let Some(v) <- nativeMemDetailValue) {
            jsonObj.put("nativeMemDetail", JsonString(v))
        }
        if (let Some(v) <- memPersistTimeValue) {
            jsonObj.put("memPersistTime", JsonString(v))
        }
        if (let Some(v) <- rawheapResourceTypeValue) {
            jsonObj.put("rawheapResourceType", JsonString(v))
        }
        if (let Some(v) <- rawheapMemoryLimitValue) {
            jsonObj.put("rawheapMemoryLimit", JsonString(v))
        }
        if (let Some(v) <- rawheapCurrentMemoryValue) {
            jsonObj.put("rawheapCurrentMemory", JsonString(v))
        }
        if (let Some(v) <- rawheapExternalLogsValue) {
            jsonObj.put("rawheapExternalLogs", JsonString(v))
        }
        if (let Some(v) <- rawheapFilePathValue) {
            jsonObj.put("rawheapFilePath", JsonString(v))
        }
        jsonObj.toString()
    }

    public static func fromJson(jsonObject: JsonObject): CrashInfo {
        let crashInfo = CrashInfo()
        if (let Some(v) <- jsonObject.get("language")) {
            crashInfo.language = JsonValueToString(v)
        }
        if (let Some(v) <- jsonObject.get("meminfo")) {
            crashInfo.meminfo = JsonValueToString(v)
        }
        if (let Some(v) <- jsonObject.get("timestamp")) {
            crashInfo.timestamp = JsonValueToString(v)
        }
        if (let Some(v) <- jsonObject.get("pid")) {
            crashInfo.pid = JsonValueToString(v)
        }
        if (let Some(v) <- jsonObject.get("pname")) {
            crashInfo.pname = JsonValueToString(v)
        }
        if (let Some(v) <- jsonObject.get("stacktrace")) {
            crashInfo.stacktrace = JsonValueToString(v)
        }
        if (let Some(v) <- jsonObject.get("hilog")) {
            crashInfo.hilog = JsonValueToString(v)
        }
        if (let Some(v) <- jsonObject.get("tid")) {
            crashInfo.tid = JsonValueToString(v)
        }
        if (let Some(v) <- jsonObject.get("tname")) {
            crashInfo.tname = JsonValueToString(v)
        }
        if (let Some(v) <- jsonObject.get("fds")) {
            let fields: HashMap<String, JsonValue> = v.asObject().getFields()
            crashInfo.fds = json2map(fields)
        }
        if (let Some(v) <- jsonObject.get("limits")) {
            crashInfo.limits = JsonValueToString(v)
        }
        if (let Some(v) <- jsonObject.get("threads")) {
            crashInfo.threads = JsonValueToString(v)
        }
        if (let Some(v) <- jsonObject.get("extraInfo")) {
            crashInfo.extraInfo = v
        }
        if (let Some(v) <- jsonObject.get("crashLogPath")) {
            crashInfo.crashLogPath = JsonValueToString(v)
        }
        if (let Some(v) <- jsonObject.get("dumpOnOOMPath")) {
            crashInfo.dumpOnOOMPath = JsonValueToString(v)
        }
        if (let Some(v) <- jsonObject.get("appVersion")) {
            crashInfo.appVersion = JsonValueToString(v)
        }
        if (let Some(v) <- jsonObject.get("rawFile")) {
            crashInfo.rawFile = JsonValueToString(v)
        }
        if (let Some(v) <- jsonObject.get("systemLog")) {
            crashInfo.systemLog = JsonValueToString(v)
        }
        if (let Some(v) <- jsonObject.get("lastNHilog")) {
            crashInfo.lastNHilog = JsonValueToString(v)
        }
        if (let Some(v) <- jsonObject.get("dumpTime")) {
            crashInfo.dumpTime = JsonValueToString(v)
        }
        if (let Some(v) <- jsonObject.get("historyRawFiles")) {
            crashInfo.historyRawFiles = JsonValueToString(v)
        }
        if (let Some(v) <- jsonObject.get("nativeMemDetail")) {
            crashInfo.nativeMemDetail = JsonValueToString(v)
        }
        if (let Some(v) <- jsonObject.get("memPersistTime")) {
            crashInfo.memPersistTime = JsonValueToString(v)
        }
        if (let Some(v) <- jsonObject.get("rawheapResourceType")) {
            crashInfo.rawheapResourceType = JsonValueToString(v)
        }
        if (let Some(v) <- jsonObject.get("rawheapMemoryLimit")) {
            crashInfo.rawheapMemoryLimit = JsonValueToString(v)
        }
        if (let Some(v) <- jsonObject.get("rawheapCurrentMemory")) {
            crashInfo.rawheapCurrentMemory = JsonValueToString(v)
        }
        if (let Some(v) <- jsonObject.get("rawheapExternalLogs")) {
            crashInfo.rawheapExternalLogs = JsonValueToString(v)
        }
        if (let Some(v) <- jsonObject.get("rawheapFilePath")) {
            crashInfo.rawheapFilePath = JsonValueToString(v)
        }
        crashInfo
    }

    func reset() {
        this.meminfoValue = None
        this.languageValue = None
        this.timestampValue = None
        this.pidValue = None
        this.pnameValue = None
        this.stacktraceValue = None
        this.hilogValue = None
        this.tidValue = None
        this.tnameValue = None
        this.fdsValue = None
        this.limitsValue = None
        this.threadsValue = None
        this.extraInfoValue = None
        this.crashLogPathValue = None
        this.dumpOnOOMPathValue = None
        this.appVersionValue = None
        this.rawFileValue = None
        this.systemLogValue = None
        this.dumpTimeValue = None
        this.historyRawFilesValue = None
        this.nativeMemDetailValue = None
        this.memPersistTimeValue = None
        this.rawheapResourceTypeValue = None
        this.rawheapMemoryLimitValue = None
        this.rawheapCurrentMemoryValue = None
        this.rawheapExternalLogsValue = None
        this.rawheapFilePathValue = None
    }
}

class PersistentPaths {
    let dir: Path
    let lastCrashFilePath: Path
    let filePath: Path
    let systemLogPath: Path
    let memMapPath: Path
    let memMallocPath: Path
    let parsedAddrPath: Path
    let lastNHilogPath: Path
    let dumpTimePath: Path
    let memPersistTimePath: Path
    let cleanFileRecordPath: Path

    public init(persistentDir: Path) {
        this.dir = persistentDir
        this.lastCrashFilePath = persistentDir.join("lastCrash.json")
        this.filePath = persistentDir.join("crash.json")
        this.systemLogPath = persistentDir.join("crashSystemLog.txt")
        this.memMapPath = persistentDir.join("crashMemMap.txt")
        this.memMallocPath = persistentDir.join("crashMemMalloc.txt")
        this.parsedAddrPath = persistentDir.join("crashParsedAddrPath.txt")
        this.lastNHilogPath = persistentDir.join("crashLastNHilog.txt")
        this.dumpTimePath = persistentDir.join("dumpTime.txt")
        this.memPersistTimePath = persistentDir.join("crashMemPersistTime.txt")
        this.cleanFileRecordPath = persistentDir.join("cleanFileRecord.txt")
    }
}

class MallocModel {
    let size: Int64
    let ptr: Int64
    let stack: Array<Int64>

    public init(size: Int64, ptr: Int64, stack: Array<Int64>) {
        this.size = size
        this.ptr = ptr
        this.stack = stack
    }
}

class MallocStack {
    let stack: String
    let size: Int64
    public init(stack: String, size: Int64) {
        this.stack = stack
        this.size = size
    }
}

class ParsedAddr {
    let pc: Int64
    let parsedAddr: String
    let soName: String
    public init(pc: Int64, parsedAddr: String, soName: String){
        this.pc = pc
        this.parsedAddr = parsedAddr
        this.soName = soName
    }
}

private func extractInt64FromJsonValue(param: ?JsonValue): Int64 {
    match (param) {
        case Some(v) => Int64.tryParse(v.toString()).getOrThrow()
        case _ => 0
    }
}

public class CMemMonitorConfig {
    let shouldBeClusteredToThisSo: (soName: String) -> Bool
    public init(shouldBeClusteredToThisSo: (soName: String) -> Bool){
        this.shouldBeClusteredToThisSo = shouldBeClusteredToThisSo
    }
}

@C
struct DumpTime {
    var total: Int64 = 0
    var stw: Int64 = 0
    var fork: Int64 = 0
    var dump: Int64 = 0
    var compress: Int64 = 0
}

private var inited = false
private let TIMEOUT = Duration.second
private let reported = HashSet<String>()
private var OOMHandlerInited = false;
private let PRIORITY_HIGH: Array<String> = []
private let PRIORITY_LOW: Array<String> = []
public var crashPid: String = ""
var crash_init_flag = false

public func initCrashHandler(
    applicationContext: ApplicationContext,
    persistentDir: Path,
    callbacks: CrashCallbacks,
    config!: CrashConfig = CrashConfig()
) {
    if (crash_init_flag) {
    	return
    }
    crash_init_flag = true
    if (inited) {
        return
    }
    if (!exists(persistentDir)) {
        throw IllegalArgumentException("persistentDir does not exist: ${persistentDir}")
    }
    let persistentPaths = PersistentPaths(persistentDir)
    cleanHistoryLogFiles({name => name.startsWith("APP_CRASH")}, persistentPaths.cleanFileRecordPath, "initCrashHandler")
    let lastNHilogNumber = config.lastNHilogNumber
    let systemLogNumber = config.systemLogNumber
    if (lastNHilogNumber < 0 || systemLogNumber < 0) {
    	throw IllegalArgumentException("negative value ${lastNHilogNumber} or ${systemLogNumber}")
    }

    spawn { =>
        reportLastCrash(persistentPaths, callbacks.reportCrashInfo)
    }
    let crashInfo = CrashInfo()
    crashInfo.limits = collectLimits()
    // 设置 collectCrashInfo
    var optCollectCrashInfo = callbacks.collectCrashInfo
    if (let Some(cb) <- optCollectCrashInfo) {
        initErrorObserver(crashInfo, applicationContext, cb, persistentPaths)

    } else {
        initErrorObserver(crashInfo, applicationContext, {=> JsonValue.fromStr("{}")}, persistentPaths)
    }
    var collectNativeCrashInfo = unsafe { LibC.mallocCString("{}") }
    initNativeSignalHandler(applicationContext, crashInfo.limits.getOrThrow(),
        {=> unsafe { LibC.mallocCString("{}") }}, persistentPaths, lastNHilogNumber, systemLogNumber)
    initCrashWatcher(applicationContext, callbacks.reportCrashInfo, persistentPaths, config.memMonitor)
    initResourceLeakWatcher(applicationContext, persistentPaths, callbacks.reportCrashInfo)

    initHilogWatcher()
    let optMemMonitor = config.memMonitor
    if(let Some(v) <- optMemMonitor){
        spawn { =>
            initNativeMemoryWatcher()
        }
    }
    spawn { =>
        initOOMHandler(persistentDir.toString())
    }
    inited = true
}

private func reportLastCrash(persistentPaths: PersistentPaths, reportCrashInfo: (crashInfo: CrashInfo) -> Unit) {
    if (exists(persistentPaths.lastCrashFilePath)) {
        try {
            let content = readFile(persistentPaths.lastCrashFilePath)
            deleteFile(persistentPaths.lastCrashFilePath)
            let jsonArr = JsonArray.fromStr(content).asArray()
            if (jsonArr.size() <= 0) {
                return
            }
            let dumpTime = readFile(persistentPaths.dumpTimePath)
            deleteFile(persistentPaths.dumpTimePath)
            for (i in 0..jsonArr.size()) {
                let jsonValue = jsonArr.get(i)
                if (let Some(v) <- jsonValue) {
                    let crashInfo = CrashInfo.fromJson(v.asObject())
                    crashInfo.dumpTime = dumpTime
                    if (let Some(pid) <- crashInfo.pid) {
                        crashInfo.dumpOnOOMPath = compressOOMFile(pid, persistentPaths.dir)
                        if (!reported.contains(pid)) {
                            reportCrashInfo(crashInfo)
                            reported.add(pid)
                        }
                    }
                }
            }
        } catch (e: JsonException) {
            AppLog.warn("hm-metricx-cj error: " + e.toString())
        }
    }
}

private func initOOMHandler(persistentDir: String) {
    setVariable("cjHeapDumpOnOOM", "on")
    setVariable("cjHeapDumpLog", persistentDir)
    unsafe {
        let pid = getProcessId().toString()
        let targetFile = LibC.mallocCString(persistentDir + "/cj_OOM_pid${pid}.dat")
        let zlibFile = LibC.mallocCString(persistentDir + "/cj_OOM_pid${pid}.zlib")
        let dumpTimePath = LibC.mallocCString(persistentDir + "/dumpTime.txt")
        if (InitOOMHandler(targetFile, dumpTimePath) != 0) {
            AppLog.warn("hm-metricx-cj error: InitOOMHandler failed.")
        }
        else {
            OOMHandlerInited = true
        }
        LibC.free(targetFile)
        LibC.free(zlibFile)
        LibC.free(dumpTimePath)
    }
}

private func initNativeSignalHandler(applicationContext: ApplicationContext, limits: String,
    collectCrashInfo: CFunc<() -> CString>, persistentPaths:PersistentPaths, lastNHilogNumber: Int64,
    systemLogNumber: Int64) {
    unsafe {
        let cstr = LibC.mallocCString(persistentPaths.filePath.toString())
        let lmts = LibC.mallocCString(limits)
        let cSystemLogPath = LibC.mallocCString(persistentPaths.systemLogPath.toString())
        let cLastNHilogPath = LibC.mallocCString(persistentPaths.lastNHilogPath.toString())
        let cMemMapPath=LibC.mallocCString(persistentPaths.memMapPath.toString())
        let cMemMallocPath = LibC.mallocCString(persistentPaths.memMallocPath.toString())
        let cParsedAddrPath = LibC.mallocCString(persistentPaths.parsedAddrPath.toString())
        let cMemPersistTimePath = LibC.mallocCString(persistentPaths.memPersistTimePath.toString())
        if (InitNativeSignalHandler(
            cstr,
            lmts,
            collectCrashInfo,
            cSystemLogPath,
            cMemMapPath,
            cMemMallocPath,
            cParsedAddrPath,
            cMemPersistTimePath,
            cLastNHilogPath,
            lastNHilogNumber,
            systemLogNumber,
            {
                persistentFilePath, limits, collectCrashInfo, fds, threads, meminfo =>
                try {
                    let crashInfo = CrashInfo()
                    crashInfo.limits = limits.toString()
                    crashInfo.fds = parseFDs(fds.toString())
                    // sometimes invoking collectThreads will crash, so read tids at native side
                    crashInfo.threads = threads.toString()
                    // sometimes invoking collectMemInfo will crash, so read meminfo at native side
                    crashInfo.meminfo = meminfo.toString()
                    crashInfo.extraInfo = JsonValue.fromStr(collectCrashInfo().toString())
                    let res = WriteCrashJson(LibC.mallocCString(crashInfo.toString()))
                    if (res != 0) {
                        AppLog.warn("hm-metricx-cj error: WriteCrashJson failed.")
                    }
                } catch (e: Exception) {
                    AppLog.warn("hm-metricx-cj error: " + e.toString())
                }
            }
        ) != 0) {
            AppLog.warn("hm-metricx-cj error: InitNativeSignalHandler failed.")
        }
        LibC.free(cstr)
        LibC.free(lmts)
        LibC.free(cSystemLogPath)
        LibC.free(cLastNHilogPath)
        LibC.free(cMemMapPath)
        LibC.free(cMemMallocPath)
        LibC.free(cParsedAddrPath)
        LibC.free(cMemPersistTimePath)
    }
}

private func parseFDs(fds: String) {
    let map: HashMap<String, String> = HashMap()
    let arr = fds.split(",", removeEmpty: true)
    if (arr.size % 2 != 0) {
        AppLog.warn("hm-metricx-cj error: parseFDs failed.")
        return map
    }
    var i = 0
    while (i < arr.size) {
        map.add(arr[i], arr[i + 1])
        i += 2
    }
    map
}

private func waitOOMDumping(applicationContext: ApplicationContext, dumpTimePath: Path): Unit {
    Timer.once(TIMEOUT) {
        let isOOMDumping = unsafe {
            IsOOMDumping()
        }
        AppLog.warn("hm_metricx_cj: isOOMDumping: ${isOOMDumping}")
        if (isOOMDumping) {
            waitOOMDumping(applicationContext, dumpTimePath)
        }
        else {
            let dumpTime = unsafe {
                GetDumpTime()
            }
            writeFile(dumpTimePath, "dump time: total: ${dumpTime.total} ms, stw: ${dumpTime.stw} ms, fork: ${dumpTime.fork} ms, dump: ${dumpTime.dump} ms")
            exit(applicationContext)
        }
    }
}

private func initErrorObserver(crashInfo: CrashInfo, applicationContext: ApplicationContext,
    collectCrashInfo: () -> JsonValue, persistentPaths: PersistentPaths) {
    let errorObserver = ErrorObserver(
        {errMsg: String =>},
        onException: {
            errObject =>
            try {
                unsafe { MarkCrash() }
                cleanHistoryLogFiles({name => name.startsWith("APP_CRASH")}, persistentPaths.cleanFileRecordPath,
                "initErrorObserver", keepLatest: false)
                crashInfo.meminfo = collectMemInfo()
                crashInfo.fds = collectFDInfo()
                crashInfo.threads = collectThreads()
                crashInfo.extraInfo = collectCrashInfo()
                writeFile(persistentPaths.filePath, crashInfo.toString())
                writeSystemLog2File(persistentPaths.systemLogPath.toString())
                writeLastNHilog2File(persistentPaths.lastNHilogPath.toString())
                persistMemoryData2File(persistentPaths.memMapPath.toString(), persistentPaths.memMallocPath.toString(),
                                        persistentPaths.parsedAddrPath.toString(), persistentPaths.memPersistTimePath.toString())
                if (OOMHandlerInited) {
                    waitOOMDumping(applicationContext, persistentPaths.dumpTimePath)
                }
                else {
                    exit(applicationContext)
                }
            } catch (e: Exception) {
                AppLog.warn("hm-metricx-cj error: initErrorObserver error, " + e.toString())
                exit(applicationContext)
            } catch (e: OutOfMemoryError) {
                AppLog.warn("hm-metricx-cj error: initErrorObserver OOM error, " + e.toString())
                exit(applicationContext)
            }
        }
    )
    let index = ErrorManager.on("error", errorObserver)
    if (index != 0) {
        // TODO Once ErrorManager supports "freeze" handler, this condition may need to be tweaked.
        AppLog.warn(
            "There are other error observers registered before crash obsverver, which may interfere with its behavior.")
    }
}

private func collectThreads() {
    readFile(Path("/proc/self/tids"))
}

private func collectLimits() {
    readFile(Path("/proc/self/limits"))
}

private func collectFDInfo() {
    let fds: HashMap<String, String> = HashMap()
    let path = Path("/proc/self/fd")
    if (!exists(path)) {
        return fds
    }
    try {
        Directory.walk(
            path,
            {
                file =>
                let fdPath = file.path
                if (exists(fdPath)) {
                    let realPath = SymbolicLink.readFrom(fdPath)
                    fds.add(fdPath.toString(), realPath.toString())
                } else {
                    fds.add(fdPath.toString(), "unknown")
                }
                true
            }
        )
    } catch (e: Exception) {
        AppLog.warn("hm-metricx-cj error: collectFDInfo failed: " + e.toString())
    } catch (e: OutOfMemoryError) {
        AppLog.warn("hm-metricx-cj error: collectFDInfo OOM failed: " + e.toString())
    }
    fds
}

private func collectMemInfo() {
    let rollupPath = Path("/proc/self/smaps_rollup")
    let smaps_rollup = readFile(rollupPath)
    var vss = ""
    let statmPath = Path("/proc/self/statm")
    try {
        let statm = readFile(statmPath)
        vss = "Vss:\t\t\t\t" + (Int32.tryParse(statm.split(" ", removeEmpty: true)[0]).getOrThrow() * 4).toString() + " KB"
    } catch (e:Exception) {
        AppLog.warn("hm-metricx-cj error: statm failed: " + e.toString())
    }
    smaps_rollup + "\n" + vss
}

private func initCrashWatcher(applicationContext: ApplicationContext, reportCrashInfo: (crashInfo: CrashInfo) -> Unit,
    persistentPaths: PersistentPaths, enableMemMonitor: Option<CMemMonitorConfig>) {
    let watcher = Watcher(
        "crashWatcher",
        appEventFilters: [AppEventFilter(OS, names: [APP_CRASH], eventTypes: [FAULT])],
        onReceive: {
            domain: String, appEventGroups: Array<AppEventGroup> =>
            try {
                if (domain != OS) {
                    return
                }
                
                var curCrashInfo = CrashInfo()
                if (exists(persistentPaths.filePath)) {
                    try {
                        let jsonObj = JsonValue.fromStr(String.fromUtf8(File.readFrom(persistentPaths.filePath))).asObject()
                        curCrashInfo = CrashInfo.fromJson(jsonObj)
                    } catch (e: JsonException) {
                        AppLog.warn("hm-metricx-cj error: " + e.toString())
                    }
                    deleteFile(persistentPaths.filePath)
                } else {
                    AppLog.warn("hm-metricx-cj error: No persistent crash file.")
                }
                curCrashInfo.dumpTime = readFile(persistentPaths.dumpTimePath)
                deleteFile(persistentPaths.dumpTimePath)
                curCrashInfo.systemLog = readFile(persistentPaths.systemLogPath).replace("\n\n", "\n")
                deleteFile(persistentPaths.systemLogPath)
                curCrashInfo.lastNHilog = readFile(persistentPaths.lastNHilogPath).replace("\n\n", "\n")
                deleteFile(persistentPaths.lastNHilogPath)
                curCrashInfo.memPersistTime = readFile(persistentPaths.memPersistTimePath)
                deleteFile(persistentPaths.memPersistTimePath)
                if (exists(persistentPaths.memMapPath) && exists(persistentPaths.memMallocPath)) {
                    var shouldBeClusteredToThisSo = {soName: String => false}
                    if(let Some(v) <- enableMemMonitor) {
                        shouldBeClusteredToThisSo=v.shouldBeClusteredToThisSo
                    }
                    curCrashInfo.nativeMemDetail = parseStackFrame(persistentPaths, shouldBeClusteredToThisSo)
                    deleteFile(persistentPaths.memMapPath)
                    deleteFile(persistentPaths.memMallocPath)
                    deleteFile(persistentPaths.parsedAddrPath)
                } else {
                    AppLog.warn("No persistent crash memory file.")
                }

                let nextReportCrashInfos = ArrayList<CrashInfo>()
                let reportCrashInfos = ArrayList<CrashInfo>()
                for (eventGroup in appEventGroups) {
                    if (eventGroup.name != APP_CRASH) {
                        continue
                    }
                    for (eventInfo in eventGroup.appEventInfos) {
                        let crashInfo = CrashInfo.fromJson(JsonValue.fromStr(curCrashInfo.toString()).asObject())
                        if (eventInfo.params.get("external_log").isNone()) {
                            crashInfo.rawFile = "hm-metricx-cj error: external_log is none"
                            continue
                        }
                        if (let Some(v) <- eventInfo.params.get("crash_type")) {
                            if (v.toString() == "JsError") {
                                crashInfo.language = "js_crash"
                            } else if (v.toString() == "NativeCrash") {
                                crashInfo.language = "cpp_crash"
                            }
                        }
                        crashInfo.timestamp = match (eventInfo.params.get("time")) {
                            case Some(value) => value.toString()
                            case _ => None
                        }
                        crashInfo.pid = match (eventInfo.params.get("pid")) {
                            case Some(value) => value.toString().removeSuffix(".000000")
                            case _ => None
                        }
                        if (let Some(v) <- crashInfo.pid) {
                            crashPid = v
                        }
                        crashInfo.stacktrace = match (eventInfo.params.get("exception")) {
                            case Some(value) => match (value) {
                                case OBJECT(v) => extractStackTrace(v)
                                case _ => unescapeString(value.toString())
                            }
                            case _ => "hm-metricx-cj error: exception is none"
                        }
                        crashInfo.hilog = match (eventInfo.params.get("hilog")) {
                            case Some(value) => hilogWordWrap(unescapeString(value.toString()))
                            case _ => None
                        }
                        crashInfo.appVersion = match (eventInfo.params.get("bundle_version")) {
                            case Some(value) => value.toString()
                            case _ => None
                        }
                        let crashLogPath: String = eventInfo.params.get("external_log")
                            .getOrThrow().toString().removePrefix("[").removeSuffix("]")
                        crashInfo.crashLogPath = crashLogPath
                        if (crashLogPath.isEmpty()) {
                            let logFileInfo = getLogFileInfo()
                            crashInfo.historyRawFiles = collectAndCleanHistoryLogFiles({name => name.startsWith("APP_CRASH")},
                                persistentPaths.cleanFileRecordPath, "initCrashWatcher")
                            crashInfo.rawFile = "hm-metricx-cj error: crash log path is empty \n" + logFileInfo + "\n" +
                                readFile(persistentPaths.cleanFileRecordPath)
                        } else {
                            if (!exists(crashLogPath)) {
                                crashInfo.rawFile = "hm-metricx-cj error: crash log path ${crashLogPath} does not exist \n" +
                                    getLogFileInfo() + "\n" + readFile(persistentPaths.cleanFileRecordPath)
                            } else {
                                let content = readFile(Path(crashLogPath), isReturnException: true)
                                crashInfo.rawFile = content
                                deleteFile(crashLogPath)
                                let res = extractFromCrashLog(content.split("\n", removeEmpty: true), crashInfo.pid,
                                    crashInfo.threads)
                                crashInfo.pname = res[0]
                                crashInfo.tid = res[1]
                                crashInfo.tname = res[2]
                            }
                        }

                        if (getProcessId().toString() == crashInfo.pid.getOrDefault({=> ""})) {
                            let shouldIgnore = crashInfo.language == "cpp_crash" && unsafe { IsSigCaught() }
                            if (shouldIgnore) {
                                unsafe {
                                    ResetSigCaught()
                                }
                                continue
                            }
                            nextReportCrashInfos.add(crashInfo)
                        } else {
                            reportCrashInfos.add(crashInfo)
                        }
                    }
                }
                if(!nextReportCrashInfos.isEmpty()) {
                    let jsonArray = JsonArray()
                    for (info in nextReportCrashInfos) {
                        jsonArray.add(JsonValue.fromStr(info.toString()))
                    }
                    writeFile(persistentPaths.lastCrashFilePath, jsonArray.toString())
                }
                if(!reportCrashInfos.isEmpty()) {
                    spawn { =>
                        for (crashInfo in reportCrashInfos) {
                            if (let Some(pid) <- crashInfo.pid) {
                                crashInfo.dumpOnOOMPath = compressOOMFile(pid, persistentPaths.dir)
                                // onReceive callback sometimes will be invoked both before app crash and next launch on high-verion (API 18?) devcies
                                if (!reported.contains(pid)) {
                                    reportCrashInfo(crashInfo)
                                    reported.add(pid)
                                }
                            }
                        }
                    }
                }
            } catch (e: Exception) {
                AppLog.warn("hm-metricx-cj error: initCrashWatcher error, " + e.toString())
            } catch (e: OutOfMemoryError) {
                AppLog.warn("hm-metricx-cj error: initCrashWatcher error, " + e.toString())
            }
        }
    )
    addWatcher(watcher)
}

private func compressOOMFile(pid: String, dir: Path): Option<String> {
    let rawDumpOnOOMPath = dir.join("cj_OOM_pid" + pid + ".dat")
    let dumpOnOOMPath = dir.join("cj_OOM_pid" + pid + ".zlib")

    if (exists(dumpOnOOMPath)) {
        return dumpOnOOMPath.toString()
    }

    if (!exists(rawDumpOnOOMPath)) {
        return Option.None
    }

    let ret = compressFile(rawDumpOnOOMPath.toString(), dumpOnOOMPath.toString())
    deleteFile(rawDumpOnOOMPath)
    if (!ret) {
        AppLog.warn("hm-metricx-cj error: compressFile failed in crash watcher.")
        return Option.None
    }
    return dumpOnOOMPath.toString()
}

/**
 * 初始化 resourceLeakWatcher - 监控 ArkTS 内存 OOM 预警
 */
private func initResourceLeakWatcher(applicationContext: ApplicationContext,
    persistentPaths: PersistentPaths,
    reportCrashInfo: (crashInfo: CrashInfo) -> Unit) {
    let watcher = Watcher(
        "resourceLeakWatcher",
        appEventFilters: [AppEventFilter(OS, names: [RESOURCE_OVERLIMIT], eventTypes: [FAULT])],
        onReceive: {
            domain: String, appEventGroups: Array<AppEventGroup> =>
            try {
                if (domain != OS) {
                    return
                }
                
                AppLog.info("hm-metricx-cj: RESOURCE_OVERLIMIT event received")
                
                for (eventGroup in appEventGroups) {
                    if (eventGroup.name != RESOURCE_OVERLIMIT) {
                        continue
                    }
                    for (eventInfo in eventGroup.appEventInfos) {
                        let crashInfo = CrashInfo()
                        crashInfo.pid = match (eventInfo.params.get("pid")) {
                            case Some(value) => value.toString().removeSuffix(".000000")
                            case _ => "unknown"
                        }
                        
                        crashInfo.dumpTime = match (eventInfo.params.get("time")) {
                            case Some(value) => value.toString()
                            case _ => getCurTimestampMillis()
                        }
                        
                        crashInfo.rawheapResourceType = match (eventInfo.params.get("resource_type")) {
                            case Some(value) => value.toString()
                            case _ => "unknown"
                        }
                        
                        var memoryLimit: Int64 = 0
                        var currentMemory: Int64 = 0
                        
                        if (let Some(memoryObj) <- eventInfo.params.get("memory")) {
                            let memStr = memoryObj.toString()
                            let memJson = JsonValue.fromStr(memStr).asObject()
                            memoryLimit = extractInt64FromJsonValue(memJson.get("limit_size"))
                            currentMemory = extractInt64FromJsonValue(memJson.get("live_object_size"))
                        }
                        crashInfo.rawheapMemoryLimit = memoryLimit.toString()
                        crashInfo.rawheapCurrentMemory = currentMemory.toString()
                        crashInfo.rawheapExternalLogs = match (eventInfo.params.get("external_log")) {
                            case Some(value) => value.toString()
                            case _ => "unknown"
                        }
                        reportCrashInfo(crashInfo)
                        
                        AppLog.info("hm-metricx-cj: RESOURCE_OVERLIMIT: pid=${crashInfo.pid}, resourceType=${crashInfo.rawheapResourceType}, memoryLimit=${memoryLimit}KB, currentMemory=${currentMemory}KB, externalLogs=${crashInfo.rawheapExternalLogs}")
                    }
                }
            } catch (e: Exception) {
                AppLog.warn("hm-metricx-cj error: initResourceLeakWatcher error, " + e.toString())
            } catch (e: OutOfMemoryError) {
                AppLog.warn("hm-metricx-cj error: initResourceLeakWatcher OOM error, " + e.toString())
            }
        }
    )
    addWatcher(watcher)
}

private func getLogFileInfo(): String {
    let info = ArrayList<String>()
    let path = "/data/storage/el2/log/hiappevent/"
    if (exists(path)) {
        Directory.walk(path, {
                file =>
                info.add("fileName: ${file.name}, createTime: ${file.creationTime.inLocal()}, size: ${(Float64(file.size)/1024.0).format(".3")}KB")
                true
        })
    }
    info.toString()
}

private func exit(applicationContext: ApplicationContext) {
    applicationContext.killAllProcesses({err, data =>})
}

private func extractStackTrace(obj: JsonObject): String {
    var res: String = ""
    try {
        if (obj.containsKey("stack")) {
            var name: String = ""
            var message: String = ""
            var stack: String = ""
            if (let Some(v) <- obj.get("name")) {
                name = v.asString().getValue()
            }
            if (let Some(v) <- obj.get("message")) {
                message = v.asString().getValue()
            }
            if (let Some(v) <- obj.get("stack")) {
                stack = v.asString().getValue()
            }
            res = "Error name: " + name + "\n" + "Error message: " + message + "\n" + "Stacktrace:\n" + stack + "\n"
        } else  if (obj.containsKey("frames")) {
            var message: String = ""
            if (let Some(v) <- obj.get("message")) {
                message = v.asString().getValue()
            }
            res += "message: " + message + "\n"
            if (let Some(sigValue) <- obj.get("signal")) {
                let sigObj : JsonObject = sigValue.asObject()
                var address: String = ""
                var code: String = ""
                var signo: String = ""
                if (let Some(v) <- sigObj.get("address")) {
                    address = v.asString().getValue()
                }
                if (let Some(v) <- sigObj.get("code")) {
                    code = v.asInt().toString()
                }
                if (let Some(v) <- sigObj.get("signo")) {
                    signo = v.asInt().toString()
                }
                res += "Signal:\n\tcode: " + code + " signo: " + signo + " address: " + address + "\n"
            }
            var tid: String = ""
            var tname: String = ""
            if (let Some(v) <- obj.get("tid")) {
                tid = v.asInt().toString()
            }
            if (let Some(v) <- obj.get("thread_name")) {
                tname = v.asString().toString()
            }
            res += "Tid: " + tid
            res += ", Name: " + tname + "\n"
            if (let Some(frameValue) <- obj.get("frames")) {
                let framesArray: JsonArray = frameValue.asArray()
                for (i in 0..framesArray.size()) {
                    let frameObj: JsonObject = framesArray[i].asObject()
                    var file: String = ""
                    var symbol: String = ""
                    var buildId: String = ""
                    var pc: String = ""
                    var offset: String = ""
                    if (let Some(v) <- frameObj.get("file")) {
                        file = v.asString().getValue()
                    }
                    if (let Some(v) <- frameObj.get("symbol")) {
                        symbol = v.asString().getValue()
                    }
                    if (let Some(v) <- frameObj.get("buildId")) {
                        buildId = v.asString().getValue()
                    }
                    if (let Some(v) <- frameObj.get("pc")) {
                        pc = v.asString().getValue()
                    }
                    if (let Some(v) <- frameObj.get("offset")) {
                        offset = v.asInt().toString()
                    }
                    var line: String = "#" + i.format("02") + " pc " + pc + " " + file
                    if (!symbol.isEmpty()) {
                        line +=  "(" + symbol
                        if (!offset.isEmpty()) {
                            line += "+" + offset
                        }
                        line += ")"
                    }
                    if (!buildId.isEmpty()) {
                        line += "(" + buildId + ")"
                    }
                    res += line + "\n"
                }
            }
        } else {
            res = obj.toString()
        }
    } catch (e: Exception) {
        AppLog.warn("hm-metricx-cj error: extractStackTrace exception: ${e.toString()}")
    }
    res
}

private func extractFromCrashLog(lines: Array<String>, pid: ?String, threads: ?String) {
    var moduleName = ""
    var tid = ""
    var tname = ""
    var pname = ""
    var cnt = 0
    for (line in lines) {
        cnt++
        if (cnt > 40) {
            break
        }
        if (line.startsWith("Module name:")) {
            moduleName = line.removePrefix("Module name:")
        } else if (line.startsWith("Process name:")) {
            pname = line.removePrefix("Process name:")
        } else if (line.startsWith("Tid:") && line.contains(", Name:")) {
            let arr = line.split(", ")
            if (arr.size != 2) {
                continue
            }
            tid = arr[0].removePrefix("Tid:")
            tname = arr[1].removePrefix("Name:")
            break
        }
    }
    if (pname.isEmpty()) {
        pname = moduleName
    }
    if (tid.isEmpty() && pid.isSome()) {
        tid = pid.getOrThrow()
        if (let Some(ts) <- threads) {
            let arr = ts.split("\n")
            for (thread in arr) {
                let prefix = tid + ":"
                if (thread.startsWith(prefix)) {
                    tname = thread.removePrefix(prefix)
                    break
                }
            }
        }
    }
    return (pname, tid, tname)
}

private func extractFromNativeCrashLog(lines: Array<String>) {
    var timestamp = ""
    var pid = ""
    var stacktrace = ""
    var hilog = ""
    var inHiLog = false
    var inStacktrace = false
    for (line in lines) {
        if (timestamp.isEmpty() && line.startsWith("Timestamp:")) {
            timestamp = line.removePrefix("Timestamp:")
        } else if (pid.isEmpty() && line.startsWith("Pid:")) {
            pid = line.removePrefix("Pid:")
        } else if (inHiLog) {
            hilog += line + "\n"
        } else if (line == "Reason:") {
            inStacktrace = true
            stacktrace += line.removePrefix("Reason:")
        } else if (line == "Other thread info:") {
            inStacktrace = false
        } else if (line == "HiLog:") {
            inHiLog = true
        } else if (inStacktrace) {
            stacktrace += line + "\n"
        }
    }
    return (timestamp, pid, stacktrace, hilog)
}

private func compressFile(src: String, dest: String): Bool {
    if (!exists(src)) {
        AppLog.warn("hm-metricx-cj error: compressFile failed due to ${src} does not exist")
        return false
    }
    var count: Int64 = 0
    try {
        let srcFile: File = File(src, OpenMode.Read)
        let destFile: File = File(dest, OpenMode.Append)

        var tempBuf: Array<UInt8> = Array<UInt8>(1024, repeat: 0)
        var compressOutputStream: CompressOutputStream = CompressOutputStream(destFile, wrap: GzipFormat)
        while (true) {
            var readNum = srcFile.read(tempBuf)
            if (readNum > 0) {
                compressOutputStream.write(tempBuf.slice(0, readNum).toArray())
                count += readNum
            } else {
                break
            }
        }
        compressOutputStream.flush()
        compressOutputStream.close()

        srcFile.close()
        destFile.close()
    } catch (e: Exception) {
        AppLog.warn("hm-metricx-cj error: compressFile failed due to ${e.toString()}")
    }
    return count > 0
}

private func writeSystemLog2File(persistentSystemLogPath: String) {
    unsafe {
        let filePath = LibC.mallocCString(persistentSystemLogPath)
        if (WriteSystemLog(filePath) != 0) {
            AppLog.warn("hm-metricx-cj error: write system log file failed.")
        }
        LibC.free(filePath)
    }
}

private func persistMemoryData2File(persistentMemMapFileName: String, persistentMemMallocPath: String,
    parsedAddrPath: String, memPersistTimePath: String) {
    unsafe {
        let mapFilePath = LibC.mallocCString(persistentMemMapFileName)
        let memMallocPath = LibC.mallocCString(persistentMemMallocPath)
        let cParsedAddrPath = LibC.mallocCString(parsedAddrPath)
        let cMemPersistTimePath = LibC.mallocCString(memPersistTimePath)
        if (persistMemoryData(mapFilePath, memMallocPath, cParsedAddrPath, cMemPersistTimePath) != 0) {
            AppLog.warn("write crash memMap file failed.")
        }
        LibC.free(mapFilePath)
        LibC.free(memMallocPath)
        LibC.free(cParsedAddrPath)
        LibC.free(cMemPersistTimePath)
    }
}

private func writeLastNHilog2File(persistentLastNHilogPath: String) {
    unsafe {
        let filePath = LibC.mallocCString(persistentLastNHilogPath)
        if (WriteLastNHiLog(filePath) != 0) {
            AppLog.warn("hm-metricx-cj error: write lastNHilog log file failed.")
        }
        LibC.free(filePath)
    }
}

private func initHilogWatcher() {
    unsafe {
        if (registerCrashSystemlogCallback() != 0) {
            AppLog.warn("hm-metricx-cj error: registerCrashSystemlogCallback failed.")
        }
        if (registerCrashLastNHilogCallback() != 0) {
            AppLog.warn("hm-metricx-cj error: registerCrashLastNHilogCallback failed.")
        }
    }
}

private func initNativeMemoryWatcher() {
    unsafe {
        if (installNativeMemoryMonitor() != 0) {
            AppLog.warn("registerNativeMemoryCallback failed.")
        }
    }
}

private func parseMallocLog(filePath: Path): List<MallocModel> {
    let mallocModels = ArrayList<MallocModel>()
    try {
        let reader = StringReader(File(filePath, OpenMode.Read))

        while (let Some(line) <- reader.readln()) {
            let strings = line.trim().split(" ", removeEmpty: true)
            if (strings.size < 3) {
                AppLog.info("parseMallocLog skiped line: " + line)
                continue
            }
            try {
                let size = Int64.parse(strings[0])
                let ptr = Int64.parse("0x" + strings[1])
                let stacks = strings[2].split(',', removeEmpty: true)
                let longStacks = Array<Int64>(stacks.size, {i => Int64.parse("0x" + stacks[i])})

                mallocModels.add(MallocModel(size, ptr, longStacks))
            } catch (e: Exception) {
                AppLog.info("parseMallocLog skiped line: ${line},exception: ${e.toString()}")
            }
        }
        reader.close()
    } catch (e: Exception) {
        AppLog.warn("parse malloc log failed: " + e.toString())
    }
    mallocModels
}

private func parseStackFrame(persistentPaths: PersistentPaths, shouldBeClusteredToThisSo: (soName: String) -> Bool): String {
    let parsedMap: String = parseMaps(persistentPaths.memMapPath, Int32.Max)
    let mallocModels = parseMallocLog(persistentPaths.memMallocPath)
    if (mallocModels.isEmpty()) {
        return ""
    }
    let stacks = getParsedStacks(persistentPaths.parsedAddrPath)
    let soMemory = getSoMemory(mallocModels, stacks, shouldBeClusteredToThisSo)
    let mallocStacks = parseMallocWithStack(mallocModels, stacks)
    soMemory + mallocStacks + parsedMap
}

private func getParsedStacks(parsedPath: Path): HashMap<Int64, ParsedAddr> {
    let map = HashMap<Int64, ParsedAddr>()
    try {
        let reader = StringReader(File(parsedPath, OpenMode.Read))
        while (let Some(line) <- reader.readln()) {
            try {
                let arr = line.split(" ", removeEmpty: true)
                let pc = arr[0]
                let pcInt = Int64.parse("0x" + pc)
                let parsedAddr = line.removePrefix(pc).trim()
                let soName = arr[2]
                map.add(pcInt, ParsedAddr(pcInt, parsedAddr, soName))
            } catch (e: Exception){
                AppLog.warn("getParsedStacks skip line: " + line)
            }
        }
        reader.close()
    } catch (e: Exception) {
        AppLog.warn("getParsedStacks failed: " + e.toString())
    }
    map
}

private func getSoMemory(mallocModels: List<MallocModel>, stackMap: HashMap<Int64, ParsedAddr>,
    shouldBeClusteredToThisSo: (soName: String) -> Bool): String {
    let soMemoryMap = HashMap<String, Int64>()
    for (mallocModel in mallocModels) {
        let so = findSo(mallocModel, stackMap, shouldBeClusteredToThisSo)
        let sum = (soMemoryMap.get(so) ?? 0) + mallocModel.size
        soMemoryMap.add(so, sum)
    }
    let by: ((String, Int64), (String, Int64)) -> Ordering = {
        a, b =>
            if (a[1] < b[1]) {
                return Ordering.GT
            } else if (a[1] > b[1]) {
                return Ordering.LT
            }
            return Ordering.EQ
    }
    let soMemoryArr = soMemoryMap.toArray()
    sort(soMemoryArr, by: by, stable: true)

    let stringBuilder = StringBuilder()
    var total: Int64 = 0
    stringBuilder.append("Malloc Group By So(kB):\n")
    for ((so, size) in soMemoryArr) {
        stringBuilder.append("${so}: ${size / 1024}\n")
        total += size / 1024
    }
    stringBuilder.append("Total: ${total} kB \n")
    stringBuilder.toString()
}

private func findSo(mallocModel: MallocModel, stackMap: HashMap<Int64, ParsedAddr>,
    shouldBeClusteredToThisSo: (soName: String) -> Bool): String {

    let soList = ArrayList<String>()
    let stacks = mallocModel.stack.clone()
    sort(stacks)
    for (pc in stacks) {
        if (let Some(parsedAddr) <- stackMap.get(pc)) {
            if (let Some(last) <- soList.last && last == parsedAddr.soName){
                continue
            }
            soList.add(parsedAddr.soName)
        }
    }

    var so: String = "<unknown>"
    for (soName in soList) {
        if (shouldBeClusteredToThisSo(soName)) {
            return soName
        }
        if (so == "<unknown>") {
            so = soName
        }
        if (let Some(v) <- PRIORITY_HIGH.indexOf(so) && let Some(p) <- PRIORITY_HIGH.indexOf(soName)) {
            if (v > p) {
                so = soName
            }
        } else if (PRIORITY_HIGH.contains(soName)) {
            so = soName
        } else if (!PRIORITY_HIGH.contains(so)) {
            so = soName
        }
    }
    so
}

private func parseMallocWithStack(mallocModels: List<MallocModel>, stacks: HashMap<Int64, ParsedAddr>): String {
    let mallocStacks = ArrayList<MallocStack>()
    for (mallocModel in mallocModels) {
        let stack = findStack(mallocModel.stack, stacks)
        mallocStacks.add(MallocStack(stack, mallocModel.size / 1024))
    }
    let by: (MallocStack, MallocStack) -> Ordering = {
        a, b =>
            if (a.size < b.size) {
                return Ordering.GT
            } else if (a.size > b.size) {
                return Ordering.LT
            }
            return Ordering.EQ
    }
    sort(mallocStacks, by: by)
    let stringBuilder = StringBuilder("\nMalloc Stack:\n")
    var index = 0

    for (mallocStack in mallocStacks) {
        stringBuilder.append("malloc ${index + 1}: ${mallocStack.size}kB\n")
        stringBuilder.append(mallocStack.stack)
        stringBuilder.append("\n")
        index++
    }
    stringBuilder.toString()
}

private func findStack(stack: Array<Int64>, stackMap: HashMap<Int64, ParsedAddr>): String {
    let stringBuilder = StringBuilder()
    for (pc in stack) {
        if (pc <= 0) {
            continue
        }
        var find: Bool = false
        if (let Some(parsedPc) <- stackMap.get(pc)) {
            stringBuilder.append(parsedPc.parsedAddr + "\n")
            find = true
        }
        if (!find) {
            stringBuilder.append("unknown \n")
        }
    }
    stringBuilder.toString()
}

private func parseMaps(filePath: Path, headCount: Int32): String {
    let specs = HashMap<String, Array<String>>(
        [("code", [".hap", ".hsp", ".har", ".so"]), ("malloc", ["libc_malloc"]), ("font", [".ttc", ".ttf", ".otf"]),
            ("stack", ["stack"]), ("thread", ["thread"])])
    let pathLength = HashMap<String, Int64>()
    let specPathLength = HashMap<String, Int64>()

    try {
        let reader = StringReader(File(filePath, OpenMode.Read))
        while (let Some(line) <- reader.readln()) {
            let segments = line.trim().split(" ", removeEmpty: true)
            if (segments.size < 5) {
                AppLog.info("parse memMap skiped line: " + line)
                continue
            }
            if (segments.size > 6) {
                for (str in segments[6..]) {
                    segments[5] += " " + str
                }
            }
            var zonePath = "unknown"
            if (segments.size >= 6) {
                zonePath = segments[5]
            }
            let zoneItem = segments[0].split("-")
            if (zoneItem.size != 2) {
                continue
            }
            try {
                let start = Int64.parse("0x" + zoneItem[0])
                let end = Int64.parse("0x" + zoneItem[1])
                let curSize = end - start

                let originPathSize = pathLength.get(zonePath) ?? 0
                pathLength.add(zonePath, originPathSize + curSize)

                for ((spec, keywords) in specs) {
                    for (keyword in keywords) {
                        if (zonePath.contains(keyword)) {
                            let specSize: Int64 = specPathLength.get(spec) ?? 0
                            specPathLength.add(spec, specSize + curSize)
                            break
                        }
                    }
                }
            } catch (e: Exception) {
                AppLog.info("parse memMap skiped line: ${line}, exception: ${e.toString()}")
            }
        }
        reader.close()
    } catch (e: Exception) {
        AppLog.warn("parse memMap failed: " + e.toString())
    }

    // 格式化
    let by: ((String, Int64), (String, Int64)) -> Ordering = {
        a, b =>
            if (a[1] < b[1]) {
                return Ordering.GT
            } else if (a[1] > b[1]) {
                return Ordering.LT
            }
            return Ordering.EQ
    }
    let specLengthArr = specPathLength.toArray()
    sort(specLengthArr, by: by, stable: true)
    let pathLengthArr = pathLength.toArray()
    sort(pathLengthArr, by: by, stable: true)

    let stringBuilder = StringBuilder()
    stringBuilder.append("Memory Map:\n")
    stringBuilder.append("============Summarry============\n")
    for ((spec, size) in specLengthArr) {
        stringBuilder.append("${formatWithCommasAndPadding(size / 1024, 10)} kB    ${spec}\n")
    }

    stringBuilder.append("============Details============\n")
    var totalSize: Int64 = 0
    var count: Int32 = 0
    for ((path, size) in pathLengthArr) {
        stringBuilder.append("${formatWithCommasAndPadding(size / 1024, 10)} kB    ${path}\n")
        totalSize += size
        count++
        if (count >= headCount) {
            stringBuilder.append("${(-1).format("10")} kB   others\n")
            break
        }
    }
    stringBuilder.append("${formatWithCommasAndPadding(totalSize / 1024, 10)} kB    Total\n")
    stringBuilder.toString()
}

foreign func InitNativeSignalHandler(persistentFilePath: CString, limits: CString,
    collectCrashInfo: CFunc<() -> CString>, persistentSystemLogPath: CString, pMemMapFilePath: CString,
    pMemMallocPath: CString, parsedAddrPath: CString, memPersistTimePath: CString,
    persistentLastNHilogPath: CString, lastNHilogNumber: Int64, systemLogNumber: Int64,
    cb: CFunc<(CString, CString, CFunc<() -> CString>, CString, CString, CString) -> Unit>): Int8

foreign func InitOOMHandler(targetFile: CString, dumpTimePath: CString): Int8

foreign func WriteCrashJson(content: CString): Int8

foreign func WriteSystemLog(persistentFilePath: CString): Int8

foreign func WriteLastNHiLog(persistentFilePath: CString): Int8

foreign func registerCrashSystemlogCallback(): Int8

foreign func registerCrashLastNHilogCallback(): Int8

foreign func registerCrashHilogCallback(): Int8

foreign func IsOOMDumping(): Bool

foreign func GetDumpTime(): DumpTime

foreign func persistMemoryData(mapPath: CString, memMallocPath: CString, parsedAddrPath: CString, memPersistTimePath: CString): Int8

foreign func installNativeMemoryMonitor(): Int8

foreign func IsSigCaught(): Bool

foreign func ResetSigCaught(): Unit

foreign func MarkCrash(): Unit