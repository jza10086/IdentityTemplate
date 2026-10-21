# 阿瓦隆 · 5–8 人派对小游戏

独立场景 `scenes/avalon.tscn`，使用独立的「湖上圆桌」月夜青绿 / 古金美术。既有狼人杀仍位于 `scenes/main.tscn`，F5 默认入口不变；两种游戏不共享秘密规则状态。

## 直接预览

在 Godot 4.7.2 打开 `scenes/avalon.tscn`，按 F6 直接进入 **8 人同屏传递**。也可运行：

```sh
godot --path /path/to/IdentityParty res://scenes/avalon.tscn
```

没有新增首页、大厅、房间设置或独立规则菜单。自己的座位始终在底部，8 人布局为上 3 / 左 2 / 右 2 / 下 1；5–7 人使用相同四周布局原则。中央仍是无边框逐句字幕，底部显示当前任务、领队、失败票门槛、任务轨迹和连续否决次数，以及对应阶段操作。

- 领队点击完整玩家卡片进行多选，也可以选择自己。达到当前任务所需人数后才能确认；再次点击取消，不会单击直接发送。
- 组队投票与任务投票均先交接，再进入不透明私密画面。确认后不可修改；所有队员交完任务牌才统一结算。
- 善良角色只能提交成功牌，邪恶角色可提交成功或失败。角色相关操作不直接暴露在公共座位舞台。
- 每位玩家全程在场，没有淘汰、夜间袭击、放逐或弃票。
- 需要所有人的行动自动等待；投票结果 / 任务结果由房主或同屏持机人主动继续，无倒计时。
- 空格跳到本段字幕最后一句，不推进游戏；Escape 仍先确认退出。

## 湖上圆桌美术与动画

- 原创 `avalon_lake.svg`：远处的卡美洛剪影、青绿湖光、月牙、岸边芦苇与抄本式藤纹；中央依然留白，不新增边框或调试信息。
- 卡片采用青铜蚀刻边角、队长冠饰与誓约封印。选人时封印轻落、外沿短暂扩散；键盘焦点和悬停有相同的温和反馈。
- 公布组队票后，全部公开的赞成 / 反对票使用不同颜色的封印。不会在投票完成前显示选择。
- 任务成功是圣杯与散开的金色光线；失败是破碎誓约与铜红裂纹。7–8 人第 4 次任务依据实际的两失败票门槛表现，不会把一张失败牌误画成任务失败。
- 刺杀阶段呈现蚀月弧线与徐徐落下的剑；不使用闪屏、震屏或强制等待。结果和按钮即时可用，动画不推进规则。
- 少量湖畔萤光使用 Kenney 免费 CC0 粒子；不透明私密页使用低对比窗光。完整来源和随包许可见 `ART_SOURCES.md`。

`reduced_motion = true` 会停用所有装饰运动和封印缩放，保留静态图案与字幕可读性。装饰仅接收公开阶段、任务结果，使用独立且持久的时钟；同阶段快照、卡片重绘或热座交接不重播结果动画。新阶段取消旧特效，延迟的选人波纹也受渲染序号保护。私密页始终先绘制完全不透明遮罩。

实现位于 `scripts/ui/avalon_atmosphere.gd` 和 `avalon_card_ornament.gd`；狼人杀的背景、脚本与字幕组件均未改动。

## 基础规则

仅包含梅林、亚瑟的忠臣、刺客、莫德雷德的爪牙。没有派西维尔、莫甘娜、奥伯伦、莫德雷德隐藏角色或湖中仙女扩展。

| 人数 | 善良 / 邪恶 | 第 1–5 次任务人数 |
|---|---|---|
| 5 | 3 / 2 | 2、3、2、3、3 |
| 6 | 4 / 2 | 2、3、4、3、4 |
| 7 | 4 / 3 | 2、3、3、4、4 |
| 8 | 5 / 3 | 3、4、4、5、5 |

善良方固定 1 位梅林，其余忠臣；邪恶方固定 1 位刺客，其余爪牙。初始领队随机，然后按座次轮转。领队不必加入自己提出的队伍。

1. 全员私密确认身份。梅林知道邪恶玩家的位置，但不知道其具体角色；邪恶角色互认同阵营，但不获知同伴具体角色。忠臣不知道其他人的身份。
2. 领队提出规定人数的队伍，全员投同意或反对。**严格过半同意**才通过，平票否决。全员提交前不公开任何人的选择；完成后统一公开具名票数。
3. 否决后领队顺时针移交，重新组队，任务序号不变。**连续第 5 次否决，邪恶方立即获胜**；成功批准队伍后连续否决数清零。
4. 获批队员秘密提交任务牌，其他人不能提交。通常至少 1 张失败即任务失败；**7–8 人局的第 4 个任务需要至少 2 张失败**才失败。
5. 只公布成功 / 失败牌的匿名数量，不公布任何任务牌的提交者。任务完成后领队顺时针移交，再进入下次任务。
6. 累计 3 次任务失败，邪恶方获胜。累计 3 次任务成功进入刺杀：只有刺客选择一名善良玩家。命中梅林则邪恶方获胜，否则善良方获胜。第三次成功不是直接宣布善良胜利。

规则依据：发行方规则书第 3–5 页 [The Resistance: Avalon rulebook](https://cdn.1j1ju.com/medias/a6/dc/c1-the-resistance-avalon-rulebook.pdf) 与发行方维护的 [Dized Avalon rules](https://rules.dized.com/game/rZluqS52QmGdpoVxcmVLtg/the-resistance-avalon)。美术为本项目原创，不使用官方角色卡、商标图形或规则书插画。

## 派对宿主接入

```gdscript
var game = preload("res://scenes/avalon.tscn").instantiate()
game.standalone_preview = false
add_child(game)
game.finished.connect(_on_minigame_finished)
game.exit_requested.connect(_on_minigame_exit)
game.start_game(["青禾", "晚星", "听雨", "拾光", "远山"], 1)
```

`start_game(roster: Array, local_player_id: int = 1)` 接受 5–8 个唯一昵称，按顺序映射座位 ID 1..N；第二个参数只指定首个同屏查看者，不是网络鉴权。参数错误不替换进行中的对局。场景可在加入树之前启动或绑定，会延迟到准备完成。

会话层已注册两个游戏 ID：`werewolf` 和 `avalon`。宿主可直接选择：

```gdscript
session.start_local(names, "avalon")
# 或由派对宿主先负责联网：
session.host_lan("房主", 24567, "avalon")
# 客户端无需猜测游戏类型；收到房主快照后自动同步 game_id。
session.join_lan("青禾", "192.168.1.10", 24567)
# 宿主在开局前也可调用 select_game("avalon")；对局中禁止切换。
# 宿主自行处理加入、准备及 start_match() 后，各端绑定相应场景：
game.bind_session(session)
```

默认 `GameSession` 仍选狼人杀，原有不带游戏 ID 的方法继续有效。`select_game()` 只有房主且尚未开局时可用，联网切换游戏后客户端需重新准备；新注册游戏的元数据、工厂和载荷形状在 `GameCatalog` 扩展，RPC 不需要按游戏重写。网络端真实玩家 ID 由 ENet 发送者提供，绝不使用行动载荷声称的玩家 ID。

`finished(result)` 仅在终局首次出现时发出公开快照，`exit_requested` 通知宿主接管退出。绑定外部会话后，UI 不擅自重开、离开或销毁宿主会话。原有同屏 / ENet 机制得到复用，但没有承诺接入未提供的外部派对框架。所有网络端仍需相同 RPC 节点路径。

## 隐私边界

- `AvalonRules.state` 仅权威房主持有；客户端只收到白名单裁剪后的 `public_view(viewer_id)`。
- 具体身份只发给本人，直到终局才公开。梅林和邪恶队友分别获得其被规则允许知道的阵营玩家 ID，不公开精确角色。
- 全员提交组队票前，`team_votes` 为空；结果阶段才公开所有具名组队票。
- 任务阶段的 `submitted_ids` 只含查看者本人（如果已提交），不透露其他队员的提交顺序或进度；结果只有匿名成功 / 失败计数，不存在任务牌与玩家的对应表。
- 同屏模式依赖玩家遵守交接约定，不能防旁观、录屏或持机者检查内存。房主本身拥有全量规则；ENet 未配置加密，面向可信朋友局域网，不是公网反作弊服务。
- 任一玩家掉线即中止本局，返回会话等待状态。界面不恢复大厅，后续由宿主管理。无断线重连、主持人迁移、持久存档、聊天或 AI 玩家。

## 代码与验证

- `scripts/core/avalon_rules.gd`：独立纯规则、阵营分配、胜负与私密视图。
- `scripts/core/game_catalog.gd`：元数据、规则工厂和传输载荷格式校验。
- `scripts/session/game_session.gd`：复用同屏 / ENet 会话，按游戏 ID 分发。
- `scripts/ui/avalon.gd` 与 `scenes/avalon.tscn`：阿瓦隆场景，复用月夜舞台组件。
- `tests/test_avalon_rules.gd`、`tests/test_avalon_session.gd`、`tests/test_avalon_ui.gd`：规则、会话与界面自动化。
- `tests/test_avalon_embedding_review.gd`：独立嵌入边界验证，包含非连续玩家 ID、最长昵称、小屏布局与外部会话所有权。
- `tests/test_avalon_adversarial.gd`：额外反例验证，覆盖身份置换不泄漏、任务牌不可归因、无效行为原子性与所有终局路径。
- `tests/capture_avalon_screens.gd`：真实图形渲染器截图与字幕动画帧，不用 headless 截图代替。
- `tests/test_avalon_network.gd` 和 `tests/run_avalon_network_smoke.py`：5 人和 8 人真实 ENet 多进程对局，覆盖三成功后刺杀、连续五次否决、重开、掉线、身份与选票隔离、伪造和异常载荷。

```sh
godot --headless --path . --script tests/test_avalon_rules.gd
godot --headless --path . --script tests/test_avalon_session.gd
godot --headless --path . --script tests/test_avalon_ui.gd
godot --headless --path . --script tests/test_avalon_adversarial.gd
godot --headless --path . --script tests/test_avalon_embedding_review.gd
GODOT_BIN=/absolute/path/to/godot python3 tests/run_avalon_network_smoke.py
# 必须在真实图形显示环境中运行：
CAPTURE_DIR=/tmp/avalon-captures godot --path . --script tests/capture_avalon_screens.gd
```

原版狼人杀的全部规则、界面、字幕、集成与真实 ENet 测试仍保留，命令见 README。桌面源码项目不含各平台可执行文件，也未验证 Web / 手机导出。

### 本次验证记录

使用 Godot **4.7.2**：阿瓦隆纯规则 9,967 项、会话 2,177 项、独立对抗验证 19,440 项、界面与嵌入生命周期 1,765 项、独立嵌入边界 1,523 项均通过。阿瓦隆 5 人 / 8 人真实多进程 ENet 场景均通过。

狼人杀回归：纯规则 10,812 项、会话 1,221 项、界面 926 项、布局控件 1,320 项、字幕 46 项、嵌入集成 15 项均通过；原有 4 人完整 ENet 对局和 8 人准入测试也通过。狼人杀规则与 UI 脚本、默认场景及原版美术未修改。

真实渲染器核验包含 1280×800 与 960×640 截图，以及直接从实际字幕动画渲染帧生成的演示 GIF；不是静态设计稿或 headless 模拟图。网络验证在同一机器的独立 ENet 进程完成，未测试公网 / NAT 穿透。
