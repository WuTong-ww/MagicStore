# A 组人物、客流与模型网关：开发中交接

本目录是 A 组的独立开发成果，**尚未接入主游戏、公共存档或 C 的 HTTP provider，不表示 A1–A7 已验收**。新《分工》为职责基准；A 负责人物和排程，B 负责案例与可披露结果，C 负责统一资源、时钟、存档和最终集成。

## 当前文件

- `scripts/people/people.gd`：纯规则模块，调用方传入未提交的 A 数据候选；不直接保存、不修改 C 的钱包，也不直接揭示 B 的隐藏事实。
- `scripts/people/memory.gd`：按知情者保存记忆、过滤模型上下文、按熟悉度和信任开放追问，并记录每次追问来源。
- `scripts/people/director.gd`：构造有限的自主行动候选，验证模型的候选 ID 后调用 A 规则；来源事件去重，不直接改变 B 的世界事实或 C 的资源。
- `data/people/templates.json`：普通来客、外观部件、耐心和流量样例。参考家族仅为开发样例，人物名单、来源和文案仍待策划确认，不应直接当作最终美术或剧情。
- `scenes/people/people_panel.tscn`：独立的候客及外观占位面板，仅输出信号。尚未挂入 `scenes/main.tscn`；外观选择没有正式素材预览。
- `start-people-demo.cmd`：A 组独立交互演示。点击等待可观察来客、预约和接待；它使用临时示例数据，关闭即清空，不读取或修改正式存档，也不代表 A/C 已集成。
- `server/ai/gateway.py`：本机模型网关，支持对话和原创人物资料草稿。它不持有或修改游戏存档。`tests/people/test_gateway.py` 使用模拟模型测试网关；`tests/people/rules.gd` 是 Godot 人物规则测试。

B 的旧物联调样例中已有 `npc_demo_ji`（纪寄棠）；本模块的家族样例复用该 ID。正式合入前仍须把已遇见的 B 人物及其经历映射到 A 档案，并避免 B 的联调选择入口绕过正式稀有客流。示例家族的 MBTI、生日和背景均是待确认内容。

## 与 C 的接入约定（待双方确认并实施）

1. 在新档中调用 `People.create(save_id, seed, clock_minutes)` 并调用 `add_fixed` 注册林照晚。旧 v1/v2 档要在内存中初始化 A 命名空间，保留原人物、活动接待、时间、钱包、B 记录与备份；第一次成功业务动作时与其他字段一起写盘。升级版本及校验方式由 C 定稿，不能覆盖或重新生成现有身份。
2. 始终在 `GameState` 的候选状态副本内执行 A 规则；C 统一检查及保存候选，保存成功才发布。读档时 `People.validate` 只是 A 命名空间的基础检查，仍需 C 校验 `save_id`、时钟及人物、接待、事件与整个存档的交叉引用。
3. 游戏时钟推进时按共同事件顺序调用 `advance_with_schedule`，并把口碑传入 `plan_day`；同一日生成结果与排队截止时刻要持久化。时间、接待、钱包和库存必须使用 C 原有状态，不能把 A 的 `people.clock` 当第二个权威时钟。`forced_count` 仅用于测试，不能作为正式玩家入口。
4. 主界面只消费 `visible_queue`、`public_profile`、`visible_relationships` 和已获准的历史；不要把整个 `people` 字典、未来到店计划或未认识的人物关系返回给玩家。`reveal_relationship` 仅由可信的已披露线索或事件触发，调用方须核对来源与接待。连接 `people_panel` 的信号时，协商预约必须确认顾客已同意；购物客的完整交易由 C 接入。
5. 选中有效队列项后，C 创建或复用同一个 `npc_id` 的钱包，开始唯一 `visit_id`，并在同一候选中调用 `begin`、B 的 `DivinationSession.add_case`。`People.case_context` 只包含已披露的关系；`case_seed` 是给 B 的可信内部提案，不可直接展示给玩家或原样发给模型。B 仍需提供适配任意关系的正式案例；当前两个固定案例不能冒充随机剧情。
6. 已验证的对话或反馈可通过 `Memory.record` 按 `player`、`npc`、`both` 知情范围保存；`Memory.dialogue_context` 只返回双方均已知道的材料，`followups` 检查熟悉度、信任和本次接待重复记录。调用 `mark_followup_asked` 前，C 必须验证对应动作和来源确实已提交。
7. B 的 `divination_feedback_queue()` 传给 `schedule_feedback`，由 A 按事件时间、人物行程、信任及熟悉度排程；新接待里仍由 B 的 `receive_feedback` 授权披露，再调用 `record_disclosed_feedback` 记录共享记忆。B 给 A 的效果通过 `effect_id` 传给 `apply_effect`，禁止重复执行；A 不能直接发放 C 负责的金币、物品、口碑或成长。推荐需要真实关系对象；`Director` 或 `schedule_referral` 都必须再次检查目标和时间。
8. `record_observation` 只接收有至少两个真实可选项的自愿行为，并记录选择、精力、剩余时间、队列、金币及可见线索等情境。同次接待的相同话题不会重复计数。当前报告只统计可追溯动作及接待数，满 10 条、覆盖 3 次接待才给出行为描述，不输出现实人格结论；更丰富的报告维度仍待策划确认。

## 模型服务

网关默认只监听 `127.0.0.1:8765`。上游使用已提供的兼容 Chat Completions 服务，模型默认 `deepseek-v4.1-flash`；地址和模型均可通过环境变量覆盖，上游地址必须使用 HTTPS。它不会自行部署 A100 或证明底层硬件规格。

在运行网关的 PowerShell **进程**中配置密钥；不要将密钥写进 Git、游戏资源、日志或 Windows 游戏包。下例不包含真实密钥：

```powershell
$secureKey = Read-Host '上游 API Key' -AsSecureString
$env:MAGIC_AI_KEY = [System.Net.NetworkCredential]::new('', $secureKey).Password
$tokenBytes = New-Object byte[] 32
$tokenRng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
$tokenRng.GetBytes($tokenBytes)
$tokenRng.Dispose()
$env:MAGIC_GATEWAY_TOKEN = [Convert]::ToBase64String($tokenBytes)
python server/ai/gateway.py
```

`MAGIC_GATEWAY_TOKEN` 用于客户端调用本机网关，C 的 provider 应在本地安全地取得对应进程的临时值；它不是上游 API Key。不要从包含 `MAGIC_AI_KEY` 的环境启动游戏进程，以免把上游密钥传给客户端。生产远程部署还需网关鉴权、TLS、访问限制、运维和真实压测，不能直接把当前仅限本机的服务暴露公网。

- `GET /health`：进程存活，不证明上游模型可用。
- `POST /v1/dialogue`：请求使用现有 `GameState._prepare_talk` 结构，可由可信调用方额外传双方已知的 `known_memories` 和人物表达方式。模型只从允许的话题中识别意图；最终正文由该话题的手写文本、有限语气和同话题的共同记忆组成，防止模型额外泄露或编造事实。因此当前并非开放式生成对话。
- `POST /v1/profile/choices`：接收 `{"profile":{"npc_id":"...","name":"...","role":"...","personality":"...","birthday":"..."}}`，从 `profile_choices` 选择三项合法 ID；`People.apply_profile_choices` 再次核验并固定文本和生成来源。将响应头 `online` 映射为来源 `model`、`offline` 映射为来源 `offline`。上游失败时使用稳定的本地候选。
- `POST /v1/profile`：同样的输入产生自由文本草稿；它**不能**直接当作已核验人设。`People.apply_profile_draft` 只接收尚未登场的原创人物的已批准草稿；完整自动语义核验仍未实现。
- `POST /v1/event-proposal`：只接收来源事件、公开人物、共同记忆和规则许可的 `{candidate_id,label}`；模型只能选择其中一项，调用方通过 `Director.apply` 在最新候选状态中重新校验。超时或越权时返回 `no_action`。
- 响应头 `X-Magic-Mode` 为 `online` 或 `offline`；C 应展示实际模式并在网关不可达时使用已有本地 Mock。每次上游请求最长 12 秒，自由输入可能调用两次；C 需设置相应的总超时、取消和状态版本校验。现实等待不推进游戏时间。

## 验证和未完成

本机用 Python 标准库运行：

```powershell
python -m unittest discover -s tests/people -p test_gateway.py -v
```

2026 年 11 月 15 日，固定版 Godot 已运行 A 组独立规则、真实 B 组反馈的接口联调、两个进程的隔离恢复以及面板和独立演示动作测试；200 组固定种子产生 400 次普通来客和 9 次参考人物初次接待。本机网关也用现成模型实测按钮、自由提问、人物草稿及受约束的人物候选。`-Test` 不包含 A 组脚本；以下检查是无界面测试，不能代替人工画面和输入法验收。

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/dev/test-people.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/dev/run.ps1 -Test
```

未完成：A 组面板的实际图形验证、A 规则与公共状态集成、正式捏脸素材、完整随机案例、自由创作文本的可靠语义校验、更加丰富的经营报告、A/B/C 联调及 Windows 包验收。当前数据与面板是开发样例，不将上述项目标为已完成。
