/*
 * Copyright (c) Huawei Technologies Co., Ltd. 2025-2025. All rights reserved.
 */
package ohos_app_cangjie_hm_metricx_cj.battery

import ohos_app_cangjie_hm_metricx_cj.util.*
import tpc.AbilityKit.UIAbility
import tpc.AbilityKit.UIAbilityContext
import tpc.BasicServicesKit.*
import tpc.BasicServicesKit.batteryInfo.*
import tpc.BasicServicesKit.commonEventManager.*
import tpc.BasicServicesKit.systemDateTime.*
import tpc.BasicServicesKit.settings.*
import tpc.BasicServicesKit.power.*
import tpc.AbilityKit.kit_common.*
import tpc.AbilityKit.ApplicationContextType
import tpc.UIKit.Observer.*
import stdx.encoding.json.*
import tpc.UIKit.component_interop.ResourceStr
import tpc.UIKit.window
import std.convert.*
import std.fs.*
import std.io.*
import std.time.*
import std.sync.*
import ohos.hilog.Hilog
import tpc.UIKit.global.setInterval
import ohos.ability.ApplicationContext
import tpc.AbilityKit.appManager.*
import std.collection.ArrayList
import std.process.Process
import std.runtime.getThreadCount
import tpc.PerformanceAnalysisKit.hidebug.getAppThreadCpuUsage
import tpc.PerformanceAnalysisKit.hidebug.ThreadCpuUsage
import std.collection.HashMap
import ohos.ui_test.On
import tpc.AbilityKit.AbilityLifecycleCallback
import ohos.window.WindowStage
import tpc.UIKit.global.setTimeout
import tpc.CoreFileKit.fs.listFile
import std.posix.isDir

public class BatteryUsageInfo {
    private var currentPageNameValue: ?String = None
    private var levelValue: ?Int32 = None
    private var temperatureValue: ?Float64 = None
    private var capacityValue: ?Float64 = None
    private var scaleValue: ?Int32 = None
    private var statusValue: ?Int32 = None
    private var healthValue: ?Int32 = None
    private var voltageValue: ?Int32 = None
    private var technologyValue: ?String = None
    private var pluggedValue: ?Int32 = None
    private var chargingValue: ?Bool = None
    private var limitValue: ?Int32 = None
    private var brightnessValue: ?Int32 = None
    private var useTimeValue: ?Int64 = None
    private var timeValue: ?Int64 = None

    public mut prop currentPageName: ?String {
        get() {
            currentPageNameValue
        }
        set(value) {
            currentPageNameValue = value
        }
    }
    public mut prop level: ?Int32 {
        get() {
            levelValue
        }
        set(value) {
            levelValue = value
        }
    }
    public mut prop temperature: ?Float64 {
        get() {
            temperatureValue
        }
        set(value) {
            temperatureValue = value
        }
    }
    public mut prop capacity: ?Float64 {
        get() {
            capacityValue
        }
        set(value) {
            capacityValue = value
        }
    }
    public mut prop scale: ?Int32 {
        get() {
            scaleValue
        }
        set(value) {
            scaleValue = value
        }
    }
    public mut prop status: ?Int32 {
        get() {
            statusValue
        }
        set(value) {
            statusValue = value
        }
    }
    public mut prop health: ?Int32 {
        get() {
            healthValue
        }
        set(value) {
            healthValue = value
        }
    }
    public mut prop voltage: ?Int32 {
        get() {
            voltageValue
        }
        set(value) {
            voltageValue = value
        }
    }
    public mut prop technology: ?String {
        get() {
            technologyValue
        }
        set(value) {
            technologyValue = value
        }
    }
    public mut prop plugged: ?Int32 {
        get() {
            pluggedValue
        }
        set(value) {
            pluggedValue = value
        }
    }
    public mut prop charging: ?Bool {
        get() {
            chargingValue
        }
        set(value) {
            chargingValue = value
        }
    }
    public mut prop limit: ?Int32 {
        get() {
            limitValue
        }
        set(value) {
            limitValue = value
        }
    }
    public mut prop brightness: ?Int32 {
        get() {
            brightnessValue
        }
        set(value) {
            brightnessValue = value
        }
    }
    public mut prop useTime: ?Int64 {
        get() {
            useTimeValue
        }
        set(value) {
            useTimeValue = value
        }
    }
    public mut prop time: ?Int64 {
        get() {
            timeValue
        }
        set(value) {
            timeValue = value
        }
    }

    public init() {
        this.scale = 100
    }

    public init(limit: Int32) {
        this.scale = 100
        this.limit = limit
    }

    public func toString(): String {
        let jsonObj = JsonObject()
        if (let Some(v) <- currentPageNameValue) {
            jsonObj.put("currentPageName", JsonString(v))
        }
        if (let Some(v) <- levelValue) {
            jsonObj.put("level", JsonString(v.toString()))
        }
        if (let Some(v) <- temperatureValue) {
            jsonObj.put("temperature", JsonString(v.toString()))
        }
        if (let Some(v) <- capacityValue) {
            jsonObj.put("capacity", JsonString(v.toString()))
        }
        if (let Some(v) <- scaleValue) {
            jsonObj.put("scale", JsonString(v.toString()))
        }
        if (let Some(v) <- statusValue) {
            jsonObj.put("status", JsonString(v.toString()))
        }
        if (let Some(v) <- healthValue) {
            jsonObj.put("health", JsonString(v.toString()))
        }
        if (let Some(v) <- voltageValue) {
            jsonObj.put("voltage", JsonString(v.toString()))
        }
        if (let Some(v) <- technologyValue) {
            jsonObj.put("technology", JsonString(v))
        }
        if (let Some(v) <- pluggedValue) {
            jsonObj.put("pluegged", JsonString(v.toString()))
        }
        if (let Some(v) <- chargingValue) {
            jsonObj.put("charging", JsonString(v.toString()))
        }
        if (let Some(v) <- limitValue) {
            jsonObj.put("limit", JsonString(v.toString()))
        }
        if (let Some(v) <- brightnessValue) {
            jsonObj.put("brightness", JsonString(v.toString()))
        }
        if (let Some(v) <- useTimeValue) {
            jsonObj.put("useTime", JsonString(v.toString()))
        }
        if (let Some(v) <- timeValue) {
            jsonObj.put("time", JsonString(v.toString()))
        }
        jsonObj.toString()
    }
}

private func getChargingStatus(): Int32 {
    let chargingStatus: BatteryChargeState = BatteryInfo.chargingStatus
    let status: Int32 = match (chargingStatus) {
        case BatteryChargeState.NONE => 1
        case BatteryChargeState.ENABLE => 2
        case BatteryChargeState.DISABLE => 4
        case BatteryChargeState.FULL => 5
    }
    return status
}

private func getHealthStatus(): Int32 {
    let healthStatus: BatteryHealthState = BatteryInfo.healthStatus
    let status: Int32 = match (healthStatus) {
        case BatteryHealthState.UNKNOWN => 1
        case BatteryHealthState.GOOD => 2
        case BatteryHealthState.OVERHEAT => 3
        case BatteryHealthState.OVERVOLTAGE => 5
        case BatteryHealthState.COLD => 7
        case BatteryHealthState.DEAD => 4
    }
    return status
}

private func getPulggedType(): Int32 {
    let pluggedType: BatteryPluggedType = BatteryInfo.pluggedType
    let status: Int32 = match (pluggedType) {
        case BatteryPluggedType.NONE => 0
        case BatteryPluggedType.AC => 1
        case BatteryPluggedType.USB => 2
        case BatteryPluggedType.WIRELESS => 4
    }
    return status
}

private func isPulggedStatus(): Bool {
    let pluggedType: BatteryPluggedType = BatteryInfo.pluggedType
    let status: Bool = match (pluggedType) {
        case BatteryPluggedType.NONE => false
        case BatteryPluggedType.AC => true
        case BatteryPluggedType.USB => true
        case BatteryPluggedType.WIRELESS => true
    }
    return status
}

var uiContext: Option<UIAbilityContext> = None
var events: Array<String> = [
    Support.COMMON_EVENT_POWER_CONNECTED,
    Support.COMMON_EVENT_POWER_DISCONNECTED,
    Support.COMMON_EVENT_BATTERY_CHANGED
]
var subscribeInfo: CommonEventSubscribeInfo = CommonEventSubscribeInfo(events)
var eventSubscriber: CommonEventSubscriber = createSubscriber(subscribeInfo)
var reportBatteryCallback: (batteryInfo: BatteryUsageInfo) -> Unit = {info: BatteryUsageInfo =>}
var batteryLimit: Int32 = 1
var lastLevel: Int32 = -1
var lastTime: Int64 = getUptime(TimeType.STARTUP)
var lastScreenOnTimeStamp: Int64 = getUptime(TimeType.STARTUP)
var screenOnTotalSecond: Int64 = 0
var frontStatus: Bool = true
var currentPageName: String = defaultPageName

private func reset() {
    lastLevel = -1
    screenOnTotalSecond = 0
    lastScreenOnTimeStamp = getUptime(TimeType.STARTUP)
}

private func getBrightness(): Int32 {
    let brightness = getValue<Display>(uiContext.getOrThrow(), Display.SCREEN_BRIGHTNESS_STATUS,
        DomainName.DEVICE_SHARED.toString())
    let convertValue: Option<Int32> = Int32.tryParse(brightness)
    var status: Int32 = 0
    if (convertValue.isSome()) {
        status = convertValue.getOrThrow()
    }
    return status
}

let applicationCallback: ApplicationStateChangeCallback = ApplicationStateChangeCallback(
    {
        =>
        let currentTime = getUptime(TimeType.STARTUP)
        lastScreenOnTimeStamp = currentTime
        frontStatus = true
    },
    {
        =>
        let currentTime = getUptime(TimeType.STARTUP)
        let deltaTime = (currentTime - lastScreenOnTimeStamp) / 1000
        screenOnTotalSecond += deltaTime
        frontStatus = false
    }
)
let pageSwitchCallback: PageSwitchCallBack = PageSwitchCallBack(
    {
        info: NavDestinationSwitchInfo => currentPageName = getTargetPageName(info, defaultName: currentPageName)
    })
let commonEventCallback: AsyncCallback<CommonEventData> = {
    err, data =>
    var eventData = CommonEventData("empty")
    if (err.isNone()) {
        if (data.isSome()) {
            eventData = data.getOrThrow()
        }
    }
    if (eventData.event == Support.COMMON_EVENT_BATTERY_CHANGED) {

        let isCharging: Bool = isPulggedStatus()
        if (isCharging) {
            reset()
        } else {
            let nowLevel: Int32 = BatteryInfo.batterySOC
            if (lastLevel < 0) {
                lastLevel = nowLevel
                lastTime = getUptime(TimeType.STARTUP)
                lastScreenOnTimeStamp = lastTime
                screenOnTotalSecond = 0
            } else if (nowLevel == lastLevel) {
            } else if ((nowLevel + batteryLimit) <= lastLevel) {
                let nowTime = getUptime(TimeType.STARTUP)
                let elapsedSecond = (nowTime - lastTime) / 1000

                lastTime = nowTime
                lastLevel = nowLevel

                if (frontStatus) {
                    screenOnTotalSecond += (nowTime - lastScreenOnTimeStamp) / 1000
                }

                let screenOnSecond: Int64 = screenOnTotalSecond
                screenOnTotalSecond = 0
                lastScreenOnTimeStamp = nowTime

                let info: BatteryUsageInfo = BatteryUsageInfo(batteryLimit)
                info.currentPageName = currentPageName
                info.level = nowLevel
                info.temperature = Float64(BatteryInfo.batteryTemperature) / Float64(10.0)
                info.scale = 100
                info.status = getChargingStatus()
                info.health = getHealthStatus()
                info.voltage = BatteryInfo.voltage / 1000
                info.technology = BatteryInfo.technology
                info.plugged = getPulggedType()
                info.charging = isPulggedStatus()
                info.brightness = getBrightness()
                info.useTime = screenOnSecond
                info.time = elapsedSecond
                reportBatteryCallback(info)
            }
        }
    } else if (eventData.event == Support.COMMON_EVENT_POWER_DISCONNECTED || eventData.event == Support
        .COMMON_EVENT_POWER_CONNECTED) {
        reset()
    }
}

/**
cpu异常率
**/
var isOnBackground = false
/**
是否为从前台进入后台的标志位
进入前台 标志位重置后 下次进入所有进程处于后台状态时需要更新startBgTime
**/
var needUpdateStartBgTime = true
var startBgTime = DateTime.now().toUnixTimeStamp().toMilliseconds()
var lastJiffiesSnapshot: ?JiffiesSnapshot = None
var reportThreadCpuUsageCallback: (allThreadCpuUsageInfo: AllThreadCpuUsageInfo) -> Unit = {info: AllThreadCpuUsageInfo =>}

public class AllThreadCpuUsageInfo {
    public var threadCpuUsageInfoList = ArrayList<ThreadCpuUsageInfo>()
    public func toString(): String {
        let jsonObj = JsonObject()
        for(threadCpuUsageInfo in threadCpuUsageInfoList) {
            jsonObj.put("thread" + threadCpuUsageInfo.threadId.toString(), JsonString(threadCpuUsageInfo.toString()))
        }
        jsonObj.toString()
    }
}
public class ThreadCpuUsageInfo {
    public var threadId: UInt32
    public var threadName: String
    public var threadState: String
    public var threadJiffiesPercent: Float64
    public var threadJiffies: Int64
    public var totalJiffies: Int64
    public var startBgTime: ?Int64 = None
    public var exceptionTime: ?Float64 = None

    public init(threadId: UInt32, threadName: String, threadState: String
        , threadJiffiesPercent: Float64, threadJiffies: Int64, totalJiffies: Int64) {
        this.threadId = threadId
        this.threadName = threadName
        this.threadState = threadState
        this.threadJiffiesPercent = threadJiffiesPercent
        this.threadJiffies = threadJiffies
        this.totalJiffies = totalJiffies
    }

    public func toString(): String {
        let jsonObj = JsonObject()
        jsonObj.put("threadId", JsonString(threadId.toString()))
        jsonObj.put("threadName", JsonString(threadName))
        jsonObj.put("threadState", JsonString(threadState))
        jsonObj.put("threadJiffiesPercent", JsonString(threadJiffiesPercent.toString()))
        jsonObj.put("threadJiffies", JsonString(threadJiffies.toString()))
        jsonObj.put("totalJiffies", JsonString(totalJiffies.toString()))
        if (startBgTime.isSome()) {
            jsonObj.put("startBgTime", JsonString(startBgTime.getOrThrow().toString()))
        }
        if (exceptionTime.isSome()) {
            jsonObj.put("exceptionTime", JsonString(exceptionTime.getOrThrow().toString()))
        }
        jsonObj.toString()
    }
}

public class JiffiesSnapshot {
    public var pid: ?Int64 = -1
    public var name: ?String = None
    public var totalJiffies: Int64 = 0
    public var threadEntries = ArrayList<ThreadJiffiesSnapshot>()

    public init() {
    }

    public init(pid: Int64, name: String) {
        this.pid = pid
        this.name = name
    }
}

public class ThreadJiffiesSnapshot {
    public var tid: UInt32
    public var name: ?String = None
    public var state: ?String = None
    public var jiffies: Int64 = 0

    public init(tid: UInt32) {
        this.tid = tid
    }

    public init(tid: UInt32, name: String, state: String, jiffies: Int64) {
        this.tid = tid
        this.name = name
        this.state = state
        this.jiffies = jiffies
    }
}

private func parseThreadInfo(pid: Int64, tid: UInt32, path: String): Option<ThreadJiffiesSnapshot> {
    if (!exists(path)) {
        return None
    }
    let threadJiffiesSnapshot: ThreadJiffiesSnapshot = ThreadJiffiesSnapshot(tid)
    try (file = File(path, Read)) {
        let originText = String.fromUtf8(readToEnd(file))
        let splitText = originText.split(" ")
        threadJiffiesSnapshot.name = splitText[1].replace("(", "").replace(")", "")
        threadJiffiesSnapshot.state = splitText[2]
        let utime = Int64.parse(splitText[13])
        let stime = Int64.parse(splitText[14])
        let cutime = Int64.parse(splitText[15])
        let cstime = Int64.parse(splitText[16])
        threadJiffiesSnapshot.jiffies = utime + stime + cutime + cstime
        return threadJiffiesSnapshot
    } catch (e: Exception) {
        AppLog.warn(e.toString())
    }
    None
}

//计算两个JiffiesSnapshot的差值
private func diffThreadJiffiesSnapshot(current: JiffiesSnapshot, last: JiffiesSnapshot):(Int64, ArrayList<ThreadJiffiesSnapshot>) {
    var totalJiffies: Int64 = 0
    let deltaThreadJiffiesList = ArrayList<ThreadJiffiesSnapshot>()
    let currentThreadEntries = current.threadEntries
    let lastThreadEntries = last.threadEntries
    for (currentThread in currentThreadEntries) {
        if (currentThread.name.isNone()) {
            continue
        }
        var jiffiesConsumed = currentThread.jiffies
        for (lastThread in lastThreadEntries) {
            if (lastThread.name.isNone()) {
                continue
            }
            if (currentThread.tid == lastThread.tid && currentThread.name.getOrThrow() == lastThread.name.getOrThrow()) {
                jiffiesConsumed = currentThread.jiffies - lastThread.jiffies
                break
            }
        }
        if (jiffiesConsumed > 0) {
            let deltaThreadJiffies = ThreadJiffiesSnapshot(currentThread.tid, currentThread.name.getOrThrow()
                ,currentThread.state.getOrThrow(), jiffiesConsumed)
            deltaThreadJiffiesList.add(deltaThreadJiffies)
            totalJiffies += jiffiesConsumed
        }
    }
    deltaThreadJiffiesList.sortBy(){
        t1: ThreadJiffiesSnapshot, t2: ThreadJiffiesSnapshot =>
        if (t1.jiffies > t2.jiffies) {
            return Ordering.LT
        } else if (t1.jiffies < t2.jiffies) {
            return Ordering.GT
        } else {
            return Ordering.EQ
        }
    }
    return (totalJiffies, deltaThreadJiffiesList)
}

private func currentJiffiesSnapshot(): JiffiesSnapshot {
    let currentPid = Process.current.pid
    let jiffiesSnapshot: JiffiesSnapshot = JiffiesSnapshot(currentPid, Process.current.name)

    let threadPathList: ArrayList<(UInt32, String)> = ArrayList<(UInt32, String)>()
    let taskPath: String = "/proc/self/task"
    if (exists(taskPath) && isDir(taskPath)) {
        Directory.walk(
            taskPath,
            {
                fileinfo =>
                threadPathList.add((UInt32.parse(fileinfo.name), fileinfo.path.join("stat").toString()))
                true
            }
        )
    }
    for ((tid, tidPath) in threadPathList) {
        if (let Some(threadJiffiesSnapshot) <- parseThreadInfo(currentPid, tid, tidPath)) {
            jiffiesSnapshot.threadEntries.add(threadJiffiesSnapshot)
        }
    }
    jiffiesSnapshot
}

/**
 * 如果这3min内jiff值大于3*60*100*0.5（在3min持续时间中，当前进程有一半的时间在使用CPU）.则作为一个有效的异常抓取
 */
let SINGLE_INTERVAL_TOTAL_JIFFIES_LIMIT = 9000
private func isHitRule(deltaThreadJiffiesList: ArrayList<ThreadJiffiesSnapshot>, singleIntervalTotalJiffies: Int64): Bool {
    if (singleIntervalTotalJiffies < SINGLE_INTERVAL_TOTAL_JIFFIES_LIMIT) {
        return false
    }
    var maxThreadJiff = 0
    let threadNameJifffMap = HashMap<String, Int64>()
    //同名thread累加 不同名则比较
    for (deltaThreadJiffies in deltaThreadJiffiesList) {
        let threadName = deltaThreadJiffies.name.getOrThrow()
        let threadJiff = deltaThreadJiffies.jiffies
        if (threadNameJifffMap.contains(threadName)) {
            var threadTotalJiffies = threadNameJifffMap.get(threadName).getOrThrow()
            threadTotalJiffies += threadJiff
            threadNameJifffMap.add(threadName, threadTotalJiffies)
        } else {
            threadNameJifffMap.add(threadName, threadJiff)
        }
        let threadNewJiff =  threadNameJifffMap.get(threadName).getOrThrow()
        if (threadNewJiff > maxThreadJiff) {
            maxThreadJiff = threadNewJiff
        }
    }
    return Float64(maxThreadJiff) > Float64(singleIntervalTotalJiffies) * 0.5
}

private func calculateAndReportCpuUsage(deltaThreadJiffiesList: ArrayList<ThreadJiffiesSnapshot>, singleIntervalTotalJiffies: Int64): Unit {
    let allThreadCpuUsageInfo = AllThreadCpuUsageInfo()
    let reportThreadList = allThreadCpuUsageInfo.threadCpuUsageInfoList
    for (deltaThreadJiffies in deltaThreadJiffiesList) {
        //todo trace
        let threadJiffiesPercent = Float64(deltaThreadJiffies.jiffies) / Float64(singleIntervalTotalJiffies)
        let threadCpuUsageInfo = ThreadCpuUsageInfo(deltaThreadJiffies.tid, deltaThreadJiffies.name.getOrThrow()
            ,deltaThreadJiffies.state.getOrThrow(), threadJiffiesPercent, deltaThreadJiffies.jiffies, singleIntervalTotalJiffies)
        if (isOnBackground) {
            threadCpuUsageInfo.startBgTime = startBgTime
            threadCpuUsageInfo.exceptionTime = Float64(DateTime.now().toUnixTimeStamp().toMilliseconds() - startBgTime) / 1000.0
        }
        reportThreadList.add(threadCpuUsageInfo)
    }
    reportThreadCpuUsageCallback(allThreadCpuUsageInfo)
}

let processInfoCallback: AsyncCallback<Array<ProcessInformation>> = {
    err, data =>
    //判断所有进程是否都在后台
    if (data.isNone()) {
        return
    }
    let processInfoArray = data.getOrThrow()
    for (processInfo in processInfoArray) {
        match (processInfo.state) {
            case STATE_BACKGROUND => isOnBackground = true
            case STATE_FOREGROUND =>
                isOnBackground = false
                break
            case _ => isOnBackground = isOnBackground
        }
    }
    if (isOnBackground && needUpdateStartBgTime) {
        startBgTime = DateTime.now().toUnixTimeStamp().toMilliseconds()
        needUpdateStartBgTime = false
    }
}

private func cpuErrorPercentReport(): Unit {
    //主入口
    getRunningProcessInformation(processInfoCallback)

    let currentJiffiesSnapshot = currentJiffiesSnapshot()
    if (lastJiffiesSnapshot.isSome()) {
        let deltaThreadJiffiesSnapshot = diffThreadJiffiesSnapshot(currentJiffiesSnapshot, lastJiffiesSnapshot.getOrThrow())
        let singleIntervalTotalJiffies: Int64 = deltaThreadJiffiesSnapshot[0]
        let deltaThreadJiffiesList = deltaThreadJiffiesSnapshot[1]
        if (isHitRule(deltaThreadJiffiesList, singleIntervalTotalJiffies)) {
            calculateAndReportCpuUsage(deltaThreadJiffiesList, singleIntervalTotalJiffies)
        }
    }
    lastJiffiesSnapshot = currentJiffiesSnapshot
}

let handleCpuReport: (param: Array<String>) -> Unit = {
    param: Array<String> => cpuErrorPercentReport()
}

private func handleCpuUsage(array: Array<String>): Unit {
    lastJiffiesSnapshot = currentJiffiesSnapshot()
    setInterval(handleCpuReport, 3 * 60 * 1000, Array<String>())
}

let abilityLifecycleCallback: AbilityLifecycleCallback = AbilityLifecycleCallback(
    onAbilityCreate: { ability: UIAbility => () },
    onWindowStageCreate: { abilty: UIAbility, windowStage: window.WindowStage => () },
    onWindowStageActive: { abilty: UIAbility, windowStage: window.WindowStage => () },
    onWindowStageInactive: { abilty: UIAbility, windowStage: window.WindowStage => () },
    onWindowStageDestroy: { abilty: UIAbility, windowStage: window.WindowStage => () },
    onAbilityDestroy: { abilityUIability => () },
    //进入前台
    onAbilityForeground: { ability: UIAbility => needUpdateStartBgTime = true },
    onAbilityBackground: { ability: UIAbility => () },
    onAbilityContinue: { abilityUIability => () },
    onWindowStageRestore: { abilty: UIAbility, windowStage: window.WindowStage => () }
)

public func initBatteryHandler(
    context: UIAbilityContext,
    reportBatteryInfo: (batteryInfo: BatteryUsageInfo) -> Unit,
    reportThreadCpuUsageInfo: (allThreadCpuUsageInfo: AllThreadCpuUsageInfo) -> Unit,
    limit!: Int32 = 1
): Unit {
    uiContext = context
    reportBatteryCallback = reportBatteryInfo
    batteryLimit = limit
    let applicationContext = uiContext.getOrThrow().getApplicationContext()

    //3min轮询一次
    reportThreadCpuUsageCallback = reportThreadCpuUsageInfo
    handleCpuUsage()

    applicationContext.on(ApplicationContextType.APPLICATION_STATE_CHANGE, applicationCallback)
    applicationContext.on(ApplicationContextType.ABILITY_LIFECYCLE, abilityLifecycleCallback)
    on(navDestinationSwitch, context, pageSwitchCallback)
    subscribe(eventSubscriber, commonEventCallback)
}

public func destroyBatteryHandler(): Unit {
    reportBatteryCallback = {data: BatteryUsageInfo =>}
    let context = uiContext.getOrThrow()
    let applicationContext = context.getApplicationContext()
// todo: tpc bug
//    applicationContext.off(ApplicationContextType.APPLICATION_STATE_CHANGE, callback: applicationCallback)
    off(navDestinationSwitch, context, pageSwitchCallback)
    unsubscribe(eventSubscriber, callback: {err,_ => })
}
