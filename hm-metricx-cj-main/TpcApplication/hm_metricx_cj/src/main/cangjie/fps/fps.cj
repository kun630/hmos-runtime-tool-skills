/*
 * Copyright (c) Huawei Technologies Co., Ltd. 2025-2025. All rights reserved.
 */
package ohos_app_cangjie_hm_metricx_cj.fps

import ohos.base.{Callback1Argument}
import tpc.UIKit.Observer.{ScrollEventInfo, NavDestinationSwitchInfo, on, ObserverListenerType, ScrollEventType}
import tpc.ArkGraphics2D.displaySync.{IntervalInfo, DisplaySync, create, OnOffType}
import tpc.AbilityKit.common.UIAbilityContext
import stdx.encoding.json.{JsonObject, JsonString}
import tpc.UIKit.window.{WindowStage, WindowCallbackType, WindowEventType}
import std.collection.*
import ohos.base.AppLog
import ohos.hilog.Hilog
import ohos_app_cangjie_hm_metricx_cj.util.*


const NANOS_IN_SECOND = 1000000000
const SCROLL_HITCH_COEFF = 1000

// 滚动时间回调类
public class ScrollEventCallback <: Callback1Argument<ScrollEventInfo> {
    let elementInfoCallback: (ScrollEventInfo) -> Unit
    public init(elementInfoCallback: (ScrollEventInfo) -> Unit) {
        this.elementInfoCallback = elementInfoCallback
    }
    public func invoke(res: ScrollEventInfo): Unit {
        this.elementInfoCallback(res)
    }
}

// 页面跳转回调类
public class NavDestinationSwitchCallBack <: Callback1Argument<NavDestinationSwitchInfo> {
    let elementInfoCallback: (NavDestinationSwitchInfo) -> Unit
    public init(elementInfoCallback: (NavDestinationSwitchInfo) -> Unit) {
        this.elementInfoCallback = elementInfoCallback
    }
    public func invoke(res: NavDestinationSwitchInfo): Unit {
        this.elementInfoCallback(res)
    }
}

// window监控回调类
public class WindowEventTypeCallBack <: Callback1Argument<WindowEventType> {
    let elementInfoCallback: (WindowEventType) -> Unit
    public init(elementInfoCallback: (WindowEventType) -> Unit) {
        this.elementInfoCallback = elementInfoCallback
    }
    public func invoke(res: WindowEventType): Unit {
        this.elementInfoCallback(res)
    }
}

// 帧事件回调类
public class IntervalInfoCallback <: Callback1Argument<IntervalInfo> {
    let elementInfoCallback: (IntervalInfo) -> Unit
    public init(elementInfoCallback: (IntervalInfo) -> Unit) {
        this.elementInfoCallback = elementInfoCallback
    }
    public func invoke(res: IntervalInfo): Unit {
        this.elementInfoCallback(res)
    }
}

// 页面Fps信息类
public class FpsEventInfo {
    public FpsEventInfo(let minFps: Int64, let avgFps: Int64, let pageName: String) {}

    public func toString(): String {
        let jsonObj = JsonObject()
        jsonObj.put("minFps", JsonString("${minFps}"))
        jsonObj.put("avgFps", JsonString("${avgFps}"))
        jsonObj.put("pageName", JsonString(pageName))
        jsonObj.toString()
    }
}

// 滑动事件Fps&滑动掉帧率信息类
public class ScrollHitchInfo {
    public ScrollHitchInfo(
        let minFps: Int64,
        let avgFps: Int64,
        let frameDropRatio: Float64,
        let jankRate: Float64,
        let bigJankRate: Float64,
        let htLessThan0: Float64,
        let ht0To00001: Float64,
        let ht00001To0001: Float64,
        let ht0001To001: Float64,
        let ht001To005: Float64,
        let ht005To01: Float64,
        let ht01To1: Float64,
        let htBiggerThan1: Float64,
        let targetFPS: Float64,
        let longestLostFrame: Float64,
        let totalFrameCount: Int64,
        let pageName: String) {}

    public func toString(): String {
        let jsonObj = JsonObject()
        jsonObj.put("minFps", JsonString("${minFps}"))
        jsonObj.put("avgFps", JsonString("${avgFps}"))
        jsonObj.put("pageName", JsonString(pageName))
        jsonObj.put("frameDropRatio", JsonString("${frameDropRatio}"))
        jsonObj.put("jankRate", JsonString("${jankRate}"))
        jsonObj.put("bigJankRate", JsonString("${bigJankRate}"))
        jsonObj.put("htLessThan0", JsonString("${htLessThan0}"))
        jsonObj.put("ht0To00001", JsonString("${ht0To00001}"))
        jsonObj.put("ht00001To0001", JsonString("${ht00001To0001}"))
        jsonObj.put("ht0001To001", JsonString("${ht0001To001}"))
        jsonObj.put("ht001To005", JsonString("${ht001To005}"))
        jsonObj.put("ht005To01", JsonString("${ht005To01}"))
        jsonObj.put("ht01To1", JsonString("${ht01To1}"))
        jsonObj.put("htBiggerThan1", JsonString("${htBiggerThan1}"))
        jsonObj.put("targetFPS", JsonString("${targetFPS}"))
        jsonObj.put("longestLostFrame", JsonString("${longestLostFrame}"))
        jsonObj.put("totalFrameCount", JsonString("${totalFrameCount}"))
        jsonObj.toString()
    }
}

public open class FpsEvent {
    // 创建DisplaySync对象
    protected var backDisplaySync: DisplaySync = create()
    // 当前帧信息
    protected var timestamp: Int64 = 0
    protected var targetTimestamp: Int64 = 0
    // 统计信息
    protected var totalStatisticsTime: Int64 = 0
    protected var totalFrameCount: Int64 = 0
    protected var totalStatisticsTimePerSec: Int64 = 0
    // 是否是第一帧
    protected var isFirstFrame: Bool = true
    // 当前页面名
    protected var currentPageName: String = ""
    // minfps
    protected var minFps: Int64 = Int64.Max
    private let framesInOnePer = ArrayDeque<Int64>()
    // 重置当前Frame
    public func updateFrameInfo(timestamp: Int64, targetTimestamp: Int64): Unit {
        this.timestamp = timestamp
        this.targetTimestamp = targetTimestamp
    }
    // 开始检测frame事件
    public func startDisplaySync() {
        this.backDisplaySync.start()
    }
    // 停止检测frame事件
    public func stopDisplaySync() {
        this.backDisplaySync.stop()
    }
    // 重置监听事件
    public open func reset() {
        this.isFirstFrame = true
        this.timestamp = 0
        this.targetTimestamp = 0
        this.totalStatisticsTime = 0
        this.totalFrameCount = 0
        this.totalStatisticsTimePerSec = 0
        this.minFps = Int64.Max
        this.framesInOnePer.clear()
    }

    protected func updateMinFps(timestamp: Int64, realTimeInterval: Int64) {
        if (minFps == 0) {
            return
        }
        totalStatisticsTimePerSec += realTimeInterval
        while (!framesInOnePer.isEmpty() && framesInOnePer.first.getOrThrow() < timestamp - NANOS_IN_SECOND) {
            framesInOnePer.removeFirst()
        }
        framesInOnePer.addLast(timestamp)
        if (realTimeInterval >= NANOS_IN_SECOND) {
            minFps = 0
            totalStatisticsTimePerSec = 0
        }
        else if (totalStatisticsTimePerSec >= NANOS_IN_SECOND) {
            minFps = min(minFps, framesInOnePer.size)
            totalStatisticsTimePerSec = 0
        }
    }
}

public class PageFpsEvent <: FpsEvent {
    // 单例模式
    private static var instance = PageFpsEvent()
    public static func GetInstance() {
        instance
    }
    // 监控指标
    private var fpsEventInfo: ?FpsEventInfo = None
    public func reset() {
        super.reset()
        this.fpsEventInfo = None
    }
    // 监控每一帧，计算Fps
    public func frameEventListener() {
        let callback = {
            frameInfo: IntervalInfo =>
            if (isFirstFrame) {
                isFirstFrame = false
            } else {
                totalFrameCount += 1
                let realTimeInterval = frameInfo.timestamp - timestamp
                // avgFps
                totalStatisticsTime += realTimeInterval
                // minFps
                updateMinFps(frameInfo.timestamp, realTimeInterval)
            }
            updateFrameInfo(frameInfo.timestamp, frameInfo.targetTimestamp)
        }
        backDisplaySync.on(OnOffType.DS_FRAME, IntervalInfoCallback(callback))
    }
    // 统计minFps和avgFps
    public func report(): Option<FpsEventInfo> {
        if (totalStatisticsTime <= 0) {
            return None
        }
        let avgFps = NANOS_IN_SECOND * totalFrameCount / totalStatisticsTime
        minFps = min(minFps, avgFps)
        FpsEventInfo(minFps, avgFps, currentPageName)
    }
}

class PageScrollFps {
    private let minFpsList = ArrayList<Int64>()
    private var frameCount = 0
    private var totalTime = 0
    private var dropTime = 0
    private var htLessThan0 = 0
    private var ht0To00001 = 0
    private var ht00001To0001 = 0
    private var ht0001To001 = 0
    private var ht001To005 = 0
    private var ht005To01 = 0
    private var ht01To1 = 0
    private var htBiggerThan1 = 0
    private var htBiggerThan0001 = 0
    private var htBiggerThan07 = 0
    private var targetDuration = 0
    private var longestLostFrame = 0.0


    public func clear(): Unit {
        minFpsList.clear()
        frameCount = 0
        totalTime = 0
        dropTime = 0
        htLessThan0 = 0
        ht0To00001 = 0
        ht00001To0001 = 0
        ht0001To001 = 0
        ht001To005 = 0
        ht005To01 = 0
        ht01To1 = 0
        htBiggerThan1 = 0
        htBiggerThan0001 = 0
        htBiggerThan07 = 0
        targetDuration = 0
        longestLostFrame = 0.0
    }

    public func addInfo(
        minFps: Int64,
        totalFrameCount: Int64,
        totalStatisticsTime: Int64,
        totalFrameDropTime: Int64,
        htLessThan0Cnt: Int64,
        ht0To00001Cnt: Int64,
        ht00001To0001Cnt: Int64,
        ht0001To001Cnt: Int64,
        ht001To005Cnt: Int64,
        ht005To01Cnt: Int64,
        ht01To1Cnt: Int64,
        htBiggerThan1Cnt: Int64,
        htBiggerThan0001Cnt: Int64,
        htBiggerThan07Cnt: Int64,
        targetDurationValue: Int64,
        longestLostFrameValue: Float64): Unit {
        minFpsList.add(minFps)
        frameCount += totalFrameCount
        totalTime += totalStatisticsTime
        dropTime += totalFrameDropTime
        htLessThan0 += htLessThan0Cnt
        ht0To00001 += ht0To00001Cnt
        ht00001To0001 += ht00001To0001Cnt
        ht0001To001 += ht0001To001Cnt
        ht001To005 += ht001To005Cnt
        ht005To01 += ht005To01Cnt
        ht01To1 += ht01To1Cnt
        htBiggerThan1 += htBiggerThan1Cnt
        htBiggerThan0001 += htBiggerThan0001Cnt
        htBiggerThan07 += htBiggerThan07Cnt
        targetDuration = targetDurationValue
        longestLostFrame = max(longestLostFrame, longestLostFrameValue)
    }

    public func isEmpty(): Bool {
        minFpsList.isEmpty()
    }

    public func report(): Option<ScrollHitchInfo> {
        if (isEmpty()) {
            return None
        }
        let minFps = min<Int64>(minFpsList.iterator()).getOrThrow()
        let avgFps = NANOS_IN_SECOND * frameCount / totalTime
        let frameDropRatio: Float64 = Float64(SCROLL_HITCH_COEFF * dropTime) /
                                        Float64(totalTime)
        let jankRate = Float64(htBiggerThan0001)/Float64(frameCount)
        let bigJankRate = Float64(htBiggerThan07)/Float64(frameCount)
        let htLessThan0 = Float64(htLessThan0)/Float64(frameCount)
        let ht0To00001 = Float64(ht0To00001)/Float64(frameCount)
        let ht00001To0001 = Float64(ht00001To0001)/Float64(frameCount)
        let ht0001To001 = Float64(ht0001To001)/Float64(frameCount)
        let ht001To005 = Float64(ht001To005)/Float64(frameCount)
        let ht005To01 = Float64(ht005To01)/Float64(frameCount)
        let ht01To1 = Float64(ht01To1)/Float64(frameCount)
        let htBiggerThan1 = Float64(htBiggerThan1)/Float64(frameCount)
        let targetFPS = Float64(NANOS_IN_SECOND)/Float64(targetDuration)
        ScrollHitchInfo(
            minFps,
            avgFps,
            frameDropRatio,
            jankRate,
            bigJankRate,
            htLessThan0,
            ht0To00001,
            ht00001To0001,
            ht0001To001,
            ht001To005,
            ht005To01,
            ht01To1,
            htBiggerThan1,
            targetFPS,
            longestLostFrame,
            frameCount,
            ScrollFpsEvent.GetInstance().currentPageName)
    }
}

public class ScrollFpsEvent <: FpsEvent {
    // 单例模式
    private static var instance = ScrollFpsEvent()
    public static func GetInstance() {
        instance
    }
    // 监控指标
    private var totalFrameDropTime: Int64 = 0
    private var scrollHitchInfo: ?ScrollHitchInfo = None
    private var htLessThan0 = 0
    private var ht0To00001 = 0
    private var ht00001To0001 = 0
    private var ht0001To001 = 0
    private var ht001To005 = 0
    private var ht005To01 = 0
    private var ht01To1 = 0
    private var htBiggerThan1 = 0
    private var htBiggerThan0001 = 0
    private var htBiggerThan07 = 0
    private var firstTargetDuration = 0
    private var longestLostFrame = 0.0
    private var targetDuration = 0

    public func reset() {
        super.reset()
        this.totalFrameDropTime = 0
        this.scrollHitchInfo = None
        htLessThan0 = 0
        ht0To00001 = 0
        ht00001To0001 = 0
        ht0001To001 = 0
        ht001To005 = 0
        ht005To01 = 0
        ht01To1 = 0
        htBiggerThan1 = 0
        htBiggerThan0001 = 0
        htBiggerThan07 = 0
        firstTargetDuration = 0
        longestLostFrame = 0.0
    }
    // 监控每一帧，计算Fps和滑动掉帧时间
    public func frameEventListener() {
        let callback = {
            frameInfo: IntervalInfo =>
            if (isFirstFrame) {
                isFirstFrame = false
                firstTargetDuration = frameInfo.targetTimestamp - frameInfo.timestamp
            } else {
                totalFrameCount += 1
                let realTimeInterval = frameInfo.timestamp - timestamp
                // avgFps
                totalStatisticsTime += realTimeInterval
                // minFps
                updateMinFps(frameInfo.timestamp, realTimeInterval)
                // 滑动掉帧率, 值为负时不纳入统计
                let delta = frameInfo.timestamp - targetTimestamp
                totalFrameDropTime += max(0, delta)
                longestLostFrame = max(longestLostFrame, Float64(delta)/Float64(targetDuration) - 1.0)
                updateHt(delta)
            }
            targetDuration = frameInfo.targetTimestamp - frameInfo.timestamp
            updateFrameInfo(frameInfo.timestamp, frameInfo.targetTimestamp)
        }
        backDisplaySync.on(OnOffType.DS_FRAME, IntervalInfoCallback(callback))
    }

    func report(pageScrollFps: PageScrollFps): Unit {
        if (totalStatisticsTime <= 0) {
            return
        }
        let avgFps = NANOS_IN_SECOND * totalFrameCount / totalStatisticsTime
        minFps = min(minFps, avgFps)
        pageScrollFps.addInfo(
            minFps,
            totalFrameCount,
            totalStatisticsTime,
            totalFrameDropTime,
            htLessThan0,
            ht0To00001,
            ht00001To0001,
            ht0001To001,
            ht001To005,
            ht005To01,
            ht01To1,
            htBiggerThan1,
            htBiggerThan0001,
            htBiggerThan07,
            firstTargetDuration,
            longestLostFrame)
    }

    func updateHt(delta: Int64) {
        if (delta < 0) {
            htLessThan0 += 1
        } else if (delta < 100_000) { // 0.1ms
            ht0To00001 += 1
        } else if (delta < 1000_000) {
            ht00001To0001 += 1
        } else if (delta < 10_000_000) {
            ht0001To001 += 1
        } else if (delta < 50_000_000) {
            ht001To005 += 1
        } else if (delta < 100_000_000) {
            ht005To01 += 1
        } else if (delta < 1000_000_000) {
            ht01To1 += 1
        } else {
            htBiggerThan1 += 1
        }

        if (delta > 1000_000) {
            htBiggerThan0001 += 1
        }

        if (delta > 700_000_000) {
            htBiggerThan07 += 1
        }
    }
}

@When[debug]
private func printScrollEventInfo(info: ScrollEventInfo) {
    Hilog.warn(0, "hm_metricx_cj", "scroll component id: ${info.id}, scroll component unique id: ${info.uniqueId}")
}

@When[!debug]
private func printScrollEventInfo(info: ScrollEventInfo) {}

// 滑动时间监听
public func initScrollEventHandler(
    uiContext: UIAbilityContext,
    reportPageScrollInfo: (scrollInfo: ScrollHitchInfo) -> Unit
) {
    let instance = ScrollFpsEvent.GetInstance()
    let pageScrollFps = PageScrollFps()
    instance.currentPageName = defaultPageName
    let scrollCallback1 = {
        =>
        instance.startDisplaySync()
        instance.frameEventListener()
    }
    let scrollCallback2 = {
        =>
        instance.stopDisplaySync()
        instance.report(pageScrollFps)
        instance.reset()
    }
    on(
        scrollEvent,
        ScrollEventCallback {
            info: ScrollEventInfo =>
            match (info.scrollEvent) {
                case SCROLL_START => scrollCallback1()
                case SCROLL_STOP =>
                    printScrollEventInfo(info) // temperarily added
                    scrollCallback2()
            }
        }
    )
    on(
        navDestinationSwitch,
        uiContext,
        NavDestinationSwitchCallBack {
            info: NavDestinationSwitchInfo =>
                let pageScrollInfo = pageScrollFps.report()
                if (pageScrollInfo.isSome()) {
                    reportPageScrollInfo(pageScrollInfo.getOrThrow())
                }
                pageScrollFps.clear()
                instance.currentPageName = getTargetPageName(info)
        }
    )
}

// 页面停留监听
public func initPageEventHandler(
    uiContext: UIAbilityContext,
    reportFpsInfo: (fpsInfo: FpsEventInfo) -> Unit
) {
    let instance = PageFpsEvent.GetInstance()
    let pageCallback1 = {
        currentPageName: String =>
        instance.currentPageName = currentPageName
        instance.startDisplaySync()
        instance.frameEventListener()
    }
    let pageCallback2 = {
        =>
        instance.stopDisplaySync()
        let fpsInfo = instance.report()
        if (fpsInfo.isSome()) {
            reportFpsInfo(fpsInfo.getOrThrow())
        }
        instance.reset()
    }
    pageCallback1(defaultPageName)
    on(
        navDestinationSwitch,
        uiContext,
        NavDestinationSwitchCallBack {
            info: NavDestinationSwitchInfo =>
            pageCallback2()
            pageCallback1(getTargetPageName(info))
        }
    )
}

// 应用状态监控
public func initPageEventHandler(windowStage: WindowStage, reportFpsInfo: (fpsInfo: FpsEventInfo) -> Unit) {
    let instance = PageFpsEvent.GetInstance()
    let pageCallback1 = {
        =>
        instance.startDisplaySync()
        instance.frameEventListener()
    }
    let pageCallback2 = {
        =>
        instance.stopDisplaySync()
        let fpsInfo = instance.report()
        if (fpsInfo.isSome()) {
            reportFpsInfo(fpsInfo.getOrThrow())
        }
        instance.reset()
    }
    let window = windowStage.getMainWindowSync()
    window.on(
        WindowCallbackType.WindowEvent,
        WindowEventTypeCallBack {
            info => match (info) {
                case WINDOW_ACTIVE => pageCallback1()
                case WINDOW_INACTIVE => pageCallback2()
                case _ => ()
            }
        }
    )
}
