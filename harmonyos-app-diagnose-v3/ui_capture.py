# -*- coding: utf-8 -*-
"""HarmonyOS UI 状态采集 + 自动交互验证脚本

用法:
    # 基础采集（截图 + 控件树）
    python ui_capture.py [--bundle BUNDLE] [--ability ABILITY] [--out DIR] [--no-launch]
    python ui_capture.py --emulator 5555

    # 交互验证（执行场景 → 二次采集 → 差异报告）
    python ui_capture.py --scenario scenario.json --out ./ui_capture_output
    python ui_capture.py --scenario scenario.json --emulator 5555

功能:
    1. 检测设备连接（支持 USB 物理设备和本地模拟器）
    2. 安装并启动应用（可选）
    3. 截屏 + dump 控件树
    4. 解析控件树输出结构化摘要
    5. 可配置交互场景：点击/输入/滑动/返回/等待
    6. 交互前后二次采集，生成差异对比与断言报告

原理:
    直接调用 hdc 命令行工具完成采集与交互，不依赖 Hypium 测试框架
    hdc (HarmonyOS Device Connector) 是鸿蒙的设备调试桥，类似 Android 的 adb
    串联流程: 连接 → 启动 → 基线采集 → 交互 → 二次采集 → 差异分析
"""

import argparse
import json
import os
import re
import subprocess
import sys
import threading
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

# 无障碍屏幕朗读测试模式开关。置 True 后交互引擎把 click 改写为
# 「单击聚焦 + 双击激活」、把 swipe/fling 改写为双指滑动，并启用无障碍断言。
# 由命令行 --a11y 置位。False 时所有行为与原 v3 完全一致。
A11Y_MODE = False


# ============================================================
# 交互场景配置格式说明 (scenario JSON)
# ============================================================
# {
#   "name": "场景名称",
#   "description": "场景描述",
#   "steps": [
#     {"action": "click", "target": {"text": "按钮文字"}},
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
#   ],
#   "assertions": [
#     {"type": "exists", "target": {"text": "提交成功"}, "message": "应显示成功提示"},
#     {"type": "not_exists", "target": {"text": "加载中"}, "message": "加载应已完成"},
#     {"type": "text_changed", "target": {"key": "counter"}, "message": "计数器应变化"},
#     {"type": "text_equals", "target": {"key": "counter"}, "expected": "1", "message": "计数器应为1"},
#     {"type": "clickable", "target": {"text": "下一步"}, "expected": true, "message": "下一步应可点击"},
#     {"type": "count_changed", "target": {"type": "ListItem"}, "message": "列表项数量应变化"},
#     {"type": "page_changed", "message": "页面应发生变化"}
#   ]
# }
# ============================================================


def run(cmd: str, timeout: int = 30) -> str:
    """执行 shell 命令并返回 stdout（不含 stderr，避免错误流污染关键字判断）

    历史上这里合并了 stdout+stderr，导致 connect_emulator 的 "Connect OK" 判断、
    capture_screenshot 的 "error" 判断被 stderr 警告干扰。改为只返回 stdout；
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


def is_screen_reader_active() -> Tuple[bool, str]:
    """检测屏幕朗读是否已开启。

    判定依据：屏幕朗读开启后会起一个 com.huawei.hmos.screenreader:accessibility
    进程（HarmonyOS），grep 到即视为已开启。该方法已在物理设备上双向验证：
    未开启→空，已开启→命中该进程。

    注：aa dump -l 查不到它（AccessibilityAbility 扩展不在 ability 列表），
    静态 dumpLayout 的 focused==true 节点数为 0（要点一下才有焦点），
    二者均不可单独用于开启状态判定，故以进程检测为准。

    返回 (是否开启, 命中的进程行)；未开启时进程行为空串。
    """
    out = run("hdc shell ps -ef")
    for line in out.splitlines():
        low = line.lower()
        if "screenreader" in low and "grep" not in low:
            return True, line.strip()
    return False, ""


def wait_for_screen_reader(max_rounds: int = 2) -> bool:
    """检测屏幕朗读是否开启；未开启则提示用户手动开启并阻塞等待确认。

    设计原则（用户明确要求）：
    - 不自动改设备设置，不执行任何 settings put / param set。屏幕朗读只能由
      用户在设备上手动开启，以保证不误改用户设备状态。
    - 检测未开启时打印指引，调用 input() 阻塞等待用户开启后回车继续；回车后
      重新检测一次。最多 max_rounds 轮；之后无论结果都继续执行，并在返回值
      与报告中如实反映"屏幕朗读未确认开启"。

    非交互环境（stdin 非 tty，如 CI）直接跳过阻塞，避免卡死：打印后立即返回
    当前检测结果。
    """
    active, proc = is_screen_reader_active()
    if active:
        print(f"[OK] 屏幕朗读已开启: {proc}")
        return True

    # 非 tty（CI / 后台）：不阻塞，打印后返回
    if not sys.stdin.isatty():
        print("[提示] 屏幕朗读未开启，且当前为非交互环境，跳过等待。")
        print("       无障碍测试将在「屏幕朗读未确认开启」状态下运行，焦点/朗读断言可能不生效。")
        return False

    rounds = 0
    while not active and rounds < max_rounds:
        rounds += 1
        print(f"\n[提示] 屏幕朗读未开启（第 {rounds}/{max_rounds} 轮）。请在设备上手动开启：")
        print("  路径：设置 → 辅助功能 → 屏幕朗读 → 打开")
        try:
            input("  开启完成后按回车继续...")
        except EOFError:
            # 输入被切断（如被重定向到空），不阻塞
            print("  (输入流结束，跳过等待)")
            break
        active, proc = is_screen_reader_active()
        if active:
            print(f"[OK] 屏幕朗读已开启: {proc}")
            return True
        print(f"[WARN] 仍检测到未开启（第 {rounds}/{max_rounds} 轮）。")

    if not active:
        print("[提示] 屏幕朗读仍未确认开启。将继续执行，但无障碍焦点/朗读相关断言可能不生效。")
    return active


def install_hap(hap_path: str):
    """安装 hap 包到设备

    指定了 --hap 但路径不存在时显式告警：否则会静默跳过安装，导致用旧包
    跑完整轮诊断、给出基于过期构建的结论。诊断结论的可信度依赖被测产物
    是最新的，故此情况视为需用户介入的错误而非可忽略。
    """
    if not hap_path:
        return
    if not os.path.isfile(hap_path):
        print(f"[ERROR] 指定的 --hap 路径不存在: {hap_path}")
        print("        将跳过安装。请确认路径，否则可能诊断的是旧构建产物。")
        return
    print(f"[INFO] 安装 {hap_path} ...")
    stdout, stderr, rc = run_full(f'hdc install -r "{hap_path}"')
    if stdout:
        print(f"  {stdout}")
    if stderr:
        print(f"  [stderr] {stderr}")
    # hdc install 失败通常 rc!=0，给出明确信号
    if rc != 0 and "msg" not in (stdout + stderr).lower():
        print(f"  [WARN] hdc install 返回码 {rc}，安装可能失败，请确认设备状态")


def launch_app(bundle: str, ability: str):
    """启动应用"""
    print(f"[INFO] 启动 {bundle}/{ability} ...")
    run(f"hdc shell aa start -a {ability} -b {bundle}")
    time.sleep(3)


def capture_screenshot(out_dir: str) -> str:
    """截取设备屏幕并拉取到本地，依次尝试多种截图方式

    截图在本 skill 中是**给人看的附件**，不参与程序化诊断判断（本环境模型无
    多模态能力）。白屏等视觉判断由 detect_blank_screen() 基于控件树完成，
    此处仅尽量把图拉下来供人类复核。
    """
    local_path = os.path.join(out_dir, "screenshot.png")
    device_path = "/data/local/tmp/_ui_capture_screen.png"

    # (方法名, hdc 命令, 是否在 stdout/stderr 含 error 时跳过)
    # 用 run_full 分别检查 stdout 和 stderr，避免合并流误判
    methods = [
        ("snapshot_display", f"hdc shell snapshot_display -f {device_path}", True),
        ("uitest screenCap", f"hdc shell uitest screenCap -p {device_path}", False),
        ("screencap", f"hdc shell screencap -p {device_path}", False),
    ]
    for name, cmd, skip_on_error in methods:
        stdout, stderr, _ = run_full(cmd)
        # 只在该方法的命令本身报错时跳过（stderr 是真正的失败信号）
        if skip_on_error and ("error" in (stdout + stderr).lower()):
            continue
        run(f'hdc file recv {device_path} "{local_path}"')
        run(f"hdc shell rm -f {device_path}")
        if os.path.isfile(local_path) and os.path.getsize(local_path) > 0:
            print(f"[OK] 截图已保存({name}): {local_path}")
            return local_path

    print("[WARN] 截图拉取失败（已尝试 snapshot_display / uitest screenCap / screencap）")
    print("       截图为人类复核附件，诊断结论以控件树和日志为准。")
    return local_path


def dump_layout(out_dir: str, extra_attrs: bool = False) -> str:
    """Dump 控件树并拉取到本地

    extra_attrs=True 时附加 -a，保存 BackgroundColor/Content/FontColor/FontSize/
    extraAttrs 属性数据。无障碍屏幕朗读模式下需传 True：extraAttrs 里通常含
    accessibilityText 等无障碍标签，供 accessibility_label 断言读取。
    普通模式默认 False，避免控件树变大拖慢解析。注：-a 与 -i 不可同时使用。
    """
    device_json = "/data/local/tmp/_ui_capture_layout.json"
    local_path = os.path.join(out_dir, "layout.json")
    parts = ["hdc", "shell", "uitest", "dumpLayout"]
    if extra_attrs:
        parts.append("-a")
    parts.extend(["-p", device_json])
    run(" ".join(parts))
    run(f'hdc file recv {device_json} "{local_path}"')
    run(f"hdc shell rm {device_json}")
    if os.path.isfile(local_path):
        print(f"[OK] 控件树已保存: {local_path}" + ("（含 extraAttrs）" if extra_attrs else ""))
    else:
        print("[WARN] 控件树拉取失败")
    return local_path


def detect_project_info(project_dir: str) -> tuple:
    """从鸿蒙项目目录自动检测 bundleName 和 abilityName

    搜索 AppScope/app.json5 获取 bundleName，
    搜索 entry/src/main/module.json5 获取第一个 ability 的 name
    返回 (bundle_name, ability_name)，检测失败返回 (None, None)
    """
    bundle_name = None
    ability_name = None

    # 读取 bundleName
    app_json = os.path.join(project_dir, "AppScope", "app.json5")
    if os.path.isfile(app_json):
        try:
            content = Path(app_json).read_text(encoding="utf-8")
            # json5 可能有注释和尾逗号，用正则提取
            m = re.search(r'"bundleName"\s*:\s*"([^"]+)"', content)
            if m:
                bundle_name = m.group(1)
                print(f"[OK] 检测到 bundleName: {bundle_name}")
        except Exception as e:
            print(f"[WARN] 读取 {app_json} 失败: {e}")

    # 读取 abilityName
    module_json = os.path.join(project_dir, "entry", "src", "main", "module.json5")
    if os.path.isfile(module_json):
        try:
            content = Path(module_json).read_text(encoding="utf-8")
            m = re.search(r'"name"\s*:\s*"(\w*Ability\w*)"', content)
            if m:
                ability_name = m.group(1)
                print(f"[OK] 检测到 abilityName: {ability_name}")
        except Exception as e:
            print(f"[WARN] 读取 {module_json} 失败: {e}")

    return bundle_name, ability_name


def find_project_dir() -> Optional[str]:
    """向上搜索鸿蒙项目根目录（含 AppScope/ 的目录）

    从当前工作目录开始，逐级向上查找
    """
    cwd = Path.cwd()
    # 先检查当前目录
    if (cwd / "AppScope").is_dir():
        return str(cwd)
    # 向上最多搜索 10 级
    for parent in list(cwd.parents)[:10]:
        if (parent / "AppScope").is_dir():
            return str(parent)
    return None


def filter_tree_by_bundle(tree: dict, bundle: str) -> list:
    """从完整控件树中提取属于指定 bundleName 的子树"""
    results = []
    children = tree.get("children", []) if isinstance(tree, dict) else tree
    for child in children:
        attrs = child.get("attributes", {})
        if attrs.get("bundleName") == bundle:
            results.append(child)
        else:
            # 递归查找（系统窗口可能包裹应用窗口）
            results.extend(filter_tree_by_bundle(child, bundle))
    return results


def detect_blank_screen(flat_nodes: List[dict], bundle: Optional[str] = None) -> dict:
    """白屏/渲染失败检测（不依赖截图视觉识别，纯控件树启发式）

    本环境模型无多模态能力，无法"看"截图判断白屏。改用控件树信号交叉推断：
    - 节点极少（< 阈值）且无可见文本/图片 → 疑似白屏
    - 控件树存在但有界节点数为 0 → 渲染未完成

    返回:
        {"is_blank": bool, "reason": str, "node_count": int,
         "visible_text_count": int, "image_count": int}
    本函数不读截图像素，截图仅供人类复核。若截图确为空白而控件树丰富，
    说明是渲染层失败（框架问题），结论仍以控件树为准。
    """
    # 过滤出有 bounds 的节点（无 bounds 的多为容器/系统节点）
    nodes_with_bounds = [n for n in flat_nodes if _parse_bounds(_get_attrs(n).get("bounds", ""))]
    node_count = len(nodes_with_bounds)
    visible_texts = [n for n in nodes_with_bounds
                     if _get_attrs(n).get("text", "").strip()]
    image_count = sum(1 for n in nodes_with_bounds
                      if _get_attrs(n).get("type", "") in ("Image", "Img"))

    # 阈值：少于 3 个有界节点、且几乎无文本无图片 → 疑似白屏
    # （正常界面至少有标题栏/内容/导航等若干节点）
    threshold = 3
    is_blank = node_count < threshold and len(visible_texts) == 0 and image_count == 0

    if is_blank:
        reason = (f"有界控件仅 {node_count} 个（< {threshold}），且无可见文本/图片，"
                  f"疑似白屏或渲染未完成")
    elif node_count == 0 and flat_nodes:
        reason = "控件树存在节点但无任何有界控件，渲染可能未完成"
    else:
        reason = "控件树正常，未检测到白屏特征"

    return {
        "is_blank": is_blank or (node_count == 0 and bool(flat_nodes)),
        "reason": reason,
        "node_count": node_count,
        "visible_text_count": len(visible_texts),
        "image_count": image_count,
    }


def detect_layout_overlaps(tree: dict, bundle: Optional[str] = None,
                           max_results: int = 20) -> List[dict]:
    """布局重叠检测（纯控件树几何，不依赖截图）

    遍历控件树，对每个父节点的直接子节点两两检查 bounds 是否相交。
    重叠可能意味着 z-index/层叠错误或布局溢出。

    返回 [{"parent_type": str, "child_a": {...}, "child_b": {...}, "overlap_area": int}, ...]
    """
    overlaps = []

    def _area(b):
        return max(0, b[2] - b[0]) * max(0, b[3] - b[1])

    def _intersect(a, b):
        x1, y1 = max(a[0], b[0]), max(a[1], b[1])
        x2, y2 = min(a[2], b[2]), min(a[3], b[3])
        if x2 <= x1 or y2 <= y1:
            return None
        return (x1, y1, x2, y2)

    def _walk(node, depth=0):
        attrs = _get_attrs(node)
        children = node.get("children", []) if isinstance(node, dict) else []
        # 收集有 bounds 的直接子节点
        kid_bounds = []
        for ch in children:
            ca = _get_attrs(ch)
            cb = _parse_bounds(ca.get("bounds", ""))
            if cb:
                kid_bounds.append((ca, cb, ch))

        # 两两检查相交
        for i in range(len(kid_bounds)):
            for j in range(i + 1, len(kid_bounds)):
                a_attrs, a_b, _ = kid_bounds[i]
                b_attrs, b_b, _ = kid_bounds[j]
                inter = _intersect(a_b, b_b)
                if inter:
                    # 忽略面积过小的相交（< 9px²，多为边界接触）
                    if _area(inter) < 9:
                        continue
                    overlaps.append({
                        "parent_type": attrs.get("type", ""),
                        "child_a": {"type": a_attrs.get("type", ""),
                                     "text": a_attrs.get("text", ""),
                                     "bounds": a_attrs.get("bounds", "")},
                        "child_b": {"type": b_attrs.get("type", ""),
                                     "text": b_attrs.get("text", ""),
                                     "bounds": b_attrs.get("bounds", "")},
                        "overlap_area": _area(inter),
                    })
                    if len(overlaps) >= max_results:
                        return
        for ch in children:
            _walk(ch, depth + 1)

    # 仅分析目标 bundle 子树（若指定），避免系统窗口干扰
    trees = [tree]
    if bundle and isinstance(tree, dict):
        app_subtrees = filter_tree_by_bundle(tree, bundle)
        if app_subtrees:
            trees = app_subtrees
    for t in trees:
        _walk(t)
    return overlaps


def detect_overflow(tree: dict, bundle: Optional[str] = None,
                    max_results: int = 20) -> List[dict]:
    """布局溢出检测（纯控件树几何，不依赖截图）

    检查子节点 bounds 是否超出父节点 bounds 范围。超出意味着内容溢出
    或父容器尺寸设置错误。

    返回 [{"parent_type": str, "parent_bounds": str,
           "child_type": str, "child_bounds": str, "overflow": str}, ...]
    """
    overflows = []

    def _walk(node, depth=0):
        attrs = _get_attrs(node)
        parent_bounds = _parse_bounds(attrs.get("bounds", ""))
        if not parent_bounds:
            children = node.get("children", []) if isinstance(node, dict) else []
            for ch in children:
                _walk(ch, depth + 1)
            return
        px1, py1, px2, py2 = parent_bounds
        for ch in node.get("children", []):
            ca = _get_attrs(ch)
            cb = _parse_bounds(ca.get("bounds", ""))
            if not cb:
                _walk(ch, depth + 1)
                continue
            cx1, cy1, cx2, cy2 = cb
            # 子超出父的量（各方向）
            over_left = max(0, px1 - cx1)
            over_top = max(0, py1 - cy1)
            over_right = max(0, cx2 - px2)
            over_bottom = max(0, cy2 - py2)
            total = over_left + over_top + over_right + over_bottom
            # 容差 2px，避免边界像素误差
            if total > 2:
                overflows.append({
                    "parent_type": attrs.get("type", ""),
                    "parent_bounds": attrs.get("bounds", ""),
                    "child_type": ca.get("type", ""),
                    "child_text": ca.get("text", ""),
                    "child_bounds": ca.get("bounds", ""),
                    "overflow": f"left={over_left},top={over_top},right={over_right},bottom={over_bottom}",
                })
                if len(overflows) >= max_results:
                    return
            _walk(ch, depth + 1)

    trees = [tree]
    if bundle and isinstance(tree, dict):
        app_subtrees = filter_tree_by_bundle(tree, bundle)
        if app_subtrees:
            trees = app_subtrees
    for t in trees:
        _walk(t)
    return overflows


def summarize_layout(layout_path: str, out_dir: str, bundle: Optional[str] = None) -> str:
    """解析控件树 JSON，生成可读文本摘要

    若指定 bundle，只分析属于该应用的子树
    """
    summary_path = os.path.join(out_dir, "ui_summary.md")
    if not os.path.isfile(layout_path):
        return summary_path

    with open(layout_path, "r", encoding="utf-8") as f:
        try:
            tree = json.load(f)
        except json.JSONDecodeError:
            print("[WARN] 控件树 JSON 解析失败")
            return summary_path

    # 按 bundle 过滤，只分析目标应用的控件
    if bundle:
        app_trees = filter_tree_by_bundle(tree, bundle)
        if app_trees:
            print(f"[OK] 已过滤控件树，仅保留 {bundle} 的 {len(app_trees)} 个窗口")
        else:
            print(f"[WARN] 未找到 bundleName={bundle} 的控件，将分析全量控件树")
            app_trees = [tree] if isinstance(tree, dict) else tree
    else:
        app_trees = [tree] if isinstance(tree, dict) else tree

    lines = [f"# UI 控件树摘要\n"]
    if bundle:
        lines.append(f"**应用**: `{bundle}`\n")
    stats = {"total": 0, "types": {}, "texts": [], "keys": [], "hints": [],
             "clickable": 0, "scrollable": 0, "max_depth": 0,
             "element_sizes": [], "clickable_sizes": [],
             "text_element_sizes": [], "sibling_gaps": [],
             "screen_bounds": None}

    def walk(node, depth=0):
        attrs = _get_attrs(node)

        stats["total"] += 1
        if depth > stats["max_depth"]:
            stats["max_depth"] = depth

        comp_type = attrs.get("type", "") or "Unknown"
        stats["types"][comp_type] = stats["types"].get(comp_type, 0) + 1

        text = attrs.get("text", "")
        key = attrs.get("key", "")
        hint = attrs.get("hint", "")
        if text:
            stats["texts"].append(text)
        if key:
            stats["keys"].append(key)
        if hint:
            stats["hints"].append(hint)
        if attrs.get("clickable") == "true":
            stats["clickable"] += 1
        if attrs.get("scrollable") == "true":
            stats["scrollable"] += 1

        # 解析 bounds 提取尺寸信息
        bounds = _parse_bounds(attrs.get("bounds", ""))
        size_label = ""
        if bounds:
            x1, y1, x2, y2 = bounds
            w, h = x2 - x1, y2 - y1
            if w > 0 and h > 0:
                stats["element_sizes"].append((comp_type, w, h))
                size_label = f" {w}×{h}"
        # 记录屏幕级边界
                if stats["screen_bounds"] is None:
                    stats["screen_bounds"] = (x1, y1, x2, y2)
                else:
                    sb = stats["screen_bounds"]
                    stats["screen_bounds"] = (
                        min(sb[0], x1), min(sb[1], y1),
                        max(sb[2], x2), max(sb[3], y2))
                # 可点击控件尺寸
                if attrs.get("clickable") == "true":
                    stats["clickable_sizes"].append((comp_type, w, h, text or key or hint))
                # 有文本的控件尺寸，用于字体大小推断
                if text:
                    stats["text_element_sizes"].append((text, w, h))

        indent = "  " * depth
        label = comp_type
        if size_label:
            label += size_label
        if text:
            label += f' text="{text}"'
        if hint:
            label += f' hint="{hint}"'
        if key:
            label += f' key="{key}"'
        if attrs.get("clickable") == "true":
            label += " [clickable]"
        lines.append(f"{indent}- {label}")

        # 计算同级子元素间的间距
        children = node.get("children", [])
        child_bounds_list = []
        for child in children:
            child_attrs = _get_attrs(child)
            cb = _parse_bounds(child_attrs.get("bounds", ""))
            if cb:
                child_bounds_list.append(cb)
        # 按纵向排序，计算相邻元素垂直间距
        child_bounds_list.sort(key=lambda b: b[1])
        for i in range(1, len(child_bounds_list)):
            gap = child_bounds_list[i][1] - child_bounds_list[i - 1][3]
            if gap >= 0:  # 只记录非重叠的间距
                stats["sibling_gaps"].append(gap)

        for child in children:
            walk(child, depth + 1)

    for subtree in app_trees:
        walk(subtree)

    lines.append(f"\n## 统计")
    lines.append(f"- 控件总数: {stats['total']}")
    lines.append(f"- 可点击: {stats['clickable']}")
    lines.append(f"- 可滚动: {stats['scrollable']}")
    lines.append(f"- 最大嵌套深度: {stats['max_depth']}")
    lines.append(f"- 控件类型分布:")
    for t, c in sorted(stats["types"].items(), key=lambda x: -x[1]):
        lines.append(f"  - {t}: {c}")
    if stats["texts"]:
        lines.append(f"- 文本内容: {stats['texts']}")
    if stats["hints"]:
        lines.append(f"- Hint 提示: {stats['hints']}")
    if stats["keys"]:
        lines.append(f"- Key 标识: {stats['keys']}")

    # === 视觉审美量化数据 ===
    lines.append(f"\n## 视觉审美分析数据")

    # 屏幕利用率
    if stats["screen_bounds"] and stats["element_sizes"]:
        sb = stats["screen_bounds"]
        screen_w = sb[2] - sb[0]
        screen_h = sb[3] - sb[1]
        screen_area = screen_w * screen_h
        lines.append(f"\n### 屏幕信息")
        lines.append(f"- 屏幕尺寸: {screen_w}×{screen_h} px")
        if screen_area > 0:
            # 叶子节点面积粗估
            leaf_area = sum(w * h for _, w, h in stats["element_sizes"]
                           if w < screen_w and h < screen_h)
            utilization = min(leaf_area / screen_area * 100, 100)
            lines.append(f"- 屏幕利用率（估算）: {utilization:.1f}%")

    # 可点击控件尺寸检查
    if stats["clickable_sizes"]:
        lines.append(f"\n### 可点击控件尺寸")
        small_touch = []
        for comp_type, w, h, identifier in stats["clickable_sizes"]:
            if w < 48 or h < 48:
                small_touch.append(f"{comp_type}({identifier}) {w}×{h}")
        if small_touch:
            lines.append(f"- ⚠️ 触控区域过小（<48px）: {small_touch}")
        else:
            lines.append(f"- OK all clickable controls size >= 48px")
        sizes_summary = [(f"{ct}({ident})", w, h)
                         for ct, w, h, ident in stats["clickable_sizes"]]
        lines.append(f"- 尺寸列表: {sizes_summary}")

    # 文本控件尺寸（辅助判断字体大小）
    if stats["text_element_sizes"]:
        lines.append(f"\n### 文本控件尺寸")
        tiny_text = []
        for text_val, w, h in stats["text_element_sizes"]:
            if h < 20:  # 高度过小的文本区域，可能字体过小
                tiny_text.append(f'"{text_val}" h={h}')
        if tiny_text:
            lines.append(f"- ⚠️ 高度过小的文本控件（h<20px，可能字体过小）: {tiny_text}")
        else:
            lines.append(f"- OK all text controls height >= 20px")
        lines.append(f"- 文本控件高度分布: {sorted(set(h for _, _, h in stats['text_element_sizes']))}")

    # 间距一致性分析
    if stats["sibling_gaps"]:
        gaps = stats["sibling_gaps"]
        avg_gap = sum(gaps) / len(gaps)
        min_gap = min(gaps)
        max_gap = max(gaps)
        lines.append(f"\n### 间距分析")
        lines.append(f"- 同级元素垂直间距: 最小={min_gap}px, 最大={max_gap}px, 平均={avg_gap:.1f}px")
        if max_gap > 0 and min_gap >= 0:
            if min_gap == 0 and max_gap > 0:
                lines.append(f"- ⚠️ 间距不一致: 存在 0px 间距与 {max_gap}px 间距并存")
            elif max_gap > min_gap * 3 and min_gap > 0:
                lines.append(f"- ⚠️ 间距差异较大: 最大/最小比值 = {max_gap / min_gap:.1f}x")
            else:
                lines.append(f"- OK spacing looks consistent")
        # 大间距区域（可能是过度留白）
        large_gaps = [g for g in gaps if g > 100]
        if large_gaps:
            lines.append(f"- ⚠️ 存在 {len(large_gaps)} 处大间距（>100px）: {sorted(large_gaps, reverse=True)[:5]}")

    # 控件尺寸分布
    if stats["element_sizes"]:
        widths = [w for _, w, _ in stats["element_sizes"] if w > 0]
        heights = [h for _, _, h in stats["element_sizes"] if h > 0]
        if widths and heights:
            lines.append(f"\n### 控件尺寸分布")
            lines.append(f"- 宽度范围: {min(widths)}–{max(widths)}px, 中位数={sorted(widths)[len(widths)//2]}px")
            lines.append(f"- 高度范围: {min(heights)}–{max(heights)}px, 中位数={sorted(heights)[len(heights)//2]}px")

    # === 结构化视觉判断（不依赖截图/多模态，纯控件树几何） ===
    # 本环境模型无多模态能力，无法"看"截图。以下基于控件树 bounds 推断
    # 白屏/重叠/溢出等视觉问题，截图仅作为人类复核的附件。
    lines.append(f"\n## 结构化视觉判断（基于控件树，非截图识别）")

    # 白屏检测
    flat_all = []
    for subtree in app_trees:
        flat_all.extend(_flatten_tree(subtree))
    blank = detect_blank_screen(flat_all, bundle=bundle)
    lines.append(f"\n### 白屏/渲染失败检测")
    lines.append(f"- 有界控件数: {blank['node_count']}")
    lines.append(f"- 可见文本数: {blank['visible_text_count']}")
    lines.append(f"- 图片控件数: {blank['image_count']}")
    if blank["is_blank"]:
        lines.append(f"- ⚠️ {blank['reason']}")
    else:
        lines.append(f"- OK {blank['reason']}")

    # 布局重叠检测
    overlaps_all = []
    for subtree in app_trees:
        overlaps_all.extend(detect_layout_overlaps(subtree, bundle=None))
    lines.append(f"\n### 布局重叠检测")
    if overlaps_all:
        lines.append(f"- ⚠️ 检测到 {len(overlaps_all)} 处子控件 bounds 相交（可能层叠/遮挡）:")
        for ov in overlaps_all[:10]:
            lines.append(f"  - 父({ov['parent_type']}): "
                         f"{ov['child_a']['type']}({ov['child_a'].get('text','')}) ∩ "
                         f"{ov['child_b']['type']}({ov['child_b'].get('text','')}) "
                         f"重叠面积={ov['overlap_area']}px²")
        if len(overlaps_all) > 10:
            lines.append(f"  - ... 共 {len(overlaps_all)} 处")
    else:
        lines.append(f"- OK 未检测到子控件 bounds 相交")

    # 布局溢出检测
    overflows_all = []
    for subtree in app_trees:
        overflows_all.extend(detect_overflow(subtree, bundle=None))
    lines.append(f"\n### 布局溢出检测")
    if overflows_all:
        lines.append(f"- ⚠️ 检测到 {len(overflows_all)} 处子控件超出父 bounds:")
        for of in overflows_all[:10]:
            lines.append(f"  - 父({of['parent_type']} {of['parent_bounds']}) ← "
                         f"子({of['child_type']} {of.get('child_text','')}) "
                         f"{of['child_bounds']} 溢出: {of['overflow']}")
        if len(overflows_all) > 10:
            lines.append(f"  - ... 共 {len(overflows_all)} 处")
    else:
        lines.append(f"- OK 未检测到子控件超出父 bounds")

    with open(summary_path, "w", encoding="utf-8") as f:
        f.write("\n".join(lines))
    print(f"[OK] 摘要已保存: {summary_path}")
    return summary_path


# ============================================================
# 公共工具
# ============================================================

def _get_attrs(node: dict) -> dict:
    """从节点提取属性字典，兼容 hdc dumpLayout 两种格式"""
    attrs = node.get("attributes", {})
    if not attrs and "type" in node:
        return node
    return attrs


def _flatten_tree(node: dict) -> List[dict]:
    """将嵌套控件树扁平化为节点列表"""
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


def _safe_load_flat(path: str) -> List[dict]:
    """安全加载 JSON 控件树并扁平化为节点列表"""
    if not os.path.isfile(path):
        return []
    with open(path, "r", encoding="utf-8") as f:
        tree = json.load(f)
    return _flatten_tree(tree)


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

    # 按 key 匹配
    if "key" in target:
        for n in flat_nodes:
            if n.get("key") == target["key"]:
                return n

    # 按 text 匹配
    if "text" in target:
        t = target["text"]
        # 先精确匹配
        for n in flat_nodes:
            if n.get("text") == t:
                return n
        # 再包含匹配
        for n in flat_nodes:
            if t in (n.get("text") or ""):
                return n

    # 按 type + index 匹配
    if "type" in target:
        idx = target.get("index", 0)
        matches = [n for n in flat_nodes if n.get("type") == target["type"]]
        if 0 <= idx < len(matches):
            return matches[idx]

    # 按 hint 匹配
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


def _get_screen_size(flat_nodes: List[dict]) -> Tuple[int, int]:
    """从控件树推断屏幕尺寸"""
    max_x, max_y = 1080, 2340  # 默认值
    for n in flat_nodes:
        bounds = _parse_bounds(n.get("bounds", ""))
        if bounds:
            max_x = max(max_x, bounds[2])
            max_y = max(max_y, bounds[3])
    return max_x, max_y


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


# ============================================================
# 无障碍屏幕朗读模式交互（A11Y_MODE 置位后使用）
# ============================================================
# 屏幕朗读交互模型（参考 cj-screen-reader-application-adaptation-guide）：
#   单击元素 = 聚焦该元素 + 系统朗读其内容（不触发点击）
#   双击屏幕任意位置 = 激活当前焦点元素（触发其点击）
#   滑动/滚动 = 双指滑动（单指手势在屏幕朗读下是「移动焦点」等导航手势）
# 故 a11y 模式下 click 展开为「单击聚焦 + 双击激活」，swipe/fling 改为双指滑动。


def _find_focused_node(flat_nodes: List[dict]) -> Optional[dict]:
    """从扁平控件树中找到 focused==true 的节点（屏幕朗读单击后应存在）"""
    for n in flat_nodes:
        if n.get("focused") == "true":
            return n
    return None


def _node_label(node: dict) -> str:
    """提取节点的人类可读标签（用于报告/日志），accessibilityText 优先于 text"""
    if not node:
        return ""
    return (node.get("accessibilityText") or node.get("text")
            or node.get("hint") or node.get("key") or node.get("type", ""))


def a11y_activate(x: int, y: int, out_dir: str, step_idx: int,
                  target_desc: dict) -> dict:
    """屏幕朗读式激活：单击聚焦 → （抓焦点节点）→ 双击激活

    返回 {"focused_node": {...}|None, "detail": str}。focused_node 记录聚焦到的
    控件的 text/type/key/accessibilityText，供断言与报告引用。
    """
    # 1. 聚焦：屏幕朗读下单击即聚焦（不触发点击）
    print(f"  [STEP {step_idx}][a11y] 聚焦 click ({x}, {y}) target={target_desc}")
    run(f"hdc shell uitest uiInput click {x} {y}")
    time.sleep(0.8)  # 让焦点与朗读稳定

    # 2. 抓焦点节点（供断言/报告）
    focused_info = None
    flat, _, _ = _refresh_step_layout(out_dir)
    fnode = _find_focused_node(flat)
    if fnode:
        focused_info = {
            "text": fnode.get("text", ""),
            "type": fnode.get("type", ""),
            "key": fnode.get("key", ""),
            "accessibilityText": _get_a11y_text(fnode),
            "label": _node_label(fnode),
        }
        print(f"  [STEP {step_idx}][a11y] 已聚焦: {focused_info['label']}")
    else:
        print(f"  [STEP {step_idx}][a11y] 未检测到 focused 节点（屏幕朗读可能未生效）")

    # 3. 激活：双击触发当前焦点元素的点击
    print(f"  [STEP {step_idx}][a11y] 双击激活 doubleClick ({x}, {y})")
    out = run(f"hdc shell uitest uiInput doubleClick {x} {y}")
    return {"focused_node": focused_info,
            "detail": f"a11y 聚焦+双击 ({x},{y}): {out}"}


def _get_a11y_text(node: dict) -> str:
    """取节点的无障碍朗读标签：优先 extraAttrs.accessibilityText，回退 text

    dumpLayout -a 时无障碍标签通常在 extraAttrs 里；未带 -a 时回退到 text 字段，
    由调用方根据返回值是否为空决定是否标注「仅校验显示文本」。
    """
    if not node:
        return ""
    extra = node.get("extraAttrs") or node.get("extra")
    if isinstance(extra, dict):
        for k in ("accessibilityText", "accessibility_text", "a11yText"):
            if extra.get(k):
                return extra.get(k)
    # 直接挂在节点上的情况
    for k in ("accessibilityText", "accessibility_text"):
        if node.get(k):
            return node.get(k)
    return node.get("text", "")


def a11y_two_finger_swipe(x1: int, y1: int, x2: int, y2: int,
                          screen_w: int, speed: int,
                          is_fling: bool, step_idx: int) -> str:
    """屏幕朗读模式下的双指滑动

    hdc shell uitest uiInput 的子命令不支持多指注入（仅 API 层 PointerMatrix
    支持），故用两条并发 swipe 模拟双指：手指 A 起点取屏幕左 1/4 列，手指 B
    起点取右 3/4 列，两指 y 向量相同。两指同时触发即构成双指滑动，屏幕朗读
    据此执行滚动。

    局限：并发双 swipe 的触点时序/间距与人工双指有差异，为近似实现。若滚动未
    生效需人工复核，调用方应在结果中如实标注。
    """
    offset_a = max(50, screen_w // 4)
    offset_b = max(50, (screen_w * 3) // 4)
    cmd_a = f"hdc shell uitest uiInput swipe {offset_a} {y1} {offset_a} {y2} {speed}"
    cmd_b = f"hdc shell uitest uiInput swipe {offset_b} {y1} {offset_b} {y2} {speed}"
    tag = "双指 fling(近似)" if is_fling else "双指 swipe"
    print(f"  [STEP {step_idx}][a11y] {tag}: 两指 y {y1}→{y2} (列 {offset_a} & {offset_b})")

    errors = []

    def _fire(cmd: str):
        try:
            run(cmd)
        except Exception as e:
            errors.append(str(e))

    t_a = threading.Thread(target=_fire, args=(cmd_a,))
    t_b = threading.Thread(target=_fire, args=(cmd_b,))
    t_a.start()
    t_b.start()
    t_a.join()
    t_b.join()
    detail = f"{tag} y {y1}→{y2}"
    if errors:
        detail += f"（部分失败: {errors[:1]}）"
    return detail


def load_scenario(path: str) -> dict:
    """加载交互场景配置 JSON 文件"""
    with open(path, "r", encoding="utf-8") as f:
        content = f.read()
    # 去除 JSON 中的 // 注释
    content = re.sub(r'//.*?$', '', content, flags=re.MULTILINE)
    scenario = json.loads(content)
    print(f"[OK] 加载场景: {scenario.get('name', path)} ({len(scenario.get('steps', []))} 步, "
          f"{len(scenario.get('assertions', []))} 个断言)")
    return scenario


def execute_step(step: dict, flat_nodes: List[dict], screen_w: int, screen_h: int,
                 out_dir: str, step_idx: int, bundle: Optional[str] = None) -> dict:
    """执行单个交互步骤，返回执行结果"""
    action = step.get("action", "")
    result = {"action": action, "success": False, "detail": "", "snapshot": None}

    if action == "wait":
        seconds = step.get("seconds", 2)
        print(f"  [STEP {step_idx}] 等待 {seconds}s ...")
        time.sleep(seconds)
        result["success"] = True
        result["detail"] = f"等待 {seconds}s"
        return result

    if action == "back":
        print(f"  [STEP {step_idx}] 模拟返回键")
        out = run("hdc shell uitest uiInput keyEvent 2")
        result["success"] = True
        result["detail"] = f"返回键: {out}"
        return result

    if action == "home":
        print(f"  [STEP {step_idx}] 模拟 Home 键")
        out = run("hdc shell uitest uiInput keyEvent 1")
        result["success"] = True
        result["detail"] = f"Home 键: {out}"
        return result

    if action == "snapshot":
        label = step.get("label", f"step_{step_idx}")
        snap_dir = os.path.join(out_dir, f"snapshot_{label}")
        os.makedirs(snap_dir, exist_ok=True)
        capture_screenshot(snap_dir)
        layout_path = dump_layout(snap_dir, extra_attrs=A11Y_MODE)
        summarize_layout(layout_path, snap_dir, bundle=bundle)
        print(f"  [STEP {step_idx}] 中间快照: {snap_dir}")
        result["success"] = True
        result["detail"] = f"快照保存至 {snap_dir}"
        result["snapshot"] = snap_dir
        return result

    # 需要目标坐标的操作
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
        # 无障碍模式：单指滑动会被屏幕朗读解释为「移动焦点」等导航手势，
        # 必须改用双指滑动才能滚动。shell 层 uiInput 无多指子命令，故用并发
        # 双 swipe 近似（见 a11y_two_finger_swipe 的局限说明）。
        if A11Y_MODE:
            detail = a11y_two_finger_swipe(x1, y1, x2, y2, screen_w, speed,
                                           is_fling=(action == "fling"), step_idx=step_idx)
            result["success"] = True
            result["detail"] = detail
            return result
        if action == "fling":
            step_len = step.get("stepLen", 50)
            cmd = f"hdc shell uitest uiInput fling {x1} {y1} {x2} {y2} {step_len} {speed}"
        else:
            cmd = f"hdc shell uitest uiInput swipe {x1} {y1} {x2} {y2} {speed}"
        print(f"  [STEP {step_idx}] {action}: ({x1},{y1}) → ({x2},{y2})")
        out = run(cmd)
        result["success"] = True
        result["detail"] = f"{action} ({x1},{y1})→({x2},{y2}): {out}"
        return result

    if action in ("click", "long_click", "double_click", "input"):
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

        cmd = ""

        # 无障碍模式：click=聚焦+双击激活；long_click=聚焦后长按焦点；
        # input=聚焦输入框后注入文本。double_click 不改写（双击即激活）。
        if A11Y_MODE and action in ("click", "long_click", "input"):
            if action == "click":
                r = a11y_activate(x, y, out_dir, step_idx, target)
                result["a11y_focused_node"] = r.get("focused_node")
                result["success"] = True
                result["detail"] = r["detail"]
                return result
            if action == "long_click":
                # 聚焦（单击）后长按焦点位置，屏幕朗读下长按焦点同样生效
                print(f"  [STEP {step_idx}][a11y] 聚焦 click ({x}, {y}) target={target}")
                run(f"hdc shell uitest uiInput click {x} {y}")
                time.sleep(0.8)
                flat, _, _ = _refresh_step_layout(out_dir)
                fnode = _find_focused_node(flat)
                if fnode:
                    result["a11y_focused_node"] = {
                        "text": fnode.get("text", ""), "type": fnode.get("type", ""),
                        "key": fnode.get("key", ""),
                        "accessibilityText": _get_a11y_text(fnode),
                        "label": _node_label(fnode)}
                    print(f"  [STEP {step_idx}][a11y] 已聚焦: {result['a11y_focused_node']['label']}")
                duration = step.get("duration", 1500)
                out = run(f"hdc shell uitest uiInput longClick {x} {y} {duration}")
                result["success"] = True
                result["detail"] = f"a11y 聚焦+长按 ({x},{y}) dur={duration}ms: {out}"
                return result
            if action == "input":
                text = step.get("text", "")
                # 聚焦到输入框：屏幕朗读下单击聚焦到输入框，系统会聚焦可编辑区
                print(f"  [STEP {step_idx}][a11y] 聚焦输入框 click ({x}, {y}) target={target}")
                run(f"hdc shell uitest uiInput click {x} {y}")
                time.sleep(0.8)
                run_args(["hdc", "shell", "uitest", "uiInput", "inputText", str(text)])
                print(f'  [STEP {step_idx}][a11y] 输入 "{text}" @ ({x}, {y})')
                result["success"] = True
                result["detail"] = f'a11y 聚焦+输入 "{text}" @ ({x},{y})'
                return result

        if action == "click":
            cmd = f"hdc shell uitest uiInput click {x} {y}"
            print(f"  [STEP {step_idx}] 点击 ({x}, {y}) target={target}")
        elif action == "double_click":
            cmd = f"hdc shell uitest uiInput doubleClick {x} {y}"
            print(f"  [STEP {step_idx}] 双击 ({x}, {y}) target={target}")
        elif action == "long_click":
            # duration 必须作为第三个位置参数传给 longClick，否则长按时长
            # 永远是设备默认值，与 scenario 配置不符
            duration = step.get("duration", 1500)
            cmd = f"hdc shell uitest uiInput longClick {x} {y} {duration}"
            print(f"  [STEP {step_idx}] 长按 ({x}, {y}) duration={duration}ms target={target}")
        elif action == "input":
            text = step.get("text", "")
            # 先点击激活输入框，再输入文本
            run(f"hdc shell uitest uiInput click {x} {y}")
            time.sleep(0.5)
            # 输入文本来自 scenario JSON，可能含引号/特殊字符。旧实现用字符串插值
            # 拼 shell 命令，文本含 " 或 $(...) 会断命令甚至被 shell 执行。
            # 改用参数列表（不经 shell），由 subprocess 负责转义。
            run_args(["hdc", "shell", "uitest", "uiInput", "inputText", str(text)])
            print(f'  [STEP {step_idx}] 输入 "{text}" @ ({x}, {y}) target={target}')
            result["success"] = True
            result["detail"] = f'input "{text}" @ ({x},{y})'
            return result

        out = run(cmd)
        result["success"] = True
        result["detail"] = f"{action} ({x},{y}): {out}"
        return result

    result["detail"] = f"未知操作: {action}"
    print(f"  [STEP {step_idx}] FAIL {result['detail']}")
    return result


def _refresh_step_layout(out_dir: str) -> tuple:
    """重新 dump 控件树并返回 (flat_nodes, screen_w, screen_h)"""
    device_json = "/data/local/tmp/_ui_interact_layout.json"
    local_tmp = os.path.join(out_dir, "_tmp_layout.json")
    run(f"hdc shell uitest dumpLayout -p {device_json}")
    run(f'hdc file recv {device_json} "{local_tmp}"')
    run(f"hdc shell rm -f {device_json}")

    flat_nodes = []
    screen_w, screen_h = 1080, 2340
    if os.path.isfile(local_tmp):
        try:
            with open(local_tmp, "r", encoding="utf-8") as f:
                tree = json.load(f)
            flat_nodes = _flatten_tree(tree)
            screen_w, screen_h = _get_screen_size(flat_nodes)
        except json.JSONDecodeError:
            print("  [WARN] 控件树解析失败，使用默认屏幕尺寸")
    return flat_nodes, screen_w, screen_h


def execute_scenario(scenario: dict, out_dir: str, bundle: Optional[str] = None) -> List[dict]:
    """执行完整交互场景，返回每步结果列表"""
    steps = scenario.get("steps", [])
    if not steps:
        print("[WARN] 场景无交互步骤")
        return []

    results = []
    for i, step in enumerate(steps):
        # 每步之前重新 dump 控件树以获取最新布局
        print(f"\n--- Step {i + 1}/{len(steps)}: {step.get('action', '?')} ---")
        flat_nodes, screen_w, screen_h = _refresh_step_layout(out_dir)

        r = execute_step(step, flat_nodes, screen_w, screen_h, out_dir, i + 1, bundle)
        results.append(r)

        # 交互后默认等待 1s 让界面刷新
        wait_after = step.get("wait_after", 1)
        if wait_after > 0 and step.get("action") != "wait":
            time.sleep(wait_after)

    # 清理临时文件
    tmp_file = os.path.join(out_dir, "_tmp_layout.json")
    if os.path.isfile(tmp_file):
        os.remove(tmp_file)

    return results


# ============================================================
# 差异对比引擎
# ============================================================

def _build_node_index(flat_nodes: List[dict]) -> Dict[str, dict]:
    """构建以 key/text+type 为键的节点索引"""
    index = {}
    type_counts = {}
    for n in flat_nodes:
        k = n.get("key", "")
        t = n.get("text", "")
        comp_type = n.get("type", "Unknown")
        # 优先用 key
        if k:
            index[f"key:{k}"] = n
        # 用 text
        if t:
            index[f"text:{t}"] = n
        # 用 type+index
        cnt = type_counts.get(comp_type, 0)
        index[f"type:{comp_type}#{cnt}"] = n
        type_counts[comp_type] = cnt + 1
    return index


def diff_layouts(before_path: str, after_path: str) -> dict:
    """对比两次控件树 JSON，返回结构化差异

    返回:
    {
      "nodes_added": [...],       # 新增节点
      "nodes_removed": [...],     # 消失节点
      "attrs_changed": [...],     # 属性变化 {node_id, attr, before, after}
      "text_changes": [...],      # 文本变化
      "count_changes": {...},     # 各类型控件数量变化
      "summary": str              # 人类可读摘要
    }
    """
    diff = {
        "nodes_added": [],
        "nodes_removed": [],
        "attrs_changed": [],
        "text_changes": [],
        "count_changes": {},
        "summary": "",
    }

    before_nodes = _safe_load_flat(before_path)
    after_nodes = _safe_load_flat(after_path)

    before_idx = _build_node_index(before_nodes)
    after_idx = _build_node_index(after_nodes)

    before_keys = set(before_idx.keys())
    after_keys = set(after_idx.keys())

    # 新增节点
    for k in after_keys - before_keys:
        n = after_idx[k]
        diff["nodes_added"].append({
            "id": k, "type": n.get("type", ""), "text": n.get("text", ""),
            "bounds": n.get("bounds", "")
        })

    # 删除节点
    for k in before_keys - after_keys:
        n = before_idx[k]
        diff["nodes_removed"].append({
            "id": k, "type": n.get("type", ""), "text": n.get("text", ""),
            "bounds": n.get("bounds", "")
        })

    # 属性变化（对共同节点比较关键属性）
    check_attrs = ["text", "clickable", "scrollable", "enabled", "checked",
                   "selected", "focused", "bounds", "description"]
    for k in before_keys & after_keys:
        bn, an = before_idx[k], after_idx[k]
        for attr in check_attrs:
            bv = bn.get(attr, "")
            av = an.get(attr, "")
            if bv != av:
                change = {"node_id": k, "attr": attr, "before": bv, "after": av}
                diff["attrs_changed"].append(change)
                if attr == "text":
                    diff["text_changes"].append(change)

    # 类型数量变化
    def count_types(nodes):
        counts = {}
        for n in nodes:
            t = n.get("type", "Unknown")
            counts[t] = counts.get(t, 0) + 1
        return counts

    before_counts = count_types(before_nodes)
    after_counts = count_types(after_nodes)
    all_types = set(list(before_counts.keys()) + list(after_counts.keys()))
    for t in all_types:
        bc = before_counts.get(t, 0)
        ac = after_counts.get(t, 0)
        if bc != ac:
            diff["count_changes"][t] = {"before": bc, "after": ac, "delta": ac - bc}

    # 生成摘要
    lines = []
    if diff["nodes_added"]:
        lines.append(f"新增 {len(diff['nodes_added'])} 个节点")
    if diff["nodes_removed"]:
        lines.append(f"移除 {len(diff['nodes_removed'])} 个节点")
    if diff["text_changes"]:
        lines.append(f"文本变化 {len(diff['text_changes'])} 处")
    if diff["attrs_changed"]:
        lines.append(
            f"属性变化 {len(diff['attrs_changed'])} 处")
    if diff["count_changes"]:
        parts = [f"{t}: {v['before']}→{v['after']}" for t, v in diff["count_changes"].items()]
        lines.append(f"数量变化: {', '.join(parts)}")
    if not lines:
        lines.append("界面无明显变化")
    diff["summary"] = "; ".join(lines)
    return diff


# ============================================================
# 断言引擎：对交互后的控件树执行断言检查
# ============================================================

def evaluate_assertions(assertions: List[dict], before_path: str, after_path: str,
                        diff: dict) -> List[dict]:
    """根据断言配置检查交互前后控件树

    返回断言结果列表:
    [{"assertion": dict, "passed": bool, "detail": str}, ...]
    """
    results = []

    after_nodes = _safe_load_flat(after_path)
    before_nodes = _safe_load_flat(before_path)

    for a in assertions:
        atype = a.get("type", "")
        target = a.get("target", {})
        msg = a.get("message", "")
        r = {"assertion": a, "passed": False, "detail": ""}

        if atype == "exists":
            node = find_target_node(after_nodes, target)
            r["passed"] = node is not None
            r["detail"] = "找到目标控件" if r["passed"] else f"未找到: {target}"

        elif atype == "not_exists":
            node = find_target_node(after_nodes, target)
            r["passed"] = node is None
            r["detail"] = "目标控件不存在（符合预期）" if r["passed"] else f"目标控件仍存在: {target}"

        elif atype == "text_changed":
            # 检查目标节点交互前后 text 是否变化
            bn = find_target_node(before_nodes, target)
            an = find_target_node(after_nodes, target)
            if bn and an:
                bt = bn.get("text", "")
                at = an.get("text", "")
                r["passed"] = bt != at
                r["detail"] = f"文本变化: \"{bt}\" → \"{at}\"" if r["passed"] else f"文本未变化: \"{bt}\""
            else:
                r["detail"] = f"前后有节点未找到 (before={'有' if bn else '无'}, after={'有' if an else '无'})"

        elif atype == "text_equals":
            an = find_target_node(after_nodes, target)
            if an:
                actual = an.get("text", "")
                expected = str(a.get("expected", ""))
                r["passed"] = actual == expected
                r["detail"] = f"文本=\"{actual}\"" + ("" if r["passed"] else f", 期望=\"{expected}\"")
            else:
                r["detail"] = f"未找到节点: {target}"

        elif atype == "clickable":
            an = find_target_node(after_nodes, target)
            if an:
                actual = an.get("clickable") == "true"
                expected = a.get("expected", True)
                r["passed"] = actual == expected
                r["detail"] = f"clickable={actual}" + ("" if r["passed"] else f", 期望={expected}")
            else:
                r["detail"] = f"未找到节点: {target}"

        elif atype == "count_changed":
            comp_type = target.get("type", "")
            if comp_type in diff.get("count_changes", {}):
                delta = diff["count_changes"][comp_type]["delta"]
                r["passed"] = delta != 0
                r["detail"] = f"{comp_type} 数量变化: {delta:+d}"
            else:
                r["passed"] = False
                r["detail"] = f"{comp_type} 数量无变化"

        elif atype == "page_changed":
            total_changes = (len(diff.get("nodes_added", [])) +
                             len(diff.get("nodes_removed", [])) +
                             len(diff.get("attrs_changed", [])))
            r["passed"] = total_changes > 0
            r["detail"] = f"总变化 {total_changes} 处" if r["passed"] else "界面无任何变化"

        elif atype == "focused":
            # 无障碍：检查目标控件交互后是否 focused==true（屏幕朗读单击应聚焦）
            an = find_target_node(after_nodes, target)
            if an:
                actual = an.get("focused") == "true"
                expected = a.get("expected", True)
                r["passed"] = actual == expected
                r["detail"] = f"focused={actual}" + ("" if r["passed"] else f", 期望={expected}")
            else:
                r["detail"] = f"未找到节点: {target}"

        elif atype == "accessibility_label":
            # 无障碍：检查目标控件朗读标签（accessibilityText 优先，回退 text）
            # 包含(expected_mode默认contains)或等于 expected。未用 -a dumpLayout 时
            # 回退到 text 并标注「仅校验显示文本」。
            an = find_target_node(after_nodes, target)
            if an:
                label = _get_a11y_text(an)
                expected = str(a.get("expected", ""))
                mode = a.get("mode", "contains")  # contains | equals
                only_text = (not label) or (label == an.get("text", ""))
                if mode == "equals":
                    r["passed"] = label == expected
                else:  # contains
                    r["passed"] = expected in label
                tag = "（仅校验显示文本，无 accessibilityText）" if only_text else ""
                r["detail"] = f'朗读标签="{label}"{tag}' + (
                    "" if r["passed"] else f', 期望{mode}="{expected}"')
            else:
                r["detail"] = f"未找到节点: {target}"

        elif atype == "a11y_focusable":
            # 无障碍：检查目标控件是否对屏幕朗读可聚焦（accessibilityLevel != "no"）
            an = find_target_node(after_nodes, target)
            if an:
                level = an.get("accessibilityLevel", "")
                # extraAttrs 形式
                if not level:
                    extra = an.get("extraAttrs") or an.get("extra") or {}
                    level = extra.get("accessibilityLevel", "") if isinstance(extra, dict) else ""
                focusable = level != "no"
                expected = a.get("expected", True)
                r["passed"] = focusable == expected
                r["detail"] = (f"accessibilityLevel={level or '(未设置，默认可聚焦)'}"
                               + ("" if r["passed"] else f", 期望={expected}"))
            else:
                r["detail"] = f"未找到节点: {target}"

        else:
            r["detail"] = f"未知断言类型: {atype}"

        results.append(r)
    return results


# ============================================================
# 交互报告生成
# ============================================================

def generate_interaction_report(scenario: dict, step_results: List[dict],
                                diff: dict, assertion_results: List[dict],
                                out_dir: str) -> str:
    """生成交互验证的完整 Markdown 报告"""
    report_path = os.path.join(out_dir, "interaction_report.md")
    lines = []
    lines.append(f"# 交互验证报告\n")
    lines.append(f"**场景**: {scenario.get('name', '未命名')}")
    if scenario.get("description"):
        lines.append(f"**描述**: {scenario['description']}")
    lines.append("")

    # 步骤执行结果
    lines.append("## 交互步骤执行结果\n")
    lines.append("| # | 操作 | 状态 | 详情 |")
    lines.append("|---|------|------|------|")
    for i, r in enumerate(step_results):
        status = "PASS" if r["success"] else "FAIL"
        detail = r["detail"][:80] if r["detail"] else ""
        lines.append(f"| {i + 1} | {r['action']} | {status} | {detail} |")
    lines.append("")

    # 界面差异
    lines.append("## 交互前后界面差异\n")
    lines.append(f"**摘要**: {diff.get('summary', '无')}\n")

    if diff.get("text_changes"):
        lines.append("### 文本变化")
        for tc in diff["text_changes"]:
            lines.append(f"- `{tc['node_id']}`: \"{tc['before']}\" → \"{tc['after']}\"")
        lines.append("")

    if diff.get("nodes_added"):
        lines.append("### 新增节点")
        for n in diff["nodes_added"][:20]:
            lines.append(f"- `{n['id']}` ({n['type']}) {n.get('text', '')}")
        if len(diff["nodes_added"]) > 20:
            lines.append(f"- ... 共 {len(diff['nodes_added'])} 个")
        lines.append("")

    if diff.get("nodes_removed"):
        lines.append("### 移除节点")
        for n in diff["nodes_removed"][:20]:
            lines.append(f"- `{n['id']}` ({n['type']}) {n.get('text', '')}")
        if len(diff["nodes_removed"]) > 20:
            lines.append(f"- ... 共 {len(diff['nodes_removed'])} 个")
        lines.append("")

    if diff.get("attrs_changed"):
        non_text = [c for c in diff["attrs_changed"] if c["attr"] != "text"]
        if non_text:
            lines.append("### 属性变化")
            for c in non_text[:30]:
                lines.append(f"- `{c['node_id']}`.{c['attr']}: \"{c['before']}\" → \"{c['after']}\"")
            lines.append("")

    if diff.get("count_changes"):
        lines.append("### 控件数量变化")
        for t, v in diff["count_changes"].items():
            lines.append(f"- {t}: {v['before']} → {v['after']} ({v['delta']:+d})")
        lines.append("")

    # 无障碍测试小结（仅 a11y 模式）
    if A11Y_MODE:
        lines.append("## 无障碍屏幕朗读测试小结\n")
        active, proc = is_screen_reader_active()
        lines.append(f"- 屏幕朗读开启状态: {'已开启' if active else '未确认开启'}"
                     + (f" ({proc})" if proc else ""))
        # 每步聚焦的控件
        focused_steps = [(i, r) for i, r in enumerate(step_results) if r.get("a11y_focused_node")]
        if focused_steps:
            lines.append("\n### 各步聚焦控件（单击聚焦到的元素）")
            lines.append("| 步骤 | 动作 | 聚焦控件 | 类型 |")
            lines.append("|------|------|----------|------|")
            for i, r in focused_steps:
                fn = r["a11y_focused_node"]
                lines.append(f"| {i + 1} | {r['action']} | {fn.get('label', '')} | {fn.get('type', '')} |")
        else:
            lines.append("- 未记录到任何步骤的焦点控件（可能屏幕朗读未生效或单击未落到可聚焦控件上）")
        lines.append("")
        lines.append("> **说明**: a11y 模式下 click 已展开为「单击聚焦+双击激活」，"
                     "swipe/fling 已转为双指滑动（shell 层无多指命令，为并发双 swipe 近似实现，"
                     "若滚动未生效需人工复核）。")
        lines.append("")

    # 断言结果
    if assertion_results:
        lines.append("## 断言检查结果\n")
        passed = sum(1 for r in assertion_results if r["passed"])
        total = len(assertion_results)
        lines.append(f"**通过 {passed}/{total}**\n")
        lines.append("| # | 类型 | 结果 | 说明 | 详情 |")
        lines.append("|---|------|------|------|------|")
        for i, r in enumerate(assertion_results):
            a = r["assertion"]
            status = "PASS" if r["passed"] else "FAIL"
            msg = a.get("message", "")
            detail = r["detail"][:60]
            lines.append(f"| {i + 1} | {a.get('type', '')} | {status} | {msg} | {detail} |")
        lines.append("")

        if passed == total:
            lines.append("> **结论**: 所有断言通过，交互行为符合预期。\n")
        else:
            failed = [r for r in assertion_results if not r["passed"]]
            lines.append("> **结论**: 存在断言失败，需检查以下问题：\n")
            for r in failed:
                lines.append(f"> - {r['assertion'].get('message', r['detail'])}")
            lines.append("")

    with open(report_path, "w", encoding="utf-8") as f:
        f.write("\n".join(lines))
    print(f"[OK] 交互验证报告: {report_path}")
    return report_path


def main():
    parser = argparse.ArgumentParser(description="HarmonyOS UI 状态采集 + 自动交互验证")
    parser.add_argument("--project", default=None, help="鸿蒙项目目录（含 AppScope/），不指定则自动向上搜索")
    parser.add_argument("--bundle", default=None, help="应用包名（不指定则从项目目录自动检测）")
    parser.add_argument("--ability", default=None, help="Ability 名称（不指定则从项目目录自动检测）")
    parser.add_argument("--hap", default="", help="HAP 安装包路径（可选）")
    parser.add_argument("--out", default="./ui_capture_output", help="输出目录")
    parser.add_argument("--no-launch", action="store_true", help="跳过启动应用（已在前台时使用）")
    parser.add_argument("--wait", type=int, default=3, help="启动后等待秒数")
    parser.add_argument("--emulator", default=None, metavar="ADDR",
                        help="模拟器地址（端口号如 5555，或完整地址如 127.0.0.1:5555）")
    parser.add_argument("--scenario", default=None, metavar="JSON",
                        help="交互场景配置文件路径（JSON），指定后自动执行交互→二次采集→差异报告")
    parser.add_argument("--a11y", action="store_true",
                        help="无障碍屏幕朗读模式：采集前检测屏幕朗读是否开启，未开启则打印指引并阻塞等待用户手动开启"
                             "（不自动改设备设置）。开启后 click 自动展开为「单击聚焦+双击激活」，swipe/fling 转双指滑动")
    args = parser.parse_args()

    global A11Y_MODE
    A11Y_MODE = args.a11y

    # === 自动检测项目信息 ===
    project_dir = args.project
    if not project_dir:
        project_dir = find_project_dir()
    if project_dir:
        print(f"[OK] 鸿蒙项目目录: {project_dir}")
        detected_bundle, detected_ability = detect_project_info(project_dir)
        if not args.bundle and detected_bundle:
            args.bundle = detected_bundle
        if not args.ability and detected_ability:
            args.ability = detected_ability
    else:
        print("[WARN] 未找到鸿蒙项目目录（AppScope/），将使用命令行参数")

    if not args.bundle:
        print("[ERROR] 无法确定应用包名。请用 --bundle 指定，或在鸿蒙项目目录下运行。")
        sys.exit(1)
    if not args.ability:
        print("[ERROR] 无法确定 Ability 名称。请用 --ability 指定。")
        sys.exit(1)

    print(f"[INFO] 目标应用: {args.bundle} / {args.ability}")

    os.makedirs(args.out, exist_ok=True)
    check_device(args.emulator)

    # 无障碍模式：采集前检测屏幕朗读状态，未开启则提示并阻塞等待手动开启
    if A11Y_MODE:
        wait_for_screen_reader()

    if args.hap:
        install_hap(args.hap)

    if not args.no_launch:
        launch_app(args.bundle, args.ability)
        if args.wait > 0:
            print(f"[INFO] 等待 {args.wait}s 界面加载...")
            time.sleep(args.wait)

    # === Phase 1: 基线采集（交互前） ===
    print(f"\n{'='*50}")
    print("Phase 1: 基线采集")
    print(f"{'='*50}")
    screenshot_path = capture_screenshot(args.out)
    layout_path = dump_layout(args.out, extra_attrs=A11Y_MODE)
    summary_path = summarize_layout(layout_path, args.out, bundle=args.bundle)

    print(f"\n  采集完成: {args.out}")
    print(f"    截图: {screenshot_path}")
    print(f"    控件树: {layout_path}")
    print(f"    摘要: {summary_path}")

    # === Phase 2: 交互执行（仅在指定 --scenario 时） ===
    if args.scenario:
        scenario = load_scenario(args.scenario)

        print(f"\n{'='*50}")
        print(f"Phase 2: 执行交互场景 — {scenario.get('name', '未命名')}")
        print(f"{'='*50}")

        step_results = execute_scenario(scenario, args.out, bundle=args.bundle)

        # === Phase 3: 交互后二次采集 ===
        print(f"\n{'='*50}")
        print("Phase 3: 交互后二次采集")
        print(f"{'='*50}")

        after_dir = os.path.join(args.out, "after")
        os.makedirs(after_dir, exist_ok=True)
        after_screenshot = capture_screenshot(after_dir)
        after_layout = dump_layout(after_dir, extra_attrs=A11Y_MODE)
        after_summary = summarize_layout(after_layout, after_dir, bundle=args.bundle)

        print(f"\n  采集完成: {after_dir}")
        print(f"    截图: {after_screenshot}")
        print(f"    控件树: {after_layout}")
        print(f"    摘要: {after_summary}")

        # === Phase 4: 差异对比 + 断言检查 ===
        print(f"\n{'='*50}")
        print("Phase 4: 差异分析 + 断言检查")
        print(f"{'='*50}")

        diff = diff_layouts(layout_path, after_layout)
        print(f"  差异摘要: {diff['summary']}")

        # 保存差异 JSON
        diff_json_path = os.path.join(args.out, "diff.json")
        with open(diff_json_path, "w", encoding="utf-8") as f:
            json.dump(diff, f, ensure_ascii=False, indent=2)
        print(f"  差异数据: {diff_json_path}")

        # 执行断言
        assertions = scenario.get("assertions", [])
        assertion_results = evaluate_assertions(assertions, layout_path, after_layout, diff)

        if assertion_results:
            passed = sum(1 for r in assertion_results if r["passed"])
            total = len(assertion_results)
            print(f"\n  断言结果: {passed}/{total} 通过")
            for i, r in enumerate(assertion_results):
                status = "PASS" if r["passed"] else "FAIL"
                msg = r["assertion"].get("message", "")
                print(f"    {status} [{r['assertion']['type']}] {msg}: {r['detail']}")

        # === Phase 5: 生成报告 ===
        report_path = generate_interaction_report(
            scenario, step_results, diff, assertion_results, args.out)

        print(f"\n{'='*50}")
        print(f"交互验证完成！")
        print(f"  报告: {report_path}")
        print(f"  基线: {args.out}/screenshot.png + layout.json")
        print(f"  交互后: {after_dir}/screenshot.png + layout.json")
        print(f"  差异: {diff_json_path}")
        print(f"{'='*50}")
    else:
        print(f"\n{'='*50}")
        print(f"基础采集完成！（如需交互验证，请使用 --scenario 参数）")
        print(f"{'='*50}")


if __name__ == "__main__":
    main()
