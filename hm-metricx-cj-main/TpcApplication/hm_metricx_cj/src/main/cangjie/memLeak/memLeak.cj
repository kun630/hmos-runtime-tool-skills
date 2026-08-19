/*
 * Copyright (c) Huawei Technologies Co., Ltd. 2025-2025. All rights reserved.
 */
package ohos_app_cangjie_hm_metricx_cj.memLeak

import ohos.component.CustomView
import std.ref.WeakRef
import std.ref.CleanupPolicy
import std.collection.*
import std.reflect.TypeInfo
import ohos_app_cangjie_hm_metricx_cj.util.*
import tpc.UIKit.Observer.{NavDestinationSwitchInfo, on, ObserverListenerType}
import tpc.AbilityKit.UIAbilityContext
import tpc.UIKit.global.*
import std.runtime.gc
import std.runtime.dumpHeapData
import std.sync.Timer
import std.fs.*
import std.env.*
import ohos.base.AppLog

public class MemLeakMark {}

class Component {
    public Component(let weakRefObj: WeakRef<MemLeakMark>, let typeInfo: String) {}
}

public class PageInfo {
    public PageInfo(let fromPage: String, let toPage: String) {}
}

var inited = false
let aliveComponents: List<Component> = ArrayList<Component>()
var reportMemLeakCallback: (Path) -> Unit = {path: Path =>}
var needDumpSnapshotInfo: (PageInfo, List<String>) -> Bool = {pageInfo, arr => true}
var _clearHistoryComponentInfo: (List<String>) -> Bool = {arr => true}
var currentPageName: String = defaultPageName
var dumpDirStr: String = ""

public func collectDestroyedComponent(memLeakMark: MemLeakMark, customView: CustomView) {
    if (!inited) {
        AppLog.warn("hm-metricx-cj warn: memLeak does not init.")
        return
    }
    let weakRefObj = WeakRef<MemLeakMark>(memLeakMark, CleanupPolicy.EAGER)
    let typeInfo = TypeInfo.of(customView).toString()
    aliveComponents.add(Component(weakRefObj, typeInfo))
}

let pageSwitchCallback: PageSwitchCallBack = PageSwitchCallBack(
    {
        info: NavDestinationSwitchInfo =>
            let fromPage = currentPageName
            currentPageName = getTargetPageName(info, defaultName: currentPageName)
            let toPage = currentPageName
            let arguments: Array<String> = [fromPage, toPage]
            setTimeout(handleMemLeak, 1000, arguments)
    }
)

private func handleMemLeak(array: Array<String>): Unit {
    if (array.size < 2) {
        AppLog.warn("hm-metricx-cj error: handleMemLeak func did not receive the page switching parameter.")
        return
    }
    let fromPage = array[0]
    let toPage = array[1]

    aliveComponents.removeIf({data => data.weakRefObj.value.isNone()})
    if (aliveComponents.isEmpty()) {
        return
    }
    gc(heavy: true)
    Timer.once(Duration.second) {
        aliveComponents.removeIf({data => data.weakRefObj.value.isNone()})
        if (aliveComponents.isEmpty()) {
            return
        }
        let typeInfos = collectArrayList(aliveComponents.iterator().map({data => data.typeInfo}))
        let needDump = needDumpSnapshotInfo(PageInfo(fromPage, toPage), typeInfos)
        let shouldClear = _clearHistoryComponentInfo(typeInfos)
        if (shouldClear) {
            aliveComponents.clear()
        }
        if (!needDump) {
            return
        }
        let curTimestamp: String = getCurTimestampMillis()
        let dumpSnapshotPath = Path(dumpDirStr).join("memLeakSnapshot_${curTimestamp}.data")
        spawn {
            =>
                dumpHeapData(dumpSnapshotPath)
                reportMemLeakCallback(dumpSnapshotPath)
        }
    }
}

public func initMemLeakHandler(
    context: UIAbilityContext,
    persistentDir: Path,
    needDumpSnapshot: (pageInfo: PageInfo, typeInfos: List<String>) -> Bool,
    clearHistoryComponentInfo: (typeInfos: List<String>) -> Bool,
    reportMemLeak: (path: Path) -> Unit
) {
    dumpDirStr = persistentDir.toString()
    reportMemLeakCallback = reportMemLeak
    needDumpSnapshotInfo = needDumpSnapshot
    _clearHistoryComponentInfo = clearHistoryComponentInfo
    on(navDestinationSwitch, context, pageSwitchCallback)
    inited = true
}

@When[os == "Windows"]
const CJPROF_NAME: String = "cjprof.exe"
@When[os != "Windows"]
const CJPROF_NAME: String = "cjprof"
@When[os == "Windows"]
const NEW_LINE: String = "\r\n"
@When[os != "Windows"]
const NEW_LINE: String = "\n"

func analyzeCjprofRoot(output: String): ArrayList<String> {
    let items: ArrayList<String> = ArrayList<String>()
    var item: String = ""
    let lines: Array<String> = output.split(NEW_LINE, removeEmpty: true)
    for (i in 0..lines.size) {
        let line: String = lines[i]
        if (!line.contains("@")) {
            continue
        }
        if (line.startsWith(" ")) {
            if (!item.isEmpty()) {
                item += NEW_LINE + line
            }
        } else {
            if (item.contains("[ROOT")) {
                items.add(item)
            }
            item = line
        }
    }
    if (item.contains("[ROOT")) {
        items.add(item)
    }
    items
}

public func analyzeComponentMemLeak(dumpFilePath: Path): Option<ArrayList<String>> {
    if (!exists(dumpFilePath)) {
        AppLog.warn("hm-metricx-cj warn: ${dumpFilePath.toString()} does not exit.")
        return None
    }
    if (getVariable("CANGJIE_HOME").isNone()) {
        AppLog.warn("hm-metricx-cj warn: cannot find CANGJIE_HOME, please make sure cangjie sdk is configured.")
        return None
    }
    var (flag, output, errlog) = execWithOutput(CJPROF_NAME, ArrayList<String>(["-v"]))
    if (!flag) {
        AppLog.warn("hm-metricx-cj warn: failed to run ${CJPROF_NAME} -v, error: ${errlog}")
        return None
    }

    (flag, output, errlog) = execWithOutput(CJPROF_NAME, ArrayList<String>(["heap", "-i", dumpFilePath.toString(), "--show-reference"]))
    if (!flag) {
        AppLog.warn("hm-metricx-cj warn: failed to run cjprof heap -i ${dumpFilePath.toString()} --show-reference, error: ${errlog}")
        return None
    }
    analyzeCjprofRoot(output)
}
