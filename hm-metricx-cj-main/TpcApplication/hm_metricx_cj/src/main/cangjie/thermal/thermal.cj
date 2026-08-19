/*
 * Copyright (c) Huawei Technologies Co., Ltd. 2025-2025. All rights reserved.
 * Co-Author: AI
 */
package ohos_app_cangjie_hm_metricx_cj.thermal

import ohos_app_cangjie_hm_metricx_cj.util.*
import tpc.AbilityKit.AbilityLifecycleCallback
import tpc.AbilityKit.ApplicationContextType
import tpc.AbilityKit.UIAbility
import tpc.AbilityKit.UIAbilityContext
import tpc.BasicServicesKit.thermal.*
import tpc.UIKit.Observer.*
import tpc.UIKit.global.*
import tpc.UIKit.window
import std.time.*
import stdx.encoding.json.*
import ohos.base.AppLog

const DEFAULT_SAMPLE_INTERVAL_MS: Int64 = 5 * 1000
const DEFAULT_REPORT_MIN_INTERVAL_MS: Int64 = 30 * 1000
const DEFAULT_ABNORMAL_LEVEL: Int32 = 3

public class ThermalEventInfo {
    private var pageNameValue: String = ""
    private var levelValue: Int32 = -1
    private var levelNameValue: String = ""
    private var thresholdValue: Int32 = -1
    private var isForegroundValue: Bool = true
    private var durationMsValue: Int64 = 0
    private var timestampValue: Int64 = 0

    public mut prop pageName: String {
        get() { 
            pageNameValue 
        }
        set(value) { 
            pageNameValue = value 
        }
    }
    public mut prop level: Int32 {
        get() { 
            levelValue 
        }
        set(value) { 
            levelValue = value 
        }
    }
    public mut prop levelName: String {
        get() { 
            levelNameValue 
        }
        set(value) { 
            levelNameValue = value
        }
    }
    public mut prop threshold: Int32 {
        get() { 
            thresholdValue 
        }
        set(value) { 
            thresholdValue = value 
        }
    }
    public mut prop isForeground: Bool {
        get() { 
        isForegroundValue 
    }
        set(value) { 
            isForegroundValue = value 
        }
    }
    public mut prop durationMs: Int64 {
        get() { 
            durationMsValue 
        }
        set(value) { 
        durationMsValue = value 
        }
    }
    public mut prop timestamp: Int64 {
        get() { 
            timestampValue 
        }
        set(value) { 
            timestampValue = value 
        }
    }

    public func toString(): String {
        let jsonObj = JsonObject()
        jsonObj.put("pageName", JsonString(pageNameValue))
        //jsonObj.put("level", JsonString(levelValue.toString()))
        jsonObj.put("levelName", JsonString(levelNameValue))
        jsonObj.put("threshold", JsonString(thresholdValue.toString()))
        jsonObj.put("isForeground", JsonString(isForegroundValue.toString()))
        jsonObj.put("durationMs", JsonString(durationMsValue.toString()))
        //jsonObj.put("timestamp", JsonString(timestampValue.toString()))
        jsonObj.toString()
    }
}

var uiContext: Option<UIAbilityContext> = None
var currentPageName: String = defaultPageName
var isForeground: Bool = true
var sampleIntervalMs: Int64 = DEFAULT_SAMPLE_INTERVAL_MS
var reportMinIntervalMs: Int64 = DEFAULT_REPORT_MIN_INTERVAL_MS
var abnormalThresholdLevel: Int32 = DEFAULT_ABNORMAL_LEVEL
var monitorId: Int64 = -1
var lastLevelInt: Int32 = -1
var levelStartTime: Int64 = 0
var lastReportTime: Int64 = 0
var lastAbnormalState: Bool = false
var reportThermalCallback: (info: ThermalEventInfo) -> Unit = {info: ThermalEventInfo =>}

private func nowMs(): Int64 {
    DateTime.now().toUnixTimeStamp().toMilliseconds()
}

private func thermalLevelToInt(levelEnum: ThermalLevel): Int32 {
    match (levelEnum) {
        case COOL => 0
        case NORMAL => 1
        case WARM => 2
        case HOT => 3
        case OVERHEATED => 4
        case WARNING => 5
        case EMERGENCY => 6
        case ESCAPE => 7
    }
}

private func thermalLevelToName(levelEnum: ThermalLevel): String {
    match (levelEnum) {
        case COOL => "COOL"
        case NORMAL => "NORMAL"
        case WARM => "WARM"
        case HOT => "HOT"
        case OVERHEATED => "OVERHEATED"
        case WARNING => "WARNING"
        case EMERGENCY => "EMERGENCY"
        case ESCAPE => "ESCAPE"
    }
}

private func buildEvent(levelEnum: ThermalLevel, levelInt: Int32, now: Int64): ThermalEventInfo {
    let info = ThermalEventInfo()
    info.pageName = currentPageName
    info.level = levelInt
    info.levelName = thermalLevelToName(levelEnum)
    info.threshold = abnormalThresholdLevel
    info.isForeground = isForeground
    info.durationMs = now - levelStartTime
    info.timestamp = now
    info
}

private func sampleThermal(force!: Bool = false): Unit {
    if (!force && !isForeground) {
        return
    }
    let now = nowMs()
    try {
        let levelEnum: ThermalLevel = getLevel()
        let levelInt: Int32 = thermalLevelToInt(levelEnum)
        let prevLevel = lastLevelInt
        if (prevLevel != levelInt) {
            levelStartTime = now
            lastLevelInt = levelInt
        }
        let abnormalNow = levelInt >= abnormalThresholdLevel
        let levelIncreased = prevLevel >= 0 && levelInt > prevLevel
        let shouldReport = abnormalNow && (!lastAbnormalState || levelIncreased || (now - lastReportTime) >= reportMinIntervalMs)
        if (shouldReport) {
            reportThermalCallback(buildEvent(levelEnum, levelInt, now))
            lastReportTime = now
        }
        lastAbnormalState = abnormalNow
    } catch (e: Exception) {
        AppLog.warn("hm-metricx-cj thermal sample failed: ${e.toString()}")
    }
}

let handleThermalSample: (param: Array<String>) -> Unit = {
    _ => sampleThermal()
}

private func startThermalMonitor(): Unit {
    if (monitorId != -1) {
        clearInterval(monitorId)
    }
    lastLevelInt = -1
    levelStartTime = nowMs()
    lastReportTime = 0
    lastAbnormalState = false
    monitorId = setInterval(handleThermalSample, sampleIntervalMs, Array<String>())
    sampleThermal(force: true)
}

private func stopThermalMonitor(): Unit {
    if (monitorId != -1) {
        clearInterval(monitorId)
        monitorId = -1
    }
}

let pageSwitchCallback: PageSwitchCallBack =
    PageSwitchCallBack({
        info: NavDestinationSwitchInfo =>
            currentPageName = getTargetPageName(info, defaultName: currentPageName)
    }
)

public func onAbilityForegroundCallBack(ability: UIAbility) {
    isForeground = true
    startThermalMonitor()
}

public func onAbilityBackgroundCallBack(ability: UIAbility) {
    sampleThermal(force: true)
    isForeground = false
    stopThermalMonitor()
}

let abilityLifecycleCallback: AbilityLifecycleCallback = AbilityLifecycleCallback(
        onAbilityCreate: { ability: UIAbility => () },
        onWindowStageCreate: { abilty: UIAbility, windowStage: window.WindowStage => () },
        onWindowStageActive: { abilty: UIAbility, windowStage: window.WindowStage => () },
        onWindowStageInactive: { abilty: UIAbility, windowStage: window.WindowStage => () },
        onWindowStageDestroy: { abilty: UIAbility, windowStage: window.WindowStage => () },
        onAbilityDestroy: { abilityUIability => () },
        onAbilityForeground: onAbilityForegroundCallBack,
        onAbilityBackground: onAbilityBackgroundCallBack,
        onAbilityContinue: { abilityUIability => () },
        onWindowStageRestore: { abilty: UIAbility, windowStage: window.WindowStage => () }
    )

public func initThermalHandler(
    context: UIAbilityContext,
    reportThermalInfo: (info: ThermalEventInfo) -> Unit,
    sampleInterval!: Int64 = DEFAULT_SAMPLE_INTERVAL_MS,
    reportMinInterval!: Int64 = DEFAULT_REPORT_MIN_INTERVAL_MS,
    abnormalThreshold!: Int32 = DEFAULT_ABNORMAL_LEVEL
): Unit {
    uiContext = context
    reportThermalCallback = reportThermalInfo
    sampleIntervalMs = sampleInterval
    reportMinIntervalMs = reportMinInterval
    abnormalThresholdLevel = abnormalThreshold
    let applicationContext = uiContext.getOrThrow().getApplicationContext()
    applicationContext.on(ApplicationContextType.ABILITY_LIFECYCLE, abilityLifecycleCallback)
    on(navDestinationSwitch, uiContext.getOrThrow(), pageSwitchCallback)
    isForeground = true
    startThermalMonitor()
}

public func destroyThermalHandler(): Unit {
    reportThermalCallback = {info: ThermalEventInfo =>}
    stopThermalMonitor()
    if (uiContext.isSome()) {
        off(navDestinationSwitch, uiContext.getOrThrow(), pageSwitchCallback)
    }
}

