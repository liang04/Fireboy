# -*- coding: utf-8 -*-
"""
生成 scripts/levels/levels.gd，并对关卡做静态校验。

为什么要生成而不是手写 GDScript：
  网格是二维字符画，手写极易数错列；而关卡的「能不能跳过去」是可以算出来的。
  所以这里做两件事：
    1. 用一个极小的 DSL（填矩形 / 画一行 / 放一格）拼出网格，杜绝手数格子
    2. 生成后立刻跑一次可达性校验 —— 用冒烟测试实测出来的运动能力
       （跳跃高度、跳远距离、液体上浮高度）做约束，BFS 搜出每个角色能到的地方，
       验证出口确实可达、池子确实跳得过去 / 游得出来

用法： python tools/gen_levels.py
"""

import os
import sys
from collections import deque

CELL = 32

# ---------------------------------------------------------------- 运动能力上限
# 这些数字来自 scripts/autoload/smoke.gd 的动作探针（--smoke 会打印实测值）。
# 它们是关卡设计的硬边界：改了 player.gd 的手感参数后，必须重跑探针并同步这里。
MAX_STEP_UP_CELLS = 2      # 走动能跨上的台阶高度（实测极限 3.06 格）
MAX_GAP_CELLS = 5          # 水平跳跃能跨过的最大列距（实测极限 6.21 格）
MAX_JUMP_UP_CELLS = 3      # 跨沟时允许同时上升的格数（实测极限 3.06 格）
MAX_SWIM_UP_CELLS = 3      # 液体里划一次水能上浮的格数（实测约 3.5 格）

SOLID_CHARS = "#="
FLUID_CHARS = {"^": "lava", "~": "water", "*": "acid"}


# ---------------------------------------------------------------- 网格 DSL
class Grid:
    def __init__(self, w, h):
        self.w, self.h = w, h
        self.g = [["." for _ in range(w)] for _ in range(h)]

    def rect(self, x0, y0, x1, y1, ch):
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                self.g[y][x] = ch

    def row(self, y, x0, x1, ch):
        self.rect(x0, y, x1, y, ch)

    def put(self, x, y, ch):
        self.g[y][x] = ch

    def border(self, ch="#"):
        for y in range(self.h):
            self.g[y][0] = ch
            self.g[y][self.w - 1] = ch

    def rows(self):
        return ["".join(r) for r in self.g]


# ============================================================ 关卡 1
def level_01():
    """教学关：认识元素相克 + 第一次爬台阶。"""
    W, H = 46, 23
    g = Grid(W, H)
    g.border()
    # 地面：第 20 行是站立面，21 行继续挖深，22 行是基岩
    g.row(22, 1, W - 2, "#")
    g.row(21, 1, W - 2, "#")
    g.row(20, 1, W - 2, "#")
    # 岩浆池（3 格宽，2 格深）：火娃可涉水，水娃必须跳过
    g.rect(12, 20, 14, 21, "^")
    # 水潭（3 格宽，2 格深）：水娃可涉水，火娃必须跳过
    g.rect(28, 20, 30, 21, "~")
    # 终点台阶：三级，每级只高 1 格，保证一定爬得上来
    g.row(19, 34, 44, "#")
    g.row(18, 37, 44, "#")
    g.row(17, 40, 44, "#")
    g.put(3, 19, "F")
    g.put(6, 19, "W")
    g.put(42, 16, "E")     # 火门在最高一级
    g.put(36, 18, "Q")     # 水门在第一级

    objects = [
        # 岩浆池底 —— 只有火娃敢下去
        {"type": "gem", "cell": [12, 21], "color": "red"},
        {"type": "gem", "cell": [14, 21], "color": "red"},
        {"type": "gem", "cell": [38, 17], "color": "red"},
        # 水潭底 —— 只有水娃敢下去
        {"type": "gem", "cell": [28, 21], "color": "blue"},
        {"type": "gem", "cell": [30, 21], "color": "blue"},
        {"type": "gem", "cell": [35, 18], "color": "blue"},
    ]
    return {
        "name": "1 - 初识元素",
        "subtitle": "火娃不怕岩浆，水娃不怕水。碰到克自己的液体就跳过去。",
        "grid": g.rows(),
        "objects": objects,
    }


# ============================================================ 关卡 2
def level_02():
    """机关关：推箱压板开门 → 移动平台渡毒池 → 拉杆再开门 → 传送门取宝石。"""
    W, H = 52, 24
    g = Grid(W, H)
    g.border()
    g.row(23, 1, W - 2, "#")          # 基岩
    g.row(22, 1, W - 2, "#")          # 站立面
    # 毒液池 8 格宽 —— 远超跳跃极限，必须坐移动平台
    g.row(22, 25, 32, "*")
    # 水潭 3 格宽（水娃涉水，火娃跳过）
    g.row(22, 39, 41, "~")
    # 终点台阶：两级，每级 1 格
    g.row(21, 45, 50, "#")
    g.row(20, 48, 50, "#")
    # 传送门高台：离地 5 格，只能靠传送门抵达，跳完再跳下来
    g.row(17, 12, 16, "=")
    g.put(3, 21, "F")
    g.put(6, 21, "W")
    g.put(50, 19, "E")
    g.put(46, 20, "Q")

    objects = [
        # 机关链 1：把木箱推上压力板 → 门 A 打开
        {"type": "box", "cell": [10, 21]},
        {"type": "plate", "cell": [17, 21], "channel": "A"},
        # 门从格子向下延伸，高 7 格 = 覆盖第 15~21 行，把通路整个封死
        {"type": "door", "cell": [21, 15], "height": 7, "channel": "A"},
        # 移动平台：站立面在第 20 行（离地 2 格），往返渡毒池
        {"type": "moving_platform", "from": [22, 20], "to": [33, 20],
         "width": 3, "speed": 95},
        # 机关链 2：过了毒池拉下拉杆 → 门 B 打开
        {"type": "lever", "cell": [35, 21], "channel": "B"},
        {"type": "door", "cell": [37, 15], "height": 7, "channel": "B"},
        # 传送门：出生点左侧的隐蔽角落 ↔ 高空宝石台。
        # 关键：入口绝不能放在主干道上 —— 玩家每次路过都会被意外传走。
        # 放在出生点左边，玩家只会往右走，就成了需要主动探索的秘密。
        {"type": "portal", "cell": [2, 21], "pair": "V1"},
        {"type": "portal", "cell": [14, 16], "pair": "V1"},
        {"type": "gem", "cell": [13, 16], "color": "red"},
        {"type": "gem", "cell": [34, 21], "color": "red"},
        {"type": "gem", "cell": [49, 19], "color": "red"},
        {"type": "gem", "cell": [15, 16], "color": "blue"},
        {"type": "gem", "cell": [39, 22], "color": "blue"},   # 水潭底
        {"type": "gem", "cell": [47, 20], "color": "blue"},
    ]
    return {
        "name": "2 - 机关重重",
        "subtitle": "木箱压板开门，平台渡毒池，拉杆再开一扇。出生点往左有传送门。",
        "grid": g.rows(),
        "objects": objects,
    }


# ============================================================ 关卡 3
def level_03():
    """分头行动：宽液体当「元素门」，把两人强行分开，再互相为对方开门。

    设计要点（也是这一关和前两关的本质区别）：
      · 前两关是「串联」—— 一个人做的事，另一个人接着做。
        这一关是「并联」—— 两人各走各的，谁也替不了谁。
      · 分岔不用墙，用液体宽度：≤4 格两人都能过（一个趟水一个跳过），
        ≥6 格只有免疫方能过。宽液体就是一道只认身份的门。
      · 互相开门的顺序是死结，必须靠沟通解开：
        火娃拉杆 A → 开水娃路上的门 B
        水娃站住板 C → 开火娃路上的门 D（人一走门就关）
        火娃趁门 D 开着冲过去拉自锁拉杆 E → 开水娃路上的门 F
        水娃这才敢离开板 C
    """
    W, H = 64, 24
    g = Grid(W, H)
    g.border()
    # 地面：21 是站立面，22/23 是池底与基岩
    g.row(21, 1, W - 2, "#")
    g.row(22, 1, W - 2, "#")
    g.row(23, 1, W - 2, "#")
    # 水潭 8 格宽 2 格深 —— 水娃趟过去，火娃跳不过（跳跃上限 5 格）
    g.rect(18, 21, 25, 22, "~")
    # 上层平台：12 是站立面，13 是支撑兼熔岩池底
    g.row(12, 24, 56, "#")
    g.row(13, 24, 56, "#")
    # 上层岩浆 8 格宽 —— 火娃趟过去，水娃过不去。元素门。
    g.row(12, 32, 39, "^")
    # 从地面爬上上层的台阶：每级抬升 2 格，最后一级与平台同高直接接上
    g.row(19, 13, 15, "#")
    g.row(17, 16, 18, "#")
    g.row(15, 19, 21, "#")
    g.rect(22, 12, 23, 13, "#")   # 与平台同高的最后一级

    g.put(3, 20, "F")
    g.put(6, 20, "W")
    g.put(55, 11, "E")            # 火门：上层尽头
    g.put(50, 20, "Q")            # 水门：地面尽头

    objects = [
        # 火娃（上层）：趟过岩浆 → 拉下拉杆 A → 开水娃路上的门 B
        {"type": "lever", "cell": [44, 11], "channel": "A"},
        {"type": "door", "cell": [36, 15], "height": 7, "channel": "A"},
        # 水娃（地面）：趟过水潭 → 站住压力板 C → 开火娃路上的门 D
        # 门 D 只在人站着时开，所以火娃必须趁这时候冲过去
        {"type": "plate", "cell": [30, 20], "channel": "C"},
        {"type": "door", "cell": [48, 7], "height": 6, "channel": "C"},
        # 火娃过了门 D 拉下自锁拉杆 E → 门 F 永久打开，水娃才敢离开板子
        {"type": "lever", "cell": [51, 11], "channel": "E"},
        {"type": "door", "cell": [44, 15], "height": 7, "channel": "E"},
        # 宝石：各自藏在只有自己敢下去的液体里，外加一颗要对方帮忙才拿得到
        {"type": "gem", "cell": [34, 12], "color": "red"},
        {"type": "gem", "cell": [37, 12], "color": "red"},
        {"type": "gem", "cell": [52, 11], "color": "red"},
        {"type": "gem", "cell": [20, 22], "color": "blue"},
        {"type": "gem", "cell": [23, 22], "color": "blue"},
        {"type": "gem", "cell": [46, 20], "color": "blue"},
    ]
    return {
        "name": "3 - 分头行动",
        "subtitle": "八格宽的液体只有一个人敢过。火娃走上层，水娃走地面，互相开门。",
        "grid": g.rows(),
        "objects": objects,
    }


# ============================================================ 关卡 4
def level_04():
    """时序接力：推箱压板只是入场券，真正的难点是「谁先动、谁等着」。

    新机制：压力板 + 木箱是「一次性投资」（箱子推上去就一直压着），
    压力板 + 人是「持续投资」（人一走门就关）。这一关把两种混在一起，
    逼玩家分清哪些资源是永久的、哪些得有人守着。

    结构性教训（改了三版才对）：
    最早把水娃设计成「上层全程栈道」，结果火娃顺着栈道走到头直接跳进终点，
    整条机关链被绕过 —— 而且校验器看不出来，因为它只验证「能不能到」，
    不验证「是不是按设计的路到」。两条全程平行的路线必然给出捷径，
    分头必须是「一处 分岔」。所以改成单走廊 + 一段水娃专用的绕行栈桥：
    栈桥只跨火娃的岩浆段，两端都被门和地形封死。
    """
    W, H = 62, 24
    g = Grid(W, H)
    g.border()
    # 地面走廊：21 是站立面，22/23 是池底与基岩
    g.row(21, 1, W - 2, "#")
    g.row(22, 1, W - 2, "#")
    g.row(23, 1, W - 2, "#")
    # 毒液池 7 格宽：谁都过不去，必须坐移动平台
    g.rect(19, 21, 25, 22, "*")
    # 岩浆 6 格宽：只有火娃敢过，水娃从上面的栈桥绕
    g.rect(40, 21, 45, 22, "^")
    # 终点台阶
    g.row(20, 54, 59, "#")
    # 水娃的绕行栈桥：17 是站立面，18 是支撑。只跨岩浆这一段，别给全程。
    g.row(17, 33, 44, "#")
    g.row(18, 33, 44, "#")
    # 通往栈桥的台阶（每级 2 格）
    g.row(19, 31, 32, "#")

    g.put(2, 20, "F")
    g.put(5, 20, "W")
    g.put(57, 19, "E")            # 火门：地面终点台阶上
    g.put(44, 16, "Q")            # 水门：栈桥尽头

    objects = [
        # 一次性投资：火娃把木箱推上板 A，门 A 就永久开着
        {"type": "box", "cell": [10, 20]},
        {"type": "plate", "cell": [14, 20], "channel": "A"},
        {"type": "door", "cell": [16, 15], "height": 7, "channel": "A"},
        # 毒液池：平台往返，得等时机（平台不带 channel，一直运行）
        {"type": "moving_platform", "from": [18, 19], "to": [26, 19],
         "width": 3, "speed": 90},
        # 持续投资：水娃站在板 B 上，地面门 B 才开 —— 人一走门就关。
        # 门 B 只封走廊（19~21 行），够不到 17 行的栈桥。
        {"type": "plate", "cell": [32, 20], "channel": "B"},
        {"type": "door", "cell": [36, 19], "height": 3, "channel": "B"},
        # 火娃趁门 B 开着趟过岩浆，拉下自锁拉杆 C，水娃才能离开板 B 上栈桥
        {"type": "lever", "cell": [48, 20], "channel": "C"},
        {"type": "door", "cell": [42, 13], "height": 5, "channel": "C"},
        {"type": "gem", "cell": [42, 22], "color": "red"},
        {"type": "gem", "cell": [48, 20], "color": "red"},
        {"type": "gem", "cell": [56, 19], "color": "red"},
        {"type": "gem", "cell": [30, 20], "color": "blue"},
        {"type": "gem", "cell": [36, 16], "color": "blue"},
        {"type": "gem", "cell": [43, 16], "color": "blue"},
    ]
    return {
        "name": "4 - 时序接力",
        "subtitle": "箱子压住的板是永久的，人踩住的板一走就关。分清楚再动手。",
        "grid": g.rows(),
        "objects": objects,
    }


# ============================================================ 关卡 5
def level_05():
    """双子电梯：把「移动平台」从横向渡河升级成纵向电梯，并且给它接上 channel。

    这是全局第一次让平台受机关控制 —— 平台不再是一直在跑的背景道具，
    而是「谁在供电，谁才能走」的稀缺资源。由此得到一条干净的依赖链：
        水娃踩住压力板 A → 火娃的电梯才有电 → 火娃上到顶层
        火娃拉下自锁拉杆 B → 水娃的电梯才有电 → 水娃上到顶层

    两个设计要点：
      · 压力板必须挂在【箱子推不上去】的高台上（离地 3 格）。
        如果箱子能压住它，火娃一个人就搞定了，合作就没了。
      · 两台电梯的落点各自只有自己那一侧的顶层，
        跨不过去（中间是 30 多格的空档），所以别人开的门帮不了自己。
    """
    W, H = 54, 22
    g = Grid(W, H)
    g.border()
    # 地面：19 是站立面，20/21 是池底与基岩
    g.row(19, 1, W - 2, "#")
    g.row(20, 1, W - 2, "#")
    g.row(21, 1, W - 2, "#")
    # 岩浆池 4 格宽 —— 火娃趟过去，水娃跳过去（正好卡在跳跃极限 5 格）
    g.rect(18, 19, 21, 20, "^")
    # 水潭 6 格宽 —— 水娃趟过去，火娃过不去。右半张图对火娃是禁区
    g.rect(28, 19, 33, 20, "~")
    # 压力板高台：离地 3 格，只能跳上去，箱子推不上来
    g.row(16, 14, 16, "#")
    # 两座顶层：各自只有自己的电梯能到
    g.row(4, 2, 8, "#")        # 左顶：火娃出口 + 拉杆 B
    g.row(4, 45, 51, "#")      # 右顶：水娃出口

    g.put(3, 18, "F")
    g.put(6, 18, "W")
    g.put(4, 3, "E")
    g.put(48, 3, "Q")

    objects = [
        # 水娃踩住板 A，火娃的电梯才有电（高台，箱子够不着，只能人站）
        {"type": "plate", "cell": [15, 15], "channel": "A"},
        {"type": "moving_platform", "from": [9, 17], "to": [9, 4],
         "width": 3, "speed": 130, "channel": "A"},
        # 火娃到顶后拉下自锁拉杆 B，水娃的电梯才解锁
        {"type": "lever", "cell": [6, 3], "channel": "B"},
        {"type": "moving_platform", "from": [41, 17], "to": [41, 4],
         "width": 3, "speed": 130, "channel": "B"},
        # 宝石：各自藏在自己敢下去的池底，再各放一颗在对方要去的高台上
        {"type": "gem", "cell": [18, 20], "color": "red"},
        {"type": "gem", "cell": [21, 20], "color": "red"},
        {"type": "gem", "cell": [7, 3], "color": "red"},
        {"type": "gem", "cell": [29, 20], "color": "blue"},
        {"type": "gem", "cell": [32, 20], "color": "blue"},
        {"type": "gem", "cell": [49, 3], "color": "blue"},
    ]
    return {
        "name": "5 - 双子电梯",
        "subtitle": "水娃踩住压力板，火娃的电梯才有电；火娃拉杆后，水娃的电梯才解锁。",
        "grid": g.rows(),
        "objects": objects,
    }


# ============================================================ 关卡 6
def level_06():
    """传送终局：把前面五关教过的所有手法串成一条长路。

    全程机关链：
        木箱压板 A → 门 A    （一次性投资，两人一起推箱）
        水潭 4 格宽          （水娃趟、火娃跳 —— 元素分层，不是阻断）
        毒液 8 格宽 + 往返平台（谁都过不去，必须等平台）
        岩浆 4 格宽          （火娃趟进去捡红宝石，水娃跳过去）
        拉杆 B → 门 B         （自锁；门后是传送门壁龛）
        传送门 → 终点高台    （高台 6 格高，四面封死，只有传送门能上）

    传送门为什么放在门 B 后面：校验器不认识「传送门带不带机关」——
    portal_links 是无条件连通的。如果把传送门入口摆在开阔地，
    「什么都不做也能到出口」的捷径体检就会报警。所以入口必须被一扇
    机关门挡着，这样它才真正是机关链的最后一环，而不是绕过整条链的洞。

    壁龛的进出也是刻意设计的：壁龛离地 3 格，从正下方（门 B 那一侧的死角）
    跳不上去 —— 跳跃弧线会被壁龛自己的边缘挡住；只有从门 B 打开后的左侧
    隔 2 格起跳才够得着。
    """
    W, H = 64, 22
    g = Grid(W, H)
    g.border()
    # 地面：19 是站立面，20/21 是池底与基岩
    g.row(19, 1, W - 2, "#")
    g.row(20, 1, W - 2, "#")
    g.row(21, 1, W - 2, "#")
    # 水潭 4 格宽：水娃趟，火娃跳
    g.rect(22, 19, 25, 20, "~")
    # 毒液池 8 格宽：谁都过不去，必须坐平台
    g.rect(29, 19, 36, 20, "*")
    # 岩浆 4 格宽：火娃趟进去捡宝石，水娃跳过去
    g.rect(40, 19, 43, 20, "^")
    # 传送门壁龛：离地 3 格的悬空台
    g.row(16, 49, 51, "#")
    # 终点高台：6 格高，四面封死，只能靠传送门上
    g.rect(52, 13, 62, 21, "#")

    g.put(3, 18, "F")
    g.put(6, 18, "W")
    g.put(58, 12, "E")
    g.put(61, 12, "Q")

    objects = [
        # 一次性投资：把木箱推上板 A，门 A 永久打开
        {"type": "box", "cell": [10, 18]},
        {"type": "plate", "cell": [16, 18], "channel": "A"},
        # 门从格子向下延伸，高 8 格 = 覆盖第 11~18 行，正好封死整条走廊
        {"type": "door", "cell": [19, 11], "height": 8, "channel": "A"},
        # 毒液池：平台往返，得等时机（不带 channel，一直运行）
        {"type": "moving_platform", "from": [27, 17], "to": [37, 17],
         "width": 3, "speed": 95},
        # 过了毒池拉下拉杆 B → 门 B 打开，传送门壁龛才够得着
        {"type": "lever", "cell": [45, 18], "channel": "B"},
        {"type": "door", "cell": [48, 11], "height": 8, "channel": "B"},
        # 传送门：壁龛 ↔ 终点高台
        {"type": "portal", "cell": [50, 15], "pair": "V1"},
        {"type": "portal", "cell": [56, 12], "pair": "V1"},
        # 宝石：两颗在岩浆底（只有火娃敢下去），两颗在水潭底，
        # 一颗在壁龛上、一颗在门 B 后的死角里（都要先解门 B）
        {"type": "gem", "cell": [40, 20], "color": "red"},
        {"type": "gem", "cell": [43, 20], "color": "red"},
        {"type": "gem", "cell": [49, 15], "color": "red"},
        {"type": "gem", "cell": [22, 20], "color": "blue"},
        {"type": "gem", "cell": [25, 20], "color": "blue"},
        {"type": "gem", "cell": [50, 18], "color": "blue"},
    ]
    return {
        "name": "6 - 传送终局",
        "subtitle": "推箱开门、坐平台过毒池、拉杆解锁传送门 —— 高台只有传送门上得去。",
        "grid": g.rows(),
        "objects": objects,
    }


LEVELS = [level_01(), level_02(), level_03(), level_04(),
          level_05(), level_06()]


# ============================================================ 可达性校验
def immune_to(element, kind):
    if kind == "acid":
        return False
    if kind == "lava":
        return element == "fire"
    if kind == "water":
        return element == "water"
    return True


def channel_active(o, active):
    """机关是否已通电：channel 为空 = 一直工作；否则要看 channel 有没有被激活。"""
    ch = o.get("channel", "")
    return ch == "" or ch in active


def build_block_maps(grid, objects, element, active=frozenset()):
    """blocked[y][x]：该格对 element 不可进入（实心 / 会致死的液体 / 关着的门）
       virtual：移动平台两端提供的站立面（平台本身也可能受 channel 控制）
       fluid_surf：免疫液体的「液面」——免疫角色能浮在液面上走过去。
       deadly：会致死的液体格 —— 绝不能当落脚面。

    deadly 这一项看着多余（它本来就在 blocked 里），但缺了它会出大事：
    致命液体在物理上是触发区不是实体，角色踩上去是掉进去死，不是站住。
    如果只因为它「不可进入」就当成可站立的地面，校验器就会认为角色能
    从岩浆顶上走过去 —— 于是再宽的岩浆也拦不住人，元素门彻底失效。

    第三项是「元素门」这个设计手法的前提。角色免疫的液体对他不是障碍：
    他可以下到液里、浮起来、沿着液面一路走过去。如果只把液体当成
    「可以跳过去的空隙」，那 6 格宽的岩浆会变成谁都过不去 —— 可实际上
    火娃大可以趟过去，水娃不行。宽度差就是元素门：
      ≤4 格宽：两人都能过（一个趟水、一个跳过去）
      ≥6 格宽：只有免疫方能过，另一方被彻底分开
    """
    H, W = len(grid), len(grid[0])
    blocked = [[False] * W for _ in range(H)]
    for y in range(H):
        for x in range(W):
            ch = grid[y][x]
            if ch in SOLID_CHARS:
                blocked[y][x] = True
            elif ch in FLUID_CHARS:
                blocked[y][x] = not immune_to(element, FLUID_CHARS[ch])

    # 关着的门是墙。门从 cell 所在格向下延伸 height 格。
    for o in objects:
        if o.get("type") != "door" or channel_active(o, active):
            continue
        cx, cy = o["cell"]
        h = int(o.get("height", 3))
        for r in range(cy, cy + h):
            if 0 <= r < H:
                blocked[r][cx] = True

    fluid_surf = set()
    deadly = set()
    for y in range(H):
        for x in range(W):
            ch = grid[y][x]
            if ch not in FLUID_CHARS:
                continue
            if not immune_to(element, FLUID_CHARS[ch]):
                deadly.add((x, y))
                continue
            # 液面 = 液体格，且正上方不是液体（头顶净空由落点检查负责）
            if y - 1 >= 0 and grid[y - 1][x] not in FLUID_CHARS:
                fluid_surf.add((x, y))

    virtual = set()
    for o in objects:
        if o.get("type") != "moving_platform" or not channel_active(o, active):
            continue
        fx, fy = o["from"]
        tx, ty = o["to"]
        w = int(o.get("width", 3))
        # 平台碰撞体只占格子上半部分，站立面就在格子的顶边
        for cx in range(fx, fx + w):
            virtual.add((cx, fy))
        for cx in range(tx, tx + w):
            virtual.add((cx, ty))
    return blocked, virtual, fluid_surf, deadly


def surfaces_at(col, blocked, virtual, fluid_surf=frozenset(),
                deadly=frozenset()):
    """某一列所有可站立的面（返回行号，数值越小越高）。
       免疫液体的液面也算落脚点 —— 角色会浮在液面上。
       会致死的液体不算 —— 踩上去是掉进去死，不是站住。"""
    out = []
    for y in range(len(blocked)):
        if (col, y) in deadly:
            continue
        here = blocked[y][col] or ((col, y) in virtual) or ((col, y) in fluid_surf)
        if not here:
            continue
        # 头顶净空：不能是实心，也不能是平台。
        # 注意这里【不能】排除「头顶是免疫液体」—— 站在池底时身体本来
        # 就浸在液体里，那正是合法状态，排掉它就无法下到池底捡宝石。
        above_free = (y - 1 >= 0) and (not blocked[y - 1][col]) \
            and ((col, y - 1) not in virtual)
        if above_free:
            out.append(y)
    return out


def platform_links(objects, active=frozenset()):
    """移动平台两端的连边：站上这一头就被带到另一头。"""
    links = []
    for o in objects:
        if o.get("type") != "moving_platform" or not channel_active(o, active):
            continue
        fx, fy = o["from"]
        tx, ty = o["to"]
        w = int(o.get("width", 3))
        a = [(cx, fy) for cx in range(fx, fx + w)]
        b = [(cx, ty) for cx in range(tx, tx + w)]
        for p in a:
            for q in b:
                links.append((p, q))
                links.append((q, p))
    return links


# ---------------------------------------------------------------- 谜题求解
def _solid_at(grid, c, y):
    return 0 <= y < len(grid) and 0 <= c < len(grid[0]) \
        and grid[y][c] in SOLID_CHARS


def _door_blocks(objects, c, y, active):
    for o in objects:
        if o.get("type") != "door" or channel_active(o, active):
            continue
        cx, cy = o["cell"]
        h = int(o.get("height", 3))
        if c == cx and cy <= y < cy + h:
            return True
    return False


def _exposed_surface(grid, objects, c, y, active):
    """(c, y) 是不是一个露天的落脚面：y 行实心，且 y-1 行没有实心方块或关着的门。"""
    if not _solid_at(grid, c, y):
        return False
    if y - 1 < 0:
        return False
    return not _solid_at(grid, c, y - 1) and not _door_blocks(objects, c, y - 1, active)


def box_reachable(grid, objects, box_cell, player_reach, active):
    """木箱能被推到哪些位置，返回 {(列, 落脚行)}。

    规则来自 PushBox._detect_push()：
      · 玩家必须紧贴木箱（水平距离 ≤ 1.05 格）
      · 玩家与木箱的高度差 ≤ 0.9 格 —— 因为落脚面都是整格的，
        等价于「玩家站的那一格必须和木箱同一层」
      · 木箱只能沿同一高度的连续地面被推，推不上台阶
    """
    W = len(grid[0])
    c0 = box_cell[0]
    # 木箱受重力，落在它下方第一个实心格上
    s0 = None
    for y in range(box_cell[1], len(grid)):
        if _solid_at(grid, c0, y):
            s0 = y
            break
    if s0 is None:
        return set()

    seen = {(c0, s0)}
    q = deque([(c0, s0)])
    while q:
        c, s = q.popleft()
        for dc in (-1, 1):
            nc = c + dc
            if not (0 <= nc < W):
                continue
            # 目标列必须在同一高度有落脚面，且头顶净空
            if not _exposed_surface(grid, objects, nc, s, active):
                continue
            # 推的人站在木箱背后，且那一格玩家真的走得到
            behind = c - dc
            if not (0 <= behind < W):
                continue
            if not _exposed_surface(grid, objects, behind, s, active):
                continue
            if (behind, s) not in player_reach:
                continue
            if (nc, s) in seen:
                continue
            seen.add((nc, s))
            q.append((nc, s))
    return seen


def solve_channels(grid, objects):
    """求「哪些 channel 最终能被激活」，返回 (active, 未解开的依赖列表)。

    思路是不动点迭代 —— 不断问「现在能到的地方里，有没有新的开关可以打开」：
      · 杠杆：够得着就能拉，且自锁 → 永久激活
      · 压力板 + 木箱：箱子推上去就一直压着 → 永久激活
      · 压力板 + 人站：只能临时生效（站着的人去不了出口），
        所以只当作「探路的踏脚石」：如果它让另一个人够到了新杠杆，
        那根杠杆就是永久解
    迭代到不再增长为止。这样「门的开关在门后面」这类循环依赖会被自然识别为无解。
    """
    active = set()
    unsolved = []
    for _ in range(24):
        fire = compute_reach(grid, objects, "fire", active)
        water = compute_reach(grid, objects, "water", active)
        grew = False

        # --- 杠杆：够得着就永久激活
        for o in objects:
            if o.get("type") != "lever" or o.get("channel") in active:
                continue
            cx, cy = o["cell"]
            if (cx, cy + 1) in fire or (cx, cy + 1) in water:
                active.add(o["channel"])
                grew = True

        # --- 压力板 + 木箱：推上去就永久压住
        for o in objects:
            if o.get("type") != "plate" or o.get("channel") in active:
                continue
            px, py = o["cell"]
            target = (px, py + 1)
            both = fire | water
            for b in objects:
                if b.get("type") != "box":
                    continue
                if target in box_reachable(grid, objects, b["cell"], both, active):
                    active.add(o["channel"])
                    grew = True
                    break

        # --- 压力板 + 人站着：只是踏脚石，看它能不能换来一根杠杆
        for o in objects:
            if o.get("type") != "plate" or o.get("channel") in active:
                continue
            px, py = o["cell"]
            for pinner, explorer in (("fire", "water"), ("water", "fire")):
                held = fire if pinner == "fire" else water
                if (px, py + 1) not in held:
                    continue
                tmp = active | {o["channel"]}
                after = compute_reach(grid, objects, explorer, tmp)
                before = fire if explorer == "fire" else water
                for l in objects:
                    if l.get("type") != "lever" or l.get("channel") in active:
                        continue
                    lx, ly = l["cell"]
                    if (lx, ly + 1) in after and (lx, ly + 1) not in before:
                        active.add(l["channel"])
                        grew = True

        if not grew:
            break

    # 报告没被解开的门
    for o in objects:
        if o.get("type") == "door" and not channel_active(o, active):
            unsolved.append(o.get("channel"))
    return active, unsolved


def compute_reach(grid, objects, element, active):
    """在给定已激活 channel 的前提下，算出 element 能站到哪些地方。"""
    blocked, virtual, fluid_surf, deadly = build_block_maps(
        grid, objects, element, active)
    links = platform_links(objects, active) + portal_links(objects)
    marker = "F" if element == "fire" else "W"
    for y, line in enumerate(grid):
        x = line.find(marker)
        if x >= 0:
            return reachable(blocked, virtual, links, (x, y + 1),
                             fluid_surf, deadly)
    return set()


def portal_links(objects):
    """传送门：同 pair_id 的两端互相连通，站进去就被送到另一头的脚下。"""
    by_pair = {}
    for o in objects:
        if o.get("type") != "portal":
            continue
        cx, cy = o["cell"]
        by_pair.setdefault(o.get("pair", ""), []).append((cx, cy + 1))
    links = []
    for cells in by_pair.values():
        for i in range(len(cells)):
            for j in range(i + 1, len(cells)):
                links.append((cells[i], cells[j]))
                links.append((cells[j], cells[i]))
    return links


def _can_move(blocked, virtual, x, y, nx, ny, d):
    """从站立面 (x,y) 到 (nx,ny) 是否可行。"""
    H, W = len(blocked), len(blocked[0])
    rise = y - ny                     # 正数 = 要往上爬

    # 落点头顶必须有 1 格净空（角色高 28px，占 1 格）
    if ny - 1 < 0 or blocked[ny - 1][nx] or ((nx, ny - 1) in virtual):
        return False

    if d == 1:
        if rise > MAX_STEP_UP_CELLS:
            return False
        if rise < 0:                  # 往下跳：中间不能卡住
            for r in range(y, ny):
                if 0 <= r < H and (blocked[r][nx] or ((nx, r) in virtual)):
                    return False
        return True

    # 跨沟：上升不能超过跳跃高度
    if rise > MAX_JUMP_UP_CELLS:
        return False
    # 跳跃弧线经过的头顶几格必须净空（注意不含起跳行本身 —— 那正是要跨过去的坑）
    lo, hi = (x, nx) if x < nx else (nx, x)
    for cx in range(lo + 1, hi):
        for r in range(y - 1, y - 2 - MAX_JUMP_UP_CELLS, -1):
            if 0 <= r < H and (blocked[r][cx] or ((cx, r) in virtual)):
                return False
    return True


def reachable(blocked, virtual, links, start, fluid_surf=frozenset(),
                deadly=frozenset()):
    """BFS：按实测运动能力扩散，返回可达站立面的集合。"""
    W = len(blocked[0])
    seen = set()
    q = deque()
    if start is None:
        return seen
    seen.add(start)
    q.append(start)
    while q:
        x, y = q.popleft()
        for a, b in links:
            if a == (x, y) and b not in seen:
                seen.add(b)
                q.append(b)
        for d in range(1, MAX_GAP_CELLS + 1):
            for nx in (x - d, x + d):
                if not (0 <= nx < W):
                    continue
                for ny in surfaces_at(nx, blocked, virtual, fluid_surf, deadly):
                    if (nx, ny) in seen:
                        continue
                    if not _can_move(blocked, virtual, x, y, nx, ny, d):
                        continue
                    seen.add((nx, ny))
                    q.append((nx, ny))
    return seen


def solve_endgame(grid, objects, base_active, exits):
    """求一种「谁按住哪块压力板」的分配，让两人都能到各自出口。

    为什么需要这一步：门不一定能被永久打开。经典解法是
    「一人站板、一人过门」，过门的人再拉一根自锁杠杆，把最后那扇门永久
    打开 —— 这时站板的人才能离开。所以终局判定必须允许「临时按住」的 channel，
    否则这类关卡会被误判成无解。

    模型：枚举每块压力板的归属（没人 / 火娃 / 水娃），然后
      火娃可达集 = base_active ∪ {水娃按住的板} 下算
      水娃可达集 = base_active ∪ {火娃按住的板} 下算
    再要求每块被按住的板，按住它的人确实够得着。

    边界：这个模型假设「两人行动互不阻塞、且只需一次交接」。
    它覆盖不了「两人必须同时各按一块板第三扇门才开」这类设计 —— 那种关卡
    校验器会放行，得人工试玩确认。
    """
    from itertools import product

    plates = [o for o in objects if o.get("type") == "plate"]
    if len(plates) > 6:
        # 3^6=729 种分配还能秒算，再多就是关卡设计失控了
        return None, "压力板多达 %d 块，终局求解规模爆炸" % len(plates)

    best = None
    for assign in product((None, "fire", "water"), repeat=len(plates)):
        held = {"fire": set(), "water": set()}
        for p, who in zip(plates, assign):
            if who is not None:
                held[who].add(p.get("channel"))

        # 火娃享受水娃按住的板，反之亦然
        reach_f = compute_reach(grid, objects, "fire", base_active | held["water"])
        reach_w = compute_reach(grid, objects, "water", base_active | held["fire"])

        ok = True
        for p, who in zip(plates, assign):
            if who is None:
                continue
            px, py = p["cell"]
            r = reach_f if who == "fire" else reach_w
            if (px, py + 1) not in r:
                ok = False
                break
        if not ok:
            continue

        for element, marker in (("fire", "E"), ("water", "Q")):
            ex = exits[element]
            if ex is None:
                ok = False
                break
            r = reach_f if element == "fire" else reach_w
            if (ex[0], ex[1] + 1) not in r:
                ok = False
                break
        if not ok:
            continue

        # 优先选「需要按住的板最少」的分配 —— 那是最不容易玩崩的解法
        cost = sum(1 for a in assign if a is not None)
        if best is None or cost < best[0]:
            best = (cost, dict(held), reach_f, reach_w)

    if best is None:
        return None, None
    return best, None


def validate(lv, index):
    """返回问题列表（空 = 完全通过）。"""
    errs = []
    grid, objects = lv["grid"], lv["objects"]
    H, W = len(grid), len(grid[0])
    tag = "关卡%d" % (index + 1)

    for i, line in enumerate(grid):
        if len(line) != W:
            errs.append("%s: 第 %d 行宽度 %d != %d" % (tag, i, len(line), W))

    for ch, label in (("F", "火娃出生点"), ("W", "水娃出生点"),
                      ("E", "火门"), ("Q", "水门")):
        n = sum(line.count(ch) for line in grid)
        if n != 1:
            errs.append("%s: %s 出现 %d 次（应为 1 次）" % (tag, label, n))

    def find(ch):
        for y, line in enumerate(grid):
            x = line.find(ch)
            if x >= 0:
                return (x, y)
        return None

    spawns = {"fire": find("F"), "water": find("W")}
    exits = {"fire": find("E"), "water": find("Q")}

    # 先解机关链：只有真正能被打开的门才算通路
    # 先解机关链，找出「永久打不开」的门
    active, unsolved = solve_channels(grid, objects)

    # 终局：允许「一人按住压力板，另一人借机过门」。找不到任何一种
    # 板分配能让两人都到出口，才是真的不可通关。
    # 注意：即使终局不成立也不能提前 return —— 后面的池深、宝石检查
    # 必须照样跑完。否则会出现「关卡因为别的原因挂了，池深超标反而被漏掉」。
    plan, note = solve_endgame(grid, objects, active, exits)
    if note:
        errs.append("%s: 【致命】%s" % (tag, note))
        plan = None
    if plan is None:
        # 只有终局也走不通时，未解开的门才算致命。
        # 「门解不开」本身不是死罪 —— 一人按板、另一人借机通过照样能通关，
        # 而那种情形机关链求解器是看不出来的，得靠终局求解放行。
        for ch in unsolved:
            errs.append("%s: 【致命】channel '%s' 的门解不开 —— "
                        "触发它的开关要么够不着，要么在门后面（循环依赖）"
                        % (tag, ch))
        for element, marker in (("fire", "火娃"), ("water", "水娃")):
            ex = exits[element]
            if ex is None:
                continue
            seen = compute_reach(grid, objects, element, active)
            if (ex[0], ex[1] + 1) not in seen:
                errs.append("%s: 【致命】%s 走不到自己的出口 (%d,%d)，"
                            "本关无法通关" % (tag, marker, ex[0], ex[1]))
        # 退化：终局不成立时，仍用「没人按板」的可达集跑完剩余检查
        plan = (0, {"fire": set(), "water": set()},
                compute_reach(grid, objects, "fire", active),
                compute_reach(grid, objects, "water", active))

    _cost, held, reach_f, reach_w = plan
    if _cost and (held["fire"] or held["water"]):
        who = []
        if held["fire"]:
            who.append("火娃按住 %s" % "/".join(sorted(held["fire"])))
        if held["water"]:
            who.append("水娃按住 %s" % "/".join(sorted(held["water"])))
        if who:
            print("      （通关需要 %s）" % "，".join(who))

    # 捷径体检：如果什么都不做也能到出口，说明机关链被地形绕过了。
    # 校验器只回答「能不能到」，不回答「是不是按设计的路到」——
    # 这条规则是给后者兜底的最低限度保险：至少能抓出「整条链被跳过」。
    # 它抓不出「跳过一半」，那种仍要靠人工试玩。
    # 只查有门的关卡 —— 教学关本来就没有机关链可绕。
    has_mech = any(o.get("type") in ("door", "lever", "plate") for o in objects)
    if has_mech and not any("走不到自己的出口" in m for m in errs):
        bare = {"fire": compute_reach(grid, objects, "fire", frozenset()),
                "water": compute_reach(grid, objects, "water", frozenset())}
        for element, mark in (("fire", "火娃"), ("water", "水娃")):
            ex = exits[element]
            if ex is None:
                continue
            if (ex[0], ex[1] + 1) in bare[element]:
                errs.append("%s: 【警告】%s 不用触发任何机关就能到出口 —— "
                            "存在绕过整条机关链的捷径" % (tag, mark))

    for element in ("fire", "water"):
        held_by_partner = held["water"] if element == "fire" else held["fire"]
        blocked, _virtual, _fs, _deadly = build_block_maps(
            grid, objects, element, active | held_by_partner)

        sp = spawns[element]
        if sp is None:
            errs.append("%s: 缺少 %s 出生点" % (tag, element))
            continue
        start = (sp[0], sp[1] + 1)
        if start[1] >= H or not (blocked[start[1]][start[0]]):
            errs.append("%s: 【致命】%s 出生点 (%d,%d) 脚下不是实地"
                        % (tag, element, sp[0], sp[1]))
            continue

        seen = reach_f if element == "fire" else reach_w

        # 宝石按颜色归属：红宝石归火娃、蓝宝石归水娃
        for o in objects:
            if o.get("type") != "gem":
                continue
            cx, cy = o["cell"]
            owner = "fire" if o.get("color", "red") == "red" else "water"
            if owner != element:
                continue
            if not (0 <= cx < W and 0 <= cy < H):
                errs.append("%s: 宝石 (%d,%d) 越界" % (tag, cx, cy))
                continue
            if (cx, cy + 1) not in seen:
                errs.append("%s: 【警告】%s 色宝石 (%d,%d) 对 %s 不可达"
                            % (tag, o.get("color"), cx, cy, element))

        # 池深检查：免疫方掉进去必须还游得上来，否则软锁
        for y in range(H):
            for x in range(W):
                ch = grid[y][x]
                if ch not in FLUID_CHARS:
                    continue
                if not immune_to(element, FLUID_CHARS[ch]):
                    continue
                depth, yy = 0, y
                while yy + 1 < H and not blocked[yy + 1][x]:
                    yy += 1
                    depth += 1
                if depth > MAX_SWIM_UP_CELLS:
                    errs.append(
                        "%s: 【致命】(%d,%d) 的%s池深 %d 格，%s 掉进去游不上来"
                        "（上浮上限 %d 格）"
                        % (tag, x, y, FLUID_CHARS[ch], depth, element,
                           MAX_SWIM_UP_CELLS))
    return errs


# ============================================================ 自检
## 校验器最大的风险不是报错太多，而是「永远通过」——那就等于没有。
## 这里用几个故意做坏的关卡反向验证：每一个都必须被抓出来。
def _broken_fixture(kind):
    """返回一个有特定缺陷的关卡，用于验证校验器确实能发现问题。"""
    g = Grid(30, 16)
    g.border()
    g.row(14, 1, 28, "#")            # 地面（站立面）
    g.row(15, 1, 28, "#")
    g.put(3, 13, "F")
    g.put(6, 13, "W")
    g.put(26, 12, "E")               # 出口在台阶上
    g.put(20, 13, "Q")               # 出口在地面
    g.row(13, 24, 28, "#")           # 台阶：第 13 行
    objs = []
    if kind == "gap_too_wide":
        g.row(14, 10, 22, ".")       # 挖一条 13 格的沟，远超跳跃极限
    elif kind == "step_too_high":
        g.row(13, 8, 9, "#")
        g.row(12, 8, 9, "#")
        g.row(11, 8, 9, "#")
        g.row(10, 8, 9, "#")         # 4 格高墙，跳不上去
    elif kind == "door_circular":
        # 门的压力板被放在门后面 —— 循环依赖，永远打不开
        g.put(12, 13, "#")
        objs = [{"type": "plate", "cell": [20, 13], "channel": "A"},
                {"type": "door", "cell": [12, 7], "height": 7, "channel": "A"},
                {"type": "box", "cell": [5, 13]}]
    elif kind == "box_cannot_reach_plate":
        # 木箱和压板之间隔着一格台阶，箱子推不过去
        g.row(13, 12, 12, "#")
        objs = [{"type": "plate", "cell": [16, 13], "channel": "A"},
                {"type": "door", "cell": [12, 7], "height": 7, "channel": "A"},
                {"type": "box", "cell": [8, 13]}]
    elif kind == "pool_too_deep":
        g.row(14, 10, 12, "~")       # 1 格深的水潭
        g.row(15, 10, 12, "~")
        g.row(15, 1, 28, "#")
        g.row(14, 1, 9, "#")
        g.row(14, 13, 28, "#")
        for r in range(10, 16):      # 再往下挖，池子总深 6 格，水娃游不上来
            g.put(10, r, "~")
            g.put(11, r, "~")
            g.put(12, r, "~")
    elif kind == "gem_unreachable":
        # 宝石吊在半空够不着的壁龛里 —— 只该报警告，不该阻断生成
        g.put(9, 8, "#")
        g.put(10, 8, "#")
        objs = [{"type": "gem", "cell": [9, 7], "color": "red"}]
    elif kind == "plate_unreachable":
        # 压力板吊在离地 5 格的孤岛上（跳跃上限 3 格），人和箱子都够不着。
        # 门永远打不开，校验器必须判死。
        g.row(9, 19, 21, "#")
        objs = [{"type": "plate", "cell": [20, 8], "channel": "A"},
                {"type": "door", "cell": [12, 7], "height": 7, "channel": "A"},
                {"type": "box", "cell": [5, 13]}]
    elif kind == "element_gate_blocks":
        # 6 格宽的岩浆，超过 5 格跳跃上限。火娃能趟过去，水娃过不去 ——
        # 这是「元素门」的核心手法，校验器必须认得出来。
        g.row(14, 14, 19, "^")
    elif kind == "coop_hold_plate":
        # 水娃必须站在压力板上，火娃才过得去门；水娃自己的出口在门的这一侧，
        # 所以她等火娃过去后就能离开板子。全程没有自锁杠杆 ——
        # 机关链求解器会说「门解不开」，但终局求解应该判定可通关。
        g.put(24, 13, "E")           # 火门在门 C 右侧
        g.put(9, 13, "Q")            # 水门在门 C 左侧，水娃随时能到
        objs = [{"type": "plate", "cell": [12, 13], "channel": "C"},
                {"type": "door", "cell": [16, 10], "height": 5, "channel": "C"}]
    return {"name": "fixture:" + kind, "subtitle": "", "grid": g.rows(),
            "objects": objs}


## 每个夹具必须触发「指定那条规则」，而不只是「报了点什么」。
## 否则会出现这种假象：池深超标的关卡因为"火娃恰好也走不到出口"而通过自检，
## 可真正该拦它的池深规则其实从来没生效过。
FIXTURE_EXPECT = {
    "gap_too_wide":           ("出口", "致命"),
    "step_too_high":          ("出口", "致命"),
    "door_circular":          ("门解不开", "致命"),
    "box_cannot_reach_plate": ("门解不开", "致命"),
    "pool_too_deep":          ("游不上来", "致命"),
    "gem_unreachable":        ("宝石", "警告"),
    "plate_unreachable":      ("门解不开", "致命"),
    "element_gate_blocks":    ("出口", "致命"),
}

## 正例夹具：这些关卡【应该】判定为可通关。
## 只测「坏关卡被抓出来」是不够的 —— 一个把所有关卡都判死的校验器
## 同样能通过反向测试。必须有一组「明明能过、你也得放它过」的关卡。
POSITIVE_FIXTURES = ("coop_hold_plate",)


def selftest():
    print("=== 校验器自检（每个夹具都必须命中指定规则）===")
    ok = True
    for kind, (needle, level) in FIXTURE_EXPECT.items():
        errs = validate(_broken_fixture(kind), 0)
        tag = "【%s】" % level
        hit = [m for m in errs if needle in m and tag in m]
        if hit:
            print("  [OK]   %-24s -> %s" % (kind, hit[0].split("：", 1)[-1][:66]))
        else:
            got = " / ".join(m.split("：", 1)[-1][:40] for m in errs) or "什么都没报"
            print("  [FAIL] %-24s 期望含「%s」的%s，实际得到：%s"
                  % (kind, needle, level, got))
            ok = False

    for kind in POSITIVE_FIXTURES:
        errs = validate(_broken_fixture(kind), 0)
        fatal = [m for m in errs if "【致命】" in m]
        if fatal:
            print("  [FAIL] %-24s 本该能通关，却被判死：%s"
                  % (kind, fatal[0].split("：", 1)[-1][:56]))
            ok = False
        else:
            print("  [OK]   %-24s 判定为可通关（正确放行）" % kind)

    print("自检%s" % ("通过" if ok else "失败"))
    return ok


# ============================================================ 代码生成
def gd_value(v, indent):
    t = "\t" * indent
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (int, float)):
        return str(v)
    if isinstance(v, str):
        return '"%s"' % v
    if isinstance(v, list):
        return "[" + ", ".join(gd_value(i, 0) for i in v) + "]"
    if isinstance(v, dict):
        # 注意：GDScript 的字典字面量键必须带引号，裸标识符会被当成变量
        return "{\n" + "".join(
            '%s\t"%s": %s,\n' % (t, k, gd_value(x, indent + 1))
            for k, x in v.items()) + "%s}" % t
    raise TypeError("unsupported: %r" % (v,))


HEADER = '''extends RefCounted
class_name Levels
## 关卡数据仓库。
##
## 关卡 = 「ASCII 地形网格」+「机关对象列表」两部分：
##   grid    描述地形、液体、出生点、出口（适合用字符画直观表达的内容）
##   objects 描述机关（压力板/门/平台/箱子/传送门/宝石），
##           因为它们需要 channel、高度、行程等参数，用坐标+属性表达更精确
##
## 图例： # 石头  = 木板  . 空气  F/W 出生点  E/Q 出口门
##        ^ 岩浆（火娃安全）  ~ 水潭（水娃安全）  * 毒液（都致命）
##
## 本文件由 tools/gen_levels.py 生成并校验，但生成结果就是普通 GDScript，
## 之后可直接手工编辑 —— 改完重跑生成器会覆盖，请注意。

const CELL := 32


static func count() -> int:
	return _all().size()


static func get_level(index: int) -> Dictionary:
	var list := _all()
	return list[clampi(index, 0, list.size() - 1)]


static func _all() -> Array:
	return [%s]

'''


def emit_level(fn_name, lv):
    out = ["static func %s() -> Dictionary:\n\treturn {\n" % fn_name]
    out.append('\t\t"name": "%s",\n' % lv["name"])
    out.append('\t\t"subtitle": "%s",\n' % lv["subtitle"])
    out.append('\t\t"grid": [\n')
    for r in lv["grid"]:
        out.append('\t\t\t"%s",\n' % r)
    out.append("\t\t],\n")
    out.append('\t\t"objects": [\n')
    for o in lv["objects"]:
        block = gd_value(o, 4).replace("\n", "\n\t\t\t")
        out.append("\t\t\t%s,\n" % block)
    out.append("\t\t],\n")
    out.append("\t}\n")
    return "".join(out)


def main():
    out_path = os.path.join(
        os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
        "scripts", "levels", "levels.gd")

    # 先跑自检：如果坏关卡都抓不出来，后面「校验通过」这四个字毫无意义
    if not selftest():
        print("\n校验器自身不可信，已中止生成。")
        sys.exit(1)
    print()

    all_errs = []
    for i, lv in enumerate(LEVELS):
        e = validate(lv, i)
        all_errs.extend(e)
        print("%-14s %dx%d  对象 %2d 个  %s"
              % (lv["name"], len(lv["grid"][0]), len(lv["grid"]),
                 len(lv["objects"]),
                 "校验通过" if not e else "%d 个问题" % len(e)))
        for m in e:
            print("   - " + m)

    if any("【致命】" in m for m in all_errs):
        print("\n存在致命问题，已中止生成。")
        sys.exit(1)

    names = ", ".join("_level_%02d()" % (i + 1) for i in range(len(LEVELS)))
    body = HEADER % names
    body += "\n\n".join(
        emit_level("_level_%02d" % (i + 1), lv) for i, lv in enumerate(LEVELS))

    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    with open(out_path, "w", encoding="utf-8", newline="\n") as f:
        f.write(body)
    print("\n已生成 %s（%d 关，%d 字节）" % (out_path, len(LEVELS), len(body)))
    warns = [m for m in all_errs if "【警告】" in m]
    if warns:
        print("注意：有 %d 条警告（不阻断生成）" % len(warns))


if __name__ == "__main__":
    main()
