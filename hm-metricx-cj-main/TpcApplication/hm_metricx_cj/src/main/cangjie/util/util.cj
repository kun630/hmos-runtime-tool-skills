/*
 * Copyright (c) Huawei Technologies Co., Ltd. 2025-2025. All rights reserved.
 */
package ohos_app_cangjie_hm_metricx_cj.util

import std.unicode.UnicodeStringExtension
import std.collection.*
import std.fs.*
import std.regex.Regex
import std.time.*
import stdx.encoding.json.*
import std.convert.*
import std.io.*
import std.env.*
import std.process.*
import tpc.UIKit.Observer.*
import tpc.BasicServicesKit.*

const CLEAN_FILE_RECORD_MAX_NUMS = 50

public func map2json(input: HashMap<String, String>) {
    let map = HashMap<String, JsonValue>()
    input.iterator().forEach({entry => map.add(entry[0], JsonString(entry[1]))})
    JsonObject(map)
}

public func json2map(input: HashMap<String, JsonValue>) {
    let map = HashMap<String, String>()
    input.iterator().forEach({entry => map.add(entry[0], JsonValueToString(entry[1]))})
    map
}

public class PageSwitchCallBack <: Callback1Argument<NavDestinationSwitchInfo> {
    let elementInfoCallback: (NavDestinationSwitchInfo) -> Unit
    public init(elementInfoCallback: (NavDestinationSwitchInfo) -> Unit) {
        this.elementInfoCallback = elementInfoCallback
    }
    public func invoke(res: NavDestinationSwitchInfo): Unit {
        this.elementInfoCallback(res)
    }
}

public func getTargetPageName(info: NavDestinationSwitchInfo, defaultName!: String = "") {
    var name = defaultName
    match (info.to) {
        case to: NavDestinationInfo =>
            try {
                name = (to.name as String).getOrThrow()
            } catch (e: Exception) {
                AppLog.warn(e.toString())
            }
        case to: NavBar => name = "navRoot"
        case _ => throw Exception("")
    }
    name
}

public func deleteFile(path: String) {
    if (!exists(path)) {
        return
    }
    try {
        remove(path)
    } catch (e: FSException) {
        AppLog.warn(e.toString())
    }
}

public func readFile(path: Path, isReturnException!: Bool = false) {
    if (!exists(path)) {
        if (isReturnException) {
            return "hm-metricx-cj error: read file path ${path} does not exist"
        } else {
            return ""
        }
    }
    let content = File.readFrom(path)
    try {
        return String.fromUtf8(content)
    } catch (e: Exception) {
        AppLog.warn("hm-metricx-cj error: reading ${path} failed due to error occured in String.fromUtf8: ${e.toString()}")
        try {
            unsafe { return String.fromUtf8Unchecked(File.readFrom(path)) }
        } catch (e: Exception) {
            AppLog.warn("hm-metricx-cj error: reading ${path} failed due to error occured in fromUtf8Unchecked: ${e.toString()}")
            if (isReturnException) {
                return "hm-metricx-cj error: reading ${path} failed: ${e.toString()} content：" + content.toString()
            }
        }
    }
    ""
}

public func deleteFile(path: Path) {
    if (!exists(path)) {
        return
    }
    try {
        remove(path)
    } catch (e: FSException) {
        AppLog.warn(e.toString())
    }
}

public func renameFile(sourceFile: Path, targetFile: Path) {
    try {
        if (exists(sourceFile)) {
            rename(sourceFile, to: targetFile, overwrite: true)
        }
    } catch (e: Exception) {
        AppLog.warn(e.toString())
    }
}

let hiappeventPath = Path("/data/storage/el2/log/hiappevent/")

public func collectAndCleanHistoryLogFiles(predicate: (String) -> Bool, cleanFileRecordPath: Path, funcName: String): String {
    var historyFiles = ""
    if (!exists(hiappeventPath)) {
        return historyFiles
    }
    let fileList = Directory.readFrom(hiappeventPath)
    let deletedFileRecords = ArrayList<String>()
    for (file in fileList) {
        if (exists(file.path) && predicate(file.name)) {
            historyFiles += "fileName: ${file.name}\n" + readFile(file.path) + "\n"
            deletedFileRecords.add(getDetailOfDeletedFile(file, funcName))
            deleteFile(file.path)
        }
    }
    recordCleanFiles(cleanFileRecordPath, deletedFileRecords)
    historyFiles
}

public func cleanHistoryLogFiles(predicate: (String) -> Bool, cleanFileRecordPath: Path, funcName: String,
    keepLatest!: Bool = true): Unit {
    if (!exists(hiappeventPath)) {
        return
    }
    let fileList = Directory.readFrom(hiappeventPath)
    var latestFile: Option<FileInfo> = None
    let deletedFileRecords = ArrayList<String>()
    for (file in fileList) {
        if (exists(file.path) && predicate(file.name)) {
            if (!keepLatest) {
                deletedFileRecords.add(getDetailOfDeletedFile(file, funcName))
                deleteFile(file.path)
                continue
            }
            if (let Some(v) <- latestFile) {
                if (file.creationTime >= v.creationTime) {
                    deletedFileRecords.add(getDetailOfDeletedFile(v, funcName))
                    deleteFile(v.path)
                    latestFile = file
                } else {
                    deletedFileRecords.add(getDetailOfDeletedFile(file, funcName))
                    deleteFile(file.path)
                }
            } else {
                latestFile = file
            }
        }
    }
    recordCleanFiles(cleanFileRecordPath, deletedFileRecords)
}

public func cleanHistoryLogFiles(keepLatest!: Bool = true): Unit {
    let logPath = Path("/data/storage/el2/log/hiappevent/")
    if (!exists(logPath)) {
        return
    }
    let fileList = Directory.readFrom(logPath)
    let size = fileList.size
    var cnt = 0
    for (file in fileList) {
        cnt++
        if (cnt == size && keepLatest) {
            break
        }
        if (exists(file.path)) {
            deleteFile(file.path)
        }
    }
}

public const defaultPageName = "mainPage"

public func hilogWordWrap(str: String) {
    let rule = ##"(\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{3} )(.*?)(?=\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{3} |$)"##
    let arr = Regex(rule).findAll(str)
    if (arr.size == 0) {
        return str
    }
    var res: String = ""
    for (md in arr) {
        let cur = md.matchString().trim().removeSuffix(",")
        res = res + cur + "\n"
    }
    return res
}

public func JsonValueToString(value: JsonValue): String {
    return value.asString().getValue()
}

let ESCAPE_MAP: HashMap<String, String> = HashMap<String, String>([("\\n", "\n"), ("\\t", "\t")])
public func unescapeString(str: String): String {
    var res: String = str
    for (escape in ESCAPE_MAP) {
        res = res.replace(escape[0], escape[1])
    }
    res
}

public func getCurTimeStamp(): String {
    DateTime.now().format("yyyy-MM-dd HH:mm:ss")
}

public func getTodayDate(): String {
    DateTime.now().format("yyyy-MM-dd")
}

public func getCurTimestampMillis(): String {
    DateTime.now().format("yyyyMMdd-HHmmssS")
}

public func formatWithCommasAndPadding(num: Int64, width: Int64): String {
    let numStr = num.toString().toRuneArray()
    let len = numStr.size
    let withCommas = StringBuilder()
    for (i in 0..len) {
        if ((len - i) % 3 == 0 && i != 0) {
            withCommas.append(",")
        }
        withCommas.append(numStr[i])
    }
    var result = withCommas.toString()
    if (result.size < width) {
        let paddingWidth = width - result.size
        let padded = StringBuilder()
        for (i in 0..paddingWidth) {
            padded.append(' ')
        }
        result = padded.toString() + result
    }
    return result
}

public func writeFile(path: String, data: String) {
    try {
        File.writeTo(path, data.toArray())
    } catch (e: FSException) {
        AppLog.warn("hm-metricx-cj error: " + e.toString())
    } catch (e: IllegalArgumentException) {
        AppLog.warn("hm-metricx-cj error: " + e.toString())
    }
}

public func writeFile(path: Path, data: String) {
    try {
        File.writeTo(path, data.toArray())
    } catch (e: FSException) {
        AppLog.warn("hm-metricx-cj error: " + e.toString())
    } catch (e: IllegalArgumentException) {
        AppLog.warn("hm-metricx-cj error: " + e.toString())
    }
}

private func getDetailOfDeletedFile(file: FileInfo, funcName: String): String {
    "fileName: ${file.name}, createTime: ${file.creationTime.inLocal()}, " +
                "size: ${(Float64(file.size) / 1024.0).format(".3")}KB, deletedTime: ${DateTime.now().inLocal()}, deleteFunc: ${funcName}"
}

private func recordCleanFiles(path: Path, deletedFiles: List<String>) {
    try {
        if (deletedFiles.isEmpty()) {
            return
        }
        var content = readFile(path)
        let curFiles = content.split("\n", removeEmpty: true)
        let size = deletedFiles.size + curFiles.size
        if (size > CLEAN_FILE_RECORD_MAX_NUMS) {
            let res = StringBuilder()
            var curNum = 0
            for (i in deletedFiles.size-1..=0) {
                if(curNum >= CLEAN_FILE_RECORD_MAX_NUMS) {
                    break
                }
                res.append(deletedFiles[i] + '\n')
                curNum++
            }
            for (i in 0..curFiles.size) {
                if(curNum >= CLEAN_FILE_RECORD_MAX_NUMS) {
                    break
                }
                res.append(curFiles[i] + '\n')
                curNum++
            }
            writeFile(path, res.toString())
        } else {
            for (deletedFile in deletedFiles) {
                content = deletedFile + "\n" + content
            }
            writeFile(path, content)
        }

    } catch (e: Exception) {
        AppLog.warn("hm-metricx-cj error: recordCleanFile error, " + e.toString())
    }
}

// Execute the command and store the output.
public func execWithOutput(exeTool: String, arguments: ArrayList<String>): (Bool, String, String) {
    var outInfo = ""
    var errInfo = ""
    try {
        let env = HashMap<String, String>(getVariables())
        let subProcess = launch(exeTool, arguments.toArray(), environment: env, stdOut: ProcessRedirect.Pipe,
            stdErr: ProcessRedirect.Pipe)

        outInfo = StringReader(subProcess.stdOutPipe).readToEnd()
        errInfo = StringReader(subProcess.stdErrPipe).readToEnd()
        let returnCode = subProcess.wait()
        return (returnCode == 0, outInfo, errInfo)
    } catch (e: Exception) {
        AppLog.warn("hm-metricx-cj error: execWithOutput error, " + e.toString())
        return (false, outInfo, errInfo)
    }
}
