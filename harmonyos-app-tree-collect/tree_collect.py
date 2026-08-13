# -*- coding: utf-8 -*-
"""HarmonyOS 页面组件树 + 无障碍树采集脚本

用法:
    # 采集当前页面初始状态的组件树 + 无障碍树（基线，用于生成测试场景）
    python tree_collect.py --project <鸿蒙工程目录> --capture [--no-launch]
    python tree_collect.py --project <鸿蒙工程目录> --emulator 5555 --capture

    # 执行测试场景，逐步操作应用，每一步采集组件树 + 无障碍树
    python tree_collect.py --project <鸿蒙工程目录> --scenario scenario.json

功能:
    1. 检测设备连接（支持 USB 物理设备和本地模拟器）
    2. 安装并启动应用（可选）
    3. 采集页面组件树（uitest dumpLayout，合并过滤后的可见 UI 层级）
    4. 采集页面无障碍树（uitest dumpLayout -i，窗口级原始节点树，含 accessibilityId/hierarchy/visible 等语义属性）
    5. 执行测试场景：点击/输入/滑动/返回/等待，逐步操作应用
    6. 每一步执行后采集组件树 + 无障碍树，保存到工程路径下
    7. 生成采集报告（每步实际执行的 hdc 命令 + 相邻步差异）

原理:
    鸿蒙没有独立的"导出无障碍树"命令，组件树与无障碍树都通过 uitest dumpLayout 获取：
    - 组件树: dumpLayout          合并+过滤后的可见组件树（当前屏幕 UI 结构）
    - 无障碍树: dumpLayout -i     不合并窗口、不过滤节点，返回窗口级原始节点树，
                                 含 accessibilityId / hierarchy / pagePath / bundleName /
                                 abilityName / hint / description / visible / focused 等
                                 无障碍语义属性，即无障碍节点树
    串联流程: 连接 → 启动 → 基线采集(初始状态) → 逐步执行场景 → 每步双树采集 → 差异对比
"""

import argparse
import json
import os
import re
import subprocess
import sys
import time
from pathlib import Path
from typing import Dict, List, Optional, Tuple

# Windows 下 Python 默认按系统编码(gbk/cp936)输出 stdout/stderr，但终端(Git
# Bash/VSCode)按 utf-8 显示，导致中文(控件文本/报告/日志)显示为乱码。脚本一启动
# 就把 stdout/stderr 重配为 utf-8，使其与终端一致。reconfigure 仅改编码不换流，
# 对重定向到文件同样生效(写入 utf-8)。不依赖 PYTHONIOENCODING 环境变量。
for _stream in (sys.stdout, sys.stderr):
    if hasattr(_stream, "reconfigure"):
        try:
            _stream.reconfigure(encoding="utf-8")
        except (ValueError, OSError):
            # 极少数流不支持 reconfigure(如被替换的非 TextIO)，忽略后回退原行为
            pass


# ============================================================
# 测试场景配置格式说明 (scenario JSON)
# ============================================================
# {
#   "name": "场景名称",
#   "description": "场景描述（对应哪组应用内操作步骤）",
#   "steps": [
#     {"action": "click", "target": {"text": "热点"}, "note": "点击底部导航热点tab"},
#     {"action": "click", "target": {"key": "btn_submit"}},
#     {"action": "click", "target": {"type": "Button", "index": 0}},
#     {"action": "click", "target": {"x": 540, "y": 1200}},
#     {"action": "long_click", "target": {"text": "长按我"}, "duration": 2000},
#     {"action": "double_click", "target": {"text": "双击我"}},
#     {"action": "input", "target": {"type": "TextInput", "index": 0}, "text": "hello"},
#     {"action": "swipe", "direction": "up"},
#     {"action": "swipe", "from": {"x": 540, "y": 1800}, "to": {"x": 540, "y": 600}, "speed": 600},
#     {"action": "fling", "direction": "down"},
#     {"action": "back"},
#     {"action": "home"},
#     {"action": "wait", "seconds": 2},
#     {"action": "snapshot", "label": "中间状态"}
#   ]
# }
# target 定位优先级: 坐标 {x,y} > key > text > type+index > hint
# ============================================================


def run(cmd: str, timeout: int = 30) -> str:
    """执行 shell 命令并返回 stdout（不含 stderr，避免错误流污染关键字判断）

    调用方若需要诊断失败，用 run_full() 拿 (stdout, stderr, returncode)。
    """
    return run_full(cmd, timeout=timeout)[0]


def run_full(cmd: str, timeout: int = 30) -> Tuple[str, str, int]:
    """执行 shell 命令，返回 (stdout, stderr, returncode)，各自不混合"""
    r = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=timeout)
    return (r.stdout.strip(), r.stderr.strip(), r.returncode)


def run_args(args: List[str], timeout: int = 30) -> str:
    """以参数列表形式执行命令（不经 shell），避免对含特殊字符的参数做转义

    用于向设备输入文本等场景：参数中的引号/反引号/$(...) 不会被 shell 解释。
    返回 stdout（不含 stderr）。
    """
    r = subprocess.run(args, capture_output=True, text=True, timeout=timeout)
    return (r.stdout + r.stderr).strip()


def connect_emulator(addr: str) -> str:
    """通过 hdc tconn 连接本地模拟器，返回目标地址"""
    # 纯数字视为端口号，自动补全为 localhost:port
    if addr.isdigit():
        addr = f"127.0.0.1:{addr}"
    elif ":" not in addr:
        addr = f"{addr}:5555"  # 默认模拟器端口
    print(f"[INFO] 连接模拟器: {addr} ...")
    # tconn 的 "Connect OK" 可能出现在 stdout 或 stderr，两者都看
    stdout, stderr, _ = run_full(f"hdc tconn {addr}")
    combined = (stdout + "\n" + stderr).strip()
    if combined:
        print(f"  {combined}")
    if "Connect OK" in combined or "already connected" in combined.lower():
        print(f"[OK] 模拟器已连接: {addr}")
        return addr
    # 即使输出不含预期关键字，也检查 list targets 确认
    targets_out = run("hdc list targets")
    if addr in targets_out:
        print(f"[OK] 模拟器已连接: {addr}")
        return addr
    print(f"[ERROR] 模拟器连接失败，hdc tconn 输出: {combined}")
    sys.exit(1)


def check_device(emulator_addr: Optional[str] = None) -> str:
    """检查 hdc 设备连接，返回设备 SN / 地址

    若指定 emulator_addr，先执行 tconn 连接模拟器
    """
    if emulator_addr:
        return connect_emulator(emulator_addr)
    out = run("hdc list targets")
    targets = [t.strip() for t in out.splitlines() if t.strip() and "Empty" not in t]
    if not targets:
        print("[ERROR] 未检测到已连接的 HarmonyOS 设备。")
        print("  物理设备: 请确认 USB 连接和 hdc 环境")
        print("  模拟器:   请使用 --emulator <port> 参数（如 --emulator 5555）")
        sys.exit(1)
    sn = targets[0]
    print(f"[OK] 设备已连接: {sn}")
    return sn


def install_hap(hap_path: str):
    """安装 hap 包到设备

    指定了 --hap 但路径不存在时显式告警：否则会静默跳过安装，导致用旧包
    跑完整轮采集、给出基于过期构建的结论。采集结论的可信度依赖被测产物
    是最新的，故此情况视为需用户介入的错误而非可忽略。
    """
    if not hap_path:
        return
    if not os.path.isfile(hap_path):
        print(f"[ERROR] 指定的 --hap 路径不存在: {hap_path}")
        print("        将跳过安装。请确认路径，否则可能采集的是旧构建产物。")
        return
    print(f"[INFO] 安装 {hap_path} ...")
    stdout, stderr, rc = run_full(f'hdc install -r "{hap_path}"')
    if stdout:
        print(f"  {stdout}")
    if stderr:
        print(f"  [stderr] {stderr}")
    if rc != 0 and "msg" not in (stdout + stderr).lower():
        print(f"  [WARN] hdc install 返回码 {rc}，安装可能失败，请确认设备状态")


def launch_app(bundle: str, ability: str):
    """启动应用"""
    print(f"[INFO] 启动 {bundle}/{ability} ...")
    run(f"hdc shell aa start -a {ability} -b {bundle}")
    time.sleep(3)


def dump_component_tree(out_dir: str) -> str:
    """采集组件树（uitest dumpLayout，合并过滤后的可见组件树）

    鸿蒙没有独立的"导出无障碍树"命令；组件树与无障碍树都通过 dumpLayout 获取。
    组件树用默认参数：合并窗口 + 过滤不可见节点，即当前屏幕可见的 UI 组件层级。
    """
    device_json = "/data/local/tmp/_tree_collect_comp.json"
    local_path = os.path.join(out_dir, "component_tree.json")
    run(f"hdc shell uitest dumpLayout -p {device_json}")
    run(f'hdc file recv {device_json} "{local_path}"')
    run(f"hdc shell rm {device_json}")
    if os.path.isfile(local_path):
        print(f"[OK] 组件树已保存: {local_path}")
    else:
        print("[WARN] 组件树拉取失败")
    return local_path


def dump_a11y_tree(out_dir: str) -> str:
    """采集无障碍树（uitest dumpLayout -i，窗口级原始节点树）

    -i 参数：不合并窗口、不过滤节点。返回窗口级节点树，每个节点含
    accessibilityId / hierarchy / pagePath / bundleName / abilityName /
    hint / description / visible / focused / checked / selected 等
    无障碍语义属性，即鸿蒙无障碍节点树（屏幕朗读等无障碍服务消费的语义树）。
    """
    device_json = "/data/local/tmp/_tree_collect_a11y.json"
    local_path = os.path.join(out_dir, "a11y_tree.json")
    run(f"hdc shell uitest dumpLayout -i -p {device_json}")
    run(f'hdc file recv {device_json} "{local_path}"')
    run(f"hdc shell rm {device_json}")
    if os.path.isfile(local_path):
        print(f"[OK] 无障碍树已保存: {local_path}")
    else:
        print("[WARN] 无障碍树拉取失败")
    return local_path


def is_screen_reader_active(a11y_path: Optional[str] = None) -> Tuple[bool, str]:
    """检测屏幕朗读是否**实际开启**

    注意：ps 里出现 com.huawei.hmos.screenreader:accessibility 进程**不代表**读屏
    开关已打开——该服务进程可能常驻（实测设备上开关未开时进程也在跑）。实际开启
    的可靠信号是 dumpLayout -i 树里出现读屏悬浮导航窗 com.huawei.hms.floatingnavigation
    （读屏真正开启时才会注入该窗口）。

    判定顺序：
    1. 传入 a11y 树路径且树中含 floatingnavigation 窗口 → 已开启 (True)
    2. 仅检测到 screenreader 进程 → 不判已开启，返回 (False, "仅进程在跑…")
    3. 都没有 → 未开启 (False, "")

    无障碍树在屏幕朗读未开启时仍可采集（为基础语义树）；若需反映真实焦点/朗读
    语义，需用户在设备上手动开启屏幕朗读后重采。脚本只检测并如实标注，
    不自动改设备设置。
    """
    # 主信号：a11y 树里的读屏悬浮导航窗（读屏实际开启的标志）
    if a11y_path and os.path.isfile(a11y_path):
        try:
            with open(a11y_path, "r", encoding="utf-8") as f:
                tree = json.load(f)
            if filter_tree_by_bundle(tree, "com.huawei.hms.floatingnavigation"):
                return True, "a11y树含读屏悬浮导航窗 com.huawei.hms.floatingnavigation"
        except (json.JSONDecodeError, OSError):
            pass
    # 兜底：进程存在只能说明读屏服务在跑，不代表开关已开
    out = run("hdc shell ps -ef")
    for line in out.splitlines():
        low = line.lower()
        if "screenreader" in low and "grep" not in low:
            return False, "仅检测到读屏进程在跑（开关可能未打开），未见悬浮导航窗"
    return False, ""


def detect_bundle_name(project_dir: str) -> Optional[str]:
    """从 AppScope/app.json5 检测 bundleName"""
    app_json = os.path.join(project_dir, "AppScope", "app.json5")
    if not os.path.isfile(app_json):
        return None
    try:
        content = Path(app_json).read_text(encoding="utf-8")
        m = re.search(r'"bundleName"\s*:\s*"([^"]+)"', content)
        if m:
            bundle_name = m.group(1)
            print(f"[OK] 检测到 bundleName: {bundle_name}")
            return bundle_name
    except Exception as e:
        print(f"[WARN] 读取 {app_json} 失败: {e}")
    return None


def detect_ability_from_device(bundle: str) -> Optional[str]:
    """从设备查询安装应用的 mainElementName（真正可启动的 Ability）

    多模块工程（如 product/default + product/pc）本地扫描可能命中错误模块，
    而设备上安装的包只有一个 mainElementName（bm dump 给出），最可靠。
    无设备连接或查询失败时返回 None，由调用方回退本地源码扫描。
    """
    out = run(f"hdc shell bm dump -n {bundle}")
    m = re.search(r'"mainElementName"\s*:\s*"([^"]+)"', out)
    if m:
        ability = m.group(1)
        print(f"[OK] 检测到 abilityName(设备): {ability}")
        return ability
    return None


def detect_ability_from_source(project_dir: str) -> Optional[str]:
    """从各模块 module.json5 扫描 abilityName

    多模块工程按优先级选择：
      1. 路径含 "default" 的 entry 模块（对应默认手机构建）
      2. 任意 entry 模块
      3. 第一个含 Ability 的模块
    """
    candidates = []  # (优先级, 模块json路径, abilityName)
    for root, dirs, files in os.walk(project_dir):
        if any(skip in root for skip in ("oh_modules", "build", ".hvigor", "node_modules", ".idea")):
            continue
        if "module.json5" in files:
            path = os.path.join(root, "module.json5")
            try:
                content = Path(path).read_text(encoding="utf-8")
                m = re.search(r'"name"\s*:\s*"(\w*Ability\w*)"', content)
                if not m:
                    continue
                ability = m.group(1)
                module_type = re.search(r'"type"\s*:\s*"(\w+)"', content)
                is_entry = (module_type and module_type.group(1) == "entry")
                priority = 0
                if "default" in root and is_entry:
                    priority = 0
                elif is_entry:
                    priority = 1
                else:
                    priority = 2
                candidates.append((priority, path, ability))
            except Exception as e:
                print(f"[WARN] 读取 {path} 失败: {e}")
    if not candidates:
        return None
    candidates.sort(key=lambda x: (x[0], x[1]))
    ability = candidates[0][2]
    print(f"[OK] 检测到 abilityName(源码): {ability} ({candidates[0][1]})")
    return ability


def find_project_dir() -> Optional[str]:
    """向上搜索鸿蒙项目根目录（含 AppScope/ 的目录）

    从当前工作目录开始，逐级向上查找
    """
    cwd = Path.cwd()
    if (cwd / "AppScope").is_dir():
        return str(cwd)
    for parent in list(cwd.parents)[:10]:
        if (parent / "AppScope").is_dir():
            return str(parent)
    return None


def filter_tree_by_bundle(tree, bundle: str) -> list:
    """从完整控件树中提取属于指定 bundleName 的子树

    兼容 dict（组件树：树根）与 list（无障碍树 -i：窗口列表）两种输入。
    返回匹配 bundle 的窗口/子树列表，找不到时返回空列表（调用方回退全量）。
    """
    results = []
    children = tree.get("children", []) if isinstance(tree, dict) else tree
    for child in children:
        attrs = child.get("attributes", {}) if isinstance(child, dict) else {}
        if attrs.get("bundleName") == bundle:
            results.append(child)
        else:
            results.extend(filter_tree_by_bundle(child, bundle))
    return results


def _get_attrs(node: dict) -> dict:
    """从节点提取属性字典，兼容 hdc dumpLayout 两种格式"""
    attrs = node.get("attributes", {})
    if not attrs and "type" in node:
        return node
    return attrs


def _flatten_tree(node) -> List[dict]:
    """将嵌套控件树扁平化为节点列表（兼容 dict 树与 list 窗口列表）"""
    if isinstance(node, list):
        nodes = []
        for item in node:
            nodes.extend(_flatten_tree(item))
        return nodes
    nodes = [_get_attrs(node)]
    for child in node.get("children", []):
        nodes.extend(_flatten_tree(child))
    return nodes


def _parse_bounds(bounds_str: str) -> Optional[Tuple[int, int, int, int]]:
    """解析 bounds 字符串 '[x1,y1][x2,y2]' → (x1, y1, x2, y2)"""
    m = re.findall(r'\[(\d+),(\d+)\]', bounds_str or "")
    if len(m) == 2:
        return int(m[0][0]), int(m[0][1]), int(m[1][0]), int(m[1][1])
    return None


def _center_of(bounds: Tuple[int, int, int, int]) -> Tuple[int, int]:
    """返回 bounds 的中心坐标"""
    return (bounds[0] + bounds[2]) // 2, (bounds[1] + bounds[3]) // 2


def _safe_load(path: str):
    """安全加载 JSON 文件，失败返回 None"""
    if not os.path.isfile(path):
        return None
    try:
        with open(path, "r", encoding="utf-8") as f:
            return json.load(f)
    except json.JSONDecodeError:
        print(f"[WARN] JSON 解析失败: {path}")
        return None


def _safe_load_flat(path: str) -> List[dict]:
    """安全加载 JSON 控件树并扁平化为节点列表"""
    tree = _safe_load(path)
    if tree is None:
        return []
    return _flatten_tree(tree)


def _get_screen_size(flat_nodes: List[dict]) -> Tuple[int, int]:
    """从控件树推断屏幕尺寸"""
    max_x, max_y = 1080, 2340  # 默认值
    for n in flat_nodes:
        bounds = _parse_bounds(n.get("bounds", ""))
        if bounds:
            max_x = max(max_x, bounds[2])
            max_y = max(max_y, bounds[3])
    return max_x, max_y


def summarize_trees(comp_path: str, a11y_path: str, out_dir: str,
                    bundle: Optional[str] = None) -> str:
    """解析组件树 + 无障碍树，生成可读文本摘要 tree_summary.md

    组件树摘要：节点数/类型分布/文本/可点击/层级深度/可滚动
    无障碍树摘要：窗口数/各窗口 bundle/accessibilityId 范围/focused/visible 统计
    """
    summary_path = os.path.join(out_dir, "tree_summary.md")
    lines = [f"# 页面双树采集摘要\n"]
    if bundle:
        lines.append(f"**应用**: `{bundle}`\n")

    comp_tree = _safe_load(comp_path)
    a11y_tree = _safe_load(a11y_path)

    # ---------- 组件树摘要 ----------
    lines.append(f"## 组件树 (uitest dumpLayout)\n")
    if comp_tree is None:
        lines.append("（组件树采集失败）\n")
    else:
        # 按 bundle 过滤，找不到时回退全量
        comp_subtrees = filter_tree_by_bundle(comp_tree, bundle) if bundle else []
        if not comp_subtrees:
            comp_subtrees = [comp_tree] if isinstance(comp_tree, dict) else comp_tree
            if bundle:
                lines.append(f"（未在组件树中找到 bundleName={bundle} 的节点，分析全量组件树）\n")

        stats = {"total": 0, "types": {}, "texts": [], "keys": [],
                 "clickable": 0, "scrollable": 0, "max_depth": 0,
                 "clickable_nodes": []}

        def walk(node, depth=0):
            attrs = _get_attrs(node)
            stats["total"] += 1
            if depth > stats["max_depth"]:
                stats["max_depth"] = depth
            comp_type = attrs.get("type", "") or "Unknown"
            stats["types"][comp_type] = stats["types"].get(comp_type, 0) + 1
            text = attrs.get("text", "")
            key = attrs.get("key", "")
            if text:
                stats["texts"].append(text)
            if key:
                stats["keys"].append(key)
            if attrs.get("clickable") == "true":
                stats["clickable"] += 1
                stats["clickable_nodes"].append(
                    (comp_type, text or key or attrs.get("hint", ""),
                     attrs.get("bounds", "")))
            if attrs.get("scrollable") == "true":
                stats["scrollable"] += 1
            for child in node.get("children", []):
                walk(child, depth + 1)

        for subtree in comp_subtrees:
            walk(subtree)

        lines.append(f"- 控件总数: {stats['total']}")
        lines.append(f"- 可点击: {stats['clickable']}")
        lines.append(f"- 可滚动: {stats['scrollable']}")
        lines.append(f"- 最大嵌套深度: {stats['max_depth']}")
        lines.append(f"- 控件类型分布: "
                     f"{', '.join(f'{t}:{c}' for t, c in sorted(stats['types'].items(), key=lambda x: -x[1]))}")
        if stats["texts"]:
            lines.append(f"- 文本内容: {stats['texts']}")
        if stats["keys"]:
            lines.append(f"- Key 标识: {stats['keys']}")
        if stats["clickable_nodes"]:
            lines.append(f"- 可点击节点:")
            for t, label, bounds in stats["clickable_nodes"][:40]:
                lines.append(f"  - {t}({label}) {bounds}")
            if len(stats["clickable_nodes"]) > 40:
                lines.append(f"  - ... 共 {len(stats['clickable_nodes'])} 个")
        lines.append("")

    # ---------- 无障碍树摘要 ----------
    lines.append(f"## 无障碍树 (uitest dumpLayout -i)\n")
    if a11y_tree is None:
        lines.append("（无障碍树采集失败）\n")
    else:
        windows = a11y_tree if isinstance(a11y_tree, list) else a11y_tree.get("children", [])
        lines.append(f"- 窗口数量: {len(windows)}")
        a11y_stats = {"windows": [], "focused": 0, "invisible": 0}
        for w in windows:
            attrs = _get_attrs(w)
            wname = attrs.get("bundleName", "(未知)")
            wpage = attrs.get("pagePath", "")
            nodes = _flatten_tree(w)
            a11y_ids = [n.get("accessibilityId", "") for n in nodes if n.get("accessibilityId")]
            a11y_ids = [i for i in a11y_ids if str(i).isdigit()]
            focused = [n.get("text", "") for n in nodes if n.get("focused") == "true"]
            invisible = sum(1 for n in nodes if n.get("visible") == "false")
            a11y_stats["focused"] += len(focused)
            a11y_stats["invisible"] += invisible
            id_range = f"{min(map(int, a11y_ids))}-{max(map(int, a11y_ids))}" if a11y_ids else "无"
            a11y_stats["windows"].append({
                "bundle": wname, "page": wpage, "node_count": len(nodes),
                "a11y_id_range": id_range, "focused_nodes": focused, "invisible": invisible,
            })
            lines.append(f"- 窗口: {wname} page={wpage} 节点数={len(nodes)} "
                         f"accessibilityId={id_range} 不可见={invisible}")
            if focused:
                lines.append(f"  - 当前焦点节点文本: {focused}")
        # 屏幕朗读状态（进程在跑≠实际开启，以悬浮导航窗为准）
        active, proc = is_screen_reader_active(a11y_path)
        if active:
            sr_state = "已开启"
        elif proc:
            sr_state = f"未开启（{proc}；无障碍树为基础语义树，不含真实焦点/朗读语义）"
        else:
            sr_state = "未开启（无障碍树为基础语义树，不含真实焦点/朗读语义）"
        lines.append(f"- 屏幕朗读状态: {sr_state}")

    with open(summary_path, "w", encoding="utf-8") as f:
        f.write("\n".join(lines))
    print(f"[OK] 摘要已保存: {summary_path}")
    return summary_path


def capture_state(out_dir: str, bundle: Optional[str] = None) -> dict:
    """采集当前页面状态：组件树 + 无障碍树 + 摘要

    返回 {"comp": 组件树路径, "a11y": 无障碍树路径, "summary": 摘要路径}
    """
    os.makedirs(out_dir, exist_ok=True)
    comp_path = dump_component_tree(out_dir)
    a11y_path = dump_a11y_tree(out_dir)
    summary_path = summarize_trees(comp_path, a11y_path, out_dir, bundle=bundle)
    return {"comp": comp_path, "a11y": a11y_path, "summary": summary_path}


# ============================================================
# 交互引擎
# ============================================================

def find_target_node(flat_nodes: List[dict], target: dict) -> Optional[dict]:
    """从扁平节点列表中根据 target 描述查找匹配节点

    target 支持的匹配键（按优先级）:
    - x, y: 直接坐标，不做节点查找
    - key: 精确匹配控件 key
    - text: 精确匹配或包含匹配控件 text
    - type + index: 按控件类型 + 索引（默认 0）
    - hint: 精确匹配 hint 文本
    """
    if "x" in target and "y" in target:
        return {"_direct_coords": (int(target["x"]), int(target["y"]))}

    if "key" in target:
        for n in flat_nodes:
            if n.get("key") == target["key"]:
                return n

    if "text" in target:
        t = target["text"]
        for n in flat_nodes:
            if n.get("text") == t:
                return n
        for n in flat_nodes:
            if t in (n.get("text") or ""):
                return n

    if "type" in target:
        idx = target.get("index", 0)
        matches = [n for n in flat_nodes if n.get("type") == target["type"]]
        if 0 <= idx < len(matches):
            return matches[idx]

    if "hint" in target:
        for n in flat_nodes:
            if n.get("hint") == target["hint"]:
                return n

    return None


def _get_node_coords(node: dict) -> Optional[Tuple[int, int]]:
    """从节点获取中心点坐标"""
    if not node:
        return None
    if "_direct_coords" in node:
        return node["_direct_coords"]
    bounds = _parse_bounds(node.get("bounds", ""))
    if bounds:
        return _center_of(bounds)
    return None


def _swipe_coords(direction: str, screen_w: int, screen_h: int
                  ) -> Tuple[int, int, int, int]:
    """根据方向关键字计算滑动起止坐标"""
    cx, cy = screen_w // 2, screen_h // 2
    dist = screen_h // 3
    mapping = {
        "up":    (cx, cy + dist, cx, cy - dist),
        "down":  (cx, cy - dist, cx, cy + dist),
        "left":  (cx + dist, cy, cx - dist, cy),
        "right": (cx - dist, cy, cx + dist, cy),
    }
    return mapping.get(direction, mapping["up"])


def load_scenario(path: str) -> dict:
    """加载测试场景配置 JSON 文件"""
    with open(path, "r", encoding="utf-8") as f:
        content = f.read()
    content = re.sub(r'//.*?$', '', content, flags=re.MULTILINE)  # 去除 // 注释
    scenario = json.loads(content)
    print(f"[OK] 加载场景: {scenario.get('name', path)} ({len(scenario.get('steps', []))} 步)")
    return scenario


def execute_step(step: dict, flat_nodes: List[dict], screen_w: int, screen_h: int,
                 step_idx: int) -> dict:
    """执行单个交互步骤，返回执行结果（含实际执行的 hdc 命令）

    返回 {"action", "success", "hdc_command", "detail"}
    """
    action = step.get("action", "")
    result = {"action": action, "success": False, "hdc_command": "", "detail": ""}

    if action == "wait":
        seconds = step.get("seconds", 2)
        print(f"  [STEP {step_idx}] 等待 {seconds}s ...")
        time.sleep(seconds)
        result["success"] = True
        result["detail"] = f"等待 {seconds}s"
        return result

    if action == "back":
        print(f"  [STEP {step_idx}] 模拟返回键")
        cmd = "hdc shell uitest uiInput keyEvent 2"
        out = run(cmd)
        result.update(success=True, hdc_command=cmd, detail=f"返回键: {out}")
        return result

    if action == "home":
        print(f"  [STEP {step_idx}] 模拟 Home 键")
        cmd = "hdc shell uitest uiInput keyEvent 1"
        out = run(cmd)
        result.update(success=True, hdc_command=cmd, detail=f"Home 键: {out}")
        return result

    if action == "snapshot":
        # snapshot 已在 execute_scenario 中通过 capture_state 处理，这里仅占位
        result.update(success=True, detail="snapshot 采集")
        return result

    target = step.get("target", {})

    if action in ("swipe", "fling"):
        if "from" in step and "to" in step:
            x1, y1 = int(step["from"]["x"]), int(step["from"]["y"])
            x2, y2 = int(step["to"]["x"]), int(step["to"]["y"])
        elif "direction" in step:
            x1, y1, x2, y2 = _swipe_coords(step["direction"], screen_w, screen_h)
        else:
            result["detail"] = "swipe/fling 需要 direction 或 from/to"
            return result
        speed = step.get("speed", 600)
        if action == "fling":
            step_len = step.get("stepLen", 50)
            cmd = f"hdc shell uitest uiInput fling {x1} {y1} {x2} {y2} {step_len} {speed}"
        else:
            cmd = f"hdc shell uitest uiInput swipe {x1} {y1} {x2} {y2} {speed}"
        print(f"  [STEP {step_idx}] {action}: ({x1},{y1}) → ({x2},{y2})")
        out = run(cmd)
        result.update(success=True, hdc_command=cmd,
                      detail=f"{action} ({x1},{y1})→({x2},{y2}): {out}")
        return result

    if action in ("click", "double_click", "long_click", "input"):
        node = find_target_node(flat_nodes, target)
        if not node:
            result["detail"] = f"未找到目标控件: {target}"
            print(f"  [STEP {step_idx}] FAIL {result['detail']}")
            return result
        coords = _get_node_coords(node)
        if not coords:
            result["detail"] = f"无法获取控件坐标: {target}"
            print(f"  [STEP {step_idx}] FAIL {result['detail']}")
            return result
        x, y = coords

        if action == "click":
            cmd = f"hdc shell uitest uiInput click {x} {y}"
            print(f"  [STEP {step_idx}] 点击 ({x}, {y}) target={target}")
        elif action == "double_click":
            cmd = f"hdc shell uitest uiInput doubleClick {x} {y}"
            print(f"  [STEP {step_idx}] 双击 ({x}, {y}) target={target}")
        elif action == "long_click":
            duration = step.get("duration", 1500)
            cmd = f"hdc shell uitest uiInput longClick {x} {y} {duration}"
            print(f"  [STEP {step_idx}] 长按 ({x}, {y}) duration={duration}ms target={target}")
        elif action == "input":
            text = step.get("text", "")
            run(f"hdc shell uitest uiInput click {x} {y}")
            time.sleep(0.5)
            run_args(["hdc", "shell", "uitest", "uiInput", "inputText", str(text)])
            print(f'  [STEP {step_idx}] 输入 "{text}" @ ({x}, {y}) target={target}')
            result.update(success=True,
                          hdc_command=f'hdc shell uitest uiInput inputText "{text}"',
                          detail=f'input "{text}" @ ({x},{y})')
            return result

        out = run(cmd)
        result.update(success=True, hdc_command=cmd, detail=f"{action} ({x},{y}): {out}")
        return result

    result["detail"] = f"未知操作: {action}"
    print(f"  [STEP {step_idx}] FAIL {result['detail']}")
    return result


def execute_scenario(scenario: dict, out_dir: str, bundle: Optional[str] = None) -> List[dict]:
    """执行完整测试场景：每步执行前用最新组件树解析目标，执行后采集双树

    返回每步结果列表 [{step, action, label, note, hdc_command, success, detail,
                      comp_path, a11y_path, diff_before, diff_after}]
    """
    steps = scenario.get("steps", [])
    if not steps:
        print("[WARN] 场景无交互步骤")
        return []

    results = []
    prev_comp_path = os.path.join(out_dir, "step_000_baseline", "component_tree.json")

    for i, step in enumerate(steps):
        step_no = i + 1
        label = step.get("label") or re.sub(r'[^\w一-龥-]+', '_', str(step.get("note") or step.get("action")))
        step_dir = os.path.join(out_dir, f"step_{step_no:03d}_{label}")

        print(f"\n--- Step {step_no}/{len(steps)}: {step.get('action', '?')} ---")

        # 执行操作前用最新组件树解析目标坐标（上一步已采集的组件树）
        flat_nodes = _safe_load_flat(prev_comp_path) if os.path.isfile(prev_comp_path) else []
        screen_w, screen_h = _get_screen_size(flat_nodes)
        r = execute_step(step, flat_nodes, screen_w, screen_h, step_no)

        # 交互后等待界面刷新
        wait_after = step.get("wait_after", 1)
        if wait_after > 0 and step.get("action") != "wait":
            time.sleep(wait_after)

        # 采集执行后的双树
        r["step"] = step_no
        r["label"] = label
        r["note"] = step.get("note", "")
        if step.get("action") != "snapshot":
            state = capture_state(step_dir, bundle=bundle)
            r["comp_path"] = state["comp"]
            r["a11y_path"] = state["a11y"]
            r["comp_flat"] = _safe_load_flat(state["comp"])
        else:
            # snapshot 步骤仅采集中间状态，不修改任何状态
            state = capture_state(step_dir, bundle=bundle)
            r["comp_path"] = state["comp"]
            r["a11y_path"] = state["a11y"]
            r["comp_flat"] = _safe_load_flat(state["comp"])
            r["success"] = True
            r["detail"] = f"中间快照: {step_dir}"

        results.append(r)
        prev_comp_path = r["comp_path"]

    return results


# ============================================================
# 差异对比引擎
# ============================================================

def diff_layouts(before_path: str, after_path: str) -> dict:
    """对比两次组件树 JSON，返回结构化差异

    返回:
    {
      "nodes_added": [...],       # 新增节点
      "nodes_removed": [...],     # 消失节点
      "text_changes": [...],      # 文本变化
      "count_changes": {...},     # 各类型控件数量变化
      "summary": str              # 人类可读摘要
    }
    """
    diff = {"nodes_added": [], "nodes_removed": [], "text_changes": [],
            "count_changes": {}, "summary": ""}

    before_nodes = _safe_load_flat(before_path)
    after_nodes = _safe_load_flat(after_path)

    def _build_index(nodes):
        index = {}
        type_counts = {}
        for n in nodes:
            k = n.get("key", "")
            t = n.get("text", "")
            comp_type = n.get("type", "Unknown")
            if k:
                index[f"key:{k}"] = n
            if t:
                index[f"text:{t}"] = n
            cnt = type_counts.get(comp_type, 0)
            index[f"type:{comp_type}#{cnt}"] = n
            type_counts[comp_type] = cnt + 1
        return index

    before_idx = _build_index(before_nodes)
    after_idx = _build_index(after_nodes)
    before_keys = set(before_idx.keys())
    after_keys = set(after_idx.keys())

    for k in after_keys - before_keys:
        n = after_idx[k]
        diff["nodes_added"].append({"id": k, "type": n.get("type", ""),
                                    "text": n.get("text", "")})
    for k in before_keys - after_keys:
        n = before_idx[k]
        diff["nodes_removed"].append({"id": k, "type": n.get("type", ""),
                                      "text": n.get("text", "")})
    for k in before_keys & after_keys:
        bn, an = before_idx[k], after_idx[k]
        bt, at = bn.get("text", ""), an.get("text", "")
        if bt != at:
            diff["text_changes"].append({"node_id": k, "before": bt, "after": at})

    def _count_types(nodes):
        counts = {}
        for n in nodes:
            t = n.get("type", "Unknown")
            counts[t] = counts.get(t, 0) + 1
        return counts

    before_counts = _count_types(before_nodes)
    after_counts = _count_types(after_nodes)
    for t in set(list(before_counts.keys()) + list(after_counts.keys())):
        bc, ac = before_counts.get(t, 0), after_counts.get(t, 0)
        if bc != ac:
            diff["count_changes"][t] = {"before": bc, "after": ac, "delta": ac - bc}

    lines = []
    if diff["nodes_added"]:
        lines.append(f"新增 {len(diff['nodes_added'])} 个节点")
    if diff["nodes_removed"]:
        lines.append(f"移除 {len(diff['nodes_removed'])} 个节点")
    if diff["text_changes"]:
        lines.append(f"文本变化 {len(diff['text_changes'])} 处")
    if diff["count_changes"]:
        parts = [f"{t}: {v['before']}→{v['after']}" for t, v in diff["count_changes"].items()]
        lines.append(f"数量变化: {', '.join(parts)}")
    if not lines:
        lines.append("界面无明显变化")
    diff["summary"] = "; ".join(lines)
    return diff


def diff_a11y_summary(before_path: str, after_path: str) -> dict:
    """对比两次无障碍树 JSON，返回窗口/焦点层面的结构化差异

    -i 返回窗口列表，比较：窗口数量、各窗口 bundle、页面路径变化、焦点节点变化。
    """
    diff = {"window_changes": [], "focused_changes": [], "summary": ""}

    def _win_info(path):
        tree = _safe_load(path)
        if tree is None:
            return []
        windows = tree if isinstance(tree, list) else tree.get("children", [])
        infos = []
        for w in windows:
            attrs = _get_attrs(w)
            infos.append({
                "bundle": attrs.get("bundleName", "(未知)"),
                "page": attrs.get("pagePath", ""),
                "nodes": len(_flatten_tree(w)),
                "focused": [n.get("text", "") for n in _flatten_tree(w)
                            if n.get("focused") == "true"],
            })
        return infos

    before_win = _win_info(before_path)
    after_win = _win_info(after_path)

    if len(before_win) != len(after_win):
        diff["window_changes"].append(f"窗口数量: {len(before_win)} → {len(after_win)}")
    for i, w in enumerate(after_win):
        if i < len(before_win):
            b = before_win[i]
            if b["page"] != w["page"]:
                diff["window_changes"].append(
                    f"窗口{i} 页面: {b['bundle']} {b['page']} → {w['page']}")
        diff["focused_changes"].append({"step": i, "focused": w["focused"]})

    if diff["window_changes"] or any(c["focused"] for c in diff["focused_changes"]):
        parts = diff["window_changes"]
        focus_lines = [c["focused"] for c in diff["focused_changes"] if c["focused"]]
        if focus_lines:
            parts.append(f"焦点节点: {focus_lines}")
        diff["summary"] = "; ".join(parts) if parts else "无障碍树无明显变化"
    else:
        diff["summary"] = "无障碍树无明显变化"
    return diff


# ============================================================
# 采集报告生成
# ============================================================

def generate_collection_report(scenario: dict, step_results: List[dict],
                               manifest: dict, out_dir: str,
                               baseline_dir: str) -> str:
    """生成页面双树采集报告 collection_report.md

    每步：执行动作、note（对应的用户操作步骤）、实际 hdc 命令、状态、
    组件树/无障碍树 diff（相对上一步）。
    """
    report_path = os.path.join(out_dir, "collection_report.md")
    lines = []
    lines.append(f"# 页面组件树 + 无障碍树采集报告\n")
    lines.append(f"**场景**: {scenario.get('name', '未命名')}")
    if scenario.get("description"):
        lines.append(f"**描述**: {scenario['description']}")
    lines.append(f"**应用**: {manifest.get('bundle')} / {manifest.get('ability')}")
    lines.append(f"**设备**: {manifest.get('device')}")
    if manifest.get("screen_reader"):
        lines.append(f"**屏幕朗读**: {manifest['screen_reader']}")
    lines.append(f"**输出目录**: {out_dir}")
    lines.append("")

    # 初始状态
    lines.append("## 初始状态 (未执行任何操作)\n")
    lines.append(f"- `{baseline_dir}/component_tree.json` — 组件树")
    lines.append(f"- `{baseline_dir}/a11y_tree.json` — 无障碍树")
    lines.append(f"- `{baseline_dir}/tree_summary.md` — 双树摘要")
    lines.append("")

    # 步骤执行结果 + 差异
    lines.append("## 步骤执行结果\n")
    lines.append("| # | 动作 | 对应操作步骤(note) | hdc 命令 | 状态 | 组件树 diff | 无障碍树 diff |")
    lines.append("|---|------|------|----------|------|------|------|")
    prev_comp = os.path.join(baseline_dir, "component_tree.json")
    prev_a11y = os.path.join(baseline_dir, "a11y_tree.json")
    for r in step_results:
        status = "PASS" if r.get("success") else "FAIL"
        cmd = r.get("hdc_command", "")
        comp_diff = ""
        a11y_diff = ""
        if r.get("comp_path") and os.path.isfile(prev_comp):
            d = diff_layouts(prev_comp, r["comp_path"])
            comp_diff = d["summary"]
        if r.get("a11y_path") and os.path.isfile(prev_a11y):
            d = diff_a11y_summary(prev_a11y, r["a11y_path"])
            a11y_diff = d["summary"]
        lines.append(f"| {r.get('step','')} | {r.get('action','')} | {r.get('note','')} | "
                     f"`{cmd}` | {status} | {comp_diff} | {a11y_diff} |")
        if r.get("comp_path"):
            prev_comp = r["comp_path"]
        if r.get("a11y_path"):
            prev_a11y = r["a11y_path"]
    lines.append("")

    # 采集产物清单
    lines.append("## 采集产物\n")
    lines.append(f"- 初始状态: `{baseline_dir}/`")
    for r in step_results:
        if r.get("comp_path"):
            step_dir = os.path.dirname(r["comp_path"])
            lines.append(f"- Step {r.get('step','')} ({r.get('action','')} {r.get('note','')}): `{step_dir}/`")

    with open(report_path, "w", encoding="utf-8") as f:
        f.write("\n".join(lines))
    print(f"[OK] 采集报告: {report_path}")
    return report_path


def write_manifest(out_dir: str, bundle: str, ability: str, device: str,
                   scenario: Optional[dict] = None,
                   a11y_path: Optional[str] = None) -> str:
    """生成 manifest.json：应用/设备/时间/屏幕朗读状态"""
    active, proc = is_screen_reader_active(a11y_path)
    if active:
        sr = "已开启"
    elif proc:
        sr = "进程在跑（可能未实际开启）"
    else:
        sr = "未开启"
    manifest = {
        "bundle": bundle,
        "ability": ability,
        "device": device,
        "screen_reader": sr,
        "screen_reader_proc": proc,
        "timestamp": time.strftime("%Y-%m-%d %H:%M:%S"),
        "output_dir": out_dir,
    }
    if scenario:
        manifest["scenario"] = {"name": scenario.get("name", ""),
                                "description": scenario.get("description", ""),
                                "steps": scenario.get("steps", [])}
    path = os.path.join(out_dir, "manifest.json")
    with open(path, "w", encoding="utf-8") as f:
        json.dump(manifest, f, ensure_ascii=False, indent=2)
    print(f"[OK] 采集元数据: {path}")
    return manifest


def main():
    parser = argparse.ArgumentParser(description="HarmonyOS 页面组件树 + 无障碍树采集")
    parser.add_argument("--project", default=None, help="鸿蒙项目目录（含 AppScope/），不指定则自动向上搜索")
    parser.add_argument("--bundle", default=None, help="应用包名（不指定则从项目目录自动检测）")
    parser.add_argument("--ability", default=None, help="Ability 名称（不指定则从项目目录自动检测）")
    parser.add_argument("--hap", default="", help="HAP 安装包路径（可选）")
    parser.add_argument("--out", default=None, help="输出目录（默认 <项目目录>/tree_collect_output）")
    parser.add_argument("--no-launch", action="store_true", help="跳过启动应用（已在前台时使用）")
    parser.add_argument("--wait", type=int, default=3, help="启动后等待秒数")
    parser.add_argument("--emulator", default=None, metavar="ADDR",
                        help="模拟器地址（端口号如 5555，或完整地址如 127.0.0.1:5555）")
    parser.add_argument("--capture", action="store_true",
                        help="仅采集当前页面初始状态的组件树 + 无障碍树（用于生成测试场景）")
    parser.add_argument("--scenario", default=None, metavar="JSON",
                        help="测试场景配置文件路径（JSON），执行场景并逐步采集双树")
    args = parser.parse_args()

    # === 自动检测项目信息 ===
    project_dir = args.project
    if not project_dir:
        project_dir = find_project_dir()
    if project_dir:
        print(f"[OK] 鸿蒙项目目录: {project_dir}")
        if not args.bundle:
            args.bundle = detect_bundle_name(project_dir)
    else:
        print("[WARN] 未找到鸿蒙项目目录（AppScope/），将使用命令行参数")

    if not args.bundle:
        print("[ERROR] 无法确定应用包名。请用 --bundle 指定，或在鸿蒙项目目录下运行。")
        sys.exit(1)

    # 输出目录默认放到工程路径下
    out_dir = args.out
    if not out_dir:
        base = project_dir if project_dir else os.getcwd()
        out_dir = os.path.join(base, "tree_collect_output")

    # 先连接设备，再检测 ability：优先查设备上真正安装的 mainElementName
    device = check_device(args.emulator)
    if not args.ability:
        args.ability = detect_ability_from_device(args.bundle)
    if not args.ability and project_dir:
        args.ability = detect_ability_from_source(project_dir)
    if not args.ability:
        print("[ERROR] 无法确定 Ability 名称。请用 --ability 指定，或在鸿蒙项目目录下运行。")
        sys.exit(1)

    print(f"[INFO] 目标应用: {args.bundle} / {args.ability}")
    os.makedirs(out_dir, exist_ok=True)

    if args.hap:
        install_hap(args.hap)

    if not args.no_launch:
        launch_app(args.bundle, args.ability)
        if args.wait > 0:
            print(f"[INFO] 等待 {args.wait}s 界面加载...")
            time.sleep(args.wait)

    # === 基线采集：初始状态（未执行任何操作） ===
    print(f"\n{'='*50}")
    print("采集初始状态（未执行任何操作）")
    print(f"{'='*50}")
    baseline_dir = os.path.join(out_dir, "step_000_baseline")
    capture_state(baseline_dir, bundle=args.bundle)
    write_manifest(out_dir, args.bundle, args.ability, device,
                   a11y_path=os.path.join(baseline_dir, "a11y_tree.json"))

    if args.capture:
        print(f"\n{'='*50}")
        print(f"初始状态采集完成！")
        print(f"  组件树: {baseline_dir}/component_tree.json")
        print(f"  无障碍树: {baseline_dir}/a11y_tree.json")
        print(f"  摘要: {baseline_dir}/tree_summary.md")
        print(f"  元数据: {out_dir}/manifest.json")
        print(f"{'='*50}")
        print("提示: 请结合组件树摘要 + 项目源码 + 用户操作步骤生成测试场景 JSON，")
        print("      再用 --scenario 执行并逐步采集双树。")
        return

    if not args.scenario:
        print("[WARN] 请指定 --capture 或 --scenario。")
        return

    # === 场景执行：逐步操作 + 逐步采集双树 ===
    scenario = load_scenario(args.scenario)

    print(f"\n{'='*50}")
    print(f"执行测试场景 — {scenario.get('name', '未命名')}")
    print(f"{'='*50}")

    step_results = execute_scenario(scenario, out_dir, bundle=args.bundle)

    # === 生成报告 ===
    last_a11y = os.path.join(baseline_dir, "a11y_tree.json")
    for r in step_results:
        if r.get("a11y_path"):
            last_a11y = r["a11y_path"]
    report_path = generate_collection_report(
        scenario, step_results,
        write_manifest(out_dir, args.bundle, args.ability, device, scenario, a11y_path=last_a11y),
        out_dir, baseline_dir)

    print(f"\n{'='*50}")
    print(f"场景执行 + 双树采集完成！")
    print(f"  报告: {report_path}")
    print(f"  初始状态: {baseline_dir}/")
    for r in step_results:
        if r.get("comp_path"):
            print(f"  Step {r.get('step','')}: {os.path.dirname(r['comp_path'])}/")
    print(f"{'='*50}")


if __name__ == "__main__":
    main()
