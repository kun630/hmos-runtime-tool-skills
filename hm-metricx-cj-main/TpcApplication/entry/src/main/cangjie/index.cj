/*
 * Copyright (c) Huawei Technologies Co., Ltd. 2025-2025. All rights reserved.
 */
package ohos_app_cangjie_entry

import ohos.hybrid_base.CJPageEntry
import tpc.UIKit.Text
import tpc.UIKit.Button
import tpc.UIKit.Column
import tpc.UIKit.CustomView
import tpc.UIKit.*
import ohos.state_macro_manage.State
import ohos.state_macro_manage.Component
import ohos.state_manage.LocalStorage
import ohos.state_manage.ObservedProperty
import ohos.state_manage.SubscriberManager
import ohos.state_manage.ViewStackProcessor
import ohos.state_macro_manage.{HybridComponentEntry, Component}
import ohos.hybrid_base.CJPageEntry
import ohos.hybrid_base.HybridComponentBase
import ohos_app_cangjie_hm_metricx_cj.util.*
import ohos_app_cangjie_hm_metricx_cj.freeze.*
import ohos_app_cangjie_hm_metricx_cj.storage.*
import ohos_app_cangjie_hm_metricx_cj.memLeak.*
import ohos.base.nativeLog
import ohos.hilog.*
import tpc.AbilityKit.*
import tpc.UIKit.component_interop.getContext
import std.collection.ArrayList
import ohos.base.AppLog
import tpc.UIKit.component_interop.NavDestination
import ohos.state_macro_manage.Provide
import ohos.state_macro_manage.Builder
import tpc.ArkWeb.webview.WebviewController

//对于thermal测试的新增
import tpc.UIKit.global.*   // setTimeout
import std.time.*           // DateTime
import std.sync.*
import std.convert.*

@Component
class pageOneTmp {
    public func build() {
        NavDestination() {
            TextInput(placeholder: 'search...').height(40).width(90).backgroundColor(0XFFFFFF).margin(top: 8)
        }
    }
}

@HybridComponentEntry
@Component
class Index {
    @State
    var webviewController: WebviewController = WebviewController()
    var msg: String = "Hello"
    let arr = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 100]
    @Provide
    var pageInfos: NavPathStack = NavPathStack()

    @Builder
    public func PageMap(name: String): Unit {
        if (name == "pageOne") {
            PageOne()
        } else if (name == "pageTwo") {
            PageTwo()
        } else if (name == "blankPage") {
            BlankPage()
        } else if (name == "halfBlankPage") {
            HalfBlankPage()
        } else if (name == "imagePage") {
            ImagePage()
        } else if (name == "slowImagePage") {
            SlowImagePage()
        } else if (name == "slowLoadPage") {
            SlowLoadPage()
        } else if (name == "pageOpenTriggerPage") {
            PageOpenTriggerPage()
        } else if (name == "switchResultTriggerPage") {
            SwitchResultTriggerPage()
        } else if (name == "switchResultBlankPage") {
            SwitchResultBlankPage()
        }
    }

    public func build() {
        Navigation(this.pageInfos) {
            Column {
                Button("click to change Text").onClick {
                    =>
                    msg = "world"
                    oom()
                }
                Button("Hilog-Freeze").onClick {
                    =>
                    msg = "Hilog"
                    Hilog.info(218108688, "AppDfr", "appfreeze_inner cj log : hilog")
                }
                Button("freeze").onClick {
                    =>
                    msg = "freeze"
                    Hilog.info(0, "testTag", "cj log : freeze clicked")
                    while (true) {
                    }
                }
                Button("storage").onClick {
                    =>
                    Hilog.info(0, "testTag", "storage click")
                    reportAppStorageInfo()
                }

                Button("Start Heating (CPU Burn)").onClick {
                    =>
                    msg = "Heating..."
                    startCpuBurnMulti()
                }

                Button("Stop Heating").onClick {
                    =>
                    msg = "Stop heating"
                    stopCpuBurnMulti()
                }

                Button("WhiteScreen: Page Open Trigger Page").onClick {
                    => this.pageInfos.pushPath(NavPathInfo(name: "pageOpenTriggerPage", param: ""))
                }
                Button("WhiteScreen: Switch Result Trigger Page").onClick {
                    => this.pageInfos.pushPath(NavPathInfo(name: "switchResultTriggerPage", param: ""))
                }

                Text(msg)

                TextInput(placeholder: 'search...').height(40).width(90).backgroundColor(0XFFFFFF).margin(top: 8)

                List(space: 20, initialIndex: 0) {
                    ForEach(
                        this.arr,
                        itemGeneratorFunc: {
                            item: Int64, _: Int64 => ListItem() {
                                Text("${item}")
                                    .width(100)
                                    .height(100)
                                    .fontSize(16)
                                    .textAlign(TextAlign.Center)
                                    .borderRadius(10)
                                    .backgroundColor(0xFFFFFF)
                                    .onClick(
                                        {event => this.pageInfos.pushPath(NavPathInfo(name: "pageOne", param: ""))}
                                    )
                            }
                        }
                    )
                }.scrollBar(BarState.Off).width(90).layoutWeight(1)
            }
            .width(100.percent)
            .height(100.percent)
        }
        .id("root")
        .hideTitleBar(true)
        .navDestination(bind<String>(PageMap, this))
    }

    private var memLeakMark: Option<MemLeakMark> = None
    protected override func aboutToDisappear() {
        this.memLeakMark = MemLeakMark()
        collectDestroyedComponent(this.memLeakMark.getOrThrow(), this)
    }
}

@Component
class PageOne{
    @State
    var webviewController: WebviewController = WebviewController()
    var pageInfos:NavPathStack = NavPathStack()
    public func build() {
        NavDestination() {
            Text("cur page is PageOne")
            Text("enter page two").onClick {
                evt => pageInfos.pushPath(NavPathInfo(name:"pageTwo",param:""))
            }
        }
        .onReady {
            context => pageInfos=context.pathStack
        }
        .onBackPressed {
            pageInfos.pop()
            true
        }
    }

    private var memLeakMark: Option<MemLeakMark> = None
    protected override func aboutToDisappear() {
        this.memLeakMark = MemLeakMark()
        collectDestroyedComponent(this.memLeakMark.getOrThrow(), this)
    }
}

@Component
class PageTwo{
    var pageInfos:NavPathStack = NavPathStack()
    public func build() {
        NavDestination() {
            Text("cur page is PageTwo")
            Text("enter page one").onClick {
                evt => pageInfos.pushPath(NavPathInfo(name:"pageOne",param:""))
            }
        }
        .onReady {
            context => pageInfos=context.pathStack
        }
        .onBackPressed {
            pageInfos.pop()
            true
        }
    }

    private var memLeakMark: Option<MemLeakMark> = None
    protected override func aboutToDisappear() {
        this.memLeakMark = MemLeakMark()
        collectDestroyedComponent(this.memLeakMark.getOrThrow(), this)
    }
}

// ===================== White Screen Test Pages =====================

var blankPageNavStack: ?NavPathStack = None
var blankPageInstance: ?BlankPage = None
var switchResultBlankPageInstance: ?SwitchResultBlankPage = None

const PAGE_OPEN_TTID_BLOCK_MS: Int64 = 1500i64
const WHITE_SCREEN_RECOVERY_STAY_MS: Int64 = 1200i64

private func blankPagePopTimer(_: Array<String>): Unit {
    if (let Some(stack) <- blankPageNavStack) {
        stack.pop()
    }
}

private func parseDurationMs(paramStr: String, defaultDurationMs: Int64, pageName: String): Int64 {
    if (!paramStr.isEmpty()) {
        try {
            return Int64.parse(paramStr)
        } catch (e: Exception) {
            AppLog.warn("Invalid duration param for ${pageName}, using default ${defaultDurationMs}ms")
        }
    }
    defaultDurationMs
}

private func blockUiThreadMs(durationMs: Int64): Unit {
    if (durationMs <= 0) {
        return
    }

    let startNs = DateTime.now().toUnixTimeStamp().toNanoseconds()
    let waitNs = durationMs * 1_000_000i64
    while (DateTime.now().toUnixTimeStamp().toNanoseconds() - startNs < waitNs) {
    }
}

private func blankPageRevealTimer(_: Array<String>): Unit {
    if (let Some(page) <- blankPageInstance) {
        page.revealContent()
    }
}

private func blankPageReturnTimer(_: Array<String>): Unit {
    if (let Some(page) <- blankPageInstance) {
        page.returnToPrevPage()
    }
}

private func switchResultBlankPageRevealTimer(_: Array<String>): Unit {
    if (let Some(page) <- switchResultBlankPageInstance) {
        page.revealContent()
    }
}

private func switchResultBlankPageReturnTimer(_: Array<String>): Unit {
    if (let Some(page) <- switchResultBlankPageInstance) {
        page.returnToPrevPage()
    }
}

@Component
class BlankPage {
    @State
    var contentReady: Bool = false
    var pageInfos: NavPathStack = NavPathStack()
    var revealTimerId: Int64 = -1
    var returnTimerId: Int64 = -1

    public func revealContent(): Unit {
        if (contentReady) {
            return
        }

        contentReady = true
        if (revealTimerId != -1) {
            clearTimeout(revealTimerId)
            revealTimerId = -1
        }

        returnTimerId = setTimeout(blankPageReturnTimer, WHITE_SCREEN_RECOVERY_STAY_MS, Array<String>())
    }

    public func returnToPrevPage(): Unit {
        if (returnTimerId != -1) {
            clearTimeout(returnTimerId)
            returnTimerId = -1
        }
        pageInfos.pop()
    }

    public func build() {
        NavDestination() {
            Stack() {
                Row() {
                }
                .width(100.percent)
                .height(100.percent)
                .backgroundColor(0xFFFFFF)

                if (contentReady) {
                    Column() {
                        Text("Recovered From Page-Open White Screen")
                            .fontSize(22)
                            .fontWeight(FontWeight.Medium)
                            .margin(bottom: 10)
                        Text("This demo blocks the UI thread before the first frame to trigger TTID timeout.")
                            .fontSize(16)
                            .fontColor(0x3D4A5D)
                            .margin(bottom: 10)
                        Text("If MetricX is working, blankPage should report PAGE_OPEN + TIMEOUT.")
                            .fontSize(15)
                            .fontColor(0x56657A)
                    }
                    .width(100.percent)
                    .height(100.percent)
                    .padding(24)
                    .backgroundColor(0xF3F8FF)
                }
            }
            .width(100.percent)
            .height(100.percent)
            .backgroundColor(0xFFFFFF)
            .id("whiteScreenTestRoot")
        }
        .hideTitleBar(true)
        .onReady {
            context => 
            pageInfos = context.pathStack
            blankPageInstance = this
            contentReady = false

            let whiteDurationMs = parseDurationMs(context.pathInfo.param, 6000, "blankPage")
            var blockDurationMs = PAGE_OPEN_TTID_BLOCK_MS
            if (whiteDurationMs < blockDurationMs) {
                blockDurationMs = whiteDurationMs
            }

            blockUiThreadMs(blockDurationMs)

            let remainingWhiteMs = whiteDurationMs - blockDurationMs
            if (remainingWhiteMs <= 0) {
                revealContent()
            } else {
                revealTimerId = setTimeout(blankPageRevealTimer, remainingWhiteMs, Array<String>())
            }
        }
        .onBackPressed {
            if (revealTimerId != -1) {
                clearTimeout(revealTimerId)
                revealTimerId = -1
            }
            if (returnTimerId != -1) {
                clearTimeout(returnTimerId)
                returnTimerId = -1
            }
            pageInfos.pop()
            true
        }
    }

    protected override func aboutToDisappear() {
        if (revealTimerId != -1) {
            clearTimeout(revealTimerId)
        }
        if (returnTimerId != -1) {
            clearTimeout(returnTimerId)
        }
        blankPageInstance = None
    }
}

@Component
class HalfBlankPage {
    var pageInfos: NavPathStack = NavPathStack()
    var timerId: Int64 = -1

    public func build() {
        NavDestination() {
            Column() {
                Row() {
                }
                .width(100.percent)
                .height(50.percent)
                .backgroundColor(0x000000)

                Row() {
                }
                .width(100.percent)
                .height(50.percent)
                .backgroundColor(0xFFFFFF)
            }
            .width(100.percent)
            .height(100.percent)
            .id("whiteScreenTestRoot")
        }
        .hideTitleBar(true)
        .onReady {
            context => 
            pageInfos = context.pathStack
            blankPageNavStack = context.pathStack
            
            let durationMs = parseDurationMs(context.pathInfo.param, 6000, "halfBlankPage")
            timerId = setTimeout(blankPagePopTimer, durationMs, Array<String>())
        }
        .onBackPressed {
            if (timerId != -1) {
                clearTimeout(timerId)
            }
            pageInfos.pop()
            true
        }
    }

    protected override func aboutToDisappear() {
        if (timerId != -1) {
            clearTimeout(timerId)
        }
        blankPageNavStack = None
    }
}

@Component
class ImagePage {
    var pageInfos: NavPathStack = NavPathStack()
    var timerId: Int64 = -1

    public func build() {
        NavDestination() {
            Stack() {
                Image("https://pic.baike.soso.com/ugc/baikepic2/17155/20220223180002-2131977287_png_512_512_124034.jpg/0")
                    .width(100.percent)
                    .height(100.percent)
                    .objectFit(ImageFit.Cover)
            }
            .width(100.percent)
            .height(100.percent)
            .id("whiteScreenTestRoot")
        }
        .hideTitleBar(true)
        .onReady {
            context =>
            pageInfos = context.pathStack
            blankPageNavStack = context.pathStack

            let durationMs = parseDurationMs(context.pathInfo.param, 8000, "imagePage")
            timerId = setTimeout(blankPagePopTimer, durationMs, Array<String>())
        }
        .onBackPressed {
            if (timerId != -1) {
                clearTimeout(timerId)
            }
            pageInfos.pop()
            true
        }
    }

    protected override func aboutToDisappear() {
        if (timerId != -1) {
            clearTimeout(timerId)
        }
        blankPageNavStack = None
    }
}

var slowImagePageInstance: ?SlowImagePage = None

private func slowImageShowTimer(_: Array<String>): Unit {
    if (let Some(page) <- slowImagePageInstance) {
        page.setShowImage(true)
    }
}

private func slowImageReturnTimer(_: Array<String>): Unit {
    if (let Some(page) <- slowImagePageInstance) {
        page.returnToPrevPage()
    }
}

var slowLoadPageInstance: ?SlowLoadPage = None

private func slowLoadAnimationTimer(_: Array<String>): Unit {
    if (let Some(page) <- slowLoadPageInstance) {
        page.advanceLoading()
    }
}

private func slowLoadContentTimer(_: Array<String>): Unit {
    if (let Some(page) <- slowLoadPageInstance) {
        page.finishLoading()
    }
}

private func slowLoadReturnTimer(_: Array<String>): Unit {
    if (let Some(page) <- slowLoadPageInstance) {
        page.returnToPrevPage()
    }
}

@Component
class SlowImagePage {
    @State
    var showImage: Bool = false
    var pageInfos: NavPathStack = NavPathStack()
    var timerId: Int64 = -1
    var returnTimerId: Int64 = -1

    public func setShowImage(value: Bool): Unit {
        showImage = value
        if (value) {
            if (returnTimerId != -1) {
                clearTimeout(returnTimerId)
            }
            returnTimerId = setTimeout(slowImageReturnTimer, 1000, Array<String>())
        }
    }

    public func returnToPrevPage(): Unit {
        if (returnTimerId != -1) {
            clearTimeout(returnTimerId)
            returnTimerId = -1
        }
        pageInfos.pop()
    }

    public func build() {
        NavDestination() {
            Stack() {
                Row() {
                }
                .width(100.percent)
                .height(100.percent)
                .backgroundColor(0xFFFFFF)

                if (showImage) {
                    Image("https://pic.baike.soso.com/ugc/baikepic2/17155/20220223180002-2131977287_png_512_512_124034.jpg/0")
                        .width(100.percent)
                        .height(100.percent)
                        .objectFit(ImageFit.Cover)
                }
            }
            .width(100.percent)
            .height(100.percent)
            .backgroundColor(0xFFFFFF)
            .id("whiteScreenTestRoot")
        }
        .hideTitleBar(true)
        .onReady {
            context =>
            pageInfos = context.pathStack
            slowImagePageInstance = this
            showImage = false

            var delayMs: Int64 = 8000
            let paramStr = context.pathInfo.param
            if (!paramStr.isEmpty()) {
                try {
                    delayMs = Int64.parse(paramStr)
                } catch (e: Exception) {
                    AppLog.warn("Invalid delay param, using default 8000ms")
                }
            }

            timerId = setTimeout(slowImageShowTimer, delayMs, Array<String>())
        }
        .onBackPressed {
            if (timerId != -1) {
                clearTimeout(timerId)
            }
            if (returnTimerId != -1) {
                clearTimeout(returnTimerId)
            }
            pageInfos.pop()
            true
        }
    }

    protected override func aboutToDisappear() {
        if (timerId != -1) {
            clearTimeout(timerId)
        }
        if (returnTimerId != -1) {
            clearTimeout(returnTimerId)
        }
        slowImagePageInstance = None
    }
}

@Component
class SlowLoadPage {
    @State
    var loadingStep: Int64 = 0
    @State
    var contentReady: Bool = false
    var pageInfos: NavPathStack = NavPathStack()
    var animationTimerId: Int64 = -1
    var contentTimerId: Int64 = -1
    var returnTimerId: Int64 = -1

    public func loadingLabel(): String {
        match (loadingStep) {
            case 0 => "Loading"
            case 1 => "Loading."
            case 2 => "Loading.."
            case _ => "Loading..."
        }
    }

    public func advanceLoading(): Unit {
        if (contentReady) {
            return
        }

        loadingStep = (loadingStep + 1) % 4
        animationTimerId = setTimeout(slowLoadAnimationTimer, 180, Array<String>())
    }

    public func finishLoading(): Unit {
        if (contentReady) {
            return
        }

        contentReady = true
        if (animationTimerId != -1) {
            clearTimeout(animationTimerId)
            animationTimerId = -1
        }
        returnTimerId = setTimeout(slowLoadReturnTimer, 1500, Array<String>())
    }

    public func returnToPrevPage(): Unit {
        if (returnTimerId != -1) {
            clearTimeout(returnTimerId)
            returnTimerId = -1
        }
        pageInfos.pop()
    }

    public func build() {
        NavDestination() {
            Stack() {
                Column() {
                    if (!contentReady) {
                        Text(loadingLabel())
                            .fontSize(24)
                            .fontWeight(FontWeight.Medium)
                            .margin(bottom: 16)

                        Row() {
                            Row().width(52).height(12).backgroundColor(0xE8E8E8).borderRadius(6)
                            Row().width(120).height(12).backgroundColor(0xD8D8D8).borderRadius(6).margin(top: 12)
                            Row().width(88).height(12).backgroundColor(0xE8E8E8).borderRadius(6).margin(top: 12)
                        }
                        .width(100.percent)
                        .margin(bottom: 24)

                        Text("Content is still loading, but frames keep updating.")
                            .fontSize(16)
                            .fontColor(0x666666)
                    } else {
                        Image("https://pic.baike.soso.com/ugc/baikepic2/17155/20220223180002-2131977287_png_512_512_124034.jpg/0")
                            .width(100.percent)
                            .height(220)
                            .objectFit(ImageFit.Cover)
                            .margin(bottom: 18)
                        Text("Content loaded")
                            .fontSize(22)
                            .fontWeight(FontWeight.Medium)
                            .margin(bottom: 8)
                        Text("This page simulates a slow-loading business page.")
                            .fontSize(16)
                            .fontColor(0x666666)
                    }
                }
                .width(100.percent)
                .height(100.percent)
                .padding(24)
                .backgroundColor(0xFFFFFF)
            }
            .width(100.percent)
            .height(100.percent)
            .id("whiteScreenTestRoot")
        }
        .hideTitleBar(true)
        .onReady {
            context =>
            pageInfos = context.pathStack
            slowLoadPageInstance = this
            loadingStep = 0
            contentReady = false

            var delayMs: Int64 = 8000
            let paramStr = context.pathInfo.param
            if (!paramStr.isEmpty()) {
                try {
                    delayMs = Int64.parse(paramStr)
                } catch (e: Exception) {
                    AppLog.warn("Invalid delay param, using default 8000ms")
                }
            }

            animationTimerId = setTimeout(slowLoadAnimationTimer, 180, Array<String>())
            contentTimerId = setTimeout(slowLoadContentTimer, delayMs, Array<String>())
        }
        .onBackPressed {
            if (animationTimerId != -1) {
                clearTimeout(animationTimerId)
            }
            if (contentTimerId != -1) {
                clearTimeout(contentTimerId)
            }
            if (returnTimerId != -1) {
                clearTimeout(returnTimerId)
            }
            pageInfos.pop()
            true
        }
    }

    protected override func aboutToDisappear() {
        if (animationTimerId != -1) {
            clearTimeout(animationTimerId)
        }
        if (contentTimerId != -1) {
            clearTimeout(contentTimerId)
        }
        if (returnTimerId != -1) {
            clearTimeout(returnTimerId)
        }
        slowLoadPageInstance = None
    }
}

@Component
class PageOpenTriggerPage {
    var pageInfos: NavPathStack = NavPathStack()

    public func build() {
        NavDestination() {
            Column() {
                Text("Page-open white screen trigger page")
                    .fontSize(20)
                    .margin(bottom: 12)
                Text("Expected Positive means the detector should report white screen.")
                    .fontSize(16)
                    .margin(bottom: 8)
                Text("Control pages are for contrast and should not be treated as real white screens.")
                    .fontSize(15)
                    .fontColor(0x666666)
                    .margin(bottom: 20)
                Button("Go To TTID Timeout White Screen").onClick {
                    => this.pageInfos.pushPath(NavPathInfo(name: "blankPage", param: "8000"))
                }
                Button("Go To Half Blank Control Page").margin(top: 12).onClick {
                    => this.pageInfos.pushPath(NavPathInfo(name: "halfBlankPage", param: "8000"))
                }
                Button("Go To Image Control Page").margin(top: 12).onClick {
                    => this.pageInfos.pushPath(NavPathInfo(name: "imagePage", param: "8000"))
                }
                Button("Go To Delayed Image Page (Experimental)").margin(top: 12).onClick {
                    => this.pageInfos.pushPath(NavPathInfo(name: "slowImagePage", param: "8000"))
                }
                Button("Go To Slow Load Control Page").margin(top: 12).onClick {
                    => this.pageInfos.pushPath(NavPathInfo(name: "slowLoadPage", param: "8000"))
                }
                Button("Back To Home").margin(top: 16).onClick {
                    => this.pageInfos.pop()
                }
            }
            .width(100.percent)
            .height(100.percent)
            .padding(24)
            .backgroundColor(0xF5F5F5)
        }
        .hideTitleBar(true)
        .onReady {
            context => pageInfos = context.pathStack
        }
        .onBackPressed {
            pageInfos.pop()
            true
        }
    }
}

@Component
class SwitchResultTriggerPage {
    var pageInfos: NavPathStack = NavPathStack()

    public func build() {
        NavDestination() {
            Column() {
                Text("Switch-result white screen trigger page")
                    .fontSize(20)
                    .margin(bottom: 12)
                Text("The first button keeps the next page white for a while before real content appears.")
                    .fontSize(16)
                    .margin(bottom: 8)
                Text("Other buttons are contrast pages for manual comparison.")
                    .fontSize(15)
                    .fontColor(0x666666)
                    .margin(bottom: 20)
                Button("Go To Switch-Result White Screen").onClick {
                    => this.pageInfos.pushPath(NavPathInfo(name: "switchResultBlankPage", param: "8000"))
                }
                Button("Go To Switch-Result Half Blank Control").margin(top: 12).onClick {
                    => this.pageInfos.pushPath(NavPathInfo(name: "halfBlankPage", param: "8000"))
                }
                Button("Go To Switch-Result Image Control").margin(top: 12).onClick {
                    => this.pageInfos.pushPath(NavPathInfo(name: "imagePage", param: "8000"))
                }
                Button("Go To Switch-Result Delayed Image").margin(top: 12).onClick {
                    => this.pageInfos.pushPath(NavPathInfo(name: "slowImagePage", param: "8000"))
                }
                Button("Go To Switch-Result Slow Load Control").margin(top: 12).onClick {
                    => this.pageInfos.pushPath(NavPathInfo(name: "slowLoadPage", param: "8000"))
                }
                Button("Back To Home").margin(top: 16).onClick {
                    => this.pageInfos.pop()
                }
            }
            .width(100.percent)
            .height(100.percent)
            .padding(24)
            .backgroundColor(0xF5F5F5)
        }
        .hideTitleBar(true)
        .onReady {
            context => pageInfos = context.pathStack
        }
        .onBackPressed {
            pageInfos.pop()
            true
        }
    }
}

@Component
class SwitchResultBlankPage {
    @State
    var contentReady: Bool = false
    var pageInfos: NavPathStack = NavPathStack()
    var revealTimerId: Int64 = -1
    var returnTimerId: Int64 = -1

    public func revealContent(): Unit {
        if (contentReady) {
            return
        }

        contentReady = true
        if (revealTimerId != -1) {
            clearTimeout(revealTimerId)
            revealTimerId = -1
        }

        returnTimerId = setTimeout(switchResultBlankPageReturnTimer, WHITE_SCREEN_RECOVERY_STAY_MS, Array<String>())
    }

    public func returnToPrevPage(): Unit {
        if (returnTimerId != -1) {
            clearTimeout(returnTimerId)
            returnTimerId = -1
        }
        pageInfos.pop()
    }

    public func build() {
        NavDestination() {
            Stack() {
                Row() {
                }
                .width(100.percent)
                .height(100.percent)
                .backgroundColor(0xFFFFFF)

                if (contentReady) {
                    Column() {
                        Text("Recovered From Switch-Result White Screen")
                            .fontSize(22)
                            .fontWeight(FontWeight.Medium)
                            .margin(bottom: 10)
                        Text("The destination page stayed fully white before business content appeared.")
                            .fontSize(16)
                            .fontColor(0x3D4A5D)
                            .margin(bottom: 10)
                        Text("If MetricX is working, switchResultBlankPage should report PAGE_SWITCH_RESULT + CONTENT_MISSING.")
                            .fontSize(15)
                            .fontColor(0x56657A)
                    }
                    .width(100.percent)
                    .height(100.percent)
                    .padding(24)
                    .backgroundColor(0xF6FBFF)
                }
            }
            .width(100.percent)
            .height(100.percent)
            .backgroundColor(0xFFFFFF)
            .id("whiteScreenTestRoot")
        }
        .hideTitleBar(true)
        .onReady {
            context =>
            pageInfos = context.pathStack
            switchResultBlankPageInstance = this
            contentReady = false

            let durationMs = parseDurationMs(context.pathInfo.param, 8000, "switchResultBlankPage")
            revealTimerId = setTimeout(switchResultBlankPageRevealTimer, durationMs, Array<String>())
        }
        .onBackPressed {
            if (revealTimerId != -1) {
                clearTimeout(revealTimerId)
                revealTimerId = -1
            }
            if (returnTimerId != -1) {
                clearTimeout(returnTimerId)
                returnTimerId = -1
            }
            pageInfos.pop()
            true
        }
    }

    protected override func aboutToDisappear() {
        if (revealTimerId != -1) {
            clearTimeout(revealTimerId)
        }
        if (returnTimerId != -1) {
            clearTimeout(returnTimerId)
        }
        switchResultBlankPageInstance = None
    }
}

// ===================== Crash / OOM Test Helpers =====================

func crash() {
    let xxx = 1
    var flag = 10
    for (i in 0..10) {
        flag--
    }
    let qqq = xxx / flag
}

foreign func Crash(): Unit

func oom() {
    let arr = ArrayList<Int64>(4200000000000)
}


// ===================== Multi-Thread CPU Heating =====================

var burnRunning: Bool = false
var burnFutures: ArrayList<Future<Unit>> = ArrayList<Future<Unit>>()

const THREAD_COUNT: Int64 = 6i64   // 直接写死
const BURN_LOOP_COUNT: Int64 = 80_000_000i64

public func startCpuBurnMulti(): Unit {
    if (burnRunning) {
        AppLog.info("CPU burn already running")
        return
    }

    burnRunning = true
    burnFutures.clear()

    AppLog.info("Starting CPU burn with ${THREAD_COUNT} threads")

    for (n in 1i64..THREAD_COUNT) {
        let future = spawn {
            =>
            var x: Int64 = 1

            while (burnRunning) {
                for (i in 1i64..BURN_LOOP_COUNT) {
                    x = (x * 1664525 + 1013904223 + i) & 0xffffffff
                }
            }

            ()
        }

        burnFutures.add(future)
    }
}

public func stopCpuBurnMulti(): Unit {
    if (!burnRunning) {
        AppLog.info("CPU burn not running")
        return
    }

    burnRunning = false

    for (f in burnFutures) {
        try { f.cancel() } catch (_: Exception) {}
    }

    burnFutures.clear()

    AppLog.info("CPU burn stopped")
}