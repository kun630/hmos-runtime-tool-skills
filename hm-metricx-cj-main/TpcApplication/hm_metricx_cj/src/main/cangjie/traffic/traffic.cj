/*
 * Copyright (c) Huawei Technologies Co., Ltd. 2025-2025. All rights reserved.
 * Co-Author: AI
 */
package ohos_app_cangjie_hm_metricx_cj.traffic

import tpc.AbilityKit.bundleManager
import tpc.AbilityKit.bundleManager.BundleFlag
import tpc.AbilityKit.UIAbilityContext
import tpc.NetworkKit.statistics
import ohos.base.BusinessException
import tpc.ArkData.preferences
import tpc.ArkData.preferences.*
import tpc.UIKit.global.*
import stdx.encoding.json.*
import std.collection.*
import std.convert.*
import ohos.base.AppLog
import tpc.UIKit.Observer.{NavDestinationSwitchInfo, on, ObserverListenerType}
import ohos_app_cangjie_hm_metricx_cj.util.*

let pageTrafficMap: HashMap<String, PageTrafficInfo> = HashMap<String, PageTrafficInfo>()
let uid: UInt32 = GetAppUid()
var pageRxStart: Int64 = 0
var pageTxStart: Int64 = 0
var prevUpload: Int64 = 0
var prevDownload: Int64 = 0
var inited: Bool = false
var uiContext: Option<UIAbilityContext> = None
var currentPageName = defaultPageName
var DAY_SAMPLE_TIME: Int64 = 30 * 1000
var SAMPLE_TIME: Int64 = 0
var SAMPLE_THRESHOLD: Int64 = 0
var sampleId: Int64 = -1
var sampleDayId: Int64 = -1
var reportTrafficCallback: (sampleTrafficInfo: SampleTrafficInfo) -> Unit = {
    sampleTrafficInfo: SampleTrafficInfo =>
}

// current value, will not remove
private let KEY_CURRENT_UPLOAD: String = "current_upload"
private let KEY_CURRENT_DOWNLOAD: String = "current_download"
// today
private let KEY_TODAY_DATE: String = "today_date"
private let KEY_TODAY_UPLOAD: String = "today_upload"
private let KEY_TODAY_DOWNLOAD: String = "today_download"
// last report day
private let KEY_LAST_REPORT_DAY: String = "last_report_day"

public func GetAppUid(): UInt32 {
    let flag = BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION
    let bundleInfo = bundleManager.getBundleInfoForSelf(flag)
    let uid = bundleInfo.appInfo.getOrThrow().uid
    UInt32(uid)
}

public open class TrafficInfo {
    private var totalValue: Int64 = 0
    private var upTotalValue: Int64 = 0
    private var downTotalValue: Int64 = 0
    public init() {}
    public init(upTotalValue: Int64, downTotalValue: Int64) {
        this.upTotalValue = upTotalValue
        this.downTotalValue = downTotalValue
        this.totalValue = upTotalValue + downTotalValue
    }
    public prop total: Int64 {
        get() {
            totalValue
        }
    }
    public mut prop upTotal: Int64 {
        get() {
            upTotalValue
        }
        set(value) {
            upTotalValue = value
            totalValue = upTotalValue + downTotalValue
        }
    }
    public mut prop downTotal: Int64 {
        get() {
            downTotalValue
        }
        set(value) {
            downTotalValue = value
            totalValue = upTotalValue + downTotalValue
        }
    }
}

public class SystemTrafficInfo <: TrafficInfo {
    private var timeStampValue: String = ""

    public init() {}
    public init(timeStamp: String, upload: Int64, download: Int64) {
        super(upload, download)
        this.timeStampValue = timeStamp
    }

    public mut prop timeStamp: String {
        get() {
            timeStampValue
        }
        set(value) {
            timeStampValue = value
        }
    }
    public func toString() {
        let jsonObj = JsonObject()
        jsonObj.put("timeStamp", JsonString(timeStampValue))
        jsonObj.put("total", JsonString(total.toString()))
        jsonObj.put("upTotal", JsonString(upTotal.toString()))
        jsonObj.put("downTotal", JsonString(downTotal.toString()))
        jsonObj.toString()
    }
}

public class PageTrafficInfo <: TrafficInfo {
    private var pageNameValue: String = ""

    public init() {}
    public init(pageName: String, upload: Int64, download: Int64) {
        super(upload, download)
        this.pageNameValue = pageName
    }

    public mut prop pageName: String {
        get() {
            pageNameValue
        }
        set(value) {
            pageNameValue = value
        }
    }
    public func toString() {
        let jsonObj = JsonObject()
        jsonObj.put("pageName", JsonString(pageNameValue))
        jsonObj.put("total", JsonString(total.toString()))
        jsonObj.put("upTotal", JsonString(upTotal.toString()))
        jsonObj.put("downTotal", JsonString(downTotal.toString()))
        jsonObj.toString()
    }
}

public class DayTrafficInfo <: TrafficInfo {
    private var dateValue: String = ""

    public init() {}
    public init(date: String, upload: Int64, download: Int64) {
        super(upload, download)
        this.date = date
    }

    public mut prop date: String {
        get() {
            dateValue
        }
        set(value) {
            dateValue = value
        }
    }
    public func toString() {
        let jsonObj = JsonObject()
        jsonObj.put("date", JsonString(dateValue))
        jsonObj.put("total", JsonString(total.toString()))
        jsonObj.put("upTotal", JsonString(upTotal.toString()))
        jsonObj.put("downTotal", JsonString(downTotal.toString()))
        jsonObj.toString()
    }
}

public class UrlTrafficInfo <: TrafficInfo {
    private var urlValue: String = ""

    public init() {}
    public init(url: String, upload: Int64, download: Int64) {
        super(upload, download)
        this.url = url
    }

    public mut prop url: String {
        get() {
            urlValue
        }
        set(value) {
            urlValue = value
        }
    }

    public func toString() {
        let jsonObj = JsonObject()
        jsonObj.put("url", JsonString(urlValue))
        jsonObj.put("total", JsonString(total.toString()))
        jsonObj.put("upTotal", JsonString(upTotal.toString()))
        jsonObj.put("downTotal", JsonString(downTotal.toString()))
        jsonObj.toString()
    }

    public static func fromString(data: String, splitStr!: String = ","): UrlTrafficInfo {
        let urlInfo: UrlTrafficInfo = UrlTrafficInfo()
        let items: Array<String> = data.split(splitStr, removeEmpty: true)
        if (items.size >= 3) {
            urlInfo.url = items[0]
            urlInfo.upTotal = Int64.tryParse(items[1]).getOrDefault({=> 0})
            urlInfo.downTotal = Int64.tryParse(items[2]).getOrDefault({=> 0})
        }
        urlInfo
    }
}

public class SampleTrafficInfo {
    private var systemInfoValue: SystemTrafficInfo = SystemTrafficInfo()
    private var pageInfoMapValue: HashMap<String, PageTrafficInfo> = HashMap<String, PageTrafficInfo>()
    private var urlInfoArrayValue: ArrayList<UrlTrafficInfo> = ArrayList<UrlTrafficInfo>()
    public init() {}

    public init(systemInfo: SystemTrafficInfo, pageInfoMap: HashMap<String, PageTrafficInfo>,
        urlInfoArray: ArrayList<UrlTrafficInfo>) {
        systemInfoValue = systemInfo
        pageInfoMapValue = pageInfoMap
        urlInfoArrayValue = urlInfoArray
    }
    public mut prop systemInfo: SystemTrafficInfo {
        get() {
            systemInfoValue
        }
        set(value) {
            systemInfoValue = value
        }
    }
    public mut prop pageInfoMap: HashMap<String, PageTrafficInfo> {
        get() {
            pageInfoMapValue
        }
        set(value) {
            pageInfoMapValue = value
        }
    }
    public mut prop urlInfoArray: ArrayList<UrlTrafficInfo> {
        get() {
            urlInfoArrayValue
        }
        set(value) {
            urlInfoArrayValue = value
        }
    }
}

private func setStoredData(key: String, value: String): Bool {
    var status: Bool = false
    try {
        let options = preferences.Options("Traffic")
        let dataPreferences = preferences.getPreferences(uiContext.getOrThrow(), options)
        dataPreferences.put(key, preferences.ValueType.STRING(value))
        dataPreferences.flush({err, data =>})
        status = true
    } catch (e: Exception) {
        AppLog.warn(e.toString())
    }
    status
}

private func getStoredData(key: String): String {
    var value: String = ""
    try {
        let options = preferences.Options("Traffic")
        let dataPreferences = preferences.getPreferences(uiContext.getOrThrow(), options)
        let status: Bool = dataPreferences.has(key)
        if (status) {
            let val = dataPreferences.get(key, preferences.ValueType.STRING(""))
            match (val) {
                case preferences.ValueType.STRING(v) => value = v
                case _ => ()
            }
        }
    } catch (e: Exception) {
        AppLog.warn(e.toString())
    }
    value
}

public func initTrafficHandler(
    context: UIAbilityContext,
    reportTraffic: (sampleTraffixInfo: SampleTrafficInfo) -> Unit,
    reportYesterdayTraffic: (yesterdayTraffic: DayTrafficInfo) -> Unit,
    sampleTime!: Int64 = 10 * 60 * 1000,
    sampleThreshold!: Int64 = 50 * 1024 * 1024,
    daySampleTime!: Int64 = 30 * 1024
) {
    uiContext = context
    reportTrafficCallback = reportTraffic
    SAMPLE_TIME = sampleTime
    DAY_SAMPLE_TIME = daySampleTime
    SAMPLE_THRESHOLD = sampleThreshold
    let yesterdayTraffic = getYesterdayTraffic()
    if (let Some(v) <- yesterdayTraffic) {
        reportYesterdayTraffic(v)
    }
    doTrafficSample()
    on(navDestinationSwitch, uiContext.getOrThrow(), PageSwitchCallBack(navDestinationSwitchCallBack))
    sampleId = setInterval(doTrafficSample, SAMPLE_TIME, Array<String>())
    sampleDayId = setInterval(doDayTrafficSample, DAY_SAMPLE_TIME, Array<String>())
    spawn {
        unsafe {
            let initStatus: Int8 = InitTrafficNativeHandler()
            if (0 != initStatus) {
                AppLog.warn("hm_metricx_cj error: InitTrafficHandler failed.")
            }
        }
    }
}

private func processUidTrafficBytes(callback: (upload: Int64, download: Int64, pageName: String) -> Unit, pageName: String) {
    statistics.getUidRxBytes(
        uid,
        {
            err: ?BusinessException, data: ?Int64 =>
            if (let Some(v) <- err) {
                AppLog.warn("Rx error: ${v.toString()}")
                return
            }
            if (data.isNone()) {
                AppLog.warn("Rx data is none")
            }
            let curDownload = data ?? 0
            statistics.getUidTxBytes(
                uid,
                {
                    err: ?BusinessException, data: ?Int64 =>
                    if (let Some(v) <- err) {
                        AppLog.warn("Tx error: ${v.toString()}")
                        return
                    }
                    if (data.isNone()) {
                        AppLog.warn("Tx data is none")
                    }
                    let curUpload = data ?? 0
                    callback(curUpload, curDownload, pageName)
                }
            )
        }
    )
}

let updataPageMapCallback: (upload: Int64, download: Int64, pageName: String) -> Unit = {
    upload: Int64, download: Int64, pageName: String =>
    let curTx = upload - pageTxStart
    let curRx = download - pageRxStart
    updatePageMap(pageName, curTx, curRx)
    pageTxStart = upload
    pageRxStart = download
}

let updateDayTrafficCallback: (upload: Int64, download: Int64, pageName: String) -> Unit = {
    upload: Int64, download: Int64, pageName: String =>
    // upload
    let todayUpload: Int64 = Int64.tryParse(getStoredData(KEY_TODAY_UPLOAD)).getOrDefault({ => 0})
    let prevUpload: Int64 = Int64.tryParse(getStoredData(KEY_CURRENT_UPLOAD)).getOrDefault({ => 0})
    let newUpload: Int64 = todayUpload + upload - prevUpload
    // download
    let todayDownload: Int64 = Int64.tryParse(getStoredData(KEY_TODAY_DOWNLOAD)).getOrDefault({ => 0})
    let prevDownload: Int64 = Int64.tryParse(getStoredData(KEY_CURRENT_DOWNLOAD)).getOrDefault({ => 0})
    let newDownload: Int64 = todayDownload + download - prevDownload

    setStoredData(KEY_CURRENT_UPLOAD, upload.toString())
    setStoredData(KEY_CURRENT_DOWNLOAD, download.toString())
    if (prevUpload == 0 && prevDownload == 0) {
        AppLog.warn("hm_metricx_cj: first time only save value")
        return
    }

    setStoredData(KEY_TODAY_UPLOAD, newUpload.toString())
    setStoredData(KEY_TODAY_DOWNLOAD, newDownload.toString())
}

let sampleCallback: (upload: Int64, download: Int64, pageName: String) -> Unit = {
    upload: Int64, download: Int64, pageName: String =>
    if (!inited) {
        inited = true
    } else {
        let deltaUpload: Int64 = upload - prevUpload
        let deltaDownload: Int64 = download - prevDownload
        let delta: Int64 = deltaUpload + deltaDownload
        if (delta >= SAMPLE_THRESHOLD) {
            // update page traffic
            let curTx = upload - pageTxStart
            let curRx = download - pageRxStart
            updatePageMap(pageName, curTx, curRx)

            let curTimeStamp = getCurTimeStamp()
            let systemTrafficInfo: SystemTrafficInfo = SystemTrafficInfo(curTimeStamp, deltaUpload, deltaDownload)
            let urlInfoArray: ArrayList<UrlTrafficInfo> = getUrlTrafficInfo()
            let sampleTrafficInfo = SampleTrafficInfo(systemTrafficInfo, pageTrafficMap, urlInfoArray)
            reportTrafficCallback(sampleTrafficInfo)
        }
    }
    prevUpload = upload
    prevDownload = download
    pageTxStart = upload
    pageRxStart = download
    pageTrafficMap.clear()
    clearUrlTrafficInfo()
}

private func doTrafficSample(array: Array<String>) {
    processUidTrafficBytes(sampleCallback, currentPageName)
}

private func doDayTrafficSample(array: Array<String>) {
    processUidTrafficBytes(updateDayTrafficCallback, currentPageName)
}

private func navDestinationSwitchCallBack(info: NavDestinationSwitchInfo) {
    processUidTrafficBytes(updataPageMapCallback, currentPageName)
    currentPageName = getTargetPageName(info)
}

private func updatePageMap(pageName: String, curTx: Int64, curRx: Int64) {
    if (!pageTrafficMap.contains(pageName)) {
        let pageTrafficInfo = PageTrafficInfo(pageName, curTx, curRx)
        pageTrafficMap.add(pageName, pageTrafficInfo)
        return
    }
    let pageTrafficInfo = pageTrafficMap.get(pageName).getOrThrow()
    pageTrafficInfo.upTotal += curTx
    pageTrafficInfo.downTotal += curRx
}

private func getYesterdayTraffic(): Option<DayTrafficInfo> {
    var res: Option<DayTrafficInfo> = None
    let today: String = getTodayDate()
    let lastReportDay: String = getStoredData(KEY_LAST_REPORT_DAY)
    if (!lastReportDay.isEmpty() && today != lastReportDay) {
        let upload: Int64 = Int64.tryParse(getStoredData(KEY_TODAY_UPLOAD)).getOrDefault({ => 0})
        let download: Int64 = Int64.tryParse(getStoredData(KEY_TODAY_DOWNLOAD)).getOrDefault({ => 0})
        res = DayTrafficInfo(lastReportDay, upload, download)
        setStoredData(KEY_TODAY_UPLOAD, "0")
        setStoredData(KEY_TODAY_DOWNLOAD, "0")
        setStoredData(KEY_LAST_REPORT_DAY, today)
    }
    res
}

public func destroyTrafficHandler() {
    if (sampleId != -1) {
        clearInterval(sampleId)
    }
    if (sampleDayId != -1) {
        clearInterval(sampleDayId)
    }
    processUidTrafficBytes({upload, download, _ => updateDayTrafficCallback(upload, download, currentPageName)}, "")
}

private func getUrlTraficNativeInfo(): ArrayList<UrlTrafficInfo> {
    let res: ArrayList<UrlTrafficInfo> = ArrayList<UrlTrafficInfo>()
    let data: CString = unsafe { getTrafficNativeData() }
    var urlStr: String = ""
    if (data.isNull()) {
        return res
    }
    urlStr = data.toString()
    if (urlStr.isEmpty()) {
        return res
    }
    let items: Array<String> = urlStr.split(";", removeEmpty: true)
    for (item in items) {
        let info: UrlTrafficInfo = UrlTrafficInfo.fromString(item)
        res.add(info)
    }
    res
}

private func clusterUrlTrafficInfo(datas: ArrayList<UrlTrafficInfo>): ArrayList<UrlTrafficInfo> {
    var res: ArrayList<UrlTrafficInfo> = ArrayList<UrlTrafficInfo>()
    if (datas.isEmpty()) {
        return res
    }
    let map: HashMap<String, UrlTrafficInfo> = HashMap<String, UrlTrafficInfo>()
    for (item in datas) {
        if (map.contains(item.url)) {
            map[item.url].upTotal += item.upTotal
            map[item.url].downTotal += item.downTotal
        } else {
            map[item.url] = item
        }
    }
    res = collectArrayList<UrlTrafficInfo>(map.values().iterator())
    res
}

private func getUrlTrafficInfo(): ArrayList<UrlTrafficInfo> {
    let nativeInfo: ArrayList<UrlTrafficInfo> = getUrlTraficNativeInfo()
    let res = clusterUrlTrafficInfo(nativeInfo)
    res
}

private func clearUrlTrafficInfo(): Unit {
    unsafe {
        clearTrafficNativeData()
    }
}

foreign func InitTrafficNativeHandler(): Int8

foreign func getTrafficNativeData(): CString

foreign func clearTrafficNativeData(): Int8
