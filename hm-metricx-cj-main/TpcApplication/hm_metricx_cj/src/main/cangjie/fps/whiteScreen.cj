package ohos_app_cangjie_hm_metricx_cj.fps

import tpc.UIKit.UIContext.*
import tpc.UIKit.Observer.*
import tpc.UIKit.component_snapshot.SnapshotOptions
import tpc.ArkGraphics2D.displaySync.{IntervalInfo, DisplaySync, create, OnOffType}
import tpc.ArkGraphics2D.effectKit.{createColorPicker, ColorPicker, Color}
import tpc.UIKit.window.{WindowStage, Window}
import tpc.AbilityKit.AbilityLifecycleCallback
import tpc.AbilityKit.ApplicationContextType
import tpc.AbilityKit.UIAbility
import tpc.AbilityKit.UIAbilityContext
import tpc.ImageKit.image
import tpc.PerformanceAnalysisKit.hiAppEvent.*
import tpc.BasicServicesKit.*
import tpc.UIKit.global.{setTimeout, clearTimeout}
import ohos.base.{Callback1Argument, AppLog}
import ohos.hilog.Hilog
import std.collection.*
import std.convert.*
import std.time.*
import stdx.encoding.json.*
import ohos_app_cangjie_hm_metricx_cj.util.*

// ============================================================
// 白屏类型枚举
// ============================================================

public enum WhiteScreenType {
    | TIMEOUT
    | CONTENT_MISSING

    public func toString(): String {
        match (this) {
            case TIMEOUT => "TIMEOUT"
            case CONTENT_MISSING => "CONTENT_MISSING"
        }
    }
}

// ============================================================
// 白屏检测场景（区分页面进入 / 前台切后台）
// ============================================================

public enum WhiteScreenScene {
    | PAGE_OPEN
    | PAGE_BACKGROUND

    public func toString(): String {
        match (this) {
            case PAGE_OPEN => "PAGE_OPEN"
            case PAGE_BACKGROUND => "PAGE_BACKGROUND"
        }
    }
}

// ============================================================
// 应用前后台状态
// ============================================================

public enum WhiteScreenAppState {
    | FOREGROUND
    | BACKGROUND

    public func toString(): String {
        match (this) {
            case FOREGROUND => "FOREGROUND"
            case BACKGROUND => "BACKGROUND"
        }
    }

    public func isForeground(): Bool {
        match (this) {
            case FOREGROUND => true
            case BACKGROUND => false
        }
    }
}

// ============================================================
// 检测阶段枚举（内部状态机）
// ============================================================

enum DetectionPhase {
    | IDLE
    | WAITING_FIRST_FRAME
    | COUNTING_FRAMES
    | SNAPSHOT_ANALYSIS
}

// ============================================================
// 配置类
// ============================================================

public class WhiteScreenConfig {
    public var rootComponentId: ?String = None

    // 页面打开后 ttidTimeoutMs 内没有首帧，直接判定 TIMEOUT
    public var ttidTimeoutMs: Int64 = 1000

    // 首帧之后持续检测 frameCheckDurationMs，再截图分析页面是否白屏
    public var frameCheckDurationMs: Int64 = 3000

    // 后台双截图延迟
    public var backgroundFirstSnapshotDelayMs: Int64 = 800
    public var backgroundSecondSnapshotDelayMs: Int64 = 1800

    // 只有最近进入页面 / 页面打开检测仍在进行时，才触发后台白屏检测
    public var backgroundRecentPageEnterThresholdMs: Int64 = 3000

    // 帧数阈值：用于前台 PAGE_OPEN 辅助判断
    public var minFrameCountThreshold: Int64 = 30

    // 颜色复杂度阈值：颜色种类少，表示画面较单一
    public var maxDistinctColorCount: Int64 = 2

    // 白色 RGB 阈值：RGB 都 >= 该值，才认为主色接近白色
    // 245 比较严格；如果浅灰白也需要算白屏，可调到 240 或 235
    public var whiteRgbThreshold: Int64 = 245

    public var snapshotScale: Float64 = 0.1
    public var snapshotRegionTop: Float64 = 0.08
    public var snapshotRegionBottom: Float64 = 0.08
    public var autoWriteFaultLog: Bool = true

    public init() {}

    public init(rootComponentId: String) {
        this.rootComponentId = rootComponentId
    }

    public func validate(): Unit {
        validateNonNegativeInt64("ttidTimeoutMs", ttidTimeoutMs)
        validateNonNegativeInt64("frameCheckDurationMs", frameCheckDurationMs)
        validateNonNegativeInt64("backgroundFirstSnapshotDelayMs", backgroundFirstSnapshotDelayMs)
        validateNonNegativeInt64("backgroundSecondSnapshotDelayMs", backgroundSecondSnapshotDelayMs)
        validateNonNegativeInt64("backgroundRecentPageEnterThresholdMs", backgroundRecentPageEnterThresholdMs)
        validateNonNegativeInt64("minFrameCountThreshold", minFrameCountThreshold)
        validateNonNegativeInt64("maxDistinctColorCount", maxDistinctColorCount)
        validateNonNegativeInt64("whiteRgbThreshold", whiteRgbThreshold)
        validateFloat64InRange("snapshotScale", snapshotScale, 0.0, 1.0)
        validateFloat64InRange("snapshotRegionTop", snapshotRegionTop, 0.0, 1.0)
        validateFloat64InRange("snapshotRegionBottom", snapshotRegionBottom, 0.0, 1.0)
    }
}

private func validateNonNegativeInt64(fieldName: String, value: Int64): Unit {
    if (value < 0) {
        throw Exception("WhiteScreenConfig.${fieldName} must be >= 0, actual=${value}")
    }
}

private func validateFloat64InRange(fieldName: String, value: Float64, min: Float64, max: Float64): Unit {
    if (value < min || value > max) {
        throw Exception("WhiteScreenConfig.${fieldName} must be in [${min}, ${max}], actual=${value}")
    }
}

// ============================================================
// 白屏事件数据模型
// ============================================================

public class WhiteScreenEventInfo {
    public var pageName: String = ""
    public var whiteScreenType: WhiteScreenType = WhiteScreenType.TIMEOUT
    public var whiteScreenScene: WhiteScreenScene = WhiteScreenScene.PAGE_OPEN
    public var appState: WhiteScreenAppState = WhiteScreenAppState.FOREGROUND

    public var ttid: ?Float64 = None
    public var backgroundElapsedMs: ?Float64 = None

    public var foregroundDistinctColorCount: ?Int64 = None
    public var foregroundMainColorWhite: ?Bool = None

    public var backgroundFirstDistinctColorCount: ?Int64 = None
    public var backgroundSecondDistinctColorCount: ?Int64 = None
    public var backgroundFirstMainColorWhite: ?Bool = None
    public var backgroundSecondMainColorWhite: ?Bool = None
    public var backgroundDetectionReason: ?String = None

    public var frameCountInNSeconds: Int64 = 0

    public func ToJsonValue(): JsonObject {
        let jsObj = JsonObject()
        jsObj.put("pageName", JsonString(this.pageName))
        jsObj.put("whiteScreenType", JsonString(this.whiteScreenType.toString()))
        jsObj.put("whiteScreenScene", JsonString(this.whiteScreenScene.toString()))
        jsObj.put("appState", JsonString(this.appState.toString()))
        jsObj.put("isForeground", JsonString("${this.appState.isForeground()}"))

        if (let Some(ttid) <- this.ttid) {
            jsObj.put("ttid", JsonString("${ttid}"))
        }

        if (let Some(backgroundElapsedMs) <- this.backgroundElapsedMs) {
            jsObj.put("backgroundElapsedMs", JsonString("${backgroundElapsedMs}"))
        }

        if (let Some(foregroundDistinctColorCount) <- this.foregroundDistinctColorCount) {
            jsObj.put("foregroundDistinctColorCount", JsonString("${foregroundDistinctColorCount}"))
        }

        if (let Some(foregroundMainColorWhite) <- this.foregroundMainColorWhite) {
            jsObj.put("foregroundMainColorWhite", JsonString("${foregroundMainColorWhite}"))
        }

        if (let Some(backgroundFirstDistinctColorCount) <- this.backgroundFirstDistinctColorCount) {
            jsObj.put("backgroundFirstDistinctColorCount", JsonString("${backgroundFirstDistinctColorCount}"))
        }

        if (let Some(backgroundSecondDistinctColorCount) <- this.backgroundSecondDistinctColorCount) {
            jsObj.put("backgroundSecondDistinctColorCount", JsonString("${backgroundSecondDistinctColorCount}"))
        }

        if (let Some(backgroundFirstMainColorWhite) <- this.backgroundFirstMainColorWhite) {
            jsObj.put("backgroundFirstMainColorWhite", JsonString("${backgroundFirstMainColorWhite}"))
        }

        if (let Some(backgroundSecondMainColorWhite) <- this.backgroundSecondMainColorWhite) {
            jsObj.put("backgroundSecondMainColorWhite", JsonString("${backgroundSecondMainColorWhite}"))
        }

        if (let Some(backgroundDetectionReason) <- this.backgroundDetectionReason) {
            jsObj.put("backgroundDetectionReason", JsonString(backgroundDetectionReason))
        }

        jsObj.put("frameCountInNSeconds", JsonString("${this.frameCountInNSeconds}"))
        jsObj
    }
}

// ============================================================
// 回调适配器
// ============================================================

public class WhiteScreenIntervalInfoCallback <: Callback1Argument<IntervalInfo> {
    let elementInfoCallback: (IntervalInfo) -> Unit

    public init(elementInfoCallback: (IntervalInfo) -> Unit) {
        this.elementInfoCallback = elementInfoCallback
    }

    public func invoke(res: IntervalInfo): Unit {
        this.elementInfoCallback(res)
    }
}

public class WhiteScreenNavSwitchCallback <: Callback1Argument<NavDestinationSwitchInfo> {
    let elementInfoCallback: (NavDestinationSwitchInfo) -> Unit

    public init(elementInfoCallback: (NavDestinationSwitchInfo) -> Unit) {
        this.elementInfoCallback = elementInfoCallback
    }

    public func invoke(res: NavDestinationSwitchInfo): Unit {
        this.elementInfoCallback(res)
    }
}

// ============================================================
// 白屏检测器（单例）
// ============================================================

private var isAbilityLifecycleRegistered: Bool = false
private var whitescreen_init_flag = false

public class WhiteScreenDetector {
    private static var instance = WhiteScreenDetector()
    public static func GetInstance(): WhiteScreenDetector { instance }

    private var nextDetectionSessionId: Int64 = 0
    private var activeDetectionSessionId: Int64 = 0

    private var phase: DetectionPhase = DetectionPhase.IDLE
    private var enterTime: Int64 = 0
    private var firstFrameTime: Int64 = 0
    private var frameCount: Int64 = 0
    private var currentPageName: String = ""

    private var ttidTimerId: Int64 = -1
    private var frameCheckTimerId: Int64 = -1

    private var sync: DisplaySync = create()
    private var syncCallback: ?WhiteScreenIntervalInfoCallback = None
    private var navSwitchCallback: ?WhiteScreenNavSwitchCallback = None

    private var config: WhiteScreenConfig = WhiteScreenConfig()
    private var uiContext: ?UIContext = None
    private var windowStage: ?WindowStage = None
    private var reportCallback: (JsonObject) -> Unit = { _ => () }
    private var isConfigured: Bool = false
    private var appState: WhiteScreenAppState = WhiteScreenAppState.FOREGROUND

    private var nextBackgroundSessionId: Int64 = 0
    private var activeBackgroundSessionId: Int64 = 0
    private var backgroundFirstSnapshotTimerId: Int64 = -1
    private var backgroundSecondSnapshotTimerId: Int64 = -1
    private var backgroundPageName: String = ""
    private var backgroundStartTime: Int64 = 0
    private var backgroundDetectionActive: Bool = false
    private var backgroundFirstDistinctColorCount: ?Int64 = None
    private var backgroundSecondDistinctColorCount: ?Int64 = None
    private var backgroundFirstMainColorWhite: ?Bool = None
    private var backgroundSecondMainColorWhite: ?Bool = None
    private var backgroundDetectionReason: ?String = None

    public func configure(
        windowStage: WindowStage,
        uiContext: UIContext,
        config: WhiteScreenConfig,
        reportCallback: (JsonObject) -> Unit
    ) {
        config.validate()
        this.windowStage = windowStage
        this.uiContext = uiContext
        this.config = config
        this.reportCallback = reportCallback
        isConfigured = true
    }

    public func bindNavSwitchCallback(callback: WhiteScreenNavSwitchCallback): Unit {
        navSwitchCallback = callback
    }

    public func detachNavSwitchObserver(): Unit {
        if (let Some(cb) <- navSwitchCallback) {
            if (let Some(ctx) <- uiContext) {
                ctx.getUIObserver().off(
                    ObserverListenerType.navDestinationSwitch,
                    cb
                )
            }
        }
    }

    public func updateCurrentPageName(pageName: String): Unit {
        currentPageName = pageName
    }

    public func isCurrentPageName(pageName: String): Bool {
        currentPageName == pageName
    }

    public func notifyPageReady(pageName: String): Unit {
        if (!isConfigured) {
            return
        }

        printLog("WhiteScreen: page ready notify for page '${pageName}'")
        startDetection(pageName)
    }

    public func handleNavShownPage(pageName: String): Unit {
        if (!isConfigured) {
            return
        }

        printLog("WhiteScreen: nav observer resolved page '${pageName}'")

        if (isCurrentPageName(pageName)) {
            updateCurrentPageName(pageName)
            printLog("WhiteScreen: skip duplicate nav page '${pageName}'")
            return
        }

        updateCurrentPageName(pageName)
        startDetection(pageName)
    }

    public func destroy(): Unit {
        reset()
        resetBackgroundDetection()

        reportCallback = { _ => () }
        uiContext = None
        windowStage = None
        navSwitchCallback = None
        isConfigured = false
    }

    // --------------------------------------------------------
    // 状态重置
    // --------------------------------------------------------

    public func reset() {
        if (ttidTimerId >= 0) {
            clearTimeout(ttidTimerId)
            ttidTimerId = -1
        }

        if (frameCheckTimerId >= 0) {
            clearTimeout(frameCheckTimerId)
            frameCheckTimerId = -1
        }

        stopAndCleanDisplaySync()

        activeDetectionSessionId = 0
        phase = DetectionPhase.IDLE
        enterTime = 0
        firstFrameTime = 0
        frameCount = 0
    }

    private func resetBackgroundDetection() {
        if (backgroundFirstSnapshotTimerId >= 0) {
            clearTimeout(backgroundFirstSnapshotTimerId)
            backgroundFirstSnapshotTimerId = -1
        }

        if (backgroundSecondSnapshotTimerId >= 0) {
            clearTimeout(backgroundSecondSnapshotTimerId)
            backgroundSecondSnapshotTimerId = -1
        }

        activeBackgroundSessionId = 0
        backgroundDetectionActive = false
        backgroundPageName = ""
        backgroundStartTime = 0
        backgroundFirstDistinctColorCount = None
        backgroundSecondDistinctColorCount = None
        backgroundFirstMainColorWhite = None
        backgroundSecondMainColorWhite = None
        backgroundDetectionReason = None
    }

    private func createDetectionSessionId(): Int64 {
        nextDetectionSessionId += 1
        activeDetectionSessionId = nextDetectionSessionId
        activeDetectionSessionId
    }

    private func createBackgroundSessionId(): Int64 {
        nextBackgroundSessionId += 1
        activeBackgroundSessionId = nextBackgroundSessionId
        activeBackgroundSessionId
    }

    private func isDetectionSessionActive(sessionId: Int64): Bool {
        activeDetectionSessionId == sessionId && sessionId > 0
    }

    private func isBackgroundSessionActive(sessionId: Int64): Bool {
        activeBackgroundSessionId == sessionId && sessionId > 0 && backgroundDetectionActive
    }

    private func finishDetectionSession() {
        activeDetectionSessionId = 0
        phase = DetectionPhase.IDLE
    }

    private func stopAndCleanDisplaySync() {
        sync.stop()

        if (let Some(cb) <- syncCallback) {
            sync.off(OnOffType.DS_FRAME, callback: cb)
            syncCallback = None
        }
    }

    private func isPageOpenDetectionRunning(): Bool {
        if (activeDetectionSessionId <= 0) {
            return false
        }

        match (phase) {
            case DetectionPhase.IDLE => false
            case _ => true
        }
    }

    private func isPageRecentlyEntered(nowNanos: Int64): Bool {
        let elapsedMs = getPageEnterElapsedMs(nowNanos)
        elapsedMs >= 0.0 && elapsedMs <= Float64(config.backgroundRecentPageEnterThresholdMs)
    }

    private func getPageEnterElapsedMs(nowNanos: Int64): Float64 {
        if (enterTime <= 0) {
            return -1.0
        }

        Float64(nowNanos - enterTime) / 1_000_000.0
    }

    private func getBackgroundGateReason(nowNanos: Int64, pageOpenDetectionRunning: Bool): ?String {
        let recentlyEntered = isPageRecentlyEntered(nowNanos)

        if (recentlyEntered && pageOpenDetectionRunning) {
            return Some("RECENT_PAGE_ENTER_AND_PAGE_OPEN_DETECTION_ACTIVE")
        }

        if (recentlyEntered) {
            return Some("RECENT_PAGE_ENTER")
        }

        if (pageOpenDetectionRunning) {
            return Some("PAGE_OPEN_DETECTION_ACTIVE")
        }

        None
    }

    // --------------------------------------------------------
    // 页面打开检测
    // --------------------------------------------------------

    public func startDetection(pageName: String) {
        if (!isConfigured) {
            return
        }

        reset()

        currentPageName = pageName
        let sessionId = createDetectionSessionId()
        enterTime = DateTime.now().toUnixTimeStamp().toNanoseconds()
        phase = DetectionPhase.WAITING_FIRST_FRAME

        printLog(
            "WhiteScreen: start detection for page '${pageName}', sessionId=${sessionId}, appState=${appState.toString()}, isForeground=${appState.isForeground()}"
        )

        ttidTimerId = setTimeout(
            whiteScreenTtidTimer,
            config.ttidTimeoutMs,
            ["${sessionId}"]
        )

        let cb = WhiteScreenIntervalInfoCallback(
            { frameInfo: IntervalInfo =>
                WhiteScreenDetector.GetInstance().onFrameCallback(sessionId, frameInfo)
            }
        )

        syncCallback = cb
        sync.on(OnOffType.DS_FRAME, cb)
        sync.start()
    }

    public func onForeground(): Unit {
        appState = WhiteScreenAppState.FOREGROUND

        if (!isConfigured) {
            return
        }

        printLog("WhiteScreen: app state changed to ${appState.toString()}")
        resetBackgroundDetection()
    }

    public func onBackground(): Unit {
        appState = WhiteScreenAppState.BACKGROUND

        if (!isConfigured) {
            return
        }

        printLog("WhiteScreen: app state changed to ${appState.toString()}")

        let pageName = currentPageName
        let nowNanos = DateTime.now().toUnixTimeStamp().toNanoseconds()
        let pageOpenDetectionRunning = isPageOpenDetectionRunning()
        let recentlyEntered = isPageRecentlyEntered(nowNanos)
        let pageEnterElapsedMs = getPageEnterElapsedMs(nowNanos)
        let gateReason = getBackgroundGateReason(nowNanos, pageOpenDetectionRunning)

        if (gateReason.isNone()) {
            printLog(
                "WhiteScreen: skip background detection, page='${pageName}', recentlyEntered=${recentlyEntered}, pageOpenDetectionRunning=${pageOpenDetectionRunning}, pageEnterElapsedMs=${pageEnterElapsedMs}, recentThresholdMs=${config.backgroundRecentPageEnterThresholdMs}"
            )

            reset()
            resetBackgroundDetection()
            return
        }

        if (let Some(reason) <- gateReason) {
            reset()
            resetBackgroundDetection()

            let sessionId = createBackgroundSessionId()

            backgroundPageName = pageName
            backgroundStartTime = nowNanos
            backgroundDetectionActive = true
            backgroundDetectionReason = Some(reason)

            printLog(
                "WhiteScreen: start background detection for page '${backgroundPageName}', sessionId=${sessionId}, reason=${reason}, recentlyEntered=${recentlyEntered}, pageOpenDetectionRunning=${pageOpenDetectionRunning}, pageEnterElapsedMs=${pageEnterElapsedMs}"
            )

            backgroundFirstSnapshotTimerId = setTimeout(
                whiteScreenBackgroundFirstSnapshotTimer,
                config.backgroundFirstSnapshotDelayMs,
                ["${sessionId}"]
            )

            backgroundSecondSnapshotTimerId = setTimeout(
                whiteScreenBackgroundSecondSnapshotTimer,
                config.backgroundSecondSnapshotDelayMs,
                ["${sessionId}"]
            )
        }
    }

    public func onTtidTimeout(sessionId: Int64) {
        if (!isDetectionSessionActive(sessionId)) {
            printLog("WhiteScreen: ignore stale TTID timeout, sessionId=${sessionId}")
            return
        }

        match (phase) {
            case DetectionPhase.WAITING_FIRST_FRAME => ()
            case _ => return
        }

        printLog("WhiteScreen: TTID timeout for page '${currentPageName}', sessionId=${sessionId}")

        stopAndCleanDisplaySync()
        finishDetectionSession()

        let eventInfo = WhiteScreenEventInfo()
        eventInfo.pageName = currentPageName
        eventInfo.whiteScreenType = WhiteScreenType.TIMEOUT
        eventInfo.whiteScreenScene = WhiteScreenScene.PAGE_OPEN
        eventInfo.appState = appState
        eventInfo.ttid = Some(Float64(config.ttidTimeoutMs))

        reportWhiteScreen(eventInfo)
    }

    // --------------------------------------------------------
    // 帧回调：阶段一 → 阶段二
    // --------------------------------------------------------

    private func onFrameCallback(sessionId: Int64, frameInfo: IntervalInfo) {
        if (!isDetectionSessionActive(sessionId)) {
            return
        }

        match (phase) {
            case DetectionPhase.WAITING_FIRST_FRAME =>
                firstFrameTime = DateTime.now().toUnixTimeStamp().toNanoseconds()
                let ttidNanos = firstFrameTime - enterTime
                let ttidMs = Float64(ttidNanos) / 1_000_000.0

                printLog("WhiteScreen: first frame received, TTID = ${ttidMs}ms")

                if (ttidTimerId >= 0) {
                    clearTimeout(ttidTimerId)
                    ttidTimerId = -1
                }

                phase = DetectionPhase.COUNTING_FRAMES
                frameCount = 1

                frameCheckTimerId = setTimeout(
                    whiteScreenFrameCheckTimer,
                    config.frameCheckDurationMs,
                    ["${sessionId}"]
                )

            case DetectionPhase.COUNTING_FRAMES =>
                frameCount += 1

            case _ =>
                ()
        }
    }

    // --------------------------------------------------------
    // 阶段二：N 秒渲染活跃度检测
    // --------------------------------------------------------

    public func onFrameCheckTimeout(sessionId: Int64) {
        if (!isDetectionSessionActive(sessionId)) {
            printLog("WhiteScreen: ignore stale frame check timeout, sessionId=${sessionId}")
            return
        }

        match (phase) {
            case DetectionPhase.COUNTING_FRAMES => ()
            case _ => return
        }

        stopAndCleanDisplaySync()

        printLog(
            "WhiteScreen: frame check done, frameCount = ${frameCount} (threshold = ${config.minFrameCountThreshold}), appState=${appState.toString()}, isForeground=${appState.isForeground()}"
        )

        if (frameCount >= config.minFrameCountThreshold) {
            printLog(
                "WhiteScreen: frame activity is high, skip foreground snapshot, frameCount=${frameCount}, threshold=${config.minFrameCountThreshold}"
            )
            finishDetectionSession()
            return
        }

        phase = DetectionPhase.SNAPSHOT_ANALYSIS
        performSnapshotAnalysis(sessionId)
    }

    // --------------------------------------------------------
    // 前台截图分析
    // --------------------------------------------------------

    private func performSnapshotAnalysis(sessionId: Int64) {
        if (!isDetectionSessionActive(sessionId)) {
            return
        }

        if (let Some(componentId) <- config.rootComponentId) {
            performComponentSnapshot(sessionId, componentId)
        } else {
            performWindowSnapshot(sessionId)
        }
    }

    private func performComponentSnapshot(sessionId: Int64, componentId: String) {
        try {
            let ctx = uiContext.getOrThrow()
            let options = SnapshotOptions(
                scale: config.snapshotScale,
                waitUntilRenderFinished: true
            )
            let snapshot = ctx.getComponentSnapshot()

            snapshot.get(componentId, { err: ?BusinessException, pixelMap: ?image.PixelMap =>
                if (!WhiteScreenDetector.GetInstance().isDetectionSessionActive(sessionId)) {
                    return
                }

                if (let Some(e) <- err) {
                    AppLog.warn("WhiteScreen: component snapshot failed: ${e.toString()}")
                    WhiteScreenDetector.GetInstance().finishDetectionSession()
                    return
                }

                if (let Some(pm) <- pixelMap) {
                    WhiteScreenDetector.GetInstance().analyzeWithColorPicker(sessionId, pm)
                } else {
                    AppLog.warn("WhiteScreen: component snapshot returned None pixelMap")
                    WhiteScreenDetector.GetInstance().finishDetectionSession()
                }
            }, options: options)
        } catch (e: NoneValueException) {
            AppLog.warn("WhiteScreen: UIContext is None, cannot perform component snapshot")
            finishDetectionSession()
        }
    }

    private func performWindowSnapshot(sessionId: Int64) {
        try {
            let stage = windowStage.getOrThrow()

            stage.getMainWindow({ err: ?BusinessException, win: ?Window =>
                if (!WhiteScreenDetector.GetInstance().isDetectionSessionActive(sessionId)) {
                    return
                }

                if (let Some(e) <- err) {
                    AppLog.warn("WhiteScreen: getMainWindow failed: ${e.toString()}")
                    WhiteScreenDetector.GetInstance().finishDetectionSession()
                    return
                }

                if (let Some(w) <- win) {
                    w.snapshot({ err2: ?BusinessException, pixelMap: ?image.PixelMap =>
                        if (!WhiteScreenDetector.GetInstance().isDetectionSessionActive(sessionId)) {
                            return
                        }

                        if (let Some(e) <- err2) {
                            AppLog.warn("WhiteScreen: window snapshot failed: ${e.toString()}")
                            WhiteScreenDetector.GetInstance().finishDetectionSession()
                            return
                        }

                        if (let Some(pm) <- pixelMap) {
                            WhiteScreenDetector.GetInstance().analyzeWithColorPicker(sessionId, pm)
                        } else {
                            AppLog.warn("WhiteScreen: window snapshot returned None pixelMap")
                            WhiteScreenDetector.GetInstance().finishDetectionSession()
                        }
                    })
                } else {
                    AppLog.warn("WhiteScreen: window is None")
                    WhiteScreenDetector.GetInstance().finishDetectionSession()
                }
            })
        } catch (e: NoneValueException) {
            AppLog.warn("WhiteScreen: windowStage is None, cannot perform window snapshot")
            finishDetectionSession()
        }
    }

    private func analyzeWithColorPicker(sessionId: Int64, pixelMap: image.PixelMap) {
        if (!isDetectionSessionActive(sessionId)) {
            return
        }

        let region = [
            0.0,
            config.snapshotRegionTop,
            1.0,
            1.0 - config.snapshotRegionBottom
        ]

        createColorPicker(pixelMap, region, { err: ?BusinessException, picker: ?ColorPicker =>
            if (!WhiteScreenDetector.GetInstance().isDetectionSessionActive(sessionId)) {
                return
            }

            if (let Some(e) <- err) {
                AppLog.warn("WhiteScreen: createColorPicker failed: ${e.toString()}")
                WhiteScreenDetector.GetInstance().finishDetectionSession()
                return
            }

            if (let Some(cp) <- picker) {
                WhiteScreenDetector.GetInstance().analyzeWithPicker(sessionId, cp)
            } else {
                WhiteScreenDetector.GetInstance().finishDetectionSession()
            }
        })
    }

    private func analyzeWithPicker(sessionId: Int64, picker: ColorPicker) {
        if (!isDetectionSessionActive(sessionId)) {
            return
        }

        var distinctCount: Int64 = 0
        var mainColorWhite: Bool = false

        if (let Some(topColors) <- picker.getTopProportionColors(10)) {
            distinctCount = countDistinctColors(topColors)
            mainColorWhite = isMainColorWhite(topColors)
        }

        printLog(
            "WhiteScreen: foreground distinctColors=${distinctCount}, mainColorWhite=${mainColorWhite}, frameCount=${frameCount}"
        )

        // 前台只检测白屏，不检测其他纯色屏：
        // 颜色复杂度低 + 主色接近白色 + 帧数低
        if (
            distinctCount <= config.maxDistinctColorCount &&
            mainColorWhite
        ) {
            let ttidNanos = firstFrameTime - enterTime
            let ttidMs = Float64(ttidNanos) / 1_000_000.0

            let eventInfo = WhiteScreenEventInfo()
            eventInfo.pageName = currentPageName
            eventInfo.whiteScreenType = WhiteScreenType.CONTENT_MISSING
            eventInfo.whiteScreenScene = WhiteScreenScene.PAGE_OPEN
            eventInfo.appState = appState
            eventInfo.ttid = Some(ttidMs)
            eventInfo.frameCountInNSeconds = frameCount
            eventInfo.foregroundDistinctColorCount = Some(distinctCount)
            eventInfo.foregroundMainColorWhite = Some(mainColorWhite)

            reportWhiteScreen(eventInfo)
        } else {
            printLog(
                "WhiteScreen: foreground snapshot analysis passed, no white screen, appState=${appState.toString()}, isForeground=${appState.isForeground()}"
            )
        }

        finishDetectionSession()
    }

    // --------------------------------------------------------
    // 前台切后台：2 次截图检测
    // --------------------------------------------------------

    public func onBackgroundFirstSnapshotTimeout(sessionId: Int64): Unit {
        if (!isBackgroundSessionActive(sessionId)) {
            printLog("WhiteScreen: ignore stale background first snapshot timeout, sessionId=${sessionId}")
            return
        }

        backgroundFirstSnapshotTimerId = -1
        printLog("WhiteScreen: background first snapshot for page '${backgroundPageName}', sessionId=${sessionId}")
        performBackgroundSnapshotAnalysis(sessionId, 1)
    }

    public func onBackgroundSecondSnapshotTimeout(sessionId: Int64): Unit {
        if (!isBackgroundSessionActive(sessionId)) {
            printLog("WhiteScreen: ignore stale background second snapshot timeout, sessionId=${sessionId}")
            return
        }

        backgroundSecondSnapshotTimerId = -1
        printLog("WhiteScreen: background second snapshot for page '${backgroundPageName}', sessionId=${sessionId}")
        performBackgroundSnapshotAnalysis(sessionId, 2)
    }

    private func performBackgroundSnapshotAnalysis(sessionId: Int64, sampleIndex: Int64) {
        if (!isBackgroundSessionActive(sessionId)) {
            return
        }

        try {
            let stage = windowStage.getOrThrow()

            stage.getMainWindow({ err: ?BusinessException, win: ?Window =>
                if (!WhiteScreenDetector.GetInstance().isBackgroundSessionActive(sessionId)) {
                    return
                }

                if (let Some(e) <- err) {
                    AppLog.warn("WhiteScreen: background getMainWindow failed: ${e.toString()}")
                    resetBackgroundDetection()
                    return
                }

                if (let Some(w) <- win) {
                    w.snapshot({ err2: ?BusinessException, pixelMap: ?image.PixelMap =>
                        if (!WhiteScreenDetector.GetInstance().isBackgroundSessionActive(sessionId)) {
                            return
                        }

                        if (let Some(e) <- err2) {
                            AppLog.warn("WhiteScreen: background window snapshot failed: ${e.toString()}")
                            resetBackgroundDetection()
                            return
                        }

                        if (let Some(pm) <- pixelMap) {
                            WhiteScreenDetector.GetInstance().analyzeBackgroundWithColorPicker(
                                sessionId,
                                sampleIndex,
                                pm
                            )
                        } else {
                            AppLog.warn("WhiteScreen: background window snapshot returned None pixelMap")
                            resetBackgroundDetection()
                        }
                    })
                } else {
                    AppLog.warn("WhiteScreen: background window is None")
                    resetBackgroundDetection()
                }
            })
        } catch (e: NoneValueException) {
            AppLog.warn("WhiteScreen: windowStage is None, cannot perform background snapshot")
            resetBackgroundDetection()
        }
    }

    private func analyzeBackgroundWithColorPicker(
        sessionId: Int64,
        sampleIndex: Int64,
        pixelMap: image.PixelMap
    ) {
        if (!isBackgroundSessionActive(sessionId)) {
            return
        }

        let region = [
            0.0,
            config.snapshotRegionTop,
            1.0,
            1.0 - config.snapshotRegionBottom
        ]

        createColorPicker(pixelMap, region, { err: ?BusinessException, picker: ?ColorPicker =>
            if (!WhiteScreenDetector.GetInstance().isBackgroundSessionActive(sessionId)) {
                return
            }

            if (let Some(e) <- err) {
                AppLog.warn("WhiteScreen: background createColorPicker failed: ${e.toString()}")
                resetBackgroundDetection()
                return
            }

            if (let Some(cp) <- picker) {
                analyzeBackgroundWithPicker(sessionId, sampleIndex, cp)
            } else {
                resetBackgroundDetection()
            }
        })
    }

    private func analyzeBackgroundWithPicker(sessionId: Int64, sampleIndex: Int64, picker: ColorPicker) {
        if (!isBackgroundSessionActive(sessionId)) {
            return
        }

        var distinctCount: Int64 = 0
        var mainColorWhite: Bool = false

        if (let Some(topColors) <- picker.getTopProportionColors(10)) {
            distinctCount = countDistinctColors(topColors)
            mainColorWhite = isMainColorWhite(topColors)
        }

        printLog(
            "WhiteScreen: background sampleIndex=${sampleIndex}, distinctColors=${distinctCount}, mainColorWhite=${mainColorWhite}"
        )

        if (sampleIndex == 1) {
            backgroundFirstDistinctColorCount = Some(distinctCount)
            backgroundFirstMainColorWhite = Some(mainColorWhite)
            return
        }

        backgroundSecondDistinctColorCount = Some(distinctCount)
        backgroundSecondMainColorWhite = Some(mainColorWhite)

        if (isBackgroundDoubleSnapshotWhiteScreen()) {
            let elapsedMs =
                Float64(DateTime.now().toUnixTimeStamp().toNanoseconds() - backgroundStartTime) / 1_000_000.0

            let eventInfo = WhiteScreenEventInfo()
            eventInfo.pageName = backgroundPageName
            eventInfo.whiteScreenType = WhiteScreenType.CONTENT_MISSING
            eventInfo.whiteScreenScene = WhiteScreenScene.PAGE_BACKGROUND
            eventInfo.appState = appState
            eventInfo.backgroundElapsedMs = Some(elapsedMs)
            eventInfo.backgroundFirstDistinctColorCount = backgroundFirstDistinctColorCount
            eventInfo.backgroundSecondDistinctColorCount = backgroundSecondDistinctColorCount
            eventInfo.backgroundFirstMainColorWhite = backgroundFirstMainColorWhite
            eventInfo.backgroundSecondMainColorWhite = backgroundSecondMainColorWhite
            eventInfo.backgroundDetectionReason = backgroundDetectionReason
            eventInfo.frameCountInNSeconds = 0

            reportWhiteScreen(eventInfo)
        } else {
            printLog(
                "WhiteScreen: background snapshot analysis passed, no white screen, appState=${appState.toString()}, isForeground=${appState.isForeground()}"
            )
        }

        resetBackgroundDetection()
    }

    private func isBackgroundDoubleSnapshotWhiteScreen(): Bool {
        if (let Some(firstCount) <- backgroundFirstDistinctColorCount) {
            if (let Some(secondCount) <- backgroundSecondDistinctColorCount) {
                if (let Some(firstWhite) <- backgroundFirstMainColorWhite) {
                    if (let Some(secondWhite) <- backgroundSecondMainColorWhite) {
                        return firstCount <= config.maxDistinctColorCount &&
                            secondCount <= config.maxDistinctColorCount &&
                            firstWhite &&
                            secondWhite
                    }
                }
            }
        }

        false
    }

    // --------------------------------------------------------
    // 颜色分析工具
    // --------------------------------------------------------

    // RGB 各量化到 8 级（/32），统计不重复颜色数
    private func countDistinctColors(colors: Array<Option<Color>>): Int64 {
        let keys = HashSet<Int64>()

        for (colorOpt in colors) {
            if (let Some(c) <- colorOpt) {
                let key =
                    Int64(c.red / 32) * 64 +
                    Int64(c.green / 32) * 8 +
                    Int64(c.blue / 32)

                keys.add(key)
            }
        }

        Int64(keys.size)
    }

    // 判断第一主色是否接近白色。
    // getTopProportionColors(10) 返回主色列表，这里默认第一个有效颜色是占比最高的主色。
    private func isMainColorWhite(colors: Array<Option<Color>>): Bool {
        for (colorOpt in colors) {
            if (let Some(c) <- colorOpt) {
                return isWhiteColor(c)
            }
        }

        false
    }

    private func isWhiteColor(color: Color): Bool {
        return Int64(color.red) >= config.whiteRgbThreshold &&
            Int64(color.green) >= config.whiteRgbThreshold &&
            Int64(color.blue) >= config.whiteRgbThreshold
    }

    // --------------------------------------------------------
    // 上报
    // --------------------------------------------------------

    private func reportWhiteScreen(eventInfo: WhiteScreenEventInfo) {
        let jsonObj = eventInfo.ToJsonValue()

        printLog(
            "WhiteScreen: detected! scene=${eventInfo.whiteScreenScene.toString()}, type=${eventInfo.whiteScreenType.toString()}, page=${eventInfo.pageName}, appState=${eventInfo.appState.toString()}, isForeground=${eventInfo.appState.isForeground()}"
        )

        reportCallback(jsonObj)

        if (config.autoWriteFaultLog) {
            writeFaultLog(eventInfo)
        }
    }

    private func writeFaultLog(eventInfo: WhiteScreenEventInfo) {
        try {
            let params = HashMap<String, EventParamType>()

            params.add("pageName", EventParamType.STRING(eventInfo.pageName))
            params.add("whiteScreenScene", EventParamType.STRING(eventInfo.whiteScreenScene.toString()))
            params.add("whiteScreenType", EventParamType.STRING(eventInfo.whiteScreenType.toString()))
            params.add("appState", EventParamType.STRING(eventInfo.appState.toString()))
            params.add("isForeground", EventParamType.STRING("${eventInfo.appState.isForeground()}"))

            if (let Some(ttid) <- eventInfo.ttid) {
                params.add("ttid", EventParamType.FLOAT(ttid))
            }

            if (let Some(foregroundDistinctColorCount) <- eventInfo.foregroundDistinctColorCount) {
                params.add("foregroundDistinctColorCount", EventParamType.INT(Int32(foregroundDistinctColorCount)))
            }

            if (let Some(foregroundMainColorWhite) <- eventInfo.foregroundMainColorWhite) {
                params.add("foregroundMainColorWhite", EventParamType.STRING("${foregroundMainColorWhite}"))
            }

            if (let Some(backgroundElapsedMs) <- eventInfo.backgroundElapsedMs) {
                params.add("backgroundElapsedMs", EventParamType.FLOAT(backgroundElapsedMs))
            }

            if (let Some(firstCount) <- eventInfo.backgroundFirstDistinctColorCount) {
                params.add("backgroundFirstDistinctColorCount", EventParamType.INT(Int32(firstCount)))
            }

            if (let Some(secondCount) <- eventInfo.backgroundSecondDistinctColorCount) {
                params.add("backgroundSecondDistinctColorCount", EventParamType.INT(Int32(secondCount)))
            }

            if (let Some(firstWhite) <- eventInfo.backgroundFirstMainColorWhite) {
                params.add("backgroundFirstMainColorWhite", EventParamType.STRING("${firstWhite}"))
            }

            if (let Some(secondWhite) <- eventInfo.backgroundSecondMainColorWhite) {
                params.add("backgroundSecondMainColorWhite", EventParamType.STRING("${secondWhite}"))
            }

            if (let Some(backgroundDetectionReason) <- eventInfo.backgroundDetectionReason) {
                params.add("backgroundDetectionReason", EventParamType.STRING(backgroundDetectionReason))
            }

            params.add("frameCount", EventParamType.INT(Int32(eventInfo.frameCountInNSeconds)))

            let appEventInfo = AppEventInfo(
                "WHITE_SCREEN",
                "WHITE_SCREEN_DETECTED",
                EventType.FAULT,
                params
            )

            write(appEventInfo, { err: ?BusinessException, _: ?Unit =>
                if (let Some(e) <- err) {
                    AppLog.warn("WhiteScreen: hiAppEvent.write failed: ${e.toString()}")
                }
            })
        } catch (e: Exception) {
            AppLog.warn("WhiteScreen: writeFaultLog error: ${e.toString()}")
        }
    }

    // --------------------------------------------------------
    // 条件编译日志
    // --------------------------------------------------------

    @When[debug]
    private func printLog(msg: String) {
        Hilog.warn(0, "hm_metricx_cj", msg)
    }

    @When[!debug]
    private func printLog(msg: String) {}
}

// ============================================================
// setTimeout / Ability 生命周期回调
// ============================================================

private func onWhiteScreenAbilityForegroundCallBack(ability: UIAbility) {
    WhiteScreenDetector.GetInstance().onForeground()
}

private func onWhiteScreenAbilityBackgroundCallBack(ability: UIAbility) {
    WhiteScreenDetector.GetInstance().onBackground()
}

private func whiteScreenTtidTimer(args: Array<String>): Unit {
    WhiteScreenDetector.GetInstance().onTtidTimeout(parseSessionId(args))
}

private func whiteScreenFrameCheckTimer(args: Array<String>): Unit {
    WhiteScreenDetector.GetInstance().onFrameCheckTimeout(parseSessionId(args))
}

private func whiteScreenBackgroundFirstSnapshotTimer(args: Array<String>): Unit {
    WhiteScreenDetector.GetInstance().onBackgroundFirstSnapshotTimeout(parseSessionId(args))
}

private func whiteScreenBackgroundSecondSnapshotTimer(args: Array<String>): Unit {
    WhiteScreenDetector.GetInstance().onBackgroundSecondSnapshotTimeout(parseSessionId(args))
}

private func parseSessionId(args: Array<String>): Int64 {
    if (args.size <= 0) {
        return 0
    }

    try {
        Int64.parse(args[0])
    } catch (_: Exception) {
        0
    }
}

// ============================================================
// 路由切换回调处理
// ============================================================

func onNavDestinationSwitch(info: NavDestinationSwitchInfo) {
    match (info.to) {
        case to: NavDestinationInfo =>
            match (to.state) {
                case NavDestinationState.ON_SHOWN =>
                    let detector = WhiteScreenDetector.GetInstance()
                    let pageName = getTargetPageName(info)
                    detector.handleNavShownPage(pageName)

                case _ =>
                    ()
            }

        case _ =>
            ()
    }
}

public func notifyWhiteScreenPageReady(pageName: String): Unit {
    WhiteScreenDetector.GetInstance().notifyPageReady(pageName)
}

// ============================================================
// 页面名称获取
// ============================================================

private func getTargetPageName(info: NavDestinationSwitchInfo, defaultName!: String = ""): String {
    var name = defaultName

    match (info.to) {
        case to: NavDestinationInfo =>
            try {
                name = (to.name as String).getOrThrow()
            } catch (e: Exception) {
                AppLog.warn(e.toString())
            }

        case to: NavBar =>
            name = "navRoot"

        case _ =>
            throw Exception("")
    }

    name
}

// ============================================================
// 初始化入口
// ============================================================

public func initWhiteScreenHandler(
    context: UIAbilityContext,
    windowStage: WindowStage,
    uiContext: UIContext,
    config: WhiteScreenConfig,
    reportWhiteScreenInfo: (data: JsonObject) -> Unit
) {
    if (whitescreen_init_flag) {
    	return
    }
    whitescreen_init_flag = true
    
    let detector = WhiteScreenDetector.GetInstance()

    detector.detachNavSwitchObserver()
    detector.destroy()
    detector.configure(windowStage, uiContext, config, reportWhiteScreenInfo)

    if (!isAbilityLifecycleRegistered) {
        let abilityLifecycleCallback: AbilityLifecycleCallback = AbilityLifecycleCallback(
            onAbilityCreate: { ability: UIAbility => () },
            onWindowStageCreate: { ability: UIAbility, windowStage: WindowStage => () },
            onWindowStageActive: { ability: UIAbility, windowStage: WindowStage => () },
            onWindowStageInactive: { ability: UIAbility, windowStage: WindowStage => () },
            onWindowStageDestroy: { ability: UIAbility, windowStage: WindowStage => () },
            onAbilityDestroy: { ability: UIAbility => () },
            onAbilityForeground: onWhiteScreenAbilityForegroundCallBack,
            onAbilityBackground: onWhiteScreenAbilityBackgroundCallBack,
            onAbilityContinue: { ability: UIAbility => () },
            onWindowStageRestore: { ability: UIAbility, windowStage: WindowStage => () }
        )

        context.getApplicationContext().on(
            ApplicationContextType.ABILITY_LIFECYCLE,
            abilityLifecycleCallback
        )

        isAbilityLifecycleRegistered = true
    }

    let callback = WhiteScreenNavSwitchCallback(onNavDestinationSwitch)
    detector.bindNavSwitchCallback(callback)

    uiContext.getUIObserver().on(
        ObserverListenerType.navDestinationSwitch,
        callback
    )
}

public func destroyWhiteScreenHandler(): Unit {
    whitescreen_init_flag = false
    let detector = WhiteScreenDetector.GetInstance()

    detector.detachNavSwitchObserver()
    detector.destroy()
}
