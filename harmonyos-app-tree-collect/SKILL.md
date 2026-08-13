---
name: harmonyos-app-tree-collect
description: "采集鸿蒙应用页面组件树与无障碍树。由用户提供的应用内操作步骤驱动：先采集未执行操作时的初始状态双树，结合组件树、项目源码与操作步骤生成测试场景，再按场景逐步执行 hdc 命令操作应用，每一步采集组件树与无障碍树并保存到工程路径下。当需要采集页面结构、分析无障碍语义树、按操作步骤录制/复现界面状态序列时使用此 Skill。"
---

# HarmonyOS 应用页面组件树与无障碍树采集 Skill

## 目的

**由用户提供的应用内操作步骤驱动**，采集鸿蒙应用页面在每个操作步骤下的**组件树（组件树）与无障碍树（无障碍节点树）**，并保存到工程路径下，供后续界面结构分析、无障碍语义分析或页面状态复现。

与 `harmonyos-app-diagnose` 系列（诊断/截图/hilog）不同，本 Skill 的产出是**结构化的双树数据**，不是诊断结论。

## 双树采集说明（重要）

鸿蒙**没有**独立的"导出无障碍树"命令，组件树与无障碍树都通过 `uitest dumpLayout` 获取（详见 `tree_collect.py` 注释）：

| 树 | 命令 | 说明 |
|----|------|------|
| **组件树** `component_tree.json` | `hdc shell uitest dumpLayout -p <path>` | 合并+过滤后的可见 UI 组件层级（当前屏幕可见的组件结构、文本、可点击状态） |
| **无障碍树** `a11y_tree.json` | `hdc shell uitest dumpLayout -i -p <path>` | 不合并窗口、不过滤节点，返回**窗口级原始节点树**，含 `accessibilityId / hierarchy / pagePath / bundleName / abilityName / hint / description / visible / focused / checked / selected` 等无障碍语义属性，即无障碍节点树（含不可见节点） |

**屏幕朗读状态**：屏幕朗读（`com.huawei.hmos.screenreader`）未开启时，无障碍树为**基础语义树**（仍含 accessibilityId/hierarchy 等全部语义属性）。脚本只检测并如实标注开启状态，**不自动改设备设置**。

> **注意：`ps` 里看到 `com.huawei.hmos.screenreader:accessibility` 进程 ≠ 读屏已实际开启**。该进程可能常驻（即使设置里的开关未打开），仅凭进程存在**不能**判定读屏开启。实际开启的可靠信号是 `dumpLayout -i` 树里出现读屏悬浮导航窗 `com.huawei.hms.floatingnavigation`（读屏真正开启时才会注入该窗口）。脚本据此判定：见悬浮导航窗 → "已开启"；只有进程无该窗口 → "进程在跑，可能未实际开启"。

**屏幕朗读开启时的实测行为**（设备 `2VD0224429008874` 实测）：
- 应用自身的组件树/无障碍树**内容完全不变**；树中会**多出一个读屏悬浮导航条窗口** `com.huawei.hms.floatingnavigation`（底部居中的悬浮条，含返回 / 返回主页 / 最近任务手势按钮，约 26~27 个节点）。按 bundleName 过滤到目标应用后不受影响。**该窗口是"读屏实际开启"的标志**——实测 `screenreader` 进程在跑但开关未打开时，树里**没有**这个窗口。
- **抓不到读屏焦点**：`dumpLayout -i` 的 `focused` 字段只反映**窗口/输入焦点链**（root→Navigation→NavBar），**不反映读屏无障碍焦点**——实测真实用户轻触移动焦点后，任何节点都不会变为 `focused=true`；`uitest uiInput` 的点击/滑动/按键注入也无法驱动读屏手势引擎。
- 因此本 skill **无法从树中拿到"读屏当前聚焦到哪个元素"**；读屏焦点需通过朗读内容（音频/日志）等其它手段获取，不在本 skill 范围内。

## 前置条件

- `hdc list targets` 有可用设备（模拟器或真机）
- 应用已安装，或有 `.hap` 文件（可用 `--hap` 指定安装最新包）
- 已构建通过（需要最新产物时）

## 采集流程

### 步骤 1：确认用户提供了应用内操作步骤

**必须**先确认用户给出了应用内的操作步骤，例如：
> "进入首页，点击顶部『热点』tab，再点击『本地』tab"

操作步骤应包含：在哪个页面、做什么操作、预期结果。**若用户未提供，先向用户索取**，不要凭空假设测试目标。

### 步骤 2：采集初始状态双树 + 生成测试场景

先采集**未执行任何操作时**的初始状态组件树与无障碍树（这是场景生成的依据）：

```powershell
cd <鸿蒙工程目录>

# 推荐：指定 --hap 确保安装最新包
python "<skills_dir>/harmonyos-app-tree-collect/tree_collect.py" \
  --project <鸿蒙工程目录> --emulator 5555 \
  --hap "product/default/build/default/outputs/default/multicommunityapplicationdefaultsample-default-unsigned.hap" \
  --capture
```

> 不传 `--emulator` 时用 USB 设备；应用已在前台时加 `--no-launch`。
> bundleName/abilityName 自动检测：bundle 从 `AppScope/app.json5`，ability 优先查设备上安装包的 `mainElementName`（`bm dump`），失败回退扫描各模块 `module.json5`。

采集产物（默认 `<工程目录>/tree_collect_output/`）：
- `step_000_baseline/component_tree.json` — 初始状态组件树
- `step_000_baseline/a11y_tree.json` — 初始状态无障碍树
- `step_000_baseline/tree_summary.md` — 双树摘要（节点数/类型分布/文本/可点击节点；窗口数/accessibilityId 范围/焦点/不可见节点）
- `manifest.json` — 应用/设备/时间/屏幕朗读状态

**生成测试场景**：结合以下三者生成 `scenario.json`：
1. **初始状态组件树**（`tree_summary.md` 中可见的文本/可点击节点）
2. **项目源码**（扫描 `src/main/ets/` 的 `.ets` 文件，确定操作背后的交互）
3. **用户提供的应用内操作步骤**（`scenario.json` 每步的 `note` 标注对应哪条操作步骤）

源码模式 → 场景动作对照表（参考 `harmonyos-app-diagnose-v2`）：

| 源码模式 | 场景动作 |
|----------|----------|
| `.onClick(...)` / `Button` / `Tabs.onChange` | `click` |
| `.onLongPress(...)` | `long_click` |
| `.onTextChange(...)` / `TextInput` | `input` |
| `Scroll` / `List` / `WaterFlow` + `ForEach` | `swipe` / `fling` |
| `Navigator` / `router.pushUrl` / `NavPathStack` | `click` + 跳转后插 `wait` |

生成规则：
- 每步 `target` 从组件树摘要中选取（优先 `key` > `text` > `type+index` > 坐标）
- 页面跳转/内容加载后插 `wait`（2-3s）
- 每步 `note` 写明对应哪条用户操作步骤

### 步骤 3：执行场景，逐步采集双树

```powershell
python "<skills_dir>/harmonyos-app-tree-collect/tree_collect.py" \
  --project <鸿蒙工程目录> --emulator 5555 \
  --scenario ./scenario.json
```

脚本会：
1. 采集**初始状态**双树到 `step_000_baseline/`
2. 逐步执行场景：每一步根据上一步的组件树解析目标坐标 → 生成并执行 hdc 命令 → 采集该步双树到 `step_NNN_<label>/`
3. 生成 `collection_report.md`（每步实际执行的 hdc 命令、note、相对上一步的组件树/无障碍树 diff）

**场景 JSON 格式**：

```json
{
  "name": "热点页本地tab切换",
  "description": "点击底部导航「热点」tab进入热点页，再点击热点页顶部「本地」二级tab",
  "steps": [
    {"action": "click", "target": {"text": "热点"}, "note": "点击底部导航「热点」tab", "wait_after": 2},
    {"action": "wait", "seconds": 2, "note": "等待热点页内容加载"},
    {"action": "click", "target": {"text": "本地"}, "note": "点击热点页顶部「本地」二级tab", "wait_after": 2}
  ]
}
```

**支持的动作**：`click`、`double_click`、`long_click`（`duration` ms）、`input`（`text`）、`swipe`/`fling`（`direction` 或 `from`+`to`）、`back`、`home`、`wait`（`seconds`）

**目标定位**：坐标 `{x,y}` > `key` > `text` > `type+index` > `hint`（从组件树中解析）

### 采集产物

```
<工程目录>/tree_collect_output/
  manifest.json                 # 应用/设备/时间/屏幕朗读状态 + 场景副本
  scenario.json                 # 场景文件副本
  collection_report.md          # 每步: 执行的 hdc 命令、note、双树 diff
  step_000_baseline/            # 初始状态（未执行任何操作）
    component_tree.json
    a11y_tree.json
    tree_summary.md
  step_001_<label>/             # 每步执行后各一份
    component_tree.json
    a11y_tree.json
    tree_summary.md
  ...
```

## 常见问题排查

- **采集到的是桌面/锁屏，不是应用**：应用不在前台。检查 `aa start` 是否成功，或去掉 `--no-launch` 让脚本自动启动应用；确认 `bm dump -n <bundle>` 的 `mainElementName` 正确。
- **组件树摘要提示"未找到 bundleName=..."**：dumpLayout 合并模式下根节点可能无 bundleName，脚本已回退分析全量组件树，属正常。
- **无障碍树无目标 bundle 窗口**：`dumpLayout -i` 按窗口返回，应用需在前台才会出现其窗口；锁屏时只有 sceneboard 窗口。
- **点击后 diff 显示"界面无明显变化"**：应用可能已处于目标状态（如已选中该 tab）。可先点击其他 tab 制造状态差异，或用 `swipe` 滚动后再对比。
- **目标文本匹配到多个节点**：组件树文本可能重复（如 tab 文案与内容文案一致），可改用 `type+index` 或坐标定位。
- **屏幕朗读开启后树里多出悬浮导航条窗口，`focused` 全是窗口焦点链**：`com.huawei.hms.floatingnavigation` 是读屏的悬浮导航条（底部居中，含返回/返回主页/最近任务按钮），按 bundle 过滤可排除；`focused` 字段只反映窗口/输入焦点，**不反映读屏无障碍焦点**（实测），属预期行为，不是 bug。
- **`ps` 里有 `screenreader` 进程但树里没有悬浮导航窗**：进程在跑**不代表读屏已实际开启**（开关未打开时该服务进程仍常驻）。判定读屏是否开启以 a11y 树里是否出现 `com.huawei.hms.floatingnavigation` 窗口为准；需读屏生效请在设备上手动打开开关后重采。

## 核心原则

1. **操作步骤驱动**：没有用户提供的应用内操作步骤，不开始采集；每步 `note` 对应一条用户操作步骤。
2. **先采初始状态**：任何操作执行前，先采集未执行操作时的初始状态双树（`step_000_baseline`）。
3. **双树同采**：每一步同时采集组件树与无障碍树，保证两种视角下界面状态一一对应。
4. **只基于真实数据**：场景目标从组件树摘要中选取，不凭空编造文本/坐标。
5. **如实记录**：每步实际执行的 hdc 命令、屏幕朗读开启状态均如实写入报告。
6. **不自动改设备设置**：屏幕朗读等无障碍开关只检测并提示，由用户在设备上手动操作。
