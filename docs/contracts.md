# 零点杂货铺：接口与存档契约

Godot 4.6.3 stable、GDScript、Compatibility。只有 `SaveService` 和 `GameState` 两个 Autoload，按此顺序载入。本文描述当前已整合的公共边界；术式和案例细节见[B 组交接](divination.md)，早期原型背景见[历史说明](archive/people-prototype-history.md)。

## 当前整合边界

当前新档使用 schema_version 3，增加 shop 和 people 命名空间。v1/v2 载入只在内存初始化缺失数据，不重置金币、精力、物品、时钟、原牌、经历或活动接待；第一次成功业务动作与其他字段一起写 v3。恢复旧备份仍走同一迁移路径。

GameState 接收经营、排队接待、预约、等待和外观动作，先在深拷贝候选执行规则，再处理 A/B 时序、校验完整存档、写盘并发布。来源批次共享 player.items 数量；商品交易、使用与反馈保留稳定引用。A 的 clock 必须与公共 clock_minutes 一致，不是另一套可独立推进的时钟。同一分钟先更新 B 事件，再按 A 的稳定顺序处理排程。

UI 使用 player_snapshot、divination_view、people_view、shop_view 与 ledger_view；完整 people、隐藏案例结果和未来到店表不直接交给 UI。旧 start_visit 保留给迁移与测试，正常前台和候客面板通过 start_arrival 接待实际等候的来客。

咨询输入框内回车（含小键盘）发送，Shift+回车在光标处换行；中文输入法仍在组词时不触发发送，长按回车不重复提交。快捷键与发送按钮共用 talk 动作、500字校验及忙碌保护；失败保留草稿，仅成功后清空。

首页设置的 Chat Completions URL、模型名称和 API Key 只在当前进程使用。API Key 不进入游戏存档、状态快照、日志和交付包；provider_status 仅返回模式与请求元数据。configure_network 保留 A 网关接法，configure_api 提供直接接口接法；两种请求都受原有意图校验、超时、取消、状态版本和存档 ID 检查。网络等待不推进游戏时间。

直接接口的地址由 `ApiEndpoint.normalize_chat_url` 统一检查，接受 HTTP/HTTPS、域名/IP/端口，根地址、`/v1` 或 `/v1/chat` 自动补齐，完整 `/chat/completions` 不重复拼接并保留代理前缀。`GameState.preview_api_url` 只返回规范化结果、不修改状态或发网，设置窗口失焦时调用；应用时再由核心检查。对话和后台人物传输使用同一规则；已有网关专用路径仅由 `http_url_valid` 做结构校验，不误拼 Chat 端点。Python上游使用 `server/ai/api_endpoint.py` 的同构规则。规范化后相同端点可保留本次密钥，更换端点必须重新填写；非法输入不改变旧配置，Godot两个传输器不跟随HTTP重定向。

对白扩展：dialogue_sources 由 GameState 正向投影，只包含双方已知的资料，并标注 statement、prediction、clue、feedback 等种类；safe_persona 仅含姓名、职业、性格和说话方式。私有拒绝规则不进入 HTTP。生成器返回 intent、reply_text、evidence_ids，以及可选的 followup_questions（最多3个 {topic_id,text}，通常8–12字、上限16字）；旧三字段仍兼容。question_topics仅提供当前授权方向的ID与标签，不提供其他答案，也不能作为NPC事实证据。对白和规范化建议共同审核后才能转成对话契约；指纹包含建议内容与顺序，变化后必须重审。无效建议单独剔除，语义审核拒绝仍回退整候选。生成来源不会被写为世界事实。仅明确引用并经核验实际披露的话题才映射相应线索或分支，问题本身和人物闲聊都不发放线索。

GameState.conversation_questions()提供最多3个当前可用的{topic_id,label,enabled,generated}，供咨询区展示。批准的问题与visit.followup_action_id绑定同一已保存talk动作；失败写盘不得更新按钮，切档或新接待不能串用。点击前核对visit_id、问题ID与当前原文，忙碌时禁用。详细规则与验证见[动态后续问题](followup-questions.md)。

HTTP临时恢复在原45秒总期限内全流水线最多一次，重发同阶段同正文；仅短暂断连及408/429/500/502/503/504可尝试，过长或无法安全解释的Retry-After不提前重试。取消或配置变化清理HTTP与退避计时器；认证、格式、截断和审核拒绝不重试。

资料未提供不等于事实不存在；否定、排他或次数断言也要有来源。`general_professional_knowledge` 仅允许在给定来源内作一般经验表达，不证明本案物件发生过相应变化。安慰类闲聊可只保留人物口吻和当前玩家话语，减少未问案情进入生成器。分类失败的自由输入只返回无效果澄清；已验证话题与按钮的回退固定在本轮所选话题，不再次扫描关键词，也不能复用上一轮分类。

HTTP 的公开 `status` 提供单调计时的 `elapsed_ms`、`stage_timings_ms`（classify/generate/review/gateway）、`failure_stage` 和数值 HTTP 状态。候选原文、审核诊断与用量仅用于私有开发记录，不随状态进入 UI。DeepSeek 的分类、生成和审核关闭隐藏推理，但独立审核请求仍为必要步骤；GLM 5.3 使用低强度推理和相应输出预算，Qwen 3 关闭隐藏推理；具体参数由共享 ModelRequestPolicy 管理，见[接口切换说明](api-model-switch.md)。

三阶段 prompt 另显式要求减少无关推演：分类只做必要判断，不反复比较；生成不穷举、不反复润色，核对身份与事实后直接输出简短对白；审核完成必要核验后立即给结论，拒绝理由简短具体。提示词优化不降低事实、引用或信息权限标准；模型族的预算与温度另由共享请求策略管理，总期限保持有界。

原创新人物另走 `HttpPersonProvider` 后台任务池，生成与审核共用在途请求上限。`job_ready(job_id,token,bundle,provenance)` 只提出候选，不写游戏；GameState 在前台动作空闲时重新验证当前存档与最新姓名/配额，并用 `admit_generated_person` 内部动作提交。切档/改配置取消并更新epoch，旧token无效；写盘失败保留旧状态且可重试。玩家对话暂停后台新阶段启动，已经在途的请求可以结束。

`GeneratedPerson` 对创建包与审核哈希、身份字段、本地出生/外观数据、双人物关系和来源记录交叉核验；`created_at` 区别于预约 `at`，每日新建配额按真实入档游戏日计。动态案例目录仅从当前存档已批准包重建，不污染全局目录，切档和读档会刷新对白话题。具体字段、后台配置及专属案例边界见 `people-generation.md`。

关系线索实际披露后才正式开放介绍；`invite_contact` 必须有来客同意并保存关系/接待/动作来源。`end_visit` 可携已确认的 `return_at` 与 `guest_agreed` 原子结束并预约，`book_arrival` 改期另存同意来源。各路径共享每日到店容量，改期不清掉旧日期占额；失败不能留下半个人物、未保存预约或已消费的线索。

澄心晶追问只引用双方实际共享的 `memory.text`，不能根据 `topic_id` 推导手写话题答案。选项记录 `memory_id`、`source_visit_id`、`source_kind` 并与对白、时间及一次性消耗共同提交；写盘失败全部回滚。

完整操作和复跑说明见[功能清单](features.md)和[验收记录](verification.md)。

删除入口为 `delete_game`，传入 save_id；底层为 `SaveService.delete_save`。UI 必须先确认店名与不可恢复后果，确认时使用弹窗绑定的 ID。服务先校验 ID，并只枚举该存档在 base_dir 内的已知文件；全部暂移成功后再删除。暂移失败尝试恢复，清理阶段失败则明确返回 cleanup_pending，不声称已回滚。删除当前档成功才清空 GameState，其他档保持原状态。正在等待 provider 时仍拒绝删除，避免迟到回复重新写出已删存档。

## 所有权与入口

| 模块 | 文件 | 责任 |
| --- | --- | --- |
| 主界面 | `scenes/main.tscn`、`scripts/ui/main.gd` | 主游戏导航、设置、存档簿、人物面板、消息和确认流程 |
| 场景界面 | `scripts/ui/`、`scenes/` | 前台、咨询、店外、储物、工坊、商店、采集的公开视图与动作提交 |
| 权威状态 | `scripts/core/game_state.gd` | 前置条件、统一时钟、候选提交、幂等和跨模块引用 |
| 内容加载 | `scripts/core/content_loader.gd` | 内容目录与兼容数据的加载、配置及引用校验 |
| 存档服务 | `scripts/save/save_service.gd` | 完整 JSON 校验封装、多档、迁移、暂存、备份、恢复和删除 |
| 模型传输 | `scripts/providers/`、`server/ai/` | 获准上下文的模型候选与独立审核，不直接写游戏资源或存档 |

UI 只消费深拷贝或公开视图，不写 `GameState.state`。切屏和 `ready()` 不应创建接待；前台选中有效候客项后提交 `start_arrival`。已发生的对话、费用、库存、时间和排程通过统一动作提交，不由画面刷新触发。

## 动作与异步

- `state_changed()` 在成功写盘并发布状态后发送，UI 随后重读视图；`action_failed(message)` 提供失败提示。
- `execute_action_async(action)` 是 UI 的正式 `await` 入口，兼容本地提供器和实际 HTTP。`execute_action(action)` 保留给本地同步规则与隔离测试。
- `snapshot()`、`active_visit()`、`clock_text()`、`player_snapshot()`、`divination_view()`、`people_view()`、`shop_view()`、`ledger_view()` 是查询接口；`make_id()` 生成动作等稳定标识。

```gdscript
var result = await GameState.execute_action_async({
    "type": "talk",
    "action_id": GameState.make_id("action"),
    "expected_version": GameState.snapshot().state_version,
    "text": "最近修复了什么书？",
    "topic_id": "work"
})
```

| 动作族 | 输入及边界 |
| --- | --- |
| `new_game`、`load_game` | 店名或存档 ID；新建不覆盖旧档，恢复备份必须显式同意 |
| `start_arrival` | 当前有效队列项 `arrival_id`；共用真实人物身份、钱包和唯一接待 |
| `talk` | 非空文字及可选合法 `topic_id`；统一检查 provider 回复，保存成功后按配置推进时间 |
| `reading` 及案例动作 | 问题、术式、服务等字段见 `divination.md`；付款、原结果和资源同时提交，重放不重复收费 |
| `end_visit` | 结束当前接待；正式回访可携已同意的 `return_at`、`guest_agreed` |
| `wait`、`rest`、`next_day` | 通过公共推进入口处理营业时间、资源、案例事件和来访排程 |
| `book_arrival`、`invite_contact`、`save_appearance` | 校验目标、同意、来源与已开放选项，不能绕过人物或队列规则 |
| 经营与成长动作 | 采购、采集、研发、制作、交易、使用和案例复盘等沿用统一资源、库存批次与来源校验 |

正常 UI 提供 `action_id` 和 `expected_version`。重复动作 ID 返回已保存结果并标明重放；同 ID 用于不同动作拒绝。等待对白时阻止冲突状态动作，返回后重新核对存档、接待和版本，旧模型结果不得覆盖新配置或另一存档。失败不推进资源、游戏时间或已发布状态。

## 状态与兼容数据

当前顶层使用 `schema_version: 3`，包含 `save_id`、`state_version`、`clock_minutes`、`player`、`npcs`、`active_visit_id`、`visits`、`processed_actions`，以及人物、经营和问卜命名空间。钱包、库存、状态与来源必须交叉一致；本表不是可绕过校验的自定义扩展协议。

每次来访使用新 `visit_id`，同一人物沿用 `npc_id`。接待保存真实对话、已披露线索、术式结果及起止时间；动态问题另含 `followup_questions` 与同一次已提交 `talk` 的来源 ID。人物往事和生成包不因换一次接待而重新抽取。

`data/content.json` 提供基础人物、规则、话题和线索；人物、经营、成长及问卜目录各有专用配置。当前正式塔罗使用78张牌。早期三张牌的数据移至 `data/compatibility/legacy_cards.json`，由 `ContentLoader` 补入兼容 `cards` 目录；这是旧牌面读取支持，不是当前抽牌池，也不是删除旧档卡牌 ID 的授权。

版本迁移只在候选内补齐明确支持的旧结构，不重置旧资源和历史。未知或损坏结构必须报错，不能静默新建、重新生成人物或用当前配置改写已保存的牌面文字。

## 保存、恢复与删除

1. 先验证前置条件和资源，在完整候选中统一处理规则、结果、时间与已处理动作。
2. `SaveService.write_save` 校验 JSON 类型、范围、内容 ID、人物/案例/接待/动作来源与完整交叉引用；读取后的整数值归一化。
3. 外层保存 `format`、`payload` 和 `sha256`。校验和检出意外损坏，不是加密或防作弊。
4. 写暂存文件、flush、关闭、回读验证，保护 `.bak` 和 `.bak.guard` 后替换主档；仅成功后发布状态。失败保留旧状态并报告，不能声称硬件断电事务或数据库级原子性。
5. 主档缺失或损坏不会自动清空。用户明确选择恢复时保留 `.corrupt.*`，恢复点之后的动作可能丢失，提示应说明可能不止一步。
6. 删除先校验 ID 和目标文件，只处理该档在 `base_dir` 中的已知文件；确认与失败边界见上文删除入口。测试把 `base_dir` 指向隔离目录，失败注入点不暴露给正常 UI。

默认存档 API 仍为 `user://saves`，启动脚本将其实际位置限定在工程的 `.runtime`；测试放在 `.tools`。没有提供多进程同时写同一档的互斥锁、自动云备份或未知版本的通用迁移器。

## 提供器结果与权限

本地话题与 HTTP 提供器保留相同业务返回字段：`reply_text`、`intent`、`clue_ids`、`needs_clarification`、`error_code`，可含 `branch_id` 和可选 `followup_questions`。建议最多3条，每条恰好 `{topic_id,text}`，文字上限16字。坏建议单独剔除，未知顶层业务字段不能透传。

模型内部的 `evidence_ids`、候选原文、审核细节与 usage 不直接成为游戏动作。只有实际表达并获准披露的资料才授予相应线索；问题标签只许可提出问题，不证明该方向的事实已经发生。

`HttpDialogueProvider` 已实现异步 HTTP、模型族请求策略、严格完成性检查、取消、暂时恢复与授权回退。`HttpPersonProvider` 使用独立任务上下文和审核来源；两者都不持有金币、精力、时钟或存档写接口。直连 Key 只在客户端内存使用，网关模式的上游 Key 只在服务端进程使用，均不写入公共状态和交付包。
