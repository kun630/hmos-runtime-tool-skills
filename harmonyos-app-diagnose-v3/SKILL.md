---
name: harmonyos-app-diagnose-v3
description: "构建成功后，采集设备上的应用 UI 截图与控件树，抓取 hilog 运行日志，分析界面状态与运行时异常并给出迭代建议。当需要验证构建产物的界面表现、排查 UI 缺陷、诊断应用崩溃/ANR/运行时错误、或评估是否需要进一步开发时使用此 Skill。支持 --a11y 无障碍屏幕朗读模式，验证应用在屏幕朗读下焦点落点、朗读内容、双击激活、双指滚动是否正常。"
---

# HarmonyOS 应用运行诊断 Skill

## 目的

构建成功后，通过 UI 采集（截图 + 控件树）、hilog 日志抓取、源码驱动的交互验证，输出可落地的诊断与迭代建议。

## 多模态能力说明（重要）

本 Skill 的视觉判断**不依赖多模态/截图识别**。所有"看图"类判断（白屏、控件缺失、重叠、溢出、尺寸过小）均基于**控件树 `layout.json` 的 `bounds` 字段**用确定性算法完成（见 `ui_capture.py` 的 `detect_blank_screen` / `detect_layout_overlaps` / `detect_overflow` 及 `ui_summary.md` 的"结构化视觉判断"章节）。

**截图 `screenshot.png` 是给人看的复核附件**，模型不读它、不分析它。诊断结论以控件树和日志为准；若截图与控件树结论冲突，仍以控件树为准（截图可能是加载态/遮挡/渲染层失败，但控件树是结构事实）。

## 适用场景

- 验证界面表现、排查 UI 缺陷或交互问题
- 应用崩溃（Crash）、白屏、闪退、ANR
- 抓取运行日志定位业务逻辑错误或异常堆栈

## 前置条件

- 构建已通过（`BUILD SUCCESSFUL`）
- `hdc list targets` 有可用设备（模拟器或真机）
- 应用已安装，或有 `.hap` 文件

## 诊断流程

### 步骤 1：确认设备连接

```powershell
hdc list targets
```

- 输出含 `127.0.0.1:<port>` → 模拟器，后续传 `--emulator <port>`
- 输出为设备 SN → USB 设备，不传 `--emulator`
- 输出为空 → 先启动模拟器或连接设备

### 步骤 2：采集 UI 状态

```powershell
cd <鸿蒙项目目录>

# 推荐：指定 --hap 确保安装最新包
python "<skills_dir>/harmonyos-app-diagnose-v3/ui_capture.py" --emulator 5555 \
  --hap "entry/build/default/outputs/default/entry-default-unsigned.hap" \
  --out ./ui_capture_output
```

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `--project` | 自动向上搜索 | 鸿蒙项目目录（含 `AppScope/`） |
| `--bundle` | 自动检测 | 应用包名 |
| `--ability` | 自动检测 | 启动 Ability |
| `--hap` | 无 | 指定后自动安装 |
| `--no-launch` | 否 | 应用已在前台时跳过启动 |
| `--wait` | `3` | 启动后等待秒数 |
| `--emulator` | 无 | 模拟器端口（如 `5555`），自动 `hdc tconn` |
| `--scenario` | 无 | 场景 JSON，执行交互后二次采集 |
| `--a11y` | 否 | 无障碍屏幕朗读模式，详见下方专章 |

脚本不可用时手动采集：

```powershell
hdc shell aa start -a EntryAbility -b <bundleName>
Start-Sleep 3
hdc shell snapshot_display -f /data/local/tmp/screen.png
hdc file recv /data/local/tmp/screen.png ./screenshot.png
hdc shell uitest dumpLayout -p /data/local/tmp/layout.json
hdc file recv /data/local/tmp/layout.json ./layout.json
```

采集产物（`ui_capture_output/`）：
- `screenshot.png` — 人类复核附件（模型不读，不参与程序化判断）
- `layout.json` — 控件树（结构事实，所有视觉判断的数据源）
- `ui_summary.md` — 统计摘要 + 结构化视觉判断（白屏检测/重叠/溢出/尺寸/间距，均基于控件树 bounds，非截图识别）

### 步骤 3：自动生成并执行交互场景

扫描 `entry/src/main/ets/` 的 `.ets` 文件，与控件树交叉匹配，生成 `auto_scenario.json`：

| 源码模式 | 场景动作 |
|----------|----------|
| `.onClick(...)` | `click` |
| `.onLongPress(...)` | `long_click` |
| `.onChange(...)` / `.onTextChange(...)` | `input` + `text_changed` |
| `.onSwipe(...)` / `Scroll` / `List` + `ForEach` | `swipe` / `fling` |
| `Navigator` / `router.push` / `pushUrl` | `click` + `page_changed` |
| `@State var xxx` | 找到绑定 UI 作为断言目标 |

生成规则：
- 定位优先级：`key` > `text` > `type+index` > 坐标
- 操作间插入 `wait`（点击 0.5-1s，跳转 2-3s），关键转换点插 `snapshot`
- 追踪回调修改的 `@State`，将绑定控件作为断言目标

执行：

```powershell
python "<skills_dir>/harmonyos-app-diagnose-v3/ui_capture.py" \
  --emulator 5555 --scenario ./auto_scenario.json --out ./ui_capture_output
```

**场景 JSON 示例**：

```json
{
  "name": "计数器点击测试",
  "steps": [
    {"action": "click", "target": {"text": "点击计数"}},
    {"action": "wait", "seconds": 1},
    {"action": "click", "target": {"text": "点击计数"}}
  ],
  "assertions": [
    {"type": "text_equals", "target": {"key": "counter_display"}, "expected": "2"},
    {"type": "page_changed", "message": "界面应有变化"}
  ]
}
```

**支持的动作**：`click`、`double_click`、`long_click`（`duration` ms）、`input`（`text`）、`swipe`/`fling`（`direction` 或 `from`+`to`）、`back`、`home`、`wait`（`seconds`）、`snapshot`（`label`）

**目标定位**：坐标 `{x,y}` > `key` > `text` > `type+index` > `hint`

**支持的断言**：`exists`、`not_exists`、`text_changed`、`text_equals`（`expected`）、`clickable`（`expected`）、`count_changed`（`type`）、`page_changed`

**执行产物**：
- `ui_capture_output/screenshot.png` + `layout.json` — 基线
- `ui_capture_output/after/screenshot.png` + `layout.json` — 交互后
- `ui_capture_output/diff.json` — 差异数据
- `ui_capture_output/interaction_report.md` — 执行报告
- `ui_capture_output/snapshot_<label>/` — 中间快照

### 步骤 3.5：无障碍屏幕朗读测试（`--a11y`）

**目的**：验证应用在「屏幕朗读」无障碍模式下是否可正常操作——焦点是否落点正确、朗读内容是否完整准确、双击激活是否生效、双指滚动是否生效。

**适用场景**：无障碍合规性验证、排查"屏幕朗读下点不动/跳转错乱/朗读缺失/焦点丢失"等问题。

**屏幕朗读交互模型**（与普通模式不同，核心要点）：
- **单击元素 = 聚焦该元素 + 系统朗读其内容**（不触发点击）
- **双击屏幕任意位置 = 激活当前焦点元素**（触发其点击）
- **滑动/滚动 = 双指滑动**（单指手势在屏幕朗读下被解释为"移动焦点"等导航手势，不是滚动）
- 朗读内容取值：`accessibilityText` > 显示 `text`；`accessibilityLevel("no")` 使控件对屏幕朗读不可聚焦

因此 `--a11y` 模式下，场景 JSON 中的动作会被自动改写，**无需改写场景文件**：
| 场景动作 | a11y 模式实际执行 |
|----------|------------------|
| `click` | 单击聚焦 → 抓焦点节点 → 双击激活（两步） |
| `long_click` | 单击聚焦 → 长按焦点位置 |
| `input` | 单击聚焦输入框 → 注入文本 |
| `double_click` | 直接双击（a11y 下双击即激活，无需先聚焦） |
| `swipe`/`fling` | 双指滑动（单指会被屏幕朗读拦截为导航手势） |
| `back`/`home`/`wait`/`snapshot` | 不变（语义一致） |

**用法**：

```powershell
python "<skills_dir>/harmonyos-app-diagnose-v3/ui_capture.py" \
  --emulator 5555 --a11y \
  --hap "entry/build/default/outputs/default/entry-default-unsigned.hap" \
  --scenario ./a11y_scenario.json --out ./a11y_output
```

**屏幕朗读开启**：`--a11y` 模式下，采集前会检测屏幕朗读是否开启（检测 `com.*.screenreader` 进程）；**未开启时打印指引并阻塞等待用户在设备上手动开启**（路径：设置 → 辅助功能 → 屏幕朗读 → 打开），开启后回车继续。**脚本不自动改设备设置**，以免误改用户设备状态。非交互环境（CI / stdin 非 tty）跳过阻塞，在报告中标注"屏幕朗读未确认开启"。

**a11y 模式专属断言**（在原有断言基础上新增）：
- `focused`（`expected` 默认 true）：目标控件交互后 `focused==true`，验证"单击应聚焦该控件"
- `accessibility_label`（`expected`、`mode` 默认 `contains`）：目标控件朗读标签（`accessibilityText` 优先，回退 `text`）包含/等于期望值，验证"应朗读为 X"。未用 `-a` dumpLayout 时回退到 `text` 并标注"仅校验显示文本"
- `a11y_focusable`（`expected` 默认 true）：目标控件是否对屏幕朗读可聚焦（`accessibilityLevel != "no"`）

**a11y 场景 JSON 示例**（与普通场景格式一致，click 自动展开为两步）：

```json
{
  "name": "屏幕朗读-页面跳转测试",
  "steps": [
    {"action": "click", "target": {"text": "下一页"}},
    {"action": "wait", "seconds": 2}
  ],
  "assertions": [
    {"type": "page_changed", "message": "双击激活后应跳转页面"},
    {"type": "focused", "target": {"text": "下一页"}, "message": "单击应聚焦到该按钮"},
    {"type": "accessibility_label", "target": {"text": "下一页"}, "expected": "下一页", "message": "应朗读为下一页"}
  ]
}
```

**a11y 模式产物**：与普通模式一致（`layout.json`/`after/`/`diff.json`/`interaction_report.md`），其中 `layout.json` 会带 `-a` extraAttrs（含无障碍标签）；报告额外含"无障碍屏幕朗读测试小结"（开启状态、各步聚焦控件、双指滑动近似说明）。

**双指滑动局限说明**：`hdc shell uitest uiInput` 的子命令不支持多指注入（仅 API 层 `PointerMatrix` 支持），故 a11y 模式下滑动用**两条并发 `swipe` 近似双指**。真机双指时序/触点可能与人工双指有差异，若滚动未生效需人工复核。

### 步骤 4：hilog 日志采集

以下情况**必须**采集日志：崩溃/闪退/白屏/ANR、断言失败、`ui_summary.md` 结构化视觉判断标记异常（白屏检测命中/重叠/溢出/控件数骤降）、业务逻辑不符预期。

**推荐采集流程**：

```powershell
hdc shell hilog -r                                          # 1. 清空旧日志
hdc shell aa start -a <abilityName> -b <bundleName>         # 2. 启动应用
Start-Sleep 5                                                # 3. 等待/复现
hdc shell hilog -x > ./ui_capture_output/hilog_full.txt     # 4. 导出全量日志
hdc shell "hilog -L E" > ./ui_capture_output/hilog_error.txt # 5. 提取错误
```

**常用过滤**：

```powershell
# 按包名过滤
hdc shell hilog | Select-String "<bundleName>" > ./hilog_app.txt
# 按标签过滤（AceAbility / JsApp / ArkCompiler）
hdc shell "hilog -T AceAbility" > ./hilog_ace.txt
# 按级别：-L E（ERROR+FATAL）、-L F（仅FATAL）、-L W（WARN及以上）
```

**崩溃模式速查表**：

| 关键词 | 含义 | 排查方向 |
|--------|------|----------|
| `Signal:11(SIGSEGV)` / `Signal:6(SIGABRT)` | 原生崩溃 | 堆栈函数名→源码行 |
| `Cannot read property` / `is not callable` | ArkTS 运行时错误 | 错误消息 + 调用栈 |
| `NullPointerException` / `nullptr` | 空引用 | 变量初始化时序、生命周期 |
| `ANR` / `Application Not Responding` | 主线程阻塞 | 耗时操作异步化 |
| `OutOfMemoryError` / `OOM` | 内存溢出 | 大图 / 缓存泄漏 / 循环引用 |
| `Permission denied` | 权限不足 | `module.json5` 添加 `requestPermissions` |
| `module is not installed` | 未安装 | 重装 hap、确认包名 |
| `Ability not found` | Ability 解析失败 | `module.json5` abilities 配置 |
| `libark_jsruntime` / `ark_` 崩溃 | ArkCompiler 层 | 互操作类型不匹配 / FFI |

**日志分析原则**：
1. 先 FATAL/ERROR 后 WARN，优先致命问题
2. 关注崩溃前 0.5-2 秒日志（往往含根因）
3. 堆栈截断时用 `hilog -G 2M` 增大缓冲区重采
4. 建议清空→操作→采集至少 2 次确认
5. 日志 + 控件树 + 截图交叉验证

### 步骤 5：分析与诊断

按以下维度输出结论（均基于 `ui_summary.md` / `diff.json` / `hilog` 的结构化数据，**不读截图**）：

| 维度 | 关注点（数据来源） |
|------|--------|
| 控件完整性 | 白屏检测（`ui_summary.md` 结构化视觉判断）、关键控件是否存在、文本是否有效 |
| 交互可用性 | `clickable`/`scrollable` 状态、断言是否通过（`interaction_report.md`） |
| 布局合理性 | 重叠/溢出检测（`ui_summary.md`）、层级深度 >10、大片留白 >1/4 屏高 |
| 视觉审美（启发式） | 可点击尺寸 >=48px、文本高度 >=20px（`ui_summary.md` 量化数据，非精确 fp 值） |
| 运行时健康 | hilog ERROR/FATAL、崩溃堆栈→源码位置、权限/资源错误 |
| 数据与业务 | 状态变量与 UI 一致性、`diff.json` 是否符合预期、日志业务异常 |
| 无障碍可用性（`--a11y`） | 焦点是否落点正确（`focused` 断言）、朗读标签是否完整准确（`accessibility_label`）、双击激活是否生效（`page_changed`）、双指滚动是否生效、不可聚焦控件是否合理（`a11y_focusable`） |

### 步骤 6：输出诊断报告

```markdown
## 应用运行诊断报告

### 当前状态
<一句话概述界面表现和运行健康度>

### 运行日志摘要（如有）
- 级别分布: FATAL: X, ERROR: Y, WARN: Z
- 关键发现: <崩溃/错误摘要及源码位置>

### 交互验证结果（如有）
断言通过率: X/Y
- ✅ / ❌ <断言描述> → 修复建议

### 发现的问题
1. [高/中/低] <描述> → 修复方式

### 迭代建议
- [ ] <具体开发任务>

### 无需改动
<确认正常的部分>
```

## 常见问题排查

截图是桌面 / 控件树无目标 bundleName / `aa start` 后仍在桌面：

1. 确认已安装（传 `--hap` 或 `hdc install -r`）
2. 显式启动：`hdc shell aa start -b <bundleName> -a <abilityName>`
3. 检查 `module.json5` 中 skills 是否误含 `entity.system.home`
4. 控件树确认目标 `bundleName` 出现且过滤后窗口数 >= 1

## 核心原则

1. **不读截图**：本 Skill 模型侧无多模态能力。视觉判断全部基于控件树 `bounds` 的确定性算法（白屏/重叠/溢出/尺寸），截图仅供人类复核，不进入分析。冲突时以控件树和 hilog 为准。
2. **只基于数据**：控件树和日志中没有的信息不下结论
3. **崩溃优先**：FATAL/ERROR 优先于 UI 细节
4. **聚焦可执行**：每个问题给出明确修复方向
5. **源码驱动场景**：事件绑定与可交互节点交叉得出，不凭空猜测
6. **不过度设计**：正常且无异常时标注"无需改动"
