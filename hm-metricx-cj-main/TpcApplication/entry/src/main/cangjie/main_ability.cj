/*
 * Copyright (c) Huawei Technologies Co., Ltd. 2025-2025. All rights reserved.
 */
package ohos_app_cangjie_entry

import ohos.base.AppLog
import tpc.AbilityKit
import tpc.AbilityKit.UIAbility
import tpc.AbilityKit.Want
import tpc.AbilityKit.AbilityConstant
import tpc.UIKit.window
import ohos.hybrid_base.CJPageEntry
import ohos_app_cangjie_hm_metricx_cj.crash.*
import ohos_app_cangjie_hm_metricx_cj.freeze.*
import ohos_app_cangjie_hm_metricx_cj.fps.*
import ohos_app_cangjie_hm_metricx_cj.storage.*
import ohos_app_cangjie_hm_metricx_cj.battery.*
import ohos_app_cangjie_hm_metricx_cj.cpu.*
import ohos_app_cangjie_hm_metricx_cj.memory.*
import ohos_app_cangjie_hm_metricx_cj.laggy.*
import ohos_app_cangjie_hm_metricx_cj.traffic.*
import ohos_app_cangjie_hm_metricx_cj.memLeak.*
import ohos_app_cangjie_hm_metricx_cj.thermal.*
import ohos_app_cangjie_hm_metricx_cj.exitInfo.*
import stdx.encoding.json.*
import std.fs.*
import ohos.hilog.*
import ohos.base.BusinessException
import tpc.UIKit.UIContext.fromUIContextBase
import tpc.UIKit.UIContext.*
import tpc.UIKit.ObserverListenerType
import tpc.UIKit.NavDestinationSwitchInfo
import ohos.base.Callback0Argument
import ohos.base.Callback1Argument
import ohos.resource_manager.AppResource
import tpc.UIKit.component_interop.ClickEventEnhanced
import tpc.UIKit.arkui_node.FrameNode
import tpc.UIKit.NavDestinationInfo
import tpc.UIKit.NavBar

let ENTRYABILITY_REGISTER_RESULT = UIAbility.registerCreator("EntryAbility", {=> EntryAbility()})

class EntryAbility <: UIAbility {

    // ==================== FRT 状态（防串数据） ====================
    private var currentPageId: Int64 = 0
    private var hasDraw: Bool = false

    public override func onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): Unit {
        AppLog.info("Ability OnCreated.${want.abilityName}")
        match (launchParam.launchReason) {
            case AbilityConstant
                    .LaunchReason
                    .START_ABILITY => AppLog.info("START_ABILITY")
            case _ => ()
        }
        initExitInfoHandler(
            this.context,
            launchParam,
            { data: ExitInfo =>
                AppLog.error("[MetricX][ExitInfo] ${data.toString()}")
            },
            { data: AppStateInfo =>
                AppLog.error("[MetricX][AppState] ${data.toString()}")
            },
            Path(this.context.cacheDir)
        )
        initCrashHandler(this
            .context
            .getApplicationContext(),
            Path(this
                .context
                .cacheDir),
            CrashCallbacks(collectCrashInfo: {=> JsonValue.fromStr("{}")}, reportCrashInfo: {data => AppLog.error("xxx: " + data.toString())}),
            config: CrashConfig(memMonitor: CMemMonitorConfig({soName:String =>false}), lastNHilogNumber: 1000, systemLogNumber: 1000))
        initFreezeHandler(
            this
                .context
                .getApplicationContext(),
            {=>
                JsonValue.fromStr("{\"xxx\":\"yyy\"}")},
            {
                data => AppLog.error("freeze "+data.extraInfo.toString())
            },
            Path(this
                .context
                .cacheDir)
        )
        initThermalHandler(
            context,
            { info: ThermalEventInfo =>
                AppLog.error("[MetricX][Thermal] ${info.toString()}")
            },
            abnormalThreshold: 2
        )
        match (launchParam.launchReason) {
            case AbilityConstant
                .LaunchReason
                .START_ABILITY => AppLog.info("START_ABILITY")
            case _ => ()
        }

        // 高 CPU 占用监控初始化
        initHighCpuMonitorHandler(
            this.context,
            HighCpuMonitorConfig(
                cpuThreshold: 0.05,
                foregroundIntervalMs: 1000,
                backgroundIntervalMs: 2000,
                monitorDurationMs: 33000,
                threadCooldownMs: 60000,
                globalCooldownMs: 3000,
                highSampleRatioThreshold: 0.85,
                topNThreads: 10
            ),
            { reportInfo =>
                AppLog.warn("===== 高 CPU 占用上报 =====")
                AppLog.warn("时间：${reportInfo.timestamp}")
                AppLog.warn("进程：${reportInfo.processName} (PID: ${reportInfo.pid})")
                AppLog.warn("页面：${reportInfo.pageName}")
                AppLog.warn("进程平均 CPU: ${reportInfo.avgProcessCpu}")
                AppLog.warn("进程最大 CPU: ${reportInfo.maxProcessCpu}")
                AppLog.warn("监控时长：${reportInfo.monitorDuration}毫秒")
                AppLog.warn("高占用线程数：${reportInfo.highCpuThreads.size}")

                for (threadInfo in reportInfo.highCpuThreads) {
                    AppLog.warn("--- 线程信息 ---")
                    AppLog.warn("  TID: ${threadInfo.tid}")
                    AppLog.warn("  线程名：${threadInfo.threadName}")
                    AppLog.warn("  平均 CPU: ${threadInfo.avgCpuUsage}")
                    AppLog.warn("  最大 CPU: ${threadInfo.maxCpuUsage}")
                    AppLog.warn("  采样次数：${threadInfo.sampleCount}")
                    AppLog.warn("  高采样比例：${threadInfo.getHighSampleRatio()}")
                }
            }
        )
        AppLog.warn("高 CPU 监控已启动（快速验证模式：33 秒上报，5% 阈值，85% 高采样比例）")

        // 后台活动超长率监控初始化
        initBackgroundCpuMonitorHandler(
            this.context,
            BackgroundCpuMonitorConfig(
                cpuThreshold: 0.05,           // CPU 利用率阈值 5%
                warnDurationMs: 10000,       // 10 秒触发 WARN 级别
                errorDurationMs: 30000,      // 30 秒触发 ERROR 级别
                fatalDurationMs: 60000,      // 60 秒触发 FATAL 级别
                sampleIntervalMs: 1000,      // 1 秒采样一次
                windowSizeMs: 5000           // 5 秒滑动窗口
            ),
            { reportInfo =>
                AppLog.warn("===== 后台 CPU 活动超长率上报 =====")
                AppLog.warn("时间：${reportInfo.timestamp}")
                AppLog.warn("进程：${reportInfo.processName} (PID: ${reportInfo.pid})")
                AppLog.warn("异常级别：${reportInfo.level.toString()}")
                AppLog.warn("后台时长：${reportInfo.backgroundDuration}毫秒")
                AppLog.warn("平均 CPU: ${reportInfo.avgCpuUsage}")
                AppLog.warn("最大 CPU: ${reportInfo.maxCpuUsage}")
                AppLog.warn("滑动窗口采样数：${reportInfo.windowSamples.size}")

                // 打印滑动窗口数据
                for (sample in reportInfo.windowSamples) {
                    AppLog.warn("--- 窗口采样 ---")
                    AppLog.warn("  时间戳：${sample.timestamp}")
                    AppLog.warn("  CPU 使用率：${sample.cpuUsage}")
                    AppLog.warn("  后台时长：${sample.duration}毫秒")
                }
            }
        )
        AppLog.warn("后台 CPU 监控已启动，快速验证模式（WARN:10 秒，ERROR:30 秒，FATAL:60 秒，5% 阈值）")

        initTrafficHandler(this.context, {data =>}, {data =>})
        initStorageHandler({data: StorageInfo =>}, sizeLimit: 100000000, dirSizeLimit: 1000, reportTopNum: 5)
        initBatteryHandler(this.context, {data =>}, {data =>})
        initCpuHandler(this.context, {data =>}, {data =>})

        // 测试自定义报告间隔和保存间隔（参数单位：毫秒）
        initMemoryHandler(
            this.context,
            {data => AppLog.info("initMemoryHandler : ${data.toString()}")},
            {data => AppLog.info("initMemoryHandler2 : ${data.toString()}")},
            sampleInterval : 5 * 1000,
            reportInterval : 6 * 1000,
            saveInterval : 30 * 1000,
            totalRatio : 0.6,
            cjRatio : 0.6,
            arkTsRatio : 0.6
        )
        initMemLeakHandler(this.context, Path(this
            .context
            .cacheDir), {pageInfo, typeInfos => true}, {typeInfos => false},
            {dumpFilePath => AppLog.info("dumpFilePath : ${dumpFilePath.toString()}")})
        
        initSwipeKillHandler(
            this.context,
            launchParam,
            { info: SwipeKillInfo =>
                AppLog.warn("[MetricX] SwipeKill: User killed app and restarted quickly! timeSinceBg: ${info.toString()}")
            },
            thresholdMs: 5000
        )
    }

    public override func onDestroy(): Unit {
        destroyHighCpuMonitorHandler()
        destroyBackgroundCpuMonitorHandler()
        destroyBatteryHandler()
        destroyCpuHandler()
        destroyMemoryHandler()
        destroyTrafficHandler()
        destroyExitInfoHandler()
        AppLog.info("myAbility onDestroy.")
    }

    public override func onWindowStageCreate(windowStage: window.WindowStage): Unit {
        windowStage.loadContent("pages/index", {err, data => ()})
        windowStage.getMainWindow(
            {
                err: ?BusinessException, data: ?window.Window => match (data) {
                    case Some(x) =>
                        let uiContext = fromUIContextBase(x.getUIContext())
                        let observer = uiContext.getUIObserver()

                        // ==================== FRT 初始化 ====================
                        initFirstRenderTimeMonitor(
                            FirstRenderTimeConfig(true, 1000),
                            { info =>
                                AppLog.info("[FRT] ${info.toString()}")
                            }
                        )
                        let dispatcher = FRTDispatcher.GetInstance()
                        // ==================== draw监听（无需重复注册标记） ====================
                        let inspector = uiContext.getUIInspector()
                        let componentObserver = inspector.createComponentObserver("root")
                        componentObserver.on("draw", onDrawCallback())
                        // ==================== 点击监听 ====================
                        observer.on(ObserverListenerType.willClick, onClickCallback())
                        // ==================== 路由监听 ====================
                        observer.on(ObserverListenerType.navDestinationSwitch, onNavCallback())
                        // ==================== 原有性能监控（不动） ====================
                        initLaggyHandler(
                            this.context.getApplicationContext(),
                            uiContext,
                            10,
                            10,
                            {data =>}
                        )
                        initPageEventHandler(
                            this.context,
                            { data => AppLog.error("page fps: " + data.toString()) }
                        )
                        initPageEventHandler(
                            windowStage,
                            { data => AppLog.error("window fps: " + data.toString()) }
                        )
                        initScrollEventHandler(
                            this.context,
                            { data => AppLog.error("scroll fps: " + data.toString()) }
                        )
                        let whiteScreenConfig = WhiteScreenConfig()
                        initWhiteScreenHandler(
                            this.context,
                            windowStage,
                            fromUIContextBase(x.getUIContext()),
                            whiteScreenConfig,
                            { data: JsonObject =>
                                AppLog.error("[MetricX][WhiteScreen][TestBench] " + data.toString())
                            }
                        )
                    case None =>
                        AppLog.info("initLaggyHandle error")
                }
            }
        )
    }

    public override func onWindowStageDestroy(): Unit {
        AppLog.info("myAbility onWindowStageDestroy.")
    }

    public override func onForeground(): Unit {
        AppLog.info("myAbility onForeground.")
    }

    public override func onBackground(): Unit {
        AppLog.info("myAbility onBackground.")
    }

    public override func onConfigurationUpdate(config: AbilityKit.Configuration): Unit {
        AppLog.info("myAbility onConfigurationUpdate: ${config.mcc}")
        CJPageEntry
            .getInstance()
            .forceRerenderAllEntry()
    }
}

public class onDrawCallback <: Callback0Argument {
    public override func invoke(): Unit {
        let dispatcher = FRTDispatcher.GetInstance()
        dispatcher.onDraw()
    }
}

public class onClickCallback <: ClickEventListenerCallback {
    public override func invoke(event: ClickEventEnhanced, node: Option<FrameNode>): Unit {
        AppLog.info("[FRT] click")
        let dispatcher = FRTDispatcher.GetInstance()
        dispatcher.onClick()
    }
}

public class onNavCallback <: Callback1Argument<NavDestinationSwitchInfo> {
    public override func invoke(info: NavDestinationSwitchInfo): Unit {
        let dispatcher = FRTDispatcher.GetInstance()
        let toName: String = match (info.to) {
            case to: NavDestinationInfo => to.navDestinationId
            case to: NavBar => to.str
            case _ => ""
        }
        AppLog.info("[FRT] nav -> ${toName}")
        dispatcher.reset()
        dispatcher.onNav(toName)
    }
}