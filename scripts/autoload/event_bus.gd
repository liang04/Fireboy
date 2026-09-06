extends Node
## 全局信号总线（Autoload: EventBus）。
##
## 设计要点：关卡内的机关之间**互不直接引用**。
## 触发器（压力板 / 杠杆 / 按钮）只负责广播某个 channel 的开关状态，
## 受控物（门 / 移动平台 / 升降梯）只订阅自己关心的 channel。
## 这样增删机关、改连线都不需要改任何一方的代码，
## 关卡设计师只要保证 channel 名字对得上即可。

## channel 状态变化：active=true 表示通路/激活
signal channel_state_changed(channel: StringName, active: bool)

## 宝石被拾取：color = "red" / "blue"
signal gem_collected(color: StringName)

## 宝石被【非归属元素】碰到：不拾取、不致死，仅用于弹一次提示。
## element 是这颗宝石的归属元素（red→fire / blue→water）。
signal gem_rejected(color: StringName, element: StringName)

## 玩家死亡 / 重生
signal player_died(player_id: StringName, cause: StringName)
signal player_respawned(player_id: StringName)

## 玩家进入 / 离开自己的出口门
signal exit_occupied(player_id: StringName, occupied: bool)

## 关卡完成：stats 见 Level._build_stats()
signal level_completed(stats: Dictionary)
