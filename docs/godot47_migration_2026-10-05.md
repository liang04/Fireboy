# Godot 4.7 版本统一

日期：2026-10-05。基于 master `9c85a8300c146ffebca80f2c3ba7f504c7bffa67`。

## 当前运行方式

- 统一使用 **Godot 4.7 stable / 4.7.x**；工程 feature 声明、说明文字和 CI 固定基准已更新为 4.7
- 用 4.7 打开 `project.godot`，等待导入完成后按 **F5**，正常入口为主菜单
- 命令行首次运行先执行 `godot --headless --editor --import --path . --quit`，再运行 `godot --path .`
- 完整检查：`python tools/run_checks.py --godot /path/to/godot-4.7`
- 隔离试玩：`python tools/play_prototypes.py --godot /path/to/godot-4.7 --level 3`，可选 3、4、8；需要 Python 3.9+
- Windows 命令行检查/试玩请传 4.7.x 的 `_console.exe`；完整检查和试玩入口会提前拒绝其他版本
- 旧 Node 日志包装器仍可用：设置 `GODOT_BIN`，或在 PATH 放置 4.7 的 `godot`。不再固定某位开发者的下载目录

## 改动范围

本次不改关卡布局、角色物理、评星规则、记录格式或解锁进度，不需要删除个人存档。旧 4.6.3 / 4.7 报告描述当时的实际验证，保留原文；当前推荐运行版本和新 CI 基准为 4.7。

另保留一个独立的防御修复：关卡构建器通过显式路径预载新加入的延时踏板与可逆路线脚本，不依赖编辑器已经刷新这两个全局类的索引。旧缓存条件下原代码确实产生编译错误，修复后不再出现。用户已反馈切到 4.7 后可正常游戏；没有把此缓存缺陷认定为用户灰屏的原因。

## 验证

引擎为 Linux `4.7.stable.official.5b4e0cb0f`，GL Compatibility；Windows 本次未自动测试。

- [默认完整检查](qa/godot47/full-checks-4.7.txt)通过：静态生成一致性、全部定向回归、样板与合作恢复检查、十关冒烟、十关全宝石原始按键回放；未跳过 smoke 或 routes
- 新增 `tools/test_normal_startup.py`：临时完整工程从无 `.godot` 开始导入；以配置中的正常主场景启动，检查菜单背景、标题、十个按钮，再触发真实第一个关卡按钮并检查双角色、地形和 HUD。随后模拟旧全局类索引再次走相同正常入口。它不替换 `run/main_scene`，存档完全隔离
- 三个样板试玩入口全部通过，普通用户数据 sentinel 前后逐字相同
- 完整检查、隔离试玩和 Node 包装器均提前拒绝 4.6.3；Node 包装器在 4.7 正常启动并退出 0
- 实际云端图形验证：[菜单](qa/godot47/menu.png)、[第一关双角色与 HUD](qa/godot47/level01.png)、[暂停](qa/godot47/pause.png)。暂停返回菜单也已实际确认。使用 Mesa 软件渲染与 Dummy 音频；没有验证硬件 GPU 性能或音频听感
- `git diff --check`、Python 语法检查、Node 语法检查均通过；生成的 `scripts/levels/levels.gd` 与基线逐字相同

[机器可读摘要](qa/godot47/verification.json)。本地源码及验证已完成；本次尚未推送、合并或部署到远端，新的 CI 配置尚未在 GitHub 运行。
