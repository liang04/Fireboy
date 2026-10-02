# 森林冰火人 Fireboy & Watergirl

本地双人合作解谜平台游戏，共 10 关。火娃使用 A / D 移动、W 跳跃、S 交互；水娃使用方向键移动、上键跳跃、下键交互。R 重玩，Esc 暂停和改键。支持两只手柄。

## 启动

1. 使用 Godot 4 打开 `project.godot`，等资源导入完成
2. 按 F5 运行。也可执行 `godot --path .`
3. 两人到达各自出口后过关。红宝石归火娃，蓝宝石归水娃

工程原始配置声明 Godot 4.7；本轮在 Godot **4.6.3 stable** 的 Linux 环境验证，未修改该版本声明。Windows 和项目声明的 4.7 尚未实机验证。本包为源码工程，未附独立可执行程序。

## 自动检查

需要 Python 3 和可执行的 Godot 4，无需额外 Python 包：

```
python tools/run_checks.py --godot /path/to/godot
```

若 Godot 已在 PATH 中，运行 `python tools/run_checks.py` 即可。Windows 请传 Godot 的 `_console.exe` 路径。`--skip-smoke` 可跳过较长的十关冒烟测试。

检查包含资源导入、关卡校验、原有 59 项回归、新增 13 项操控/镜头检查、新增 19 项界面检查，以及十关冒烟。测试使用临时用户数据目录，避免污染玩家纪录；请不要用真实存档目录绕过测试保护。

关卡校验目前仍有 4 条既有木箱临近液体的警告（第 2、4、6、9 关）；无阻断错误。冒烟和自动测试不等于完整双人通关试玩。

本轮改动及验证边界见 `docs/optimization_2026-10-02.md`。
