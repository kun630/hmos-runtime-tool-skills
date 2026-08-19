/*
 * Copyright (c) Huawei Technologies Co., Ltd. 2025-2025. All rights reserved.
 */
package ohos_app_cangjie_hm_metricx_cj.laggy

import tpc.UIKit.UIContext.*
import tpc.AbilityKit.ApplicationContext
import tpc.AbilityKit.ApplicationContextType
import tpc.AbilityKit.AbilityLifecycleCallback
import tpc.UIKit.arkui_node.{FrameNode, ComponentContent}
import tpc.UIKit.Observer.*
import tpc.UIKit.component_interop.*
import tpc.ArkGraphics2D.displaySync as displaySync
import tpc.ArkGraphics2D.displaySync.*
import tpc.UIKit.window
import tpc.AbilityKit.UIAbility
import std.collection.*
import std.time.*
import stdx.encoding.json.*
import ohos.ark_interop.JSObject
import ohos.ark_interop.JSString
import ohos_app_cangjie_hm_metricx_cj.util.*
import ohos.window.WindowStage
import ohos.ability.Ability
import ohos.base.Callback1Argument

var laggyMap = HashMap<String, PageResponseLaggyModel>()
var eventMap = HashMap<Float64, ResponseEvent>()
var uploadLaggyinfo: (JsonObject) -> Unit = { info: JsonObject => () }
var timeBegain: Float64 = 0.0
var currentPageName = defaultPageName
var isFirstCallBack = true
var isComplite = false
var maxResponsesTime = 0
var maxSize = 0
var sync = displaySync.create()

public class ResponseEvent{
    var pageName = ""
    var technologyStack = "Native"
    var responseTime = 0
    var descriptionID = ""
    var nodeType = ""
    var viewTouchID = ""
    var touchX = 0.0
    var touchY = 0.0
    var hitX = 0.0
    var hitY = 0.0
    var hitWidth = 0.0
    var hitHeight = 0.0

    public func ToJsonValue() {
        var info = HashMap<String, String>()
        info.add("pageName", pageName)
        info.add("technologyStack", technologyStack)
        info.add("responseTime", responseTime.toString())
        info.add("descriptionID", descriptionID)
        info.add("nodeType", nodeType)
        info.add("viewTouchID", viewTouchID)
        info.add("touchX", touchX.toString())
        info.add("touchY", touchY.toString())
        info.add("hitX", hitX.toString())
        info.add("hitY", hitY.toString())
        info.add("hitWidth", hitWidth.toString())
        info.add("hitHeight", hitHeight.toString())
        var jsObj = JsonObject()
        jsObj.put("ResponseEvent", map2json(info))
        jsObj
    }
}

public class PageResponseLaggyModel {
    var pageName = ""
    // 触摸次数
    var touchTimes = 0
    // 卡顿次数
    var laggyTimes = 0
    // 卡顿时间集合
    var laggyTimeList = ArrayList<Float64>()

    public func ToJsonValue() {
        var info = HashMap<String, String>()
        info.add("pageName", pageName)
        info.add("touchTimes", touchTimes.toString())
        info.add("laggyTimes", laggyTimes.toString())
        info.add("laggyTimeList", laggyTimeList.toString())
        var jsObj = JsonObject()
        jsObj.put("PageResponseLaggyModel", map2json(info))
        jsObj
    }
}

public func syncCallBack(info: IntervalInfo)
{
    if (isFirstCallBack) {
        isFirstCallBack = false
        return
    }
    var timeEnd = Float64(info.timestamp)
    var event = eventMap[timeBegain]
    var cost = ((timeEnd - timeBegain) * Duration.nanosecond).toMilliseconds()
    if (cost > maxResponsesTime) {
        event.responseTime = cost
        var jsObj = event.ToJsonValue()
        uploadLaggyinfo(jsObj)
        if (laggyMap.contains(currentPageName)) {
            var model = laggyMap[currentPageName]
            model.laggyTimes += 1
            model.laggyTimeList.add(timeEnd - timeBegain)
            if (model.laggyTimeList.size > maxSize) {
                model.laggyTimeList.remove(at: 0)
            }
            isComplite = true
        }
    }
    eventMap.remove(timeBegain)
    sync.stop()
    sync.off(OnOffType.DS_FRAME)
    isFirstCallBack = true
}

public func didClickCallBack(event: ClickEventEnhanced, context: UIContext, node: ?FrameNode)
{
    if (isComplite) {
        isComplite = false
    }
    var response = ResponseEvent()
    var t_begain = event.timestamp
    timeBegain = t_begain
    response.pageName = currentPageName
    response.touchX = context.vp2px(event.windowX ?? 0.0)
    response.touchY = context.vp2px(event.windowY ?? 0.0)
    try {
        let frameNode = node.getOrThrow()
        response.viewTouchID = frameNode.getId()
        response.nodeType = frameNode.getNodeType()
        var pos = frameNode.getPositionToWindow()
        var measureSize = frameNode.getMeasuredSize()
        // waiting bugfix
        //response.descriptionID = frameNode.getInspectorInfo()
        response.hitX = context.vp2px(pos.x)
        response.hitY = context.vp2px(pos.y)
        response.hitHeight = measureSize.height
        response.hitWidth = measureSize.width
    } catch (e: NoneValueException) {
        println(e.toString())
    }
    eventMap.add(timeBegain, response)
    if (laggyMap.contains(currentPageName)) {
        laggyMap[currentPageName].touchTimes += 1
    }
    sync.on(displaySync.OnOffType.DS_FRAME, DisplaySyncCallBack(syncCallBack))
    sync.start()
}

public func navDestinationSwitchCallBack(info:NavDestinationSwitchInfo)
{
    let name = getTargetPageName(info)
    if (laggyMap.contains(currentPageName)) {
        var res = laggyMap[currentPageName]
        uploadLaggyinfo(res.ToJsonValue())
        laggyMap.remove(currentPageName)
    }
    if (!name.isEmpty()) {
        var res = PageResponseLaggyModel()
        res.pageName = name
        currentPageName = name
        laggyMap.add(name, res)
    }
}

public func onAbilityBackgroundCallBack(ability: UIAbility)
{
    if (laggyMap.contains(currentPageName)) {
        var res = laggyMap[currentPageName]
        uploadLaggyinfo(res.ToJsonValue())
        laggyMap.remove(currentPageName)
    }
}

let abilityLifecycleCallback: AbilityLifecycleCallback = AbilityLifecycleCallback(
    onAbilityCreate: { ability: UIAbility => () },
    onWindowStageCreate: { abilty: UIAbility, windowStage: window.WindowStage => () },
    onWindowStageActive: { abilty: UIAbility, windowStage: window.WindowStage => () },
    onWindowStageInactive: { abilty: UIAbility, windowStage: window.WindowStage => () },
    onWindowStageDestroy: { abilty: UIAbility, windowStage: window.WindowStage => () },
    onAbilityDestroy: { abilityUIability => () },
    onAbilityForeground: { ability: UIAbility => () },
    onAbilityBackground: onAbilityBackgroundCallBack,
    onAbilityContinue: { abilityUIability => () },
    onWindowStageRestore: { abilty: UIAbility, windowStage: window.WindowStage => () }
)

public func initLaggyHandler(applicationcontext: ApplicationContext, uiContext: UIContext,
                            maxTime: Int64, maxArraySize: Int64, reportLaggyInfo: (data: JsonObject) -> Unit)
{
    uploadLaggyinfo = reportLaggyInfo
    maxSize = maxArraySize
    maxResponsesTime = maxTime
    uiContext.getUIObserver().on(ObserverListenerType.navDestinationSwitch,
                                NavDestinationSwitchCallBack(navDestinationSwitchCallBack))
    uiContext.getUIObserver().on(ObserverListenerType.didClick, DidClickCallBack(didClickCallBack, uiContext))
    applicationcontext.on(ApplicationContextType.ABILITY_LIFECYCLE, abilityLifecycleCallback)
    0
}

// 回调函数warper
public class DidClickCallBack <: ClickEventListenerCallback {
    let elementInfoCallBack: (event: ClickEventEnhanced, context: UIContext, node: ?FrameNode) -> Unit
    let context: UIContext
    public init(elementInfoCallBack: (event: ClickEventEnhanced, context: UIContext, node: ?FrameNode) -> Unit, context: UIContext) {
        this.elementInfoCallBack = elementInfoCallBack
        this.context = context
    }
    public func invoke(event: ClickEventEnhanced, node: ?FrameNode): Unit {
        this.elementInfoCallBack(event, this.context, node)
    }
}

public class NavDestinationSwitchCallBack <: Callback1Argument<NavDestinationSwitchInfo> {
    let elementInfoCallBack: (NavDestinationSwitchInfo) -> Unit
    public init(elementInfoCallBack: (NavDestinationSwitchInfo) -> Unit) {
        this.elementInfoCallBack = elementInfoCallBack
    }
    public func invoke(info: NavDestinationSwitchInfo): Unit {
        this.elementInfoCallBack(info)
    }
}

public class DisplaySyncCallBack <: Callback1Argument<IntervalInfo> {
    let elementInfoCallBack: (IntervalInfo) -> Unit
    public init(elementInfoCallBack: (IntervalInfo) -> Unit) {
        this.elementInfoCallBack = elementInfoCallBack
    }
    public func invoke(info: IntervalInfo): Unit {
        this.elementInfoCallBack(info)
    }
}