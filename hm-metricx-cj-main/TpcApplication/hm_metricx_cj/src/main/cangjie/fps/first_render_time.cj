package ohos_app_cangjie_hm_metricx_cj.fps

import std.time.*
import ohos.base.AppLog
import stdx.encoding.json.*

var frt_init_flag: Bool = false

// 首帧渲染时间信息类
public class FirstRenderTimeInfo {
    private var startTimeValue: Int64 = 0
    private var endTimeValue: Int64 = 0
    private var durationValue: Int64 = 0
    private var targetPageValue: String = ""

    public init() {}

    public init(startTime: Int64, endTime: Int64, duration: Int64, targetPage: String) {
        this.startTimeValue = startTime
        this.endTimeValue = endTime
        this.durationValue = duration
        this.targetPageValue = targetPage
    }

    mut prop startTime: Int64 {
        get() { startTimeValue }
        set(value) { startTimeValue = value }
    }

    mut prop endTime: Int64 {
        get() { endTimeValue }
        set(value) { endTimeValue = value }
    }

    mut prop duration: Int64 {
        get() { durationValue }
        set(value) { durationValue = value }
    }

    mut prop targetPage: String {
        get() { targetPageValue }
        set(value) { targetPageValue = value }
    }

    public func toString(): String {
        let jsonObj = JsonObject()
        jsonObj.put("startTime", JsonString(startTimeValue.toString()))
        jsonObj.put("endTime", JsonString(endTimeValue.toString()))
        jsonObj.put("duration", JsonString(durationValue.toString()))
        jsonObj.put("targetPage", JsonString(targetPageValue))
        jsonObj.toString()
    }
}

// 首帧渲染时间配置类
public class FirstRenderTimeConfig {
    private var enableLoggingValue: Bool = true
    private var reportThresholdValue: Int64 = 1000

    public init() {
        enableLoggingValue = true
        reportThresholdValue = 1000
    }

    public init(enableLogging: Bool, reportThreshold: Int64) {
        this.enableLoggingValue = enableLogging
        this.reportThresholdValue = if (reportThreshold < 0 || reportThreshold > Int64.Max) {
            throw Exception("Invalid reportThresholdValue: ${reportThreshold}, expected [0, Int64.Max]")
        } else {
            reportThreshold
        }
    }

    mut prop enableLogging: Bool {
        get() { enableLoggingValue }
        set(value) { enableLoggingValue = value }
    }

    mut prop reportThreshold: Int64 {
        get() { reportThresholdValue }
        set(value) { reportThresholdValue = value }
    }
}

// 首帧渲染时间监控器（单例）
public class FirstRenderTimeMonitor {
    private static var instance: Option<FirstRenderTimeMonitor> = None
    
    public static func GetInstance(): FirstRenderTimeMonitor {
        if (instance.isNone()) {
            instance = FirstRenderTimeMonitor()
        }
        instance.getOrThrow()
    }

    // 内部状态
    private var clickStartTime: ?Int64 = None
    private var navigationTargetPage: ?String = None
    private var drawEndTime: ?Int64 = None
    private var isWaitingDraw: Bool = false
    private var config: FirstRenderTimeConfig = FirstRenderTimeConfig()
    private var reportCallback: Option<(info: FirstRenderTimeInfo) -> Unit> = None

    // 设置配置
    public func setConfig(config: FirstRenderTimeConfig): Unit {
        this.config = config
    }

    // 设置上报回调
    public func setReportCallback(callback: (info: FirstRenderTimeInfo) -> Unit): Unit {
        this.reportCallback = Some(callback)
    }

    // 记录点击开始时间
    public func recordClickStart(): Unit {
        if (isWaitingDraw) {
            if (config.enableLogging) {
                AppLog.warn("FRT click ignored, previous flow not finished")
            }
            return
        }
        let currentTime = DateTime.now().toUnixTimeStamp().toMilliseconds()
        clickStartTime = Some(currentTime)
        if (config.enableLogging) {
            AppLog.info("FRT click at: " + currentTime.toString())
        }
    }

    // 记录导航目标页面
    public func recordNavigationTarget(targetPage: String): Unit {
        navigationTargetPage = Some(targetPage)
        isWaitingDraw = true

        if (config.enableLogging) {
            AppLog.info("FRT nav: " + targetPage)
        }
    }

    // 手动计算首帧渲染时间
    public func calculateFirstRenderTimeManually(startTime: Int64, targetPage: String): Unit {
        let endTime = DateTime.now().toUnixTimeStamp().toMilliseconds()
        let duration = endTime - startTime
        if (duration >= config.reportThreshold) {
            let frtInfo = FirstRenderTimeInfo(startTime, endTime, duration, targetPage)
            if (config.enableLogging) {
                AppLog.info("FirstRenderTimeMonitor Manual calculation - First render time for " + targetPage + ": " + duration.toString() + "ms")
            }
            if (let Some(cb) <- reportCallback) {
                cb(frtInfo)
            }
        }
    }

    public func recordDrawEnd(): Unit {
        if (!isWaitingDraw) {
            return
        }

        let endTime = DateTime.now().toUnixTimeStamp().toMilliseconds()
        drawEndTime = Some(endTime)
        calculateIfReady()
    }

    // 检查是否所有条件都满足并计算
    private func calculateIfReady(): Unit {
        if (clickStartTime.isSome() && navigationTargetPage.isSome() && drawEndTime.isSome()) {
            let startTime = clickStartTime.getOrThrow()
            let endTime = drawEndTime.getOrThrow()
            let duration = endTime - startTime
            let page = navigationTargetPage.getOrThrow()

            if (duration >= config.reportThreshold) {
                let info = FirstRenderTimeInfo(startTime, endTime, duration, page)

                if (config.enableLogging) {
                    AppLog.info("FirstRenderTimeMonitor - First render time for " + page + ": " + duration.toString() + "ms")
                }

                if (let Some(cb) <- reportCallback) {
                    cb(info)
                }
            }
            reset()
        }
    }

    // 重置状态
    public func reset(): Unit {
        clickStartTime = None
        navigationTargetPage = None
        drawEndTime = None
        isWaitingDraw = false
        frt_init_flag = false
    }
}

// ==================== 公开函数接口 ====================

// 初始化首帧渲染时间监控器
public func initFirstRenderTimeMonitor(
    config: FirstRenderTimeConfig,
    reportCallback: (FirstRenderTimeInfo) -> Unit
): Unit {
    if (frt_init_flag) {
        return
    }
    frt_init_flag = true
    let monitor = FirstRenderTimeMonitor.GetInstance()
    monitor.setConfig(config)
    monitor.setReportCallback(reportCallback)
}

// 记录点击开始
public func recordClickStart(): Unit {
    FirstRenderTimeMonitor.GetInstance().recordClickStart()
}

// 记录导航目标页面
public func recordNavigationTarget(targetPage: String): Unit {
    FirstRenderTimeMonitor.GetInstance().recordNavigationTarget(targetPage)
}

// 记录Draw结束
public func recordDrawEnd(): Unit {
    FirstRenderTimeMonitor.GetInstance().recordDrawEnd()
}

// 重置监控器状态
public func resetFirstRenderTimeMonitor(): Unit {
    FirstRenderTimeMonitor.GetInstance().reset()
}