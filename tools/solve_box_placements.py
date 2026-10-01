# -*- coding: utf-8 -*-
"""
箱位求解器：给定地形，穷举「木箱放哪、往哪推、落到哪」的所有可行组合。

为什么需要这个脚本（而不是手画关卡）：
  设计「重力投递」机关时，手画地形连续失败三次，根因全都是
  **同时设计「地形分区」和「箱子位置」两个纠缠的变量** ——
  人脑做这种空间推理会一直顾此失彼。
  而箱位的搜索空间其实很小，电脑几毫秒就能穷举完。
  这与项目里「关卡是生成出来的，不是手写的」是同一条原则。

用法：
    python tools/solve_box_placements.py              # 跑内置示例
    python tools/solve_box_placements.py --demo       # 同上，打印更详细
    python tools/solve_box_placements.py --grid 关卡名  # 预留：接关卡数据

物理模型（全部来自实测 / 读码，不允许估）：
    · 推箱人必须与箱子【同层】（高度差 ≤ 0.9 格）且水平 ≤ 1.05 格
      —— scripts/objects/push_box.gd::_detect_push()
    · 箱子只能沿同一高度的连续地面被推，推不上台阶
      —— gen_levels.py::box_reachable() 的模型
    · 箱子离开边缘后【横飘 0.42 格】后几乎垂直下落
      —— 2026-09-19 --smoke 木箱落体探针实测（1~7 格落差恒定）
    · 箱子可穿过 1 格宽的竖井（碰撞体 28px < 32px 格宽）

求解器的输出不是「一个答案」，而是「一张可行箱位的表」，
让关卡设计者从「猜箱子放哪」变成「从列表里挑一个」。
"""

import argparse
import os
import sys
from collections import deque

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

# 复用生成器的常量与工具 —— 绝不在这里重新定义一套
from gen_levels import (
    Grid, SOLID_CHARS, FLUID_CHARS,
    MAX_STEP_UP_CELLS, MAX_GAP_CELLS, MAX_JUMP_UP_CELLS, MAX_SWIM_UP_CELLS,
    compute_reach,
)

# ---------------------------------------------------------------- 实测常量
## 箱子被推出边缘后的横向飘移，单位「格」。
## 来源：2026-09-19 --smoke 木箱落体探针，落差 1~7 格实测恒为 13px。
## 取整到 0.5 格作为设计安全值（见 docs/mechanic_gravity_drop.md §2.2）。
BOX_DRIFT_CELLS = 0.5

## 相机纵向分离上限，单位「格」。
## 来源：camera_rig.gd min_zoom=0.7、视口 720、margin=150
##   → 720/0.7 - 300 = 728.6px ≈ 22.8 格；现有 9 关纵向最大跨度 15 格
##   → 余量 7.8 格，取整 7。
MAX_DROP_CELLS = 7

## 推箱人与箱子的高度差阈值（格）。来自 push_box.gd 的 `absf(d.y) > size*0.9`。
PUSH_SAME_LEVEL_TOL = 0.9


# ============================================================ 基础几何
## 行号语义（务必先读懂，这里错一格会让全部输出偏掉）：
##   在 gen_levels.py 的模型里，一个「站立面」记作 (x, y)，含义是
##   **角色/箱子踩在 (x, y) 这一格上**，身体占据它上方一格 (x, y-1)。
##   所以 `surfaces_at()` 返回的是「实心格的 y」而不是「身体中心的 y」。
##   本文件沿用同一套语义。
##
##   例：地面在 y=13 那行是 "#"，则站立面 = (x, 13)。

def is_inside(grid, x, y):
    return 0 <= y < len(grid) and 0 <= x < len(grid[0])


def is_solid(grid, x, y):
    """(x,y) 是不是实心地形。越界一律当【实心】——
    这样地图边框自然不会退化出「贴着边界的假边缘」。"""
    if not is_inside(grid, x, y):
        return True
    return grid[y][x] in SOLID_CHARS


def is_fluid(grid, x, y):
    if not is_inside(grid, x, y):
        return False
    return grid[y][x] in FLUID_CHARS


def is_standable(grid, x, y):
    """(x, y) 能不能站（或放箱子）：本格实心，且上方一格是空的。"""
    if not is_solid(grid, x, y):
        return False
    return not is_solid(grid, x, y - 1)


def landing_row(grid, x, y_from):
    """从 (x, y_from) 往下自由落体，落在哪个站立面的行号；没有则 None。

    注意：液体【不是】箱子的落点 —— 这条已被实测确认（2026-09-19 --smoke）：
      木箱掉进 lava / water 池都是「下落 3.05 格后贴到池底」，
      两种情况行为完全一致，箱子不受元素相克也不受浮力影响。
      沉底后人取不回（推箱要求同层贴身，而人只能浮在液面）
      → **把箱子推进液体 = 不可逆软锁**，必须在地形上排除。
    """
    for y in range(y_from, len(grid)):
        if is_solid(grid, x, y):
            return y
    return None


def column_has_fluid_below(grid, x, y_from):
    """(x, y_from) 往下到第一个实心格之间，有没有液体。

    用来排除「箱子会沉进液体」的落点 —— 见 landing_row 的说明。
    """
    for y in range(y_from, len(grid)):
        if is_solid(grid, x, y):
            return False
        if is_fluid(grid, x, y):
            return True
    return False


# ============================================================ 求解器
def box_can_be_pushed_to(grid, box_start, targets, reach_by_element=None):
    """箱子从 box_start 出发，沿同高地面能被推到哪些位置。

    这是求解器的第三道闸（前两道是「地形允许」和「推手够得到」）：
      **箱子自己得先能走到那个投递位。**
    没有这道闸会出现这种假答案：求解器说「(6,13) 是个可行投递点」，
    但箱子在 (22,12)，中间隔着岩浆，箱子永远到不了 (6,13)。

    模型照抄 gen_levels.py::box_reachable()：
      · 箱子只能沿同一高度的连续地面被推（推不上台阶、不下落）
      · 目标格和推手背后的格子都必须可站立
    返回 {(x, row)}。
    """
    W = len(grid[0])
    # 箱子受重力落到最近的地面
    bx, by = box_start
    s0 = landing_row(grid, bx, by)
    if s0 is None:
        return set()
    start = (bx, s0)
    if start not in targets and True:
        pass
    seen = {start}
    q = deque([start])
    while q:
        c, s = q.popleft()
        for dc in (-1, 1):
            nc = c + dc
            if not (0 <= nc < W):
                continue
            # 目标列同高必须可站立
            if not is_standable(grid, nc, s):
                continue
            # 液体格不是可站立面，is_standable 已经排除（液体不是 SOLID_CHARS）
            behind = c - dc
            if not is_standable(grid, behind, s):
                continue
            if reach_by_element is not None:
                # 推的人真的走得到背后那一格吗
                if not any((behind, s) in r for r in reach_by_element.values()):
                    continue
            if (nc, s) in seen:
                continue
            seen.add((nc, s))
            q.append((nc, s))
    return seen


def push_off_edges(grid, reach_by_element=None, box_start=None):
    """找出所有「能把箱子推下去」的位置与落点。

    返回 [{ from:(x,row), dir:+1/-1, land_x, land_y, drop, ok, why, pushers }]

    from 是**箱子所在的站立面**（箱子踩在这一格上），推手就站在它背后同层。

    reach_by_element: 可选 {element: 可达站立面集合}。
      给了它就额外检查「推手站的那一格，有没有哪个角色真的走得到」——
      这是最关键的一道闸：地形上允许推 ≠ 玩家做得到。
      没有这道闸，求解器会给出「物理成立但玩法不成立」的假答案，
      正是本项目最贵的一类 bug（校验器说 OK、实际过不去）。

    box_start: 可选，箱子初始位置 (x, y)。给了它就额外检查
      「箱子自己能不能先被推到那个投递位」——第三道闸。
      没有它的假答案长这样：求解器说 (6,13) 可行，但箱子在 (22,12)，
      中间隔着岩浆，箱子永远到不了。

    判定：
      箱子在 (x, row) 上 → 往 dir 推 → (x+dir, row) 同层没有站立面
      → 箱子越过边缘 → 自由落体
    """
    W = len(grid[0])
    H = len(grid)
    box_reach = None
    if box_start is not None:
        box_reach = box_can_be_pushed_to(grid, box_start, set(), reach_by_element)
    out = []
    for y in range(H):
        for x in range(W):
            if not is_standable(grid, x, y):
                continue
            if y == 0 or x == 0 or x == W - 1:
                continue
            for d in (-1, 1):
                nx = x + d
                if not is_inside(grid, nx, y):
                    continue
                if is_standable(grid, nx, y):
                    continue
                behind = x - d
                if not is_standable(grid, behind, y):
                    continue

                # ---- 闸 1：箱子自己先得能到这儿
                if box_reach is not None and (x, y) not in box_reach:
                    out.append({"from": (x, y), "dir": d, "land_x": None,
                                "land_y": None, "drop": None, "ok": False,
                                "pushers": [],
                                "why": "箱子到不了 (x,y)（被地形/液体隔断）"
                                       .replace("x,y", "%d,%d" % (x, y))})
                    continue

                # ---- 闸 2：推手可达性
                pushers = []
                if reach_by_element is not None:
                    for el, reach in reach_by_element.items():
                        if (behind, y) in reach:
                            pushers.append(el)
                    if not pushers:
                        out.append({"from": (x, y), "dir": d, "land_x": None,
                                    "land_y": None, "drop": None, "ok": False,
                                    "pushers": [],
                                    "why": "推手站得不到（没人能走到 (%d,%d)）"
                                           % (behind, y)})
                        continue

                drift = int(BOX_DRIFT_CELLS + 0.5)
                land_x = nx + (drift if d > 0 else -drift)
                land_x = max(1, min(W - 2, land_x))
                ly = landing_row(grid, land_x, y)
                if ly is None:
                    ly = landing_row(grid, nx, y)
                    land_x = nx
                if ly is None:
                    out.append({"from": (x, y), "dir": d, "land_x": None,
                                "land_y": None, "drop": None, "ok": False,
                                "pushers": pushers,
                                "why": "箱子落不到任何地方（无底坑）"})
                    continue
                # ---- 闸 3：液体排除。箱子会沉底且取不回 = 不可逆软锁
                #      实测依据见 landing_row() 的注释。
                if column_has_fluid_below(grid, land_x, y):
                    out.append({"from": (x, y), "dir": d, "land_x": land_x,
                                "land_y": ly, "drop": None, "ok": False,
                                "pushers": pushers,
                                "why": "箱子会沉进液体（列 %d）—— 不可逆软锁"
                                       % land_x})
                    continue
                drop = ly - y
                if drop <= 0:
                    continue
                if drop > MAX_DROP_CELLS:
                    out.append({"from": (x, y), "dir": d, "land_x": land_x,
                                "land_y": ly, "drop": drop, "ok": False,
                                "pushers": pushers,
                                "why": "落差 > 相机安全上限 %d 格" % MAX_DROP_CELLS})
                    continue
                out.append({"from": (x, y), "dir": d, "land_x": land_x,
                            "land_y": ly, "drop": drop, "ok": True,
                            "pushers": pushers, "why": ""})
    return out


# ============================================================ 报告
def report_level(grid, name="", targets=None, objects=None, marks=None):
    """对一张地形做完整分析。

    targets: 可选，[(x, y), ...] 是「箱子必须落到的目标格」——
             通常是压力板的位置（板在 (x,y)，箱子要落到 (x, y+1)）。
             给了 targets 就只报能命中目标的箱位，把 F3 失败态
             （"箱子掉下去了但没人需要它"）变成一条可查的判据。
    objects: 可选，关卡对象列表。里面的 `box` 用来确定箱子初始位置
             （第三道闸：箱子自己能不能被推到投递位），
             同时给 compute_reach 提供机关信息。
    marks:   可选，{"F": (x,y), "W": (x,y)} 出生点覆盖（对象里没自带时用）。
    """
    H, W = len(grid), len(grid[0])
    print("=" * 66)
    print("箱位求解：%s   (%d 列 × %d 行)" % (name or "(未命名)", W, H))
    print("=" * 66)

    # ---- 箱子初始位置（第三道闸的输入）
    box_start = None
    if objects:
        for o in objects:
            if o.get("type") == "box":
                cell = o.get("cell", None)
                if cell:
                    box_start = (int(cell[0]), int(cell[1]))

    # ---- 推手可达性：这是「地形允许」与「玩家做得到」之间的那道闸
    reach = None
    if objects is not None:
        g2 = list(grid)
        if marks:
            for ch, (mx, my) in marks.items():
                row = list(g2[my])
                row[mx] = ch
                g2[my] = "".join(row)
        reach = {}
        for el in ("fire", "water"):
            reach[el] = compute_reach(g2, objects, el, frozenset())
        print("\n[推手可达性] 火娃可达 %d 个站立面，水娃可达 %d 个"
              % (len(reach["fire"]), len(reach["water"])))
        print("  没有这道闸，求解器会给出「地形上能推但玩家站不到」的假答案。")

    edges = push_off_edges(grid, reach, box_start)
    good = [e for e in edges if e["ok"]]
    bad = [e for e in edges if not e["ok"]]
    print("\n[三道闸] ① 箱子自己能推到该位置  ② 推手走得到  ③ 落点不在液体里")
    if box_start is not None:
        print("  箱子初始位置：(%d,%d)" % box_start)

    if targets:
        goals = {(int(t[0]), int(t[1]) + 1) for t in targets}
        hits = [e for e in good if (e["land_x"], e["land_y"]) in goals]
        miss = [e for e in good if (e["land_x"], e["land_y"]) not in goals]
        print("\n[目标命中]（箱子必须落到：%s）"
              % ", ".join("(%d,%d)" % g for g in sorted(goals)))
        if hits:
            for e in hits:
                fx, fy = e["from"]
                px = fx - e["dir"]
                who = "/".join(e["pushers"]) if e["pushers"] else "任意"
                print("  ✅ 箱子放 (%2d,%2d)  推手站 (%2d,%2d)[%s]  推向%s "
                      "→ 命中 (%2d,%2d)  落差 %d 格"
                      % (fx, fy, px, fy, who, "右" if e["dir"] > 0 else "左",
                         e["land_x"], e["land_y"], e["drop"]))
        else:
            print("  ❌ 没有任何箱位能落到目标 —— 这是 F1/F3 失败态：")
            print("     要么压力板放错地方，要么地形缺少能把箱子送过去的落差。")
            if miss:
                print("     现有 %d 个可行落点，全都不在目标上：" % len(miss))
                for e in sorted(miss, key=lambda z: (z["land_y"], z["land_x"]))[:8]:
                    print("       (%2d,%2d)  落差 %d 格" % (e["land_x"], e["land_y"], e["drop"]))
        print()

    print("\n[可行投递点]（地形允许 + 推手够得到 + 落差在相机内）")
    if not good:
        print("  （无）")
    for e in sorted(good, key=lambda z: (z["from"][1], z["from"][0])):
        fx, fy = e["from"]
        px = fx - e["dir"]
        who = "/".join(e["pushers"]) if e["pushers"] else "任意"
        arrow = "右" if e["dir"] > 0 else "左"
        print("  箱子站 (%2d,%2d)  推手站 (%2d,%2d)[%s]  往%s推 "
              "→ 落到 (%2d,%2d)  落差 %d 格"
              % (fx, fy, px, fy, who, arrow, e["land_x"], e["land_y"], e["drop"]))

    if bad:
        print("\n[不可行投递点]（被规则挡掉的原因）")
        seen_why = {}
        for e in bad:
            seen_why.setdefault(e["why"], []).append(e)
        for why, lst in seen_why.items():
            print("  %s  —— 共 %d 处，例如 %s"
                  % (why, len(lst), ", ".join("(%d,%d)" % e["from"] for e in lst[:4])))

    print("\n[设计速查]（按落点排序，直接抄进关卡设计）")
    for e in sorted(good, key=lambda z: (z["land_y"], z["land_x"])):
        fx, fy = e["from"]
        px = fx - e["dir"]
        who = "/".join(e["pushers"]) if e["pushers"] else "任意"
        print("    箱子放在 (%2d,%2d)，推手(%s)站 (%2d,%2d) 推向%s → 落点 (%2d,%2d)"
              % (fx, fy, who, px, fy, "右" if e["dir"] > 0 else "左",
                 e["land_x"], e["land_y"]))


# ============================================================ 示例地形
## 示例 A：教科书形态 —— 高台一段，右边是空地。
## 用来看求解器能不能把「所有边缘」都找出来，且不误报边框。
def demo_a():
    g = Grid(30, 14)
    g.border()
    g.row(13, 1, 28, "#")
    g.row(6, 1, 14, "#")        # 高台：列 1~14，站立面 y=6
    g.put(2, 5, "F")
    g.put(25, 12, "E")
    g.put(24, 12, "Q")
    objs = [{"type": "box", "cell": [10, 5]}]
    return (g.rows(), "示例A·单段高台", None, objs)


## 示例 B：这是「重力投递」的真实目标形态 ——
## 下层有一块压力板，只有当箱子落上去才能开门。
def demo_b():
    g = Grid(34, 16)
    g.border()
    g.row(15, 1, 32, "#")
    g.row(8, 1, 16, "#")        # 上层平台：列 1~16，站立面 y=8
    g.row(11, 20, 26, "#")      # 下层凸台：站立面 y=11
    g.put(3, 7, "F")
    g.put(30, 7, "W")
    g.put(22, 10, "E")
    g.put(29, 14, "Q")
    # 压力板放在求解器报出的落点 (18,15) 上 → 板在 (18,14)
    objs = [
        {"type": "plate", "cell": [18, 14], "channel": "K"},
        {"type": "box", "cell": [15, 7]},
        {"type": "door", "cell": [22, 7], "height": 7, "channel": "K"},
    ]
    return (g.rows(), "示例B·投递到压力板（目标 18,15）", [(18, 14)], objs)


## 示例 C：**故意做坏** —— 压力板放在箱子落点完全够不到的地方。
## 用来证明求解器真的会咬人（F1/F3 失败态）。
def demo_c():
    g = Grid(34, 16)
    g.border()
    g.row(15, 1, 32, "#")
    g.row(8, 1, 16, "#")
    g.row(11, 29, 31, "#")      # 凸台在最右，与上层平台边缘离得很远
    g.put(3, 7, "F")
    g.put(19, 7, "W")
    g.put(22, 10, "E")
    g.put(5, 14, "Q")
    objs = [
        {"type": "plate", "cell": [5, 14], "channel": "K"},
        {"type": "box", "cell": [10, 7]},
        {"type": "door", "cell": [22, 7], "height": 7, "channel": "K"},
    ]
    return (g.rows(), "示例C·故意做坏（板在 (5,14)，够不到）", [(5, 14)], objs)


def main():
    ap = argparse.ArgumentParser(description="箱位求解器")
    ap.add_argument("--demo", action="store_true", help="打印完整详情")
    args = ap.parse_args()

    cases = [demo_a(), demo_b(), demo_c()]
    for grid, name, *rest in cases:
        targets = rest[0] if len(rest) > 0 else None
        objs = rest[1] if len(rest) > 1 else None
        report_level(grid, name, targets, objs)
        print()


if __name__ == "__main__":
    main()
