/**
 * Created on 2025/12/2
 */
import std.fs.*
import std.env.*
import std.process.*

@When[os == "Windows"]
let memLeakLib: String = "libohos_app_cangjie_hm_metricx_cj.memLeak.dll"
@When[os == "macOS"]
let memLeakLib: String = "libohos_app_cangjie_hm_metricx_cj.memLeak.dylib"
@When[os == "Linux"]
let memLeakLib: String = "libohos_app_cangjie_hm_metricx_cj.memLeak.so"

func getBuildModeFromEnv(): String {
    var buildMode: String = ""
    let configVar = getVariable("config")
    if (let Some(v) <- configVar) {
        if (!v.contains("buildMode")) {
            return "debug"
        }
        let config: String = v.removePrefix("{").removeSuffix("}")
        let items: Array<String> = config.split(",", removeEmpty: true)
        for (item in items) {
            let keyValues: Array<String> = item.split(":", removeEmpty: true)
            if (keyValues.size != 2) {
                continue
            }
            if (keyValues[0] == "\"buildMode\"") {
                buildMode = keyValues[1].removeSuffix("\"").removeSuffix("\"")
                break
            }
        }
    }
    buildMode
}

func getProductTargetFromeEnv(): (String, String) {
    var product: String = ""
    var target: String = ""
    let compileEnv = getVariable("COMPILE_CONDITION_ENTRY")
    if (let Some(v) <- compileEnv) {
        let items: Array<String> = v.split(",", removeEmpty: true)
        for (item in items) {
            let keyValues: Array<String> = item.split("=", removeEmpty: true)
            if (keyValues.size != 2) {
                continue
            }
            if (keyValues[0] == "product") {
                product = keyValues[1]
            } else if (keyValues[0] == "target") {
                target = keyValues[1]
            }
        }
    }
    (product, target)
}

func stagePreBuild(): Int64 {
    println("PRE-BUILD start")
    let buildMode = getBuildModeFromEnv()
    let (product, target) = getProductTargetFromeEnv()
    let targetDir = canonicalize("../../../build/${product}/intermediates/cj/build/${target}")
    let workingDir = canonicalize("../../../oh_modules/hm_metricx_cj/src/main/cangjie")

    executeWithOutput(
        "cjpm",
        [
            "build",
            "--target=aarch64-linux-ohos",
            "--target=" + targetDir.toString(),
            "--${buildMode}"
        ],
        workingDirectory: workingDir
    )
    let finalDir = targetDir.join("aarch64-linux-ohos/release/ohos_app_cangjie_entry")
    setVariable("OHOS_APP_CANGJIE_HM_METRICX_CJ", finalDir.toString())

    executeWithOutput("cmd.exe", ["/c", "mkdir", finalDir.toString()])
    let src = canonicalize("../../../oh_modules/hm_metricx_cj/assets/" + memLeakLib).toString()
    let dst = finalDir.join(memLeakLib).toString()

    copy(src, to: dst, overwrite: true)
    println("Copied memleak Lib：" + src + " -> " + dst)
    0
}

func stagePostBuild(): Int64 {
    println("POST-BUILD")
    0
}

main(): Int64 {
    return 0
}
