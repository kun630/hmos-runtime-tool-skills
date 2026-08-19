
package ohos_app_cangjie_hm_metricx_cj.exitInfo

import ohos.base.AppLog
import tpc.AbilityKit.AbilityConstant.LaunchParam
import tpc.AbilityKit.AbilityConstant.LastExitReason
import tpc.AbilityKit.AbilityLifecycleCallback
import tpc.AbilityKit.ApplicationContextType
import tpc.AbilityKit.UIAbility
import tpc.AbilityKit.UIAbilityContext
import tpc.UIKit.window
import std.fs.*
import std.convert.*
import std.time.*
import stdx.encoding.json.*
import ohos_app_cangjie_hm_metricx_cj.util.writeFile
import ohos_app_cangjie_hm_metricx_cj.util.readFile

let DEFAULT_SWIPE_KILL_THRESHOLD_MS: Int64 = 5000

private var lastBackgroundTime: Int64 = 0
var swipeKillThresholdMs: Int64 = 0
private var swipeKillInited = false
private var isSystemKill = true
private var exitInfo: String = "unknown"

var reportSwipeKillInfo: (data: SwipeKillInfo) -> Unit = {data: SwipeKillInfo =>}

private func saveBackgroundTime() {
    try {
        writeFile(getPersistencePath(), lastBackgroundTime.toString())
    } catch (e: Exception) {
        AppLog.error("[SwipeKill] Save failed: ${e.message}")
    }
}

private func loadBackgroundTime() {
    try {
        if (exists(getPersistencePath())) {
            lastBackgroundTime = Int64.parse(readFile(getPersistencePath()).trimAscii())
        }
    } catch (e: Exception) {
        AppLog.error("[SwipeKill] Load failed: ${e.message}")
    }
}

private func getPersistencePath(): Path {
    return Path("/data/storage/el2/log/hiappevent/swipe_kill_data.txt")
}

private func clearBackgroundTime() {
    try {
        let path = getPersistencePath()
        if (exists(path)) {
            removeIfExists(path)
        }
    } catch (e: Exception) {}
}

public class SwipeKillInfo {
    public let timestamp: Int64
    public let isUserSwipeKill: Bool
    public let exitInfo: String

    public init(timestamp: Int64, isUserSwipeKill: Bool, exitInfo: String) {
        this.timestamp = timestamp
        this.isUserSwipeKill = isUserSwipeKill
        this.exitInfo = exitInfo
    }
    public func toString(): String {
        let jsonObj = JsonObject()
        jsonObj.put("timestamp", JsonString(timestamp.toString()))
        jsonObj.put("isUserSwipeKill", JsonString(isUserSwipeKill.toString()))
        jsonObj.put("exitInfo", JsonString(exitInfo))
        jsonObj.toString()
    }
}

private func getLastExitInfo(launchParam: LaunchParam): Bool {
    lastExitReasonToString(launchParam.lastExitReason)
    AppLog.info("[SwipeKill] getLastExitInfo: ${exitInfo}")
    if (exitInfo == "unknown" || exitInfo == "normal") {
    	return false
    }
    return true
}

private func lastExitReasonToString(lastExitReason: LastExitReason): Unit {
    match (lastExitReason) {
        case LastExitReason.ABILITY_NOT_RESPONDING =>
            exitInfo = "ability_not_responding"
        case LastExitReason.APP_FREEZE =>
            exitInfo = "app_freeze"
        case LastExitReason.CPP_CRASH =>
            exitInfo = "cpp_crash"
        case LastExitReason.JS_ERROR =>
            exitInfo = "js_error"
        case LastExitReason.UNKNOWN =>
            exitInfo = "unknown"
        case LastExitReason.NORMAL =>
            exitInfo = "normal"
        case LastExitReason.PERFORMANCE_CONTROL =>
            exitInfo = "performance_control"
        case LastExitReason.RESOURCE_CONTROL =>
            exitInfo = "resource_control"
        case LastExitReason.UPGRADE =>
            exitInfo = "upgrade"
    }
}

let callback: AbilityLifecycleCallback = AbilityLifecycleCallback(
    onAbilityCreate: { ability: UIAbility => () },
    onWindowStageCreate: { ability: UIAbility, windowStage: window.WindowStage =>
        let now = getCurrentTimeMillis()
        let timeSinceBg = now - lastBackgroundTime
        let isQuickRestart = timeSinceBg < swipeKillThresholdMs && lastBackgroundTime > 0
        if (isQuickRestart && !isSystemKill) {
            AppLog.warn("[SwipeKill] User swipe kill detected! timeSinceBg: ${timeSinceBg}ms")
            reportSwipeKillInfo(SwipeKillInfo(now, true, exitInfo))
        } else {
        	reportSwipeKillInfo(SwipeKillInfo(now, false, exitInfo))
        }
        clearBackgroundTime()
    },
    onWindowStageActive: { ability: UIAbility, windowStage: window.WindowStage => () },
    onWindowStageInactive: { ability: UIAbility, windowStage: window.WindowStage => () },
    onWindowStageDestroy: { ability: UIAbility, windowStage: window.WindowStage => () },
    onAbilityDestroy: { ability: UIAbility => () },
    onAbilityForeground: { ability: UIAbility => () },
    onAbilityBackground: { ability: UIAbility =>
        lastBackgroundTime = getCurrentTimeMillis()
        AppLog.info("[SwipeKill] Background time: ${lastBackgroundTime}")
        saveBackgroundTime()
    },
    onAbilityContinue: { ability: UIAbility => () },
    onWindowStageRestore: { ability: UIAbility, windowStage: window.WindowStage => () }

)


public func initSwipeKillHandler(
    context: UIAbilityContext,
    launchParam: LaunchParam,
    reportInfo: (info: SwipeKillInfo) -> Unit,
    thresholdMs!: Int64 = DEFAULT_SWIPE_KILL_THRESHOLD_MS
) {
    if (swipeKillInited) {
        return
    }
    swipeKillInited = true
    if (thresholdMs < 0) {
        throw IllegalArgumentException("negative value ${thresholdMs}")
    }
    swipeKillThresholdMs = thresholdMs
    loadBackgroundTime()

    isSystemKill = getLastExitInfo(launchParam)
    reportSwipeKillInfo = reportInfo
    let applicationContext = context.getApplicationContext()
    applicationContext.on(ApplicationContextType.ABILITY_LIFECYCLE, callback)
    AppLog.info("[SwipeKill] Initialized")
}

private func getCurrentTimeMillis(): Int64 {
    DateTime.now().toUnixTimeStamp().toMilliseconds()
}
