// 第 10 关「箱子是否硬性必需」的判定探针。
//
// 判据：模拟【把箱子拿掉】这一局，看 channel A 还能不能被激活。
//   · 有箱子 → A 激活 → 门 A 开 → 两个出口可达 → 通关
//   · 没箱子 → A 不激活 → 门 A 永远关着 → 出口不可达 → 【致命】
// 只有第二种成立，箱子才算真的必需品（而不是「可选便利」）。
//
// 为什么不只看「删掉箱子后 validate 是否报错」：那只说明「少了点东西」，
// 分不清是缺箱子还是缺别的东西。直接查 channel 状态更准。
const { spawnSync } = require('child_process');
const PY = 'C:/Users/40577/.workbuddy/binaries/python/versions/3.13.12/python.exe';

const script = `
import sys
sys.path.insert(0,'tools')
import gen_levels as G

lv = G.level_10()
grid, objs = lv["grid"], lv["objects"]

def chan_state(objects, label):
    active, unsolved = G.solve_channels(grid, objects)
    print("%-22s channel A 激活 = %-5s | 未解开的门 = %s"
          % (label, "A" in active, sorted(unsolved) or "无"))
    return "A" in active

base = [dict(o) for o in objs]
with_box = chan_state(base, "有箱子（原位）")

variants = {
    "删掉箱子": [o for o in base if o.get("type") != "box"],
    "箱子丢到虚空 (1,13)": [(dict(o, cell=[1,13]) if o.get("type")=="box" else o) for o in base],
}
# 注意不要再放「箱子挪到同一片地面另一格」这种变体 —— 那不是反例：
# box_reachable 沿同高地面扩散，挪一格照样能被推到井口，本来就该通关。
# 拿它判「装饰品」会得出错误的 WARN。判据只认两件事：
#   ① 完全没有箱子   ② 箱子存在但到不了井底
results = {}
for label, v in variants.items():
    results[label] = chan_state(v, label)

print()
print("=== 判定 ===")
if with_box and not any(results.values()):
    print("=> [OK] 箱子是硬性必需：拿掉它、或让它到不了井底，channel A 就解不开")
elif with_box and all(results.values()):
    print("=> [BAD] 箱子是装饰品：拿掉它照样能开 A")
else:
    print("=> [WARN] 部分变体仍能开 A —— 需人工看是哪一种")

print()
print("=== 完整校验（有箱子 / 各变体）===")
for label, o in [("有箱子", base)] + list(variants.items()):
    lv2 = dict(lv); lv2["objects"] = o; lv2["name"] = "probe:" + label
    msgs = G.validate(lv2, 9)
    fatal = [m for m in msgs if "致命" in m]
    print("  %-22s 致命 %d 条" % (label, len(fatal)))
    for m in fatal[:3]:
        print("      ", m)
`;

const r = spawnSync(PY, ['-c', script], {
  cwd: 'D:/lvliang/projects/games/Fireboy',
  encoding: 'utf8',
});
console.log(r.stdout || '');
if (r.stderr) console.log('[stderr]', r.stderr);
