#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""角色精灵表锚点校准工具（开发期离线工具，不参与游戏运行）。

用途
----
AI 生成的精灵表里，每个人物在格子内的位置、大小都不一致，直接播放会「每帧乱跳」。
`scripts/player.gd` 靠一张手工 offset 表把每帧拉回同一个锚点。手工算这张表有两个坑：

  1. **邻格溢出**：人物的火焰/肢体经常跨越等分格边界，把相邻格的一小条内容也框进了
     bbox，算出来的中心会偏几十像素（火娃 walk2 就是这么错的：真实需要 +39.5，
     手算成了 -28，角色每个步态循环左窜 9 个屏幕像素）。
  2. **上下被切**：等分行高不够时人物头顶/脚底会被削平，此时「脚底」其实是切口，
     用它当基线是唯一稳定的选择（头顶信息已丢失，取不回来）。

本工具用「列投影连通段过滤」先剥离邻格溢出，只保留最大的那一段主体，再按
  x：主体水平中心 → 格子水平中心
  y：主体底边 → idle 帧底边（统一基线）
算出每张帧需要的 offset，直接输出可粘贴回 player.gd 的 GDScript 片段。

依赖
----
    pip install pillow numpy
    python tools/analyze_spritesheets.py            # 只打印校准数据
    python tools/analyze_spritesheets.py --png      # 额外输出诊断图到 Godot/
"""
import argparse
import os
import sys

try:
    import numpy as np
    from PIL import Image, ImageDraw
except ImportError:
    sys.exit("需要 pillow 与 numpy：pip install pillow numpy")

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CHAR_DIR = os.path.join(ROOT, "assets", "characters")

# 与 player.gd 保持一致：12 个槽位的名字 / 每个动画用到哪几帧
NAMES = ["idle0", "idle1", "idle2", "idle3",
         "walk0", "walk1", "walk2", "walk3",
         "takeoff", "rise", "fall", "land"]
ANIM_ROWS = {
    "idle":    [0],
    "walk":    [4, 5, 6, 7],
    "takeoff": [8],
    "rise":    [9],
    "fall":    [10],
    "land":    [11],
}

# 水娃生成图不是等分网格，player.gd 里手写了一组允许重叠的裁切区域
WATER_REGIONS = [
    (180, 0, 320, 384), (500, 0, 320, 384),
    (790, 0, 320, 384), (1085, 0, 320, 384),
    (180, 360, 300, 340), (490, 360, 300, 340),
    (800, 360, 300, 340), (1100, 360, 300, 340),
    (180, 680, 300, 344), (490, 680, 300, 344),
    (800, 680, 300, 344), (1100, 680, 300, 344),
]

ALPHA_MIN = 40       # 低于此 alpha 视为背景
GAP = 8              # 列投影中超过这么多像素的空白才视为主体分隔


def load(path):
    im = Image.open(path).convert("RGBA")
    return im, (np.array(im).astype(int)[:, :, 3] > ALPHA_MIN)


def col_segments(prof, gap=GAP):
    """把列投影切成连续段，允许 gap 像素以内的空白把两段连起来。"""
    on = prof > 0
    segs, j, n = [], 0, len(on)
    while j < n:
        if on[j]:
            start = j
            last = j
            j += 1
            while j < n:
                if on[j]:
                    last = j
                    j += 1
                elif j - last > gap:
                    break
                else:
                    j += 1
            segs.append((start, last))
        else:
            j += 1
    return segs


def main_body(mask):
    """返回 (主体 x 区间, y 区间)（相对本 region 左上角）。

    主体 = 列投影里像素总量最大的那段。这一步把邻格溢出的那一条窄边剥掉。
    """
    if not mask.any():
        return None
    segs = col_segments(mask.sum(axis=0))
    if not segs:
        return None
    segs.sort(key=lambda s: -int(mask[:, s[0]:s[1] + 1].sum()))
    s0, s1 = segs[0]
    ys, xs = np.nonzero(mask[:, s0:s1 + 1])
    return (s0 + int(xs.min()), s0 + int(xs.max()), int(ys.min()), int(ys.max()))


def measure(alpha, regions):
    """对每个 region 量出主体 bbox（整图坐标）与是否被边界切断。"""
    out = []
    for (rx0, ry0, rw, rh) in regions:
        sub = alpha[ry0:ry0 + rh, rx0:rx0 + rw]
        body = main_body(sub)
        if body is None:
            out.append(None)
            continue
        bx0, bx1, by0, by1 = body
        out.append(dict(
            rx0=rx0, ry0=ry0, rw=rw, rh=rh,
            x0=rx0 + bx0, x1=rx0 + bx1, y0=ry0 + by0, y1=ry0 + by1,
            cut_top=int(sub[0].sum()) > 20,
            cut_bottom=int(sub[-1].sum()) > 20,
            cut_left=int(sub[:, 0].sum()) > 20,
            cut_right=int(sub[:, -1].sum()) > 20,
        ))
    return out


def calibrate(frames, baseline_from=0):
    """按「中心对齐 x、底边对齐 y」算出每帧 offset。

    注意 Godot 的 Sprite2D 以 **region 中心** 为绘制原点，所以参与比较的不是
    「相对 region 左上角」的裸坐标，而是减掉半宽/半高之后的局部坐标：
        local_x = cx - rw/2 + offset.x
        local_y = bottom - rh/2 + offset.y
    当各帧 region 尺寸不一致时（水娃就是 320x384 / 300x340 / 300x344 混用），
    漏掉 rh/2 这一项会让整套 y 偏移整体错半个格子的高度差。

    baseline_from: 用哪一帧当统一基线（默认 idle 帧）。
    """
    base = frames[baseline_from]
    if base is None:
        raise SystemExit("基线帧为空，无法校准")
    base_bottom = (base["y1"] - base["ry0"]) - base["rh"] / 2.0
    result = []
    for f in frames:
        if f is None:
            result.append((0, 0))
            continue
        cx = (f["x0"] + f["x1"]) / 2.0 - f["rx0"] - f["rw"] / 2.0
        bottom = (f["y1"] - f["ry0"]) - f["rh"] / 2.0
        result.append((-cx, base_bottom - bottom))
    return result


def report(title, sheet_path, regions, offsets_in_code, args=None):
    im, alpha = load(sheet_path)
    H, W = alpha.shape
    frames = measure(alpha, regions)
    print("=" * 78)
    print("%s   %dx%d" % (title, W, H))
    print("=" * 78)
    print("%-9s %-26s %-7s %-7s %s" % ("frame", "主体 bbox(整图坐标)", "宽", "高", "边界切断"))
    for n, f in zip(NAMES, frames):
        if f is None:
            print("  %-9s <空>" % n)
            continue
        cuts = "".join([c for c, k in (("上", "cut_top"), ("下", "cut_bottom"),
                                       ("左", "cut_left"), ("右", "cut_right")) if f[k]])
        print("  %-9s x[%4d,%4d] y[%4d,%4d]  %5d %5d  %s" % (
            n, f["x0"], f["x1"], f["y0"], f["y1"], f["x1"] - f["x0"] + 1, f["y1"] - f["y0"] + 1,
            cuts or "-"))

    cal = calibrate(frames)
    used = set(i for idxs in ANIM_ROWS.values() for i in idxs)
    print("\n  建议 offset（贴图像素，与 player.gd 同坐标系）:")
    print("  %-9s %-16s %-16s" % ("frame", "建议值", "代码现值"))
    for i, (n, c, cur) in enumerate(zip(NAMES, cal, offsets_in_code)):
        if i not in used:
            print("  %-9s (%7.1f,%7.1f)  (%7.1f,%7.1f)   (动画未使用，忽略)" % (n, c[0], c[1], cur[0], cur[1]))
            continue
        ok = abs(c[0] - cur[0]) < 1.5 and abs(c[1] - cur[1]) < 1.5
        print("  %-9s (%7.1f,%7.1f)  (%7.1f,%7.1f)%s" % (
            n, c[0], c[1], cur[0], cur[1], "" if ok else "   <== 需修正"))

    # 量化：应用建议值之后，各动画内部的残余抖动
    print("\n  校准后残余抖动（贴图像素 → 屏幕像素，scale=48/行高）:")
    scale = 48.0 / (H / 3.0)
    for anim, idxs in ANIM_ROWS.items():
        if len(idxs) < 2:
            continue
        cs, bs = [], []
        for k, i in enumerate(idxs):
            f = frames[i]
            ox, oy = cal[i]
            cs.append(((f["x0"] + f["x1"]) / 2.0 - f["rx0"] - f["rw"] / 2.0) + ox)
            bs.append(((f["y1"] - f["ry0"]) - f["rh"] / 2.0) + oy)
        print("    %-8s 中心x 极差 %.1f→%.2f px | 脚底y 极差 %.1f→%.2f px" % (
            anim, max(cs) - min(cs), (max(cs) - min(cs)) * scale,
            max(bs) - min(bs), (max(bs) - min(bs)) * scale))

    print("\n  可粘贴回 player.gd：")
    for anim, idxs in ANIM_ROWS.items():
        vals = ", ".join("Vector2(%d, %d)" % (round(cal[i][0]), round(cal[i][1])) for i in idxs)
        print('    &"%s": [%s],' % (anim, vals))
    print()

    if args.overlay:
        name = "fire" if "fireboy" in os.path.basename(sheet_path) else "water"
        draw_overlay(im, alpha, frames, regions, cal,
                     os.path.join(ROOT, "Godot", "diag_walk_overlay_%s.png" % name))
    return frames, cal, im


def draw_diagnostics(im, frames, regions, out_path, title):
    sheet = im.copy()
    d = ImageDraw.Draw(sheet)
    for (rx0, ry0, rw, rh) in regions:
        d.rectangle([rx0, ry0, rx0 + rw, ry0 + rh], outline=(255, 0, 0, 190), width=3)
    for n, f in zip(NAMES, frames):
        if f is None:
            continue
        d.rectangle([f["x0"], f["y0"], f["x1"], f["y1"]], outline=(255, 255, 0, 255), width=4)
        d.text((f["x0"], max(0, f["y0"] - 16)), n, fill=(255, 255, 0, 255))
    sheet.save(out_path)
    print("  诊断图 -> %s" % out_path)


def draw_overlay(im, alpha, frames, regions, cal, out_path, anim="walk", canvas=520):
    """把某个动画的所有帧按校准后的 offset 叠加到同一张图。

    Godot 的绘制原点在 region 中心，所以局部坐标是 (u - rw/2 + ox, v - rh/2 + oy)。
    叠得越紧说明锚点校准得越准——如果某一帧明显错开，就是 offset 有问题。
    """
    idxs = ANIM_ROWS[anim]
    cols = [(220, 40, 40), (40, 170, 70), (50, 90, 230), (230, 170, 20),
            (160, 40, 180), (20, 160, 160)]
    base_y = int(canvas * 0.78)
    cx = canvas // 2
    canvas_img = np.full((canvas, canvas, 4), 244, dtype=np.uint8)
    # 先用所有帧的内容算出竖向范围，把角色摆在画布里
    for k, i in enumerate(idxs):
        f = frames[i]
        ox, oy = cal[i]
        rx0, ry0, rw, rh = regions[i]
        sub = alpha[ry0:ry0 + rh, rx0:rx0 + rw]
        ys, xs = np.nonzero(sub)
        X = (xs - rw / 2.0 + ox + cx).astype(int)
        Y = (ys - rh / 2.0 + oy + base_y).astype(int)
        ok = (X >= 0) & (X < canvas) & (Y >= 0) & (Y < canvas)
        for c in range(3):
            canvas_img[Y[ok], X[ok], c] = cols[k % len(cols)][c]
        canvas_img[Y[ok], X[ok], 3] = 255
    ov = Image.fromarray(canvas_img, "RGBA")
    d = ImageDraw.Draw(ov)
    d.line([(cx, 0), (cx, canvas)], fill=(0, 0, 0, 150), width=1)
    d.text((6, 6), "%s: %s (校准后叠加)" % (anim, ", ".join(NAMES[i] for i in idxs)),
           fill=(0, 0, 0, 255))
    ov.save(out_path)
    print("  叠加验证图 -> %s" % out_path)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--png", action="store_true", help="额外输出带标注的诊断图")
    ap.add_argument("--overlay", action="store_true",
                    help="额外输出 walk 动画按校准 offset 叠加后的验证图")
    args = ap.parse_args()

    fire = os.path.join(CHAR_DIR, "fireboy-spritesheet-v2.png")
    water = os.path.join(CHAR_DIR, "watergirl-spritesheet-v2.png")

    # 火娃：与 player.gd 一致的 4x3 等分
    if os.path.exists(fire):
        im = Image.open(fire)
        W, H = im.size
        regions = []
        for i in range(12):
            col, row = i % 4, i // 4
            x0 = round(W * col / 4.0)
            x1 = round(W * (col + 1) / 4.0)
            y0 = round(H * row / 3.0)
            y1 = round(H * (row + 1) / 3.0)
            regions.append((x0, y0, x1 - x0, y1 - y0))
        # player.gd 里 _fire_anchors 的当前值，用于对比「要不要重新校准」
        in_code = [(-88, 0), (-88, 0), (-88, 0), (-88, 0),
                   (-88, 45), (-29, 0), (40, 0), (105, 44),
                   (-94, 77), (0, 114), (56, 114), (108, 77)]
        frames, cal, _ = report("火娃 fireboy（4x3 等分）", fire, regions, in_code, args)
        if args.png:
            draw_diagnostics(im, frames, regions,
                             os.path.join(ROOT, "Godot", "diag_sheet.png"), "fireboy")

    # 水娃：手写 region
    if os.path.exists(water):
        regions = [(x, y, w, h) for (x, y, w, h) in WATER_REGIONS]
        # player.gd 里 _water_anchors 的当前值
        in_code = [(12, 0), (12, 0), (12, 0), (12, 0),
                   (11, 34), (34, 9), (33, 9), (44, 34),
                   (20, 41), (50, 86), (33, 78), (38, 43)]
        frames, cal, _ = report("水娃 watergirl（手写 region）", water, regions, in_code, args)
        if args.png:
            im = Image.open(water)
            draw_diagnostics(im, frames, regions,
                             os.path.join(ROOT, "Godot", "diag_sheet_water.png"), "watergirl")


if __name__ == "__main__":
    main()
