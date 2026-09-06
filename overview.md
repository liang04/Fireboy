# 本次任务概览：宝石归属限制（红宝石只归火娃、蓝宝石只归水娃）

## 问题
`Gem._on_body_entered()` 原样是「谁碰到都算数」，注释里写的是「靠摆放位置决定谁能拿到」。
但关卡校验器（`tools/gen_levels.py`）一直按**颜色归属**做可达性校验
（红宝石必须火娃够得到、蓝宝石必须水娃够得到），两边规则不一致：
只要两人在同一区域活动，火娃路过就能顺手吃掉蓝宝石，水娃的收集目标被凭空清零。

## 改了什么
规则收口到运行时，与校验器对齐：**异色不拾取、不扣血，只给反馈**。

| 文件 | 改动 |
|---|---|
| `scripts/objects/gem.gd` | 新增 `owner_element`；颜色↔元素映射集中在 4 个 `static func`（`owner_of` / `owner_color_of` / `owner_label_of` / `color_label_of`），加第三个角色只改这一处。归属环（Line2D，元素主题色）一眼看出归谁；`_on_body_entered` 按元素分流到 `_collect()` / `_reject()` |
| `scripts/autoload/event_bus.gd` | 新增 `gem_rejected(color, element)` 信号（与既有 `gem_collected` 对称） |
| `scripts/level.gd` | 订阅 `gem_rejected` → 转发给 HUD |
| `scripts/hud.gd` | 新增底部提示条 `_warn` + `flash_hint()`（1.6s 冷却，用 `Time.get_ticks_msec()` 而非 `_process` 轮询）+ `flash_gem_owner_hint()`；计数标签改为「火娃宝石 x/y」「水娃宝石 x/y」；暂停帮助文本补一行规则说明 |
| `scripts/autoload/sound.gd` | 新增 `reject` 音效（300→190Hz 下行短音，与拾取的上行音区分） |
| `scenes/hud.tscn` | 计数标签默认文案同步 |
| `tools/regression.gd` | 新增 5 条断言（见下） |
| `docs/DESIGN.md` | §6 操作说明后补「宝石归属（硬性规则）」 |

## 两个实现细节（踩坑点）
1. **补间必须持有句柄**：`_reject_tween` 会和收起动画抢同一个 `scale` / `modulate`。
   拾取时先 `_kill_reject_tween()` 并把外观复位，否则收起动画会从一个「灰掉且压扁」的状态开始。
2. **不新增 `_process` 轮询**：提示冷却用时间戳比较，HUD 的 `process_mode` 是
   `PROCESS_MODE_ALWAYS`，加轮询等于常驻开销。

## 验证结果
- `python tools/gen_levels.py`：9 个自检夹具全绿，8 关静态校验全通过，**无宝石不可达警告**
  —— 这是强制归属的前提：不存在「只有异色角色够得到」的宝石，所以不可能出现拿不到的宝石。
- `godot --headless --path . res://tools/regression.tscn`：**24 项断言全过，errors=0**
  （原 19 项 + 新增：火/水角色各一、水拿不到红宝石、火拿不到蓝宝石、蓝宝石归属为 water、水能拿蓝宝石）
- `godot --headless --path . -- --smoke`：8 关 `errors=0`
  （第 7 关实测 `gems=2/3 red`，证明火娃拾取红宝石的正常路径没被误伤）

## 还需要人工确认
- 归属环在实机里的辨识度（红宝石 #ff4d6d + 火娃橙 #ff6b35 的环是否够区分），
  以及「压扁 + 变暗」的拒绝反馈强度是否合适——这两项靠截图/试玩判断，headless 测不到。
- 音效 `reject` 需真人试听。
