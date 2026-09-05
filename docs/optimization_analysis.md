# Fireboy 优化分析（静态审查 + 冒烟测试佐证）

> 审查范围：全部 21 个 `.gd`、4 个 `.tscn`、`project.godot`、关卡数据。
> 验证方式：`godot --headless --path . -- --smoke` → `errors=0`，4 关 + 动作能力探针 + 机关联调全部通过，无运行时崩溃。
> 结论先行：**工程能跑、架构主干设计良好（信号总线 + channel 解耦很干净），但存在 1 个确定性动画 Bug、1 个高风险的移动平台“双重载人”疑点、若干类型安全缺口，以及一处“加第三个角色”的承诺与实际出口逻辑不一致。**

---

## ✅ 实施状态（2026-09-05，已落地并通过冒烟）

| # | 项 | 结果 |
|---|---|---|
| 1 | 死亡动画被 `_process` 覆盖 | ✅ 已修：`player.gd` `_process` 加 `if not alive or frozen: return` |
| 2 | 移动平台双重载人 | ✅ 已修：`moving_platform.gd` 改 `StaticBody2D`，关引擎自动载人，仅留手动 `_carry()` |
| 3 | 出口写死 fire/water | ✅ 已修：`level.gd`+`level_builder.gd` 按 `exit_elements` 动态统计，所有出口占用即过关 |
| 4 | `Tex.solid()` 重复建纹理 | ✅ 已修：`tex.gd` 加 `static _cache`，同 (颜色,尺寸) 复用 |
| 5 | 未开 GDScript 全告警 | ✅ 已开：`project.godot` `debug/gdscript enable_all_warnings=true` |
| 6 | Lever 输入改 `_unhandled_input` | ↩️ **回退**：`smoke.gd` 用 `Input.action_press()` 只置状态不派发 InputEvent，`_unhandled_input` 收不到，测试从 0→8 错。可交互节点须保留 `_physics_process` 轮询 |

> 复跑 `godot --headless -- --smoke`：`errors=0`，4 关 + 动作探针 + 机关联调全过，能力实测值不变（跳 107 / 远 199 / 浮 146 px）。
> 未做（属设计取舍，非 bug，建议独立评估）：#11~#15 内容缺口（音效/手柄/暂停界面）、#9~#10 全量类型化重构（仅针对本次改动点了出口字典）、未验证项（平台真人试玩手感、校验器未覆盖的跳过半条机关链）。

---

## 一、正确性 / 潜在 Bug（建议优先修）

### 1. 死亡动画被 `_process` 覆盖（确定性 Bug）
- **位置**：`scripts/player.gd`
  - `die()`（约 L169-175）：用 tween 把 `_visual.scale` 缩到 `Vector2(0.15, 0.15)`。
  - `_process()`（约 L258-267）：**没有 `alive`/`frozen` 守卫**，每帧执行 `_visual.scale.x = move_toward(_visual.scale.x, float(_facing), 12.0*delta)`。
- **现象**：`die()` 里只 `set_physics_process(false)`，**没有关掉 `_process`**。于是 tween 想让缩放到 0.15，而 `_process` 每帧把 `scale.x` 拉回 ±1，二者打架。死亡时角色是“纵向压扁”而不是整体缩小（X 维度根本没缩）。
- **修复**：在 `_process` 开头加 `if not alive or frozen: return`（保留 `_time += delta` 可放守卫前）。一行改动，零行为风险。

### 2. 移动平台可能“双重载人”（高风险，需 playtest 确认）
- **位置**：`scripts/objects/moving_platform.gd`
  - 节点类型是 `AnimatableBody2D`，其 `sync_to_physics` 默认 `true` —— **引擎会自动把站在上面的 CharacterBody2D 带着走**。
  - 同时 `_carry()`（L91-96）又手动把平台位移 `body.global_position += delta_pos` 加到乘客上。
- **风险**：两套载人逻辑叠加，乘客可能被以 **2× 速度** 带动；纵向平台尤其明显（角色被往下带两倍，可能穿地或抖动）。
- **验证/修复**：playtest 纵向/横向平台各一次确认。二选一：
  - 方案 A（删手动 carry）：保留 `AnimatableBody2D`，删掉 `_carry()` 与 `_riders` 检测区，完全依赖引擎载人。
  - 方案 B（删引擎载人）：改用 `StaticBody2D`（或 `AnimatableBody2D` 且 `sync_to_physics=false`），保留手动 `_carry()`。
  - 代码注释说“比 platform velocity 更可预测”，但选了 `AnimatableBody2D` 又把引擎载人引回来了，二者自相矛盾。

### 3. 出口过关逻辑写死 fire/water（与“加第三角色免改代码”的承诺矛盾）
- **位置**：`scripts/level.gd`
  - `var _exits := {"fire": false, "water": false}`（L16）
  - `_on_exit_occupied()`（L80-83）：`if _exits["fire"] and _exits["water"]: _complete()`
- **矛盾**：`player.gd` 头部注释明说“改按键、加第三个角色都不需要改代码”。但 Level 的过关判定只认 fire+water 两个 key，加第三个元素角色时 **永远不会 `_complete()`**。
- **修复方向**：在 `_ready` 里按 `info["players"]` 实际元素集合初始化 `_exits`（用 `Dictionary[StringName, bool]`），并改为“已占用的出口数 == 存活玩家数”即过关。这样和 Player 的多元素设计对齐。

### 4. 死亡时站在机关上的占用状态是隐式依赖
- **位置**：`PressurePlate` / `ExitDoor` / `Lever` 依赖 `body_exited` 清占用；`Player.die()`（L165-166）把 `collision_layer/mask=0`，靠 Godot 因此触发 `body_exited` 来清除。
- **风险**：多数情况会触发，但这是隐式契约。若某次引擎判定时序导致 `body_exited` 未触发，压力板会“卡在按下”、出口门会“卡在占用”。
- **修复方向**（低优先）：在 `respawn()` 里主动让玩家先前站过的机关取消占用；或机关在 `body_exited` 之外，对失效 body 做 `is_instance_valid` 兜底。

---

## 二、性能（纹理生成是最大可优化点）

### 5. `Tex.solid()` 每次都新建 ImageTexture + 逐像素循环（核心优化）
- **位置**：`scripts/util/tex.gd` `solid()`（L31-44），对每个像素 `img.set_pixel` 写高光/阴影边。
- **问题**：
  - 关卡加载时大量**重复创建相同贴图**：`door.gd` 装饰线 `for i in height_cells`（L41-45）每格 new 一张相同纹理；宝石/池子/箱子等每个对象都 new。
  - 重玩（`reload_current_scene`）会**再次生成**全部纹理，旧纹理若未被引用计数及时回收，呈泄漏式增长。
- **修复**：在 `Tex` 加一个静态缓存 `var _cache: Dictionary`（`key = str(color) + str(size) + str(centered)`），命中直接返回 `ImageTexture`。零行为变化，直接省内存 + 缩短加载时间，且跨重玩不再增长。

### 6. `level_builder._make_tileset()` 每次进关重建 tileset
- **位置**：`scripts/level_builder.gd` L216-237
- **问题**：每次 `build()` 都 `TileSet.new()` + 生成 2 张材质纹理。cell 是常量 32。
- **修复**：把生成好的 tileset 按 `cell` 缓存成静态变量（或放到 Autoload/Resource），只在首次创建。

---

## 三、类型安全 / 代码质量（专家硬性要求）

### 7. 大量未类型化容器
- `level.gd`：`var _players: Array = []`（应 `Array[Player]`）、`_gems_total/_gems_got/_exits` 无类型 Dict、`info` 无类型。
- `game_state.gd`：`var results: Dictionary = {}` 无类型（key=int, value=Dictionary）。
- `levels.gd`：`_all()` 返回无类型 `Array`、`get_level()` 返回无类型 `Dictionary`。
- `level_builder.build(parent: Node2D, data: Dictionary)` 返回无类型 `Dictionary`。
- **影响**：失去编辑器自动补全与编译期校验，重构易踩坑。
- **修复**：容器改 typed（`Array[Player]`、`Dictionary[StringName, bool]`）；关卡数据用 `Resource` 子类或自定义 `class` 承载，比裸 `Dictionary` 更安全。

### 8. `project.godot` 未开严格告警
- 当前没有 `gdscript/warnings/enable_all_warnings=true`，所以上面的未类型化、潜在未用变量等问题**全程静默**。
- **修复**：开启 `enable_all_warnings`（可选 `treat_warnings_as_errors` 接 CI），让潜在问题在编辑器/构建期就暴露。

### 9. `Lever` 在 `_physics_process` 轮询输入
- **位置**：`scripts/objects/lever.gd` L44-53：`_physics_process` 里 `Input.is_action_just_pressed(p.action_key)`。
- **问题**：`just_pressed` 是帧语义，放在物理帧里读取可能因帧/物理步不一致被吞掉或重复触发。
- **修复**：改为 `_unhandled_input(event)` 或记录“本帧是否按下”的状态，再在物理帧消费。

---

## 四、内容 / 体验缺口（来自 DESIGN 已知局限）

10. **零音效 / BGM** —— overview 已诚实列出。
11. **仅键盘、无手柄** —— 双人本地合作常需手柄；可加 `InputMap` 手柄事件。
12. **Esc 直接回主菜单，无暂停界面** —— 当前 `level.gd` `_unhandled_input` 里 `pause` 直接 `change_scene_to_file(MENU_SCENE)`，可考虑暂停菜单（继续/重玩/退出）。
13. **文档与代码不一致** —— `overview.md` 写“2 个关卡”，实际 `scripts/levels/levels.gd` 已定义 4 关（1-初识元素 / 2-机关重重 / 3-分头行动 / 4-时序接力）。建议同步文档。
14. **测试覆盖缺口**（非 Bug）—— 校验器未覆盖：真实操作手感、双人同时按板、是否跳过半条机关链。DESIGN 已诚实标注。

---

## 五、值得保持不变的架构亮点

- **EventBus + channel 解耦**：触发器只 emit、受控物只 connect，加新机关零改动旧代码 —— 这是本工程最干净的部分。
- **角色共用一份 `Player`**：靠 `element` + 四个输入动作名区分，扩展成本低（除第三点的出口逻辑外）。
- **推箱用“距离 + 按键方向”判定**：绕过两 CharacterBody2D 挤压时碰撞回调顺序的玄学问题，确定性强、好调试。
- **零外部美术资源 + 程序化纹理**：工程可整体复制；配合第 5 点的缓存后，这一优点没有任何代价。

---

## 建议的优化顺序

| 优先级 | 项 | 工作量 | 风险 |
|---|---|---|---|
| P0 | #1 死亡动画被 `_process` 覆盖 | 1 行 | 零 |
| P0 | #2 移动平台双重载人（先 playtest 确认） | 中 | 中 |
| P1 | #3 出口逻辑泛化（对齐多角色承诺） | 小 | 低 |
| P1 | #5 `Tex` 纹理缓存 | 小 | 零 |
| P1 | #8 开启严格告警 | 配置 | 零 |
| P2 | #7 typed 容器 / 关卡数据类化 | 中 | 低 |
| P2 | #4 死亡占用显式清理 / #6 tileset 缓存 / #9 Lever 输入 | 小 | 低 |
| P3 | #10-#14 音效/手柄/暂停/文档 | 大 | — |

> 说明：本次只做分析与冒烟验证，未改动任何源码。
