/*
 * Copyright (c) Huawei Technologies Co., Ltd. 2025-2025. All rights reserved.
 * 支持仓颉 (CJ) 和 ArkTS (JS) 堆内存监控
 */
package ohos_app_cangjie_hm_metricx_cj.memory

import ohos_app_cangjie_hm_metricx_cj.util.*
import tpc.AbilityKit.UIAbilityContext
import tpc.BasicServicesKit.*
import tpc.UIKit.Observer.*
import tpc.PerformanceAnalysisKit.hidebug.*
import tpc.UIKit.global.*
import std.convert.*
import stdx.encoding.json.*
import std.posix.*
import tpc.ArkData.preferences
import std.unicode.UnicodeStringExtension
import std.runtime.*

public open class MemoryInfo {
    private var avgMemoryValue: Int64 = 0
    private var maxMemoryValue: Int64 = 0
    private var avgCJMemoryValue: Int64 = 0
    private var maxCJMemoryValue: Int64 = 0
    private var avgArkTsMemoryValue: Int64 = 0
    private var maxArkTsMemoryValue: Int64 = 0
    private var sampleCountValue: Int64 = 0
    private var totalMemoryLimitValue: Int64 = 0
    private var cjMemoryLimitValue: Int64 = 0
    private var arkTsMemoryLimitValue: Int64 = 0
    private var isTotalTopValue: Bool = false
    private var isCJTopValue: Bool = false
    private var isArkTsTopValue: Bool = false
    private var totalRatioThresholdValue: Float64 = 0.8
    private var cjRatioThresholdValue: Float64 = 0.8
    private var arkTsRatioThresholdValue: Float64 = 0.8

    mut prop avgMemory: Int64 {
        get() {
            avgMemoryValue
        }
        set(value) {
            avgMemoryValue = value
        }
    }

    mut prop maxMemory: Int64 {
        get() {
            maxMemoryValue
        }
        set(value) {
            maxMemoryValue = value
        }
    }

    mut prop avgCJMemory: Int64 {
        get() {
            avgCJMemoryValue
        }
        set(value) {
            avgCJMemoryValue = value
        }
    }

    mut prop maxCJMemory: Int64 {
        get() {
            maxCJMemoryValue
        }
        set(value) {
            maxCJMemoryValue = value
        }
    }

    mut prop avgArkTsMemory: Int64 {
        get() {
            avgArkTsMemoryValue
        }
        set(value) {
            avgArkTsMemoryValue = value
        }
    }

    mut prop maxArkTsMemory: Int64 {
        get() {
            maxArkTsMemoryValue
        }
        set(value) {
            maxArkTsMemoryValue = value
        }
    }

    mut prop sampleCount: Int64 {
        get() {
            sampleCountValue
        }
        set(value) {
            sampleCountValue = value
        }
    }

    public init() {
        avgMemoryValue = 0
        maxMemoryValue = 0
        avgCJMemoryValue = 0
        maxCJMemoryValue = 0
        avgArkTsMemoryValue = 0
        maxArkTsMemoryValue = 0
        sampleCountValue = 0
        totalMemoryLimitValue = 0
        cjMemoryLimitValue = 0
        arkTsMemoryLimitValue = 0
        isTotalTopValue = false
        isCJTopValue = false
        isArkTsTopValue = false
        totalRatioThresholdValue = 0.8
        cjRatioThresholdValue = 0.8
        arkTsRatioThresholdValue = 0.8
    }

    func computeAvg(currrentMemoryValue: Int64, currrentCJMemoryValue: Int64, currrentArkTsMemoryValue: Int64): Unit {
        // 系统内存 (PSS)
        this.avgMemoryValue = this.avgMemoryValue + (currrentMemoryValue - this.avgMemoryValue) / (sampleCountValue + 1)
        if (maxMemoryValue < currrentMemoryValue) {
            maxMemoryValue = currrentMemoryValue
        }

        // 仓颉堆内存
        this.avgCJMemoryValue = this.avgCJMemoryValue + (currrentCJMemoryValue - this.avgCJMemoryValue) / (sampleCountValue + 1)
        if (maxCJMemoryValue < currrentCJMemoryValue) {
            maxCJMemoryValue = currrentCJMemoryValue
        }

        // ArkTS 堆内存
        this.avgArkTsMemoryValue = this.avgArkTsMemoryValue + (currrentArkTsMemoryValue - this.avgArkTsMemoryValue) / (sampleCountValue + 1)
        if (maxArkTsMemoryValue < currrentArkTsMemoryValue) {
            maxArkTsMemoryValue = currrentArkTsMemoryValue
        }

        // 系统总内存限制 (只设置一次)
        if (totalMemoryLimitValue <= 0) {
            this.totalMemoryLimitValue = getAppMemoryLimit().rssLimit.toInt64()
        }

        // CJ 最大堆内存 (只设置一次，getMaxHeapSize 返回 byte，转 KB)
        if (cjMemoryLimitValue <= 0) {
            this.cjMemoryLimitValue = getMaxHeapSize() / 1024
        }

        // ArkTS 最大堆内存 (只设置一次)
        if (arkTsMemoryLimitValue <= 0) {
            this.arkTsMemoryLimitValue = getArkTsTotalHeap()
        }

        // 判断是否触顶
        if (totalMemoryLimitValue > 0) {
            let totalUsageRate = Float64(currrentMemoryValue) / Float64(totalMemoryLimitValue)
            this.isTotalTopValue = totalUsageRate >= totalRatioThresholdValue
        }

        if (cjMemoryLimitValue > 0) {
            let cjUsageRate = Float64(currrentCJMemoryValue) / Float64(cjMemoryLimitValue)
            this.isCJTopValue = cjUsageRate >= cjRatioThresholdValue
        }

        if (arkTsMemoryLimitValue > 0) {
            let arkTsUsageRate = Float64(currrentArkTsMemoryValue) / Float64(arkTsMemoryLimitValue)
            this.isArkTsTopValue = arkTsUsageRate >= arkTsRatioThresholdValue
        }

        sampleCountValue++
    }

    /**
     * 获取系统总内存限制
     * @return 系统总内存限制 (KB)
     */
    public func getTotalMemoryLimit(): Int64 {
        this.totalMemoryLimitValue
    }

    /**
     * 获取 CJ 最大堆内存
     * @return CJ 最大堆内存 (KB)
     */
    public func getCJMemoryLimit(): Int64 {
        this.cjMemoryLimitValue
    }

    /**
     * 获取 ArkTS 最大堆内存
     * @return ArkTS 最大堆内存 (KB)
     */
    public func getArkTsMemoryLimit(): Int64 {
        this.arkTsMemoryLimitValue
    }

    /**
     * 获取系统总内存是否触顶
     * @return true 表示系统总内存使用率已达到阈值
     */
    public func isTotalTop(): Bool {
        this.isTotalTopValue
    }

    /**
     * 获取 CJ 是否触顶
     * @return true 表示 CJ 内存使用率已达到阈值
     */
    public func isCJTop(): Bool {
        this.isCJTopValue
    }

    /**
     * 获取 ArkTS 是否触顶
     * @return true 表示 ArkTS 内存使用率已达到阈值
     */
    public func isArkTsTop(): Bool {
        this.isArkTsTopValue
    }

    /**
     * 设置系统总内存触顶阈值
     * @param ratio 阈值 (0.0-1.0)，默认 0.8
     */
    public func setTotalRatioThreshold(ratio: Float64): Unit {
        if (ratio >= 0.0 && ratio <= 1.0) {
            this.totalRatioThresholdValue = ratio
        } else {
            this.totalRatioThresholdValue = 0.8
        }
    }

    /**
     * 设置 CJ 内存触顶阈值
     * @param ratio 阈值 (0.0-1.0)，默认 0.8
     */
    public func setCJRatioThreshold(ratio: Float64): Unit {
        if (ratio >= 0.0 && ratio <= 1.0) {
            this.cjRatioThresholdValue = ratio
        } else {
            this.cjRatioThresholdValue = 0.8
        }
    }

    /**
     * 设置 ArkTS 内存触顶阈值
     * @param ratio 阈值 (0.0-1.0)，默认 0.8
     */
    public func setArkTsRatioThreshold(ratio: Float64): Unit {
        if (ratio >= 0.0 && ratio <= 1.0) {
            this.arkTsRatioThresholdValue = ratio
        } else {
            this.arkTsRatioThresholdValue = 0.8
        }
    }

    /**
     * 计算系统内存平均使用率 (avgMemory / totalMemoryLimit)
     * @return 使用率 0.0-1.0+，超过 0.8 表示高风险
     */
    public func getMemoryAvgUsageRate(): Float64 {
        if (totalMemoryLimitValue <= 0) {
            return 0.0
        }
        Float64(avgMemoryValue) / Float64(totalMemoryLimitValue)
    }

    /**
     * 计算系统内存峰值使用率 (maxMemory / totalMemoryLimit)
     * @return 使用率 0.0-1.0+，超过 0.8 表示高风险
     */
    public func getMemoryMaxUsageRate(): Float64 {
        if (totalMemoryLimitValue <= 0) {
            return 0.0
        }
        Float64(maxMemoryValue) / Float64(totalMemoryLimitValue)
    }

    /**
     * 计算 CJ 内存平均使用率 (avgCJMemory / cjMemoryLimit)
     * @return 使用率 0.0-1.0+
     */
    public func getCJMemoryAvgUsageRate(): Float64 {
        if (cjMemoryLimitValue <= 0) {
            return 0.0
        }
        Float64(avgCJMemoryValue) / Float64(cjMemoryLimitValue)
    }

    /**
     * 计算 CJ 内存峰值使用率 (maxCJMemory / cjMemoryLimit)
     * @return 使用率 0.0-1.0+
     */
    public func getCJMemoryMaxUsageRate(): Float64 {
        if (cjMemoryLimitValue <= 0) {
            return 0.0
        }
        Float64(maxCJMemoryValue) / Float64(cjMemoryLimitValue)
    }

    /**
     * 计算 ArkTS 内存平均使用率 (avgArkTsMemory / arkTsMemoryLimit)
     * @return 使用率 0.0-1.0+，超过 0.8 表示高风险
     */
    public func getArkTsMemoryAvgUsageRate(): Float64 {
        if (arkTsMemoryLimitValue <= 0) {
            return 0.0
        }
        Float64(avgArkTsMemoryValue) / Float64(arkTsMemoryLimitValue)
    }

    /**
     * 计算 ArkTS 内存峰值使用率 (maxArkTsMemory / arkTsMemoryLimit)
     * @return 使用率 0.0-1.0+，超过 0.8 表示高风险
     */
    public func getArkTsMemoryMaxUsageRate(): Float64 {
        if (arkTsMemoryLimitValue <= 0) {
            return 0.0
        }
        Float64(maxArkTsMemoryValue) / Float64(arkTsMemoryLimitValue)
    }

    public func getAvgMemory(): Int64 {
        this.avgMemoryValue
    }

    public func getMaxMemory(): Int64 {
        this.maxMemoryValue
    }

    public func getAvgCJMemory(): Int64 {
        this.avgCJMemoryValue
    }

    public func getMaxCJMemory(): Int64 {
        this.maxCJMemoryValue
    }

    public func getAvgArkTsMemory(): Int64 {
        this.avgArkTsMemoryValue
    }

    public func getMaxArkTsMemory(): Int64 {
        this.maxArkTsMemoryValue
    }

    public func getSampleCount(): Int64 {
        this.sampleCountValue
    }

    protected open func reset(): Unit {
        this.avgMemoryValue = 0
        this.maxMemoryValue = 0
        this.avgCJMemoryValue = 0
        this.maxCJMemoryValue = 0
        this.avgArkTsMemoryValue = 0
        this.maxArkTsMemoryValue = 0
        this.sampleCountValue = 0
        this.totalMemoryLimitValue = 0
        this.cjMemoryLimitValue = 0
        this.arkTsMemoryLimitValue = 0
        this.isTotalTopValue = false
        this.isCJTopValue = false
        this.isArkTsTopValue = false
    }
}

public class PageMemoryInfo <: MemoryInfo {
    private var pageNameValue: String = ""

    mut prop pageName: String {
        get() {
            pageNameValue
        }
        set(value) {
            pageNameValue = value
        }
    }

    public init() {
    }

    public init(pageName: String) {
        pageNameValue = pageName
    }

    public func getPageName(): String {
        pageNameValue
    }

    protected override func reset(): Unit {
        super.reset()
        this.pageNameValue = ""
    }

    public func toString(): String {
        let jsonObj = JsonObject()
        jsonObj.put("avgMemory", JsonString(avgMemory.toString()))
        jsonObj.put("maxMemory", JsonString(maxMemory.toString()))
        jsonObj.put("avgCJMemory", JsonString(avgCJMemory.toString()))
        jsonObj.put("maxCJMemory", JsonString(maxCJMemory.toString()))
        jsonObj.put("avgArkTsMemory", JsonString(avgArkTsMemory.toString()))
        jsonObj.put("maxArkTsMemory", JsonString(maxArkTsMemory.toString()))
        jsonObj.put("sampleCount", JsonString(sampleCount.toString()))
        jsonObj.put("pageName", JsonString(pageNameValue.toString()))
        // 内存限制
        jsonObj.put("totalMemoryLimit", JsonString(getTotalMemoryLimit().toString()))
        jsonObj.put("cjMemoryLimit", JsonString(getCJMemoryLimit().toString()))
        jsonObj.put("arkTsMemoryLimit", JsonString(getArkTsMemoryLimit().toString()))
        // 是否触顶
        jsonObj.put("isTotalTop", JsonString(isTotalTop().toString()))
        jsonObj.put("isCJTop", JsonString(isCJTop().toString()))
        jsonObj.put("isArkTsTop", JsonString(isArkTsTop().toString()))
        // 内存使用率
        jsonObj.put("memoryAvgUsageRate", JsonString(getMemoryAvgUsageRate().toString()))
        jsonObj.put("memoryMaxUsageRate", JsonString(getMemoryMaxUsageRate().toString()))
        jsonObj.put("cjMemoryAvgUsageRate", JsonString(getCJMemoryAvgUsageRate().toString()))
        jsonObj.put("cjMemoryMaxUsageRate", JsonString(getCJMemoryMaxUsageRate().toString()))
        jsonObj.put("arkTsMemoryAvgUsageRate", JsonString(getArkTsMemoryAvgUsageRate().toString()))
        jsonObj.put("arkTsMemoryMaxUsageRate", JsonString(getArkTsMemoryMaxUsageRate().toString()))
        jsonObj.toString()
    }
}

public class ProcessMemoryInfo <: MemoryInfo {
    private var pidValue: Int32 = 0

    mut prop pid: Int32 {
        get() {
            this.pidValue
        }
        set(value) {
            this.pidValue = value
        }
    }

    public init() {
        this.pidValue = getpid()
    }

    public init(pidValue: Int32) {
        this.pidValue = pidValue
    }

    public func getProcessName(): Int32 {
        this.pidValue
    }

    protected override func reset(): Unit {
        super.reset()
        this.pidValue = 0
    }

    public func toString(): String {
        let jsonObj = JsonObject()
        jsonObj.put("avgMemory", JsonString(avgMemory.toString()))
        jsonObj.put("maxMemory", JsonString(maxMemory.toString()))
        jsonObj.put("avgCJMemory", JsonString(avgCJMemory.toString()))
        jsonObj.put("maxCJMemory", JsonString(maxCJMemory.toString()))
        jsonObj.put("avgArkTsMemory", JsonString(avgArkTsMemory.toString()))
        jsonObj.put("maxArkTsMemory", JsonString(maxArkTsMemory.toString()))
        jsonObj.put("sampleCount", JsonString(sampleCount.toString()))
        jsonObj.put("pid", JsonString(pidValue.toString()))
        // 内存限制
        jsonObj.put("totalMemoryLimit", JsonString(getTotalMemoryLimit().toString()))
        jsonObj.put("cjMemoryLimit", JsonString(getCJMemoryLimit().toString()))
        jsonObj.put("arkTsMemoryLimit", JsonString(getArkTsMemoryLimit().toString()))
        // 是否触顶
        jsonObj.put("isTotalTop", JsonString(isTotalTop().toString()))
        jsonObj.put("isCJTop", JsonString(isCJTop().toString()))
        jsonObj.put("isArkTsTop", JsonString(isArkTsTop().toString()))
        // 内存使用率
        jsonObj.put("memoryAvgUsageRate", JsonString(getMemoryAvgUsageRate().toString()))
        jsonObj.put("memoryMaxUsageRate", JsonString(getMemoryMaxUsageRate().toString()))
        jsonObj.put("cjMemoryAvgUsageRate", JsonString(getCJMemoryAvgUsageRate().toString()))
        jsonObj.put("cjMemoryMaxUsageRate", JsonString(getCJMemoryMaxUsageRate().toString()))
        jsonObj.put("arkTsMemoryAvgUsageRate", JsonString(getArkTsMemoryAvgUsageRate().toString()))
        jsonObj.put("arkTsMemoryMaxUsageRate", JsonString(getArkTsMemoryMaxUsageRate().toString()))
        jsonObj.toString()
    }

    static func fromJson(jsonObject: JsonObject): ProcessMemoryInfo {
        let processMemoryInfo = ProcessMemoryInfo()
        if (let Some(v) <-  jsonObject.get("avgMemory")) {
            processMemoryInfo.avgMemory = Int64.parse(JsonValueToString(v))
        }
        if (let Some(v) <-  jsonObject.get("maxMemory")) {
            processMemoryInfo.maxMemory = Int64.parse(JsonValueToString(v))
        }
        if (let Some(v) <-  jsonObject.get("avgCJMemory")) {
            processMemoryInfo.avgCJMemory = Int64.parse(JsonValueToString(v))
        }
        if (let Some(v) <-  jsonObject.get("maxCJMemory")) {
            processMemoryInfo.maxCJMemory = Int64.parse(JsonValueToString(v))
        }
        if (let Some(v) <-  jsonObject.get("avgArkTsMemory")) {
            processMemoryInfo.avgArkTsMemory = Int64.parse(JsonValueToString(v))
        }
        if (let Some(v) <-  jsonObject.get("maxArkTsMemory")) {
            processMemoryInfo.maxArkTsMemory = Int64.parse(JsonValueToString(v))
        }
        if (let Some(v) <-  jsonObject.get("sampleCount")) {
            processMemoryInfo.sampleCount = Int64.parse(JsonValueToString(v))
        }
        if (let Some(v) <-  jsonObject.get("pid")) {
            processMemoryInfo.pid = Int32.parse(JsonValueToString(v))
        }
        processMemoryInfo
    }
}

let preferenceOptionName: String = "hm-metric-cj-memory"
var MEMOMRY_THRESHOLD: Int64 = 1024 * 100
let default_sample_interval: Int64 = 30 * 1000  // 30 秒
let default_report_interval: Int64 = 30 * 60 * 1000  // 30 分钟
let default_save_interval: Int64 = 60 * 1000  // 60 秒
var SAMPLE_INTERVAL: Int64 = default_sample_interval
var REPORT_INTERVAL: Int64 = default_report_interval
var SAVE_INTERVAL: Int64 = default_save_interval
var thresholdReported: Bool = false
var pageMemoryInfo = PageMemoryInfo(defaultPageName)
var processMemoryInfo = ProcessMemoryInfo()
var uiContext: Option<UIAbilityContext> = None
var reportPageMemory: (memoryInfo: PageMemoryInfo) -> Unit = {info: PageMemoryInfo =>}
var reportProcessMemory: (memoryInfo: ProcessMemoryInfo) -> Unit = {info: ProcessMemoryInfo =>}

var memory_init_flag = false

/**
 * 获取 ArkTS (JS) 堆内存信息
 * 使用 hidebug.getAppVMMemoryInfo() 获取虚拟机内存信息
 * @return VMMemoryInfo 包含 heapUsed, totalHeap, allArraySize
 */
public func getArkTsHeapSize(): Int64 {
    try {
        let vmMemoryInfo: VMMemoryInfo = getAppVMMemoryInfo()
        return vmMemoryInfo.heapUsed.toInt64()
    } catch (e: Exception) {
        AppLog.warn("hm-metricx-cj error: getArkTsHeapSize failed - " + e.toString())
    }
    return 0
}

/**
 * 获取 ArkTS 堆总大小
 * @return totalHeap 虚拟机堆总大小 (KB)
 */
public func getArkTsTotalHeap(): Int64 {
    try {
        return getAppMemoryLimit().vmHeapLimit.toInt64()
    } catch (e: Exception) {
        AppLog.warn("hm-metricx-cj error: getArkTsTotalHeap failed - " + e.toString())
    }
    return 0
}

let doMemorySample: (param: Array<String>) -> Unit = {
    param: Array<String> =>
    spawn {
        =>
            let memoryUsage = getPss().toInt64()
            let cjMemoryUsage = getAllocatedHeapSize() / 1024
            let arkTsMemoryUsage = getArkTsHeapSize()
            let arkTsTotalHeap = getArkTsTotalHeap()
            if (!thresholdReported) {
                if (memoryUsage >= MEMOMRY_THRESHOLD) {
                    processMemoryInfo.maxMemory = memoryUsage
                    reportProcessMemory(processMemoryInfo)
                    thresholdReported = true
                }
            }
            pageMemoryInfo.computeAvg(memoryUsage, cjMemoryUsage, arkTsMemoryUsage)
            processMemoryInfo.computeAvg(memoryUsage, cjMemoryUsage, arkTsMemoryUsage)
    }
}
let handleProcessMemoryReport: (param: Array<String>) -> Unit = {
    param: Array<String> => reportProcessMemory(processMemoryInfo)
}
var currentPageName: String = defaultPageName
let pageSwitchCallback: PageSwitchCallBack = PageSwitchCallBack(
    {
        info: NavDestinationSwitchInfo =>
        currentPageName = getTargetPageName(info, defaultName: currentPageName)
        doMemorySample()
        reportPageMemory(pageMemoryInfo)
        pageMemoryInfo.reset()
        pageMemoryInfo.pageName = currentPageName
    }
)

let saveProcessMemory: (param: Array<String>) -> Unit = {
    param: Array<String> =>
    try {
        let options = preferences.Options(preferenceOptionName)
        let dataPreferences = preferences.getPreferences(uiContext.getOrThrow(), options)
        dataPreferences.put("processMemory", preferences.ValueType.STRING(processMemoryInfo.toString()))
        dataPreferences.flush({err, data => })
    } catch (e:Exception) {
        AppLog.warn("hm-metricx-cj error: " + e.toString())
    }
}

private func handleMemory(array: Array<String>): Unit {
    setInterval(doMemorySample, SAMPLE_INTERVAL, Array<String>())
    setInterval(handleProcessMemoryReport, REPORT_INTERVAL, Array<String>())
    setInterval(saveProcessMemory, SAVE_INTERVAL, Array<String>())
}

public func getPageMemoryInfo(): PageMemoryInfo {
    pageMemoryInfo
}

public func getProcessMemoryInfo(): ProcessMemoryInfo {
    processMemoryInfo
}

private func getStoragedProcessMemory(): Option<ProcessMemoryInfo> {
    var processMemoryStr: String = ""
    try {
        let options = preferences.Options(preferenceOptionName)
        let dataPreferences = preferences.getPreferences(uiContext.getOrThrow(), options)
        let val = dataPreferences.get("processMemory", preferences.ValueType.STRING(""))
        match (val) {
            case STRING(v) => processMemoryStr = v
            case _ => ()
        }
        if (processMemoryStr.isBlank()) {
            return Option.None
        }
        let obj = JsonValue.fromStr(processMemoryStr).asObject()
        return ProcessMemoryInfo.fromJson(obj)
    } catch (e: Exception) {
        AppLog.warn("hm-metricx-cj error: " + e.toString())
    }
    Option.None
}

public func initMemoryHandler(
    context: UIAbilityContext,
    reportPageMemoryInfo: (info: PageMemoryInfo) -> Unit,
    reportProcessMemoryInfo: (info: ProcessMemoryInfo) -> Unit,
    memoryThreshold!: Int64 = 100 * 1024,
    sampleInterval!: Int64 = default_sample_interval,
    reportInterval!: Int64 = default_report_interval,
    saveInterval!: Int64 = default_save_interval,
    totalRatio!: Float64 = 0.8,
    cjRatio!: Float64 = 0.8,
    arkTsRatio!: Float64 = 0.8
): Unit {
    if (memory_init_flag) {
    	return
    }
    memory_init_flag = true

    uiContext = context
    reportPageMemory = reportPageMemoryInfo
    reportProcessMemory = reportProcessMemoryInfo
    MEMOMRY_THRESHOLD = memoryThreshold
    // 边界值判断：超出范围使用默认值
    let maxInterval: Int64 = 60 * 60 * 1000  // 1 小时
    let minInterval: Int64 = 0
    SAMPLE_INTERVAL = if (sampleInterval < minInterval || sampleInterval > maxInterval) {default_sample_interval} else {sampleInterval}
    REPORT_INTERVAL = if (reportInterval < minInterval || reportInterval > maxInterval) {default_report_interval} else {reportInterval}
    SAVE_INTERVAL = if (saveInterval < minInterval || saveInterval > maxInterval) {default_save_interval} else {saveInterval}

    // 设置触顶阈值
    pageMemoryInfo.setTotalRatioThreshold(totalRatio)
    pageMemoryInfo.setCJRatioThreshold(cjRatio)
    pageMemoryInfo.setArkTsRatioThreshold(arkTsRatio)
    processMemoryInfo.setTotalRatioThreshold(totalRatio)
    processMemoryInfo.setCJRatioThreshold(cjRatio)
    processMemoryInfo.setArkTsRatioThreshold(arkTsRatio)
    let lastProcessMemory = getStoragedProcessMemory()
    if (let Some(v) <- lastProcessMemory) {
        reportProcessMemoryInfo(v)
    }
    setTimeout(handleMemory, SAMPLE_INTERVAL, Array<String>())
    on(navDestinationSwitch, uiContext.getOrThrow(), pageSwitchCallback)
}

public func destroyMemoryHandler(): Unit {
    off(navDestinationSwitch, uiContext.getOrThrow(), pageSwitchCallback)
    memory_init_flag = false
    // todo clearInterval
}
