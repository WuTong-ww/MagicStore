# 零点杂货铺：接口与存档契约

当前基线：Godot 4.6.3 stable、GDScript、Compatibility。单机开发案例，存档 `schema_version = 1`，内容 `content_version = 1`。只有 `SaveService` 和 `GameState` 两个 Autoload，按此顺序载入；对应脚本不声明同名 `class_name`。

## 所有权与入口

| 模块 | 文件 | 责任 |
| --- | --- | --- |
| 主界面 | `scenes/main.tscn`、`scripts/ui/main.gd` | 存档选择、公共状态条、消息、画面切换 |
| 前台 | `scenes/shop_front.tscn`、`scripts/ui/shop_front.gd` | 接待/继续、休息、下一天、经历入口 |
| 咨询区 | `scenes/consultation.tscn`、`scripts/ui/consultation.gd` | 交流、费用预览、收费确认、牌面、结束 |
| 权威状态 | `scripts/core/game_state.gd` | 动作校验、统一时钟、候选状态与提交、幂等 |
| 内容加载 | `scripts/core/content_loader.gd` | 校验规则、人物、话题、线索和牌的配置与引用 |
| 存档服务 | `scripts/save/save_service.gd` | JSON 校验封装、多档、暂存、备份和显式恢复 |
| 对话提供器 | `scripts/providers/mock_dialogue_provider.gd` | 只根据最小上下文返回文本和候选意图 |

UI 只能读 `GameState.snapshot()` / `active_visit()` 返回的深拷贝，不能写 `GameState.state`。切换场景不产生业务动作。`Main` 的切屏与提示由自身负责，不能在 `ready()` 中再次创建接待。前台点击“接待/继续”会提交 `start_visit`；已有接待时只返回同一 `visit_id`。

场景中的界面节点由 UI 脚本构造，结构如下（替换美术无需接触核心）：

```text
Main (Control, 共享 Theme)
├── 背景 ColorRect
├── MarginContainer / VBoxContainer
│   ├── 标题 HBox：店名、当前位置、存档簿按钮
│   ├── 资源 PanelContainer：金币、精力、统一时钟、顾客资金、接待阶段
│   ├── scene_holder (Control)
│   │   ├── ShopFront：左侧店铺图；右侧顾客卡、接待/休息/次日/经历
│   │   └── Consultation：左侧对话/话题/TextEdit/发送；右侧牌面/经历/结束
│   └── 提示 HBox：动作结果、开发模拟标记
├── 存档 Window：列表、新建、继续、刷新、恢复
│   └── 备份恢复 ConfirmationDialog
└── 经历 Window：RichTextLabel、关闭按钮
```

`scene_holder` 同时只实例化一个子场景。咨询区在抽牌按钮旁预先显示费用和消耗，点击「确认费用，抽一张牌」后提交动作。对话通过显式发送按钮提交，Enter 可用于输入法选词或编辑。

## 信号与异步

- `GameState.state_changed()`：成功写盘并发布新状态后发送；UI 重新读取快照。
- `GameState.action_failed(message: String)`：失败提示。失败结果同样通过函数返回。
- `GameState.execute_action_async(action: Dictionary) -> Dictionary`：UI 使用 `await` 调用的正式入口，当前 mock 立即返回。未来 provider 可以等待 HTTP 响应，不改变 UI 调用方式。
- `GameState.execute_action(action: Dictionary) -> Dictionary`：当前本地 mock 的同步测试入口。
- `snapshot() -> Dictionary`、`active_visit() -> Dictionary`、`clock_text() -> String`、`make_id(prefix: String = "action") -> String` 为只读查询或 ID 辅助函数。

等待对话时 `_provider_pending` 会阻止其他状态动作；返回后重新核对存档和状态版本。网络等待、现实打字、阅读、窗口动画均不推进游戏时间。未来 HTTP provider 应自行实现超时并返回错误；不允许无限等待、以 UI 渲染速度计算游戏时间。

## 命令格式

```gdscript
var reply = await GameState.execute_action_async({
    "type": "talk",
    "action_id": GameState.make_id("action"),
    "expected_version": GameState.snapshot().state_version,
    "text": "邀请上写了什么？"
})
```

| type | 额外输入 | 行为/限制 |
| --- | --- | --- |
| `new_game` | `name`，可省略 | 创建随机独立 `save_id`；名称 1–32 字，空白使用默认值；不删除或覆盖旧档 |
| `load_game` | `save_id`，`recover_backup: bool = false` | 正常读取；仅明确传 true 时恢复备份。失败保留当前运行状态 |
| `start_visit` | 无 | 同日仅一次演示接待；已有活动接待返回原 ID；不耗时 |
| `talk` | `text`，1–500 字 | 支持已配置关键词；未知话题澄清；成功保存后耗 5 分钟 |
| `reading` | 无 | 顾客付费、店长收款、扣精力、时间和牌面一次提交；一接待一次 |
| `end_visit` | 无 | 结束接待并保存对话/线索/原牌面，清空活动 ID；不另耗时 |
| `rest` | 无 | 耗 60 分钟、恢复 30 精力，上限 100；精力满则不消耗时间 |
| `next_day` | 无 | 必须先结束活动接待；推进至次日 09:00、精力恢复至上限 |

除 `new_game`、`load_game` 外必须有非空 `action_id`，使用 `make_id` 生成。`expected_version` 可选，UI 应提供。处理顺序：查已处理 ID → 查业务幂等（已有牌面/活动接待）→ 查状态版本 → 校验前置条件和资源 → 完整候选状态 → 保存 → 发布。`action_id` 重复返回原结果并加 `replayed: true`；同 ID 用于不同类型拒绝。新 ID 重复请求已完成基础占卜也返回原牌面，不再次收费、扣精力或抽牌。

```json
{
  "success": true,
  "error_code": "",
  "message": "结算和牌面已保存。",
  "state_version": 5,
  "result": {"visit_id": "visit_…", "reading": {"reading_id": "reading_…"}},
  "action_type": "reading"
}
```

所有返回都有前五个字段。持久化成功结果附 `action_type`；失败 `result` 为空。读档失败额外返回 `backup_available`。重放原 ID 的 `state_version` 为原动作成功时版本，UI 必须刷新快照，而不能用旧返回值覆盖当前状态。

常用错误：`NO_SAVE`、`NO_VISIT`、`INVALID_ACTION`、`UNKNOWN_ACTION`、`INVALID_NAME`、`INVALID_INPUT`、`STALE_VERSION`、`ACTION_ID_REUSED`、`BUSY`、`ACTIVE_VISIT`、`ALREADY_VISITED_TODAY`、`NPC_FUNDS_LOW`、`ENERGY_LOW`、`ENERGY_FULL`、`NOT_ENOUGH_TIME`、`CONTENT_INVALID`、`PROVIDER_INVALID`、`PROVIDER_ERROR`。持久化错误包括 `SAVE_WRITE_FAILED`、`SAVE_READ_FAILED`、`SAVE_MISSING`、`SAVE_CORRUPT`、`INVALID_SAVE_ID`、`INVALID_SNAPSHOT`、`BACKUP_UNAVAILABLE`。错误不修改资源、时钟或已发布状态。

## 状态模型

```text
state
├── schema_version: 1
├── save_id: String（唯一，save_ + 随机 128 位）
├── name: String
├── state_version: int（新建为 1，每次成功状态动作递增）
├── clock_minutes: int（第 1 天 00:00 起累计分钟）
├── player: {coins: int, energy: int}
├── npcs: {npc_lin: {coins: int}}
├── active_visit_id: String（无接待为 ""）
├── visits: Array[visit]（按创建顺序，含完整已结束经历）
└── processed_actions: Dictionary[action_id, 成功动作返回结构]

visit
├── visit_id: String（每次新接待生成）
├── npc_id: "npc_lin"（身份永久稳定）
├── day: int（floor(started_at / 1440)，从 0 开始）
├── phase: "talking" | "reading_done" | "ended"
├── clue_ids: Array[String]（同次接待去重；不奖励金币）
├── dialogue: Array[{speaker: "player"|"npc", text: String}]
├── reading: {} 或完整 reading
├── started_at: int
└── ended_at: int（未结束为 -1）

reading
├── reading_id: String
├── card_id: String
├── title: String（结算时快照，后续改配置不改旧牌面文字）
├── text: String
├── fee: int
├── energy_cost: int
└── minutes: int
```

同 NPC 次日可演示新 `visit_id`，沿用钱包和历史。初始 60 金币，单次 20，因此三次收费后余额为 0；本轮不隐式刷新顾客资金。UI 可查看所有已结束记录。该回访规则是测试案例，不是正式客流或预测反馈系统。

初始时间 540（第 1 天 09:00）；游戏显示日序号为 `floor(clock_minutes / 1440) + 1`。交谈、占卜和休息在一个 `_advance` 入口累计分钟，动作结束不能超过当日 22:00；恰好 22:00 可以结束动作。下一天用同一入口前进到次日开门，结束接待不另耗时。没有运行时计时器扣时间。

## 原子结算与恢复

1. 不足顾客资金/精力/剩余营业时间时立即失败，无部分修改。
2. 在完整候选状态里同时写双方金币、精力、游戏时间、牌面、阶段和已处理动作。
3. `SaveService.write_save(candidate)` 验证 JSON 数据类型、数值范围、内容 ID、活动接待引用和阶段一致性。读取 JSON 后整数值归一化为 int。
4. 文件外层为 `format`、`payload`（内层 JSON 字符串）、`sha256`。校验和用于发现损坏，不是防作弊或加密。
5. 候选写 `save_id.json.tmp`，flush、关闭、回读校验；现有有效主档复制为备份暂存并校验，原备份保护为 `.json.bak.guard` 后替换 `.json.bak`；最后将候选重命名为主档。Windows 替换可能先移除目标文件，不能宣称严格 OS 原子性；失败时尝试用已校验备份恢复缺失主档。
6. 仅写盘成功后发布 `GameState.state`、发信号并返回完成牌面。失败保留之前状态与旧有效档，允许重试。
7. 每次接待的牌由稳定 visit ID 在三张演示牌中选择；失败保存后的重试也选择同一张。付款之前运行快照 `reading = {}`，UI 只能显示牌背。

`.bak` 通常是上一成功提交；若该备份损坏或缺失，允许发现更早的 `.bak.guard`。主档缺失或损坏会提示，绝不直接创建空档或自动恢复。用户明确选择恢复时，将旧主档保留为 `.corrupt.<ticks>`，再恢复可用备份；恢复点之后的动作会回退，可能超过一步，必须提示用户。校验不通过的现有主档禁止被普通保存覆盖。测试必须把 `SaveService.base_dir` 指向独立目录；`fail_next_write` 是确定性测试注入点，UI 不访问。

保存成功代表 Godot 文件 API 已 flush、关闭并回读且替换成功；不宣称提供超出本地文件系统能力的硬件断电事务保证。没有数据库、网络同步、迁移器或自动云端备份。结构不兼容时必须显式提升 schema 并实现迁移，不能静默初始化。

## 内容配置与 provider 边界

`res://data/content.json` 是人物和数值的唯一配置。包含 `npc`、`rules`、`topics`、`clues`、`cards`；配置缺失、类型错误、重复 ID 或未知引用会明确报错。`topics` 为 `{topic_id,label,keywords,reply_text,clue_ids}`，`clues` 为 `{clue_id:{title,text}}`，`cards` 为 `{card_id,title,text}`。更换人物、线索或牌 ID 必须考虑已有存档的引用兼容性。

provider 请求示例：

```json
{
  "npc": {"npc_id": "npc_lin", "name": "林照晚", "role": "旧书修复师"},
  "visit_id": "visit_…",
  "visible_history": [{"visit_id": "visit_之前", "day": 0, "dialogue": [], "clue_ids": []}],
  "current_dialogue": [{"speaker": "npc", "text": "你好。"}],
  "input_text": "邀请上写了什么？"
}
```

provider 返回示例：

```json
{
  "reply_text": "邀请上有一句手写附言……",
  "intent": "invitation",
  "clue_ids": ["invitation_note"],
  "needs_clarification": false,
  "error_code": ""
}
```

Mock 仅做少量明确关键词匹配；未知输入返回 `intent: clarify`。核心检查字段、长度、意图 ID 和该意图授权的线索，不信任 provider 提供的资源动作。provider 没有金币、精力、存档写接口，也不拿完整内部状态。未来在 `scripts/providers/` 增加 HTTP 实现，保留 `request_reply(request)` 返回契约，由 `execute_action_async` await；请求最小资料，设置超时，正式 API 密钥仅在代理服务端。客户端不保存生产密钥。

后续扩展：储物柜/工坊/采购/采集加新场景；规则动作放核心，配置放 data，存档字段改动先升级协议。人物关系、正式客流、反馈判定、技能树、前世、物品支付等另立小迭代；当前不建立空 Manager。
