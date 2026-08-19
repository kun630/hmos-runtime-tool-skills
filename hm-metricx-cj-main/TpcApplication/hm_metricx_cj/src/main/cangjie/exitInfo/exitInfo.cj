/*
 * Copyright (c) Huawei Technologies Co., Ltd. 2025-2025. All rights reserved.
 * Co-Author: AI
 */
package ohos_app_cangjie_hm_metricx_cj.exitInfo

import ohos.base.AppLog
import tpc.AbilityKit.AbilityConstant.LaunchParam
import tpc.AbilityKit.AbilityConstant.LastExitReason
import tpc.AbilityKit.AbilityLifecycleCallback
import tpc.AbilityKit.ApplicationContextType
import tpc.AbilityKit.UIAbility
import tpc.AbilityKit.UIAbilityContext
import tpc.UIKit.window
import std.fs.Path
import std.time.*
import stdx.encoding.json.*

var currentAppState: String = "foreground"
var lastStateChangeTime: Int64 = 0
private var inited: Bool = false

public class ExitInfo {
    public ExitInfo(
        let exitMessage: String,
        let exitReason: String,
        let isBackground: Bool,
        let appState: String,
        let stateChangeTime: Int64,
        let timestamp: Int64
    ) {}

    public func toString(): String {
        let jsonObj = JsonObject()
        jsonObj.put("exitMessage", JsonString(exitMessage))
        jsonObj.put("exitReason", JsonString(exitReason))
        jsonObj.put("isBackground", JsonString(isBackground.toString()))
        jsonObj.put("appState", JsonString(appState))
        jsonObj.put("stateChangeTime", JsonString(stateChangeTime.toString()))
        jsonObj.put("timestamp", JsonString(timestamp.toString()))
        jsonObj.toString()
    }
}

public class AppStateInfo {
    public AppStateInfo(
        let appState: String,
        let stateChangeTime: Int64,
        let timestamp: Int64
    ) {}

    public func toString(): String {
        let jsonObj = JsonObject()
        jsonObj.put("appState", JsonString(appState))
        jsonObj.put("stateChangeTime", JsonString(stateChangeTime.toString()))
        jsonObj.put("timestamp", JsonString(timestamp.toString()))
        jsonObj.toString()
    }
}

var reportExitInfoCallback: (data: ExitInfo) -> Unit = {data: ExitInfo =>}
var reportAppStateCallback: (data: AppStateInfo) -> Unit = {data: AppStateInfo =>}

private func nowMs(): Int64 {
    DateTime.now().toUnixTimeStamp().toMilliseconds()
}

private func reportExitInfo(exitInfo: ExitInfo): Unit {
    AppLog.info("hm-metricx-cj exitInfo report: ${exitInfo.toString()}")
    reportExitInfoCallback(exitInfo)
}

private func reportAppState(appStateInfo: AppStateInfo): Unit {
    AppLog.info("hm-metricx-cj appState report: ${appStateInfo.toString()}")
    reportAppStateCallback(appStateInfo)
}

private func updateAppState(state: String): Unit {
    currentAppState = state
    lastStateChangeTime = nowMs()
    reportAppState(AppStateInfo(currentAppState, lastStateChangeTime, nowMs()))
}

public func setForeground(): Unit {
    updateAppState("foreground")
}

public func setBackground(): Unit {
    updateAppState("background")
}

public func isAppInBackground(): Bool {
    currentAppState == "background"
}

public func getCurrentAppState(): String {
    currentAppState
}

public func getLastStateChangeTime(): Int64 {
    lastStateChangeTime
}

public func getExitInfo(launchParam: LaunchParam): ExitInfo {
    let exitReason = lastExitReasonToString(launchParam.lastExitReason)
    ExitInfo(
        launchParam.lastExitMessage,
        exitReason,
        isAppInBackground(),
        currentAppState,
        lastStateChangeTime,
        nowMs()
    )
}

let abilityLifecycleCallback: AbilityLifecycleCallback = AbilityLifecycleCallback(
    onAbilityCreate: { ability: UIAbility => () },
    onWindowStageCreate: { ability: UIAbility, windowStage: window.WindowStage => () },
    onWindowStageActive: { ability: UIAbility, windowStage: window.WindowStage => () },
    onWindowStageInactive: { ability: UIAbility, windowStage: window.WindowStage => () },
    onWindowStageDestroy: { ability: UIAbility, windowStage: window.WindowStage => () },
    onAbilityDestroy: { ability: UIAbility => () },
    onAbilityForeground: onAbilityForegroundCallBack,
    onAbilityBackground: onAbilityBackgroundCallBack,
    onAbilityContinue: { ability: UIAbility => () },
    onWindowStageRestore: { ability: UIAbility, windowStage: window.WindowStage => () }
)

public func initExitInfoHandler(
    context: UIAbilityContext,
    launchParam: LaunchParam,
    reportExitInfoHandler: (data: ExitInfo) -> Unit,
    reportAppStateHandler: (data: AppStateInfo) -> Unit,
    persistentDir: Path
): Unit {
    if (inited) {
        return
    }
    inited = true
    reportExitInfoCallback = reportExitInfoHandler
    reportAppStateCallback = reportAppStateHandler

    currentAppState = "foreground"
    lastStateChangeTime = nowMs()

    let applicationContext = context.getApplicationContext()
    applicationContext.on(ApplicationContextType.ABILITY_LIFECYCLE, abilityLifecycleCallback)

    AppLog.info("hm-metricx-cj exitInfo init, cacheDir: ${persistentDir.toString()}")

    reportAppState(AppStateInfo(currentAppState, lastStateChangeTime, nowMs()))
    reportExitInfo(getExitInfo(launchParam))


}

public func destroyExitInfoHandler(): Unit {
    inited = false
    reportExitInfoCallback = {data: ExitInfo =>}
    reportAppStateCallback = {data: AppStateInfo =>}
    AppLog.info("hm-metricx-cj exitInfo destroyed")
}

private func lastExitReasonToString(lastExitReason: LastExitReason): String {
    match (lastExitReason) {
        case LastExitReason.ABILITY_NOT_RESPONDING => "ability_not_responding"
        case LastExitReason.APP_FREEZE => "app_freeze"
        case LastExitReason.CPP_CRASH => "cpp_crash"
        case LastExitReason.JS_ERROR => "js_error"
        case LastExitReason.UNKNOWN => "unknown"
        case LastExitReason.NORMAL => "normal"
        case LastExitReason.PERFORMANCE_CONTROL => "performance_control"
        case LastExitReason.RESOURCE_CONTROL => "resource_control"
        case LastExitReason.UPGRADE => "upgrade"
    }
}

public func onAbilityForegroundCallBack(ability: UIAbility): Unit {
    setForeground()
}

public func onAbilityBackgroundCallBack(ability: UIAbility): Unit {
    setBackground()
}