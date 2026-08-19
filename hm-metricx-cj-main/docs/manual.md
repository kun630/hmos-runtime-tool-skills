# hm-metricx-cj

## 功能简介

`hm-metricx-cj` 是一款适用于鸿蒙应用的线上性能监控框架。 `hm-metricx-cj` 系统性地采集和分析监控指标数据，帮助开发团队及时发现性能瓶颈和异常，持续优化应用质量，提升用户体验。

`hm-metricx-cj` 目前支持的监控范围包括：Crash、Freeze、异常退出原因、FPS、滑动掉帧率、交互响应延迟、内存、CPU、热量，电量、流量、存储。

## 使用说明

### 集成方式

i.
获取 `hm-metricx-cj` 源码。

ii.
在 `DevEco Studio` 中点击 `Build -> Make module 'hm-metricx-cj'` 编译生成har包 `hm_metricx_cj.har` 。har包产物路径在 `hm_metricx_cj/build/default/outputs/default` 目录下。

iii.
将 `hm_metricx_cj.har` 放到工程模块的har目录下。在工程模块的 `oh-package.json5` 中配置依赖 `"hm_metricx_cj": "file:./har/hm_mtricx_cj.har"` 。
并且在工程模块的 `src/main/cangjie/cjpm.toml` 中配置依赖：
```text
[dependencies]
  [dependencies.ohos_app_cangjie_hm_metricx_cj]
    path = "../../../oh_modules/hm_metricx_cj/src/main/cangjie"
```

### 按需打包

如需使用按需打包功能，请修改以下目录中的 `hvigorfile.ts` 文件第 9-11 行配置：

```text
hm-metricx-cj/
└── ApmApplication/
    └── hm_metricx_cj/
        └── hvigorfile.ts
```

```ts
const INCLUDE_FEATURES: string[] = [
  'thermal', 'traffic', 'battery',
];
```

`INCLUDE_FEATURES` 中填写需要保留的功能项即可，最终打包结果将按该配置生效。

### 监控Crash

`hm_metricx_cj` 提供
```text
public func initCrashHandler(
  applicationContext: common.ApplicationContext,   -- 上下文
  persistentDir: Path, --自定义存入地址
  callbacks：CrashCallbacks,  -- 回调类
  config!: CrashConfig = CrashConfig()   -- 配置类
): Unit


public class CMemMonitorConfig {
    let shouldBeClusteredToThisSo: (soName: String) -> Bool
    public init(shouldBeClusteredToThisSo: (soName: String) -> Bool){
        this.shouldBeClusteredToThisSo = shouldBeClusteredToThisSo
    }
}
```
接口对ArkTS/仓颉/Native层引发的崩溃进行监控。

`initCrashHandler` 需要的入参说明如下：

- `applicationContext: ApplicationContext` 指定应用上下文。
- `persistentDir: Path` 指定中间日志文件和内存快照的持久化目录。
- `callbacks`：CrashCallbacks 回调类入参，里面包括：
 1. `collectCrashInfo: () -> JsonValue`  
     用于在发生 ArkTS / 仓颉层引发的 crash 时，收集若干自定义的业务 / 系统信息，例如页面浏览路径等，并以 JSON 形式返回。

  2. `reportCrashInfo: (crashInfo: CrashInfo) -> Unit`  
     用于在发生 ArkTS / 仓颉层引发的 crash 时，将收集完毕的崩溃信息进行上报，入参为 `CrashInfo` 类型对象。

- `crashconfig！`: CrashConfig = CrashConfig()：配置类入参，里面包括：
 1. `lastNHilogNumber: Int64` 
指定lastNHilog的条数。
2. `systemLogNumber: Int64` 
指定系统级日志systemLog的条数。
 3. `memMonitor: Option<CMemMonitorConfig>` 
指定是否开启C内存详情监控，Option.None表示不开启，传入`CMemMonitorConfig`对象表示开启，`CMemMonitorConfig`类表示C内存详情监控的配置项。

`CMemMonitorConfig` 参数说明：
- `shouldBeClusteredToThisSo` 用于在按照so聚合类别中，指定内存分配数据是否被聚合到该so。

`CrashInfo` 包含以下信息：

- `language` 崩溃发生所处的语言层
- `meminfo` 崩溃发生时的应用内存信息
- `timestamp` 崩溃发生的时间戳
- `pid` 崩溃进程ID
- `pname` 崩溃进程名
- `stacktrace` 崩溃调用栈
- `hilog` Hilog日志
- `tid` 崩溃线程ID
- `tname` 崩溃线程名
- `fds` FD及其对应路径
- `limits` 进程资源限制
- `threads` OS线程ID与线程名
- `extraInfo` `collectCrashInfo/reportNativeCrashInfo` 收集的自定义的业务/系统信息
- `crashLogPath` 系统生成的faultlog文件路径
- `dumpOnOOMPath` 导出的仓颉内存快照地址
- `appVersion` 应用版本
- `rawFile` 系统生成的faultlog文件的原始内容
- `systemLog` 系统级日志
- `lastNHilog` 最新的N条hilog日志
- `dumpTime` 导出仓颉内存快照的时间
- `historyRawFiles` 所有历史系统生成的crash日志文件的内容
- `nativeMemDetail` C层内存详情
- `memPersistTime` C层内存详情持久化时间

使用示例：

i.
在主模块的 `main_ability.cj` 的 `onCreate` 回调中调用 `initCrashHandler` ：
```text
class EntryAbility <: UIAbility {
    public override func onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): Unit {
        AppLog.info("Ability OnCreated.${want.abilityName}")
        match (launchParam.launchReason) {
            case AbilityConstant.LaunchReason.START_ABILITY => AppLog.info("START_ABILITY")
            case _ => ()
        }
        initCrashHandler(this
            .context
            .getApplicationContext(),
            Path(this
                .context
                .cacheDir),
            CrashCallbacks(collectCrashInfo: {=> JsonValue.fromStr("{}")}, reportCrashInfo: {data => AppLog.error("xxx: " + data.toString())}),
            config: CrashConfig(memMonitor: CMemMonitorConfig({soName:String =>false}), lastNHilogNumber: 1000, systemLogNumber: 1000))
```

> ** 注意: **
> 
> 对ArkTS/仓颉层引发的崩溃的监控依赖系统提供的ErrorManager机制。
> 
> 当存在其他ErrorManager回调，并且在崩溃监控对应的回调之前执行时，可能会干扰崩溃监控的正常行为，导致收集的数据错漏等情况。

> ** 注意: **
> 
> 如果应用编译开启了 `O2` 级别优化，在部分场景，崩溃调用栈会出现漏栈、行号不准的问题。示例如下：
>
> ```cangjie
> func pri(n: Int64): Unit {
>     if (n < 0) {
>         return;
>     }
> 
>     if (n == 90) {
>         throw Exception("e");
>     }
> 
>     pri(n - 1);
> }
> 
> main(): Unit {
>     pri(1000);
> }
> ```
> 
> 由于内联优化和基础块合并优化的影响，抛出异常点的行号信息为0，并且调用栈长度会少于程序实际递归次数。
> ** 注意: **
> ArkTS 内存监控通过 `hidebug.setAppResourceLimit` 设置应用内存资源阈值，用于在应用发生内存泄漏并达到阈值条件时触发系统资源泄漏日志。
>该能力存在以下使用约束：
>1. 需在设备“开发者选项”中开启“系统资源泄漏日志”开关，且开关状态变更后需重启设备后生效。
>2. 系统对同一应用的资源泄漏事件存在频控限制，同一应用在 24 小时内最多上报一次。
>3. 若需要在短时间内重复验证资源泄漏事件上报，需要重启设备后重新触发测试。

### 监控Freeze

`hm_metricx_cj` 提供

```text
public func initFreezeHandler(
    applicationContext: ApplicationContext,
    collectFreezeInfo: () -> JsonValue,
    reportFreezeInfo: (freezeInfo: FreezeInfo) -> Unit,
    persistentDir: Path
): Unit
```

接口对freeze事件进行监控。

`initFreezeHandler` 需要的入参说明如下：

- `applicationContext: ApplicationContext` 指定应用上下文。
- `collectFreezeInfo: () -> JsonValue` 用于在APP发生freeze事件时，收集若干自定义的业务/系统信息(比如页面操作栈等)，以 `JsonValue` 形式返回。
- `reportFreezeInfo: (freezeInfo: FreezeInfo) -> Unit` 用于在APP发生freeze事件时，将收集完成的freeze信息进行上报，入参为 `FreezeInfo` 类型对象。
- `persistentDir: Path` 指定中间日志文件的持久化目录。

`FreezeInfo` 包含以下信息：

- `timestamp` freeze发生的时间戳
- `pid` freeze进程名
- `exception` freeze发生原因
- `hilog` Hilog日志
- `tid` freeze线程ID
- `tname` freeze线程名
- `exrtaInfo` 收集的自定义的业务/系统信息
- `freezeLogPath` 系统生成的faultlog文件路径
- `cpuThread` 线程CPU使用率
- `cpu` 进程CPU使用率
- `stacktrace` freeze调用栈
- `rawFile` 系统生成的faultlog文件的原始内容
- `historyRawFiles` 所有历史系统生成的freeze日志文件的内容

使用示例：

i.

在主模块的 `main_ability.cj` 的 `onCreate` 回调中调用 `initFreezeHandler` ：

```text
class EntryAbility <: UIAbility {
    public override func onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): Unit {
        AppLog.info("Ability OnCreated.${want.abilityName}")
        match (launchParam.launchReason) {
            case AbilityConstant.LaunchReason.START_ABILITY => AppLog.info("START_ABILITY")
            case _ => ()
        }
        initFreezeHandler(this.context.getApplicationContext(), {=> JsonValue.fromStr("{}")}, {data =>}, Path(this.context.cacheDir))
    }
}
```

> ** 注意: **
> 
> 和监控Crash类似，如果应用编译开启了 `O2` 级别优化，在部分场景，freeze调用栈会出现漏栈、行号不准的问题。

### 监控系统强杀
`hm_metricx_cj` 提供
#### 1. 系统强杀
```text
public func initExitInfoHandler(
    lastExitMessage: String,
    lastExitReason: Int32,
    reportExitInfoHandler: (ExitInfo) -> Unit,
    reportAppStateHandler: (AppStateInfo) -> Unit
): Unit
```
接口对系统强杀监控进行类型分类。

`initExitInfoHandler` 需要的入参说明如下：
- `launchParam：应用本次启动时系统传入的启动参数

- `exitReason` 上次应用退出的原因，分类如下：
    - `ability_not_responding` Ability未响应
    - `app_freeze` 应用无响应
    - `cpp_crash` Native层发出异常信号导致应用退出
    - `js_error` JS层Error导致应用退出
    - `unknown` 上次应用退出原因未被应用框架记录
    - `normal` 正常退出，如用户主动关闭应用
    - `performance_control` 系统能耗管控导致应用退出，如设备低内存
    - `resource_control` 资源管控导致应用退出，如过量使用CPU/IO/内存资源
    - `upgrade` 应用升级导致应用退出
- `exitMessage` 上次应用退出的详细信息

使用示例：

i.
在主模块的 `main_ability.cj` 的 `onCreate` 回调中调用 `initThermalHandler`：
```text
class EntryAbility <: UIAbility {
    public override func onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): Unit {
        AppLog.info("Ability OnCreated.${want.abilityName}")
        match (launchParam.launchReason) {
            case AbilityConstant.LaunchReason.START_ABILITY => AppLog.info("START_ABILITY")
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
        match (launchParam.launchReason) {
            case AbilityConstant
                .LaunchReason
                .START_ABILITY => AppLog.info("START_ABILITY")
            case _ => ()
        }
    }
}
```

#### 2. 用户滑杀
```text
public func initSwipeKillHandler(
    context: UIAbilityContext,
    launchParam: LaunchParam,
    reportInfo: (info: SwipeKillInfo) -> Unit,
    thresholdMs!: Int64 = DEFAULT_SWIPE_KILL_THRESHOLD_MS
)
```
接口对用户滑杀监控。

`initSwipeKillHandler` 需要的入参说明如下：
- `context: UIAbilityContext - UI能力上下文
- `launchParam：应用本次启动时系统传入的启动参数
- `reportInfo: (SwipeKillInfo) -> Unit - 滑动杀死信息回调函数
  - `timestamp` 事件发生的时间戳
  - `isUserSwipeKill` 是否为用户滑动杀死
  - `exitInfo` 上次退出原因（同exitReason）
- `Threshold: 判断滑动杀死的阈值(毫秒)，默认5000ms

使用示例：

i.
在主模块的 `main_ability.cj` 的 `onCreate` 回调中调用 `initThermalHandler`：
```text
class EntryAbility <: UIAbility {
    public override func onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): Unit {
        AppLog.info("Ability OnCreated.${want.abilityName}")
        match (launchParam.launchReason) {
            case AbilityConstant.LaunchReason.START_ABILITY => AppLog.info("START_ABILITY")
            case _ => ()
        }
        initSwipeKillHandler(
            this.context,
            launchParam,
            { info: SwipeKillInfo =>
                AppLog.warn("[MetricX] SwipeKill: User killed app and restarted quickly! timeSinceBg: ${info.toString()}")
            },
            thresholdMs: 5000
        )
    }
}
```

### 监控热量
`hm_metricx_cj` 提供
```text
public func initThermalHandler(
    context: UIAbilityContext,
    reportThermalInfo: (info: ThermalEventInfo) -> Unit,
    sampleInterval!: Int64 = DEFAULT_SAMPLE_INTERVAL_MS,
    reportMinInterval!: Int64 = DEFAULT_REPORT_MIN_INTERVAL_MS,
    abnormalThreshold!: Int32 = DEFAULT_ABNORMAL_LEVEL
): Unit
```

接口对电池热量异常事件进行监控。

`initThermalHandler` 需要的入参说明如下：
- `applicationContext: ApplicationContext` 指定应用上下文。
- `creportThermalInfo: (info: ThermalEventInfo) -> Unit` 用于在APP发生异常发热事件时，收集若干自定义的业务/系统信息，以 `JsonValue` 形式返回。
- `sampleInterval!: Int64 = DEFAULT_SAMPLE_INTERVAL_MS` 用于热量监控sample采用频率（ms）。
- `reportMinInterval!: Int64 = DEFAULT_REPORT_MIN_INTERVAL_MS` 用于热量监控异常上报频率（ms）。
- `abnormalThreshold!: Int32 = DEFAULT_ABNORMAL_LEVEL` 指定异常的阈值。

`ThermalEventInfo` 包含以下信息：

- `pageName` 热量异常时发生的当前页面
- `level` 当前热量异常的系统热level值
- `levelName` 当前热量异常的系统热level值对应的状态
- `threshold` 所指定异常的阈值
- `isForeground` 是否在前台
- `durationMs` 异常持续时长

使用示例：

i.
在主模块的 `main_ability.cj` 的 `onCreate` 回调中调用 `initThermalHandler`：
```text
class EntryAbility <: UIAbility {
    public override func onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): Unit {
        AppLog.info("Ability OnCreated.${want.abilityName}")
        match (launchParam.launchReason) {
            case AbilityConstant.LaunchReason.START_ABILITY => AppLog.info("START_ABILITY")
            case _ => ()
        }
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
    }
}
```

### 监控FPS/滑动掉帧率

`hm_metricx_cj` 提供
```text
public func initPageEventHandler(
    uiContext: UIAbilityContext,
    reportFpsInfo: (fpsInfo: FpsEventInfo) -> Unit
): Unit

public func initPageEventHandler(
    windowStage: WindowStage,
    reportFpsInfo: (fpsInfo: FpsEventInfo) -> Unit
): Unit

public func initScrollEventHandler(
    uiContext: UIAbilityContext,
    reportScrollInfo: (scrollInfo: ScrollHitchInfo) -> Unit
): Unit
```
接口对FPS/滑动掉帧率进行监控。

`initPageEventHandler` 需要的入参说明如下：

- `uiContext: UIAbilityContext` 指定UIAbility上下文
- `reportFpsInfo: (fpsInfo: FpsEventInfo) -> Unit` 用于每次页面退出时，将统计到的FPS信息进行上报，入参为 `FpsEventInfo` 类型对象

`FpsEventInfo` 包含以下信息：

- `minFps` 一段时间内，每隔一秒采样，测量到的最低帧率值
- `avgFps` 一段时间内，测量到的平均帧率值
- `pageName` 所在页面名称

`initPageEventHandler` 需要的入参说明如下：

- `windowStage: WindowStage` 指定WindowStage
- `reportFpsInfo: (fpsInfo: FpsEventInfo) -> Unit` 用于每次进入后台时，将统计到的FPS信息进行上报，入参为 `FpsEventInfo` 类型对象

`initScrollEventHandler` 需要的入参说明如下：

- `uiContext: UIAbilityContext` 指定UIAbility上下文
- `reportScrollInfo: (scrollInfo: ScrollHitchInfo) -> Unit` 用于每次滑动事件停止时，将统计到的滑动掉帧率信息，以及FPS信息进行上报，入参为 `ScrollHitchInfo` 类型对象。 

`ScrollHitchInfo` 继承 `FpsEventInfo` 的所有信息，并包含以下信息：

- `frameDropRatio` 滑动掉帧率
- `jankRate` 卡顿率
- `bigJankRate` 严重卡顿率
- `htLessThan0` 延迟小于0的帧数比例
- `ht0To00001` 延迟在0到0.0001秒之间的帧数比例
- `ht00001To0001` 延迟在0.0001到0.001秒之间的帧数比例
- `ht0001To001` 延迟在0.001到0.01秒之间的帧数比例
- `ht001To005` 延迟在0.01到0.05秒之间的帧数比例
- `ht005To01` 延迟在0.05到0.1秒之间的帧数比例
- `ht01To1` 延迟在0.1到1秒之间的帧数比例
- `htBiggerThan1` 延迟大于1秒的帧数比例
- `targetFPS` 目标帧率
- `longestLostFrame` 最长丢失的帧时间
- `totalFrameCount` 总帧数



使用示例：

i.
在主模块的 `main_ability.cj` 的 `onCreate` 回调中调用 `initPageEventHandler` 和 `initScrollEventHandler` ：
```text
class EntryAbility <: UIAbility {
    public override func onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): Unit {
        AppLog.info("Ability OnCreated.${want.abilityName}")
        match (launchParam.launchReason) {
            case AbilityConstant.LaunchReason.START_ABILITY => AppLog.info("START_ABILITY")
            case _ => ()
        }
        initScrollEventHandler({data =>})
    }
}
```

ii.
在主模块的 `main_ability.cj` 的 `onWindowStageCreate` 回调中调用 `initPageEventHandler` ：
```text
class EntryAbility <: UIAbility {
    public override func onWindowStageCreate(windowStage: window.WindowStage): Unit {
        windowStage.loadContent("pages/index", {err, data => ()})
        initPageEventHandler(windowStage, {data =>})
        windowStage.getMainWindow(
            {
                err, data => match(data) {
                    case Some(x) => initPageEventHandler(this.context, {data =>})
                    case None => AppLog.info("initPageEventHandler error)
                }
            }
        )
    }
}
```

### 监控交互响应延迟

`hm_metricx_cj` 提供
#### 1. 延迟监控
```text
public func initLaggyHandle(applicationcontext: ApplicationContext, uiContext: UIContext,
                            maxTime: Int64, maxArraySize: Int64,
                            reportLaggyInfo: (data: JsonObject) -> Unit)
```
接口对交互式响应延迟提供监控能力。

`initLaggyHandle` 需要的入参说明如下：

- `applicationcontext` 指定应用上下文。

- `uiContext` 指定 `uiContext`。

- `maxTime` 指定最大的响应时间，超过该时间视为一次卡顿事件。

- `maxArraySize` 指定存储最大的卡顿时间集合，当卡顿次数超过该值时，会删除最早的一次卡顿数据。

- `reportLaggyInfo` 上报数据的回调函数，入参为 `JsonObject` 类型对象，该对象包含以下字段：
  - `pageName` 当前页面名称
  - `technologyStack` 技术栈
  - `responseTime` 响应时间，单位：ms
  - `descriptionID` 响应组件的结构信息
  - `nodeType` 响应组件类型
  - `viewTouchID` 响应组件ID
  - `touchX` 点击位置相对于应用窗口左上角的X坐标，单位：px
  - `touchY` 点击位置相对于应用窗口左上角的Y坐标，单位：px
  - `hitX` 响应组件相对于应用窗口的X轴偏移，单位: px
  - `hitY` 响应组件相对于应用窗口的Y轴偏移，单位: px
  - `hitWidth` 响应组件大小的宽度，单位: vp
  - `hitHeight` 响应组件大小的高度，单位: vp

使用示例：

i.

在主模块的 `main_ability.cj` 的 `onWindowStageCreate` 回调中调用 `initLaggyHandler` :

```text
public func onWindowStageCreate(windowStage: window.WindowStage): Unit {
    windowStage.loadContent("pages/index", {err, data => ()})
    windowStage.getMainWindow(
        {
            err: ?BusinessException, data: ?window.Window => match (data) {
                case Some(x) => initLaggyHandler(this.context.getApplicationContext(),
                    fromUIContextBase(x.getUIContext()), 10, 10, {data =>})
                case None => AppLog.info("initLaggyHandler error")
            }
        })
}
```

#### 2. 白屏检查
```text
public func initWhiteScreenHandler(
    context: UIAbilityContext,
    windowStage: WindowStage,
    uiContext: UIContext,
    config: WhiteScreenConfig,
    reportWhiteScreenInfo: (data: JsonObject) -> Unit
)
```
接口对App白屏提供监控能力。


`initWhiteScreenHandler` 需要的入参说明如下：

- `context` 指定应用上下文，用于注册Ability生命周期回调。

- `windowStage` 指定窗口舞台，用于获取主窗口进行截图。

- `uiContext` 指定 `uiContext`。

- `config` 指定白屏检测配置项，其中包括：

| 字段 | 类型 | 默认值 | 含义 | 约束 |
|------|------|--------|------|------|
| `rootComponentId` | String | None | 根组件ID，用于组件截图 | 可选 |
| `ttidTimeoutMs` | Int64 | 1000 | 首帧超时时间(ms)，超时判定TIMEOUT白屏 | >= 0 |
| `frameCheckDurationMs` | Int64 | 3000 | 首帧后帧检测持续时间(ms) | >= 0 |
| `backgroundFirstSnapshotDelayMs` | Int64 | 800 | 后台首次截图延迟(ms) | >= 0 |
| `backgroundSecondSnapshotDelayMs` | Int64 | 1800 | 后台第二次截图延迟(ms) | >= 0 |
| `backgroundRecentPageEnterThresholdMs` | Int64 | 3000 | 后台检测页面进入阈值(ms) | >= 0 |
| `minFrameCountThreshold` | Int64 | 30 | 帧数阈值，低于此值触发截图分析 | >= 0 |
| `maxDistinctColorCount` | Int64 | 2 | 颜色复杂度阈值，颜色种类少于等于此值判白屏 | >= 0 |
| `whiteRgbThreshold` | Int64 | 245 | 白色RGB阈值，RGB均>=此值认为主色接近白色 | >= 0 |
| `snapshotScale` | Float64 | 0.1 | 截图缩放比例 | [0.0, 1.0] |
| `snapshotRegionTop` | Float64 | 0.08 | 截图区域顶部裁剪比例 | [0.0, 1.0] |
| `snapshotRegionBottom` | Float64 | 0.08 | 截图区域底部裁剪比例 | [0.0, 1.0] |
| `autoWriteFaultLog` | Bool | true | 是否自动写入故障日志 | - |


- `reportWhiteScreenInfo` 指定白屏事件上报回调函数,入参为 `JsonObject` 类型对象，该对象包含以下字段：
 - `pageName` 当前页面名称
 - `whiteScreenType`  白屏类型原因
 - `whiteScreenScene` 白屏检测场景：`PAGE_OPEN`(页面打开) / `PAGE_BACKGROUND`(前台切后台) 
 - `appState` 白屏检测时应用状态：`FOREGROUND` / `BACKGROUND` 

使用示例：

i.

在主模块的 `main_ability.cj` 的 `onWindowStageCreate` 回调中调用 `initWhiteScreenHandler` :

```text
public func onWindowStageCreate(windowStage: window.WindowStage): Unit {
    windowStage.loadContent("pages/index", {err, data => ()})
    windowStage.getMainWindow(
        {
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
        })
}
```

#### 3. 首帧渲染
```text
public func initFirstRenderTimeMonitor(
    config: FirstRenderTimeConfig,
    reportCallback: (FirstRenderTimeInfo) -> Unit
): Unit
```
接口提供App首帧渲染监控能力。


`initFirstRenderTimeMonitor` 需要的入参说明如下：

- `config` 指指定首帧渲染检测配置项，其中包括：
 - `enableLogging` 控制是否启用日志记录功能，默认值为 true
 - `reportThreshold` 上报的时间

`reportCallback` 指定首帧渲染事件上报回调函数，该对象包含以下字段：
 - `startTime`: Int64 - 开始时间
 - `endTime`: Int64 - 结束时间  
 - `duration`: Int64 - 持续时间
 - `targetPage`: String - 目标页面

使用示例：

i.

在主模块的 `main_ability.cj` 的 `onWindowStageCreate` 回调中调用 `initFirstRenderTimeMonitor` :

```text
public func onWindowStageCreate(windowStage: window.WindowStage): Unit {
    windowStage.loadContent("pages/index", {err, data => ()})
    windowStage.getMainWindow(
        {
            initFirstRenderTimeMonitor(
                            FirstRenderTimeConfig(true, 1000),
                            { info =>
                                AppLog.info("[FRT] ${info.toString()}")
                            }
                        )
        })
}
```

### 监控内存

`hm_metricx_cj` 提供

```text
// 注册内存监控
public func initMemoryHandler(
    context: UIAbilityContext,
    reportPageMemoryInfo: (info: PageMemoryInfo) -> Unit,
    reportProcessMemoryInfo: (info: ProcessMemoryInfo) -> Unit,    
    memoryThreshold!: Int64 = 100*1024
): Unit
// 取消内存监控
public func destroyMemoryHandler(): Unit
// 获取页面内存信息
public func getPageMemoryInfo(): PageMemoryInfo
// 获取进程内存信息
public func getProcessMemoryInfo(): ProcessMemoryInfo
```

接口对应用的内存使用情况进行监控。

`initMemoryHandler` 需要的入参说明如下：

- `context: UIAbilityContext` 指定UIAbility上下文。
- `reportPageMemoryInfo: (info: PageMemoryInfo) -> Unit` 将当前页面内存的使用情况进行上报，入参为 `PageMemoryInfo` 类型对象。
- `reportProcessMemoryInfo: (info: ProcessMemoryInfo) -> Unit` 将进程内存的使用情况进行上报，入参为 `ProcessMemoryInfo` 类型对象。
- `memoryThreshold!: Int64` 内存使用阈值，默认为100 * 1024 KB。当使用内存超过该阈值时，将内存使用情况上报。
- `sampleInterval!: Int64` 内存采样时间，单位为秒，默认为30秒。

`PageMemoryInfo` 包含以下信息：
- `avgMemory` 内存使用平均值，单位为KB
- `maxMemory` 内存使用最大值，单位为KB
- `avgCJMemory` 仓颉堆已被使用的平均值，单位为 byte。
- `maxCJMemory` 仓颉堆已被使用的最大值，单位为 byte。
- `sampleCount` 内存采样次数
- `pageName` 当前页面名称

`ProcessMemoryInfo` 包含以下信息：
- `avgMemory` 内存使用平均值，单位为KB
- `maxMemory` 内存使用最大值，单位为KB
- `avgCJMemory` 仓颉堆已被使用的平均值，单位为 byte。
- `maxCJMemory` 仓颉堆已被使用的最大值，单位为 byte。
- `sampleCount` 内存采样次数
- `pid` 进程ID

使用示例：

i.

在主模块的 `main_ability.cj` 的 `onCreate` 回调中调用 `initMemoryHandler` 

ii.

在主模块的 `main_ability.cj` 的 `onDestroy` 回调中调用 `destroyMemoryHandler` ：

```text
class EntryAbility <: UIAbility {
    public override func onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): Unit {
        AppLog.info("Ability OnCreated.${want.abilityName}")
        match (launchParam.launchReason) {
            case AbilityConstant.LaunchReason.START_ABILITY => AppLog.info("START_ABILITY")
            case _ => ()
        }
        initMemoryHandler(this.context, {data =>}, {data =>})
    }
    public override func onDestroy(): Unit {
        destroyMemoryHandler()
        AppLog.info("myAbility onDestroy.")
    }
}
```

### 监控CPU

`hm_metricx_cj` 提供

 ```text	 
 // 注册CPU监控	 
 public func initCpuHandler(	 
     ability: UIAbility,	 
     reportPageCpuInfo: (info: PageCpuInfo) -> Unit,	 
     reportProcessCpuInfo: (info: ProcessCpuInfo) -> Unit	 
 ): Unit	 
 // 取消CPU监控	 
 public func destroyCpuHandler(): Unit	 
 // 获取页面CPU信息	 
 public func getPageCpuInfo(): PageCpuInfo	 
 // 获取进程CPU信息	 
 public func getProcessCpuInfo(): ProcessCpuInfo	 
 ```
接口对应用的CPU使用情况进行监控。

`initCpuHandler` 需要的入参说明如下：
 - `context: UIAbilityContext` 指定UIAbility上下文。	 
 - `reportPageCpuInfo: (info: PageCpuInfo) -> Unit` 将当前页面的CPU的使用情况进行上报，入参为 `PageCpuInfo` 类型对象。	 
 - `reportProcessCpuInfo: (info: ProcessCpuInfo) -> Unit` 将进程的CPU的使用情况进行上报，入参为 `ProcessCpuInfo` 类型对象。	 
 
 
 `PageCpuInfo` 包含以下信息：	 
 - `avgCpu` CPU使用率平均值，以比例值表示（如使用率50%，则返回0.5）	 
 - `maxCpu` CPU使用率最大值，以比例值表示	 
 - `sampleCount` CPU采样次数	 
 - `pageName` 当前页面名称	 

 `ProcessCpuInfo` 包含以下信息：	 
 - `avgCpu` CPU使用率平均值，以比例值表示（如使用率50%，则返回0.5）	 
 - `maxCpu` CPU使用率最大值，以比例值表示	 
 - `sampleCount` CPU采样次数 
 - `pid` 进程ID
使用示例：

i.在主模块的 `main_ability.cj` 的 `onCreate` 回调中调用 `initCpuHandler`

ii.在主模块的 `main_ability.cj` 的 `onDestroy` 回调中调用 `destroyCpuHandler` ：
 ```text	 
 class EntryAbility <: UIAbility {	 
     public override func onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): Unit {	 
         AppLog.info("Ability OnCreated.${want.abilityName}")	 
         match (launchParam.launchReason) {	 
             case AbilityConstant.LaunchReason.START_ABILITY => AppLog.info("START_ABILITY")	 
             case _ => ()	 
         }	 
         initCpuHandler(this.context, {data =>}, {data =>})	 
     }	 
     public override func onDestroy(): Unit {	 
         destroyCpuHandler()	 
         AppLog.info("myAbility onDestroy.")	 
     }	 
 }
 ```

#### 新增CPU异常监控 : 1）3分钟线程栈异常监控
```text
//注册CPU异常监控
public func initHighCpuMonitorHandler(
    context: UIAbilityContext,
    config: HighCpuMonitorConfig,
    reportHighCpuInfo: (info: HighCpuReportInfo) -> Unit
): unit
// 取消CPU监控
public func destroyHighCpuMonitorHandler(): Unit
// 获取页面CPU信息
public func HighCpuMonitorConfig(): PageCpuInfo
// 获取进程CPU信息
public func reportHighCpuInfo(): ProcessCpuInfo
```

接口对应用的CPU使用情况进行监控。

`initHighCpuMonitorHandler` 需要的入参说明如下：

- `context: UIAbilityContext` 指定UIAbility上下文。
- `config: HighCpuMonitorConfig` 将当前页面的CPU的使用入参为 `HighCpuMonitorConfig` 类型对象。
- `reportHighCpuInfo: (info: HighCpuReportInfo) -> Unit` 回调配置，将进程的CPU的异常使用情况进行上报。

`HighCpuMonitorConfig` 的入参包含信息：
- `cpuThreshold` CPU使用率平均值，以比例值表示（如使用率50%，则返回0.5），范围是0-1，如果是负数或者超过1，会调用系统设置的默认值
- `foregroundIntervalMs` 前台采样频率（ms，如果1s则设置为1000），如果是负数，会调用系统设置的默认值
- `backgroundIntervalMsleCount` 后台采样频率（ms，如果1s则设置为1000），如果是负数，会调用系统设置的默认值
- `monitorDurationMS` 异常上报频率（ms，如果1s则设置为1000），如果是负数，会调用系统设置的默认值
- `threadCoolDownMs` 安全限流设置（ms，如果1s则设置为1000），如果是负数，会调用系统设置的默认值，针对本模块内的冷却限限流，假如时间是60s，在threadCoolDownMs时间内，如果有异常汇报过同线程，这个threadCoolDownMs会开启，在这个冷却时间内，不会重复上报已有的异常信息。
- `globalCooldownMs` 安全限流设置（ms，如果1s则设置为1000），如果是负数，会调用系统设置的默认值，针对全局APM的冷却限限流，假如时间是180s，在globalCooldownMs时间内，如果有异常汇报过同线程，这个globalCooldownMs会开启，在这个冷却时间内，不会重复上报已有的异常信息。
- `highSampleRatioThreshold` 高采样比例阈值，在3分钟内所有采样个数内，需要保证整体采样sample异常比例超过设定阈值，且CPU使用率平均值大于cpuThreshold，最后异常事件才会上报，范围是0-1，如果是负数或者超过1，会调用系统设置的默认值
- `topNthreads` 每次采用异常线程数，0 - 200，如果在范围外，会调用系统设置的默认值

`HighCpuReportInfo` 包含以下信息：
- `timestamp` timestamp
- `processName` 进程
- `pid` 进程ID
- `pageName` 当前页面
- `avgProcessCpu` CPU平均值
- `montorDuration` 监控时长
- `highCpuThreads.length` 高占用线程数

`HighCpuThreads` 包含以下信息：
- `tid` 进程TID
- `threadName` 异常线程名
- `avgCpuUsage` 平均CPU
- `maxCpuUsage` 最大CPU
- `sampleCount` 采样次数
- `hightSampleCount/sampleCount` 高采样比例
- `moduleBane` 模块名
- `firstDetectedTime` 首次检测时间

使用示例：

i.在主模块的 `main_ability.cj` 的 `onCreate` 回调中调用 `initCpuHandler`

ii.在主模块的 `main_ability.cj` 的 `onDestroy` 回调中调用 `destroyCpuHandler` ：

```text
initHighCpuMonitorHandler(
            this.context,
            HighCpuMonitorConfig(
                cpuThreshold: 0.05,
                foregroundIntervalMs: 1000,
                backgroundIntervalMs: 2000,
                monitorDurationMs: 330000,
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
        )；
```
#### 新增CPU异常监控 : 2）CPU后台活动率异常监控
```text
//注册CPU异常监控
public func initBackgroundCpuMonitorHandler(
    context: UIAbilityContext,
    config: BackgroundCpuMonitorConfig,
    reportCallback: (info: BackgroundCpuReportInfo) -> Unit
): unit
// 取消CPU监控
public func destroyBackgroundCpuMonitorHandler(): Unit
// 手动触发后台 CPU 上报
public func triggerBackgroundCpuReport(): Unit
// 检查后台监控是否正在运行
public func isBackgroundCpuMonitoringActive(): Bool
//获取后台监控配置
public func getBackgroundCpuConfig(): Option<BackgroundCpuMonitorConfig>
```
接口对应用的CPU使用情况进行监控。

`initBackgroundCpuMonitorHandler` 需要的入参说明如下：

- `context: UIAbilityContext` 指定UIAbility上下文。
- `config: BackgroundCpuMonitorConfig` 将当前页面的CPU的使用入参为 `BackgroundCpuMonitorConfig` 类型对象。
- `reportCallback: (info: BackgroundCpuReportInfo) -> Unit` 回调配置，将进程的CPU的异常使用情况进行上报。

`BackgroundCpuMonitorConfig` 的入参包含信息：
- `cpuThreshold` CPU使用率平均值，以比例值表示（如使用率50%，则返回0.5），范围是0-1，如果是负数或者超过1，会调用系统设置的默认值
- `warnDurationMs`: (int64) 最小异常上报时长（ms），超过此时长触发warn级别上报。
- `errorDurationMs`: (int64) 最小异常上报时长（ms），超过此时长触发error级别上报。
- `errorDurationMs`: (int64) 最小异常上报时长（ms），超过此时长触发fatal级别上报。
- `sampleIntervalMs`: (int64) 采样间隔(ms)。
- `windowSizeMs`: (int64) 滑动窗口大小(ms)。

`BackgroundCpuReportInfo` 包含以下信息：
- `timestamp` timestamp
- `processName` 进程
- `pid` 进程ID
- `level` 当前异常等级
- `pageName` 当前页面
- `avgProcessCpu` CPU平均值
- `backgroundDuration` 监控时长
- `windowSamples.size` 滑动窗口采样数

使用示例：

i.在主模块的 `main_ability.cj` 的 `onCreate` 回调中调用 `initCpuHandler`

ii.在主模块的 `main_ability.cj` 的 `onDestroy` 回调中调用 `destroyCpuHandler` ：

```text
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
```

### 监控电量

`hm_metricx_cj`提供

```text
// 注册电量监控
public func initBatteryHandler(
    ability: UIAbility,
    reportBatteryInfo: (batteryInfo: BatteryUsageInfo) -> Unit,
    reportThreadCpuUsageInfo: (allThreadCpuUsageInfo: AllThreadCpuUsageInfo) -> Unit,
    limit!: Int32 = 1
): Unit
// 取消电量监控
public func destroyBatteryHandler(): Unit
```

接口对手机的掉电情况进行监控。

`initBatteryHandler` 需要的入参说明如下：

- `ability: UIAbility` 指定应用组件。
- `reportBatteryInfo: (batteryInfo: BatteryUsageInfo) -> Unit` 用于在发生掉电时，将相应的信息进行上报，入参为 `BatteryUsageInfo` 类型对象。
- `reportThreadCpuUsageInfo: (allThreadCpuUsageInfo: AllThreadCpuUsageInfo) -> Unit` 用于上报所有线程的CPU使用情况，当检测到CPU使用异常时，该回调函数会被触发，函数入参为`AllThreadCpuUsageInfo` 类型对象。
- `limit!: Int32` 掉电x格上报，默认为1。

`BatteryUsageInfo` 包含以下信息：

- `currentPageName` 当前浏览页面
- `level` 当前电量
- `temperature` 当前电池温度，单位为摄氏度（°C）
- `capacity` 电池容量（当前暂不支持获取）
- `scale` 电池的最大电量，默认为100
- `status` 电池的当前状态
- `health` 电池的健康状况
- `voltage` 电池的当前电压，单位为毫伏特
- `technology` 电池的技术类型
- `plugged`  设备的连接方式
- `charging` 设备是否在充电
- `limit` 掉电x格上报，默认为1格
- `brightness` 屏幕亮度
- `useTime` APP前台使用时间，单位为s
- `time` 距离上次掉电的时间间隔，单位为s

`AllThreadCpuUsageInfo` 包含以下信息：

- `threadCpuUsageInfoList` 所有线程的CPU使用信息，类型为`ArrayList<ThreadCpuUsageInfo>`

`ThreadCpuUsageInfo` 包含以下信息：
- `threadId` 线程id
- `threadName` 线程名
- `threadState` 线程状态
- `threadJiffiesPercent` 线程的CPU使用率百分比
- `threadJiffies` 线程的CPU使用时间
- `totalJiffies` 总的CPU时间
- `startBgTime` 线程进入后台的时间
- `exceptionTime` 线程出现异常的时间

使用示例：

i.

在主模块的 `main_ability.cj` 的 `onCreate` 回调中调用 `initBatteryHandler`

ii.

在主模块的 `main_ability.cj` 的 `onDestroy` 回调中调用 `destroyBatteryHandler` ：

```text
class EntryAbility <: UIAbility {
    public override func onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): Unit {
        AppLog.info("Ability OnCreated.${want.abilityName}")
        match (launchParam.launchReason) {
            case AbilityConstant.LaunchReason.START_ABILITY => AppLog.info("START_ABILITY")
            case _ => ()
        }
        initBatteryHandler(this, {data =>}, {data =>})
    }
    
    public override func onDestroy(): Unit {
        destroyBatteryHandler()
        AppLog.info("myAbility onDestroy.")
    }
}
```

### 监控流量

流量监控依赖正确配置对网络统计信息的访问权限，即需要在应用的 `module.json5` 中添加以下内容

```text
"requestPermissions": [
    {
        "name": "ohos.permission.GET_NETWORK_INFO"
    }
]
```

`hm_metricx_cj` 提供

```text
// 注册占用存储空间上报函数
public func initTrafficHandler(
    context: UIAbilityContext,
    reportTraffic: (sampleTraffixInfo: SampleTrafficInfo) -> Unit,
    reportYesterdayTraffic: (yesterdayTraffic: DayTrafficInfo) -> Unit,
    sampleTime!: Int64 = 10 * 60 * 1000,
    sampleThreshold!: Int64 = 50 * 1024 * 1024
): Unit


// 取消流量监控
public func destroyTrafficHandler()

```

接口对app占用存储空间获取并进行上报。

`initTrafficHandler` 需要的入参说明如下：
- `context`: `UIAbilityContext` 指定UIAbility上下文。
- `reportTraffic: (sampleTraffixInfo: SampleTrafficInfo) -> Unit` 回调函数，用于上报流量使用情况。当流量数据达到上报阈值`sampleThreshold`时，回调被触发。
- `reportYesterdayTraffic: (yesterdayTraffic: DayTrafficInfo) -> Unit` 回调函数，用于在应用启动时上报前一天的流量使用情况, 仅上报一次。
- `sampleTime` 用于设置流量数据的采样时间间隔，单位为毫秒。
- `sampleThreshold` 用于设置流量数据的上报阈值，单位为字节。

`SampleTrafficInfo` 包含以下信息：

- `systemInfo: SystemTrafficInfo` 系统级别流量信息
- `pageInfoMap: HashMap<String, PageTrafficInfo>` 页面级别的流量信息，键为页面名称，值为对应的流量信息
- `urlInfoArray: ArrayList<UrlTrafficInfo>` URL级别的流量信息

`TrafficInfo` 包含以下信息

- `totalDailyTraffic` 应用日流量信息
- `totalTraffic` 单次进程总流量
- `limit` 触发告警的流量阈值

`SystemTrafficInfo` 在 `TrafficInfo` 基础上，添加如下信息：

- `timeStamp: String` 时间戳，表示流量数据的采集时间

`PageTrafficInfo` 在 `TrafficInfo` 基础上，添加如下信息：

- `pageName: String` 页面名称

`UrlTrafficInfo` 在 `TrafficInfo` 基础上，添加如下信息：

- `url: String` url地址

`DayTrafficInfo` 在 `TrafficInfo` 基础上，添加如下信息：

- `date: String` 日期

使用示例：

i.

在主模块的 `main_ability.cj` 的 `onCreate` 回调中调用 `initTrafficHandler` ：

ii.

在主模块的 `main_ability.cj` 的 `onDestroy` 回调中调用 `destroyTrafficHandler` ：

```text
class EntryAbility <: UIAbility {
    public override func onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): Unit {
        AppLog.info("Ability OnCreated.${want.abilityName}")
        match (launchParam.launchReason) {
            case AbilityConstant.LaunchReason.START_ABILITY => AppLog.info("START_ABILITY")
            case _ => ()
        }
        initTrafficHandler(this, {data =>})
    }
    public override func onDestroy(): Unit {
        destroyTrafficHandler()
        AppLog.info("myAbility onDestroy.")
    }
}
```



### 监控存储

`hm_metricx_cj` 提供

```text
// 注册占用存储空间上报函数
public func initStorageHandler(
    reportStorageInfo: (storageInfo: StorageInfo) -> Unit,
    sizeLimit!: Int64,
    dirSizeLimit!: Int64,
    reportTopNum!: Int64 = 5
): Unit
// 上报占用存储空间
public func reportAppStorageInfo(): Unit
```

接口对app占用存储空间获取并进行上报。

`initStorageHandler` 需要的入参说明如下：

- `reportStorageInfo: (storageInfo: StorageInfo) -> Unit` 用于获取app占用存储空间时，将app占用存储空间进行上报，入参为 `StorageInfo` 类型对象。
- `sizeLimit`   存储大小阈值。超过该阈值会上报top N个异常文件和异常文件夹。
- `dirSizeLimit`  文件夹大小阈值。超过该阈值的文件夹被标记为异常文件夹。
- `reportTopNum` 用于设置上报的前N个文件/夹数量。

`StorageInfo` 包含以下信息

- `appSize` 应用安装文件大小，单位为Byte
- `cacheSize` 应用缓存文件大小，单位为Byte
- `dataSize` 应用文件存储大小（除应用安装文件和缓存文件），单位为Byte
- `totalSize` 数据的大小，单位为Byte
- `topStorageFileList` 文件列表，包含size最大的N个文件
- `exceptionDirList` 异常文件夹列表，包含超过dirSizeLimit大小限制的文件夹

使用示例：

i.

在主模块的 `main_ability.cj` 的 `onCreate` 回调中调用 `initBatteryHandler` ：

```text
class EntryAbility <: UIAbility {
    public override func onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): Unit {
        AppLog.info("Ability OnCreated.${want.abilityName}")
        match (launchParam.launchReason) {
            case AbilityConstant.LaunchReason.START_ABILITY => AppLog.info("START_ABILITY")
            case _ => ()
        }
        initStorageHandler({data: StorageInfo =>}, sizeLimit: 100000000, dirSizeLimit: 1000, reportTopNum: 5)
    }
}
```

ii.

需要上报app占用存储空间时，调用 `reportAppStorageInfo` 函数 ：

```text
reportAppStorageInfo()
```

### 监控内存泄漏

`hm_metricx_cj` 提供

```text
public func initMemLeakHandler(
    context: UIAbilityContext,
    persistentDir: Path,
    needDumpSnapshot: (pageInfo: PageInfo, typeInfos: List<String>) -> Bool,
    clearHistoryComponentInfo: (typeInfos: List<String>) -> Bool,
    reportMemLeak: (path: Path) -> Unit
)
```

接口对内存泄漏进行监控。

`initMemLeakHandler` 需要的入参说明如下：

- `context: UIAbilityContext` 指定UIAbility上下文。
- `persistentDir: Path` 指定内存快照导出目录。
- `needDumpSnapshot: (pageInfo: PageInfo, typeInfos: List<String>) -> Bool` 是否需要导出内存快照， `pageInfo` 为 `PageInfo` 类型对象，记录页面切换的名称信息，`typeInfos` 记录存活组件的类型信息。
- `clearHistoryComponentInfo: (typeInfos: List<String>) -> Bool` 每次内存检测结束，是否清除存活的组件，`typeInfos` 记录存活组件的类型信息。
- `reportMemLeak: (path: Path) -> Unit` 内存泄漏上报函数，入参为 `Path` 类型对象，表示内存快照文件路径。

`PageInfo` 包含以下信息：

- `fromPage` 页面切换的源页面名称。
- `toPage` 页面切换的目的页面名称。

使用示例：

i.

```text
class EntryAbility <: UIAbility {
    public override func onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): Unit {
        AppLog.info("Ability OnCreated.${want.abilityName}")
        match (launchParam.launchReason) {
            case AbilityConstant.LaunchReason.START_ABILITY => AppLog.info("START_ABILITY")
            case _ => ()
        }
        initMemLeakHandler(
            this.context,
            Path(this.context.cacheDir),
            {pageInfo, typeInfos => true},
            {typeInfos => false},
            {dumpFilePath => AppLog.info("dumpFilePath : ${dumpFilePath.toString()}")})
    }
}
```