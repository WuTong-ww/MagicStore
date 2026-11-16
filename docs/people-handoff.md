# 人物、来访与模型网关交接

人物规则、排程、记忆、候客队列、预约和反馈已接入主游戏、统一时钟及 v3 公共存档。原创新人物通过后台生成、独立审核和正式入档流程加入游戏，不需要另开人物演示场景。当前范围见[功能清单](features.md)、[人物生成](people-generation.md)及[验收记录](verification.md)。

## 模块与职责

- `scripts/people/people.gd`：人物与来访规则，在调用方提供的候选状态中执行，不直接写存档、修改公共钱包或揭示隐藏案情。
- `scripts/people/memory.gd`：按知情者保存记忆，只向对白提供双方已知材料，保留追问和披露来源。
- `scripts/people/director.gd`：构造有限自主行动候选，验证候选 ID 与来源事件；不能直接改变世界事实或公共资源。
- `scripts/shop/people_bridge.gd`：将人物时钟、实际队列、钱包、接待、反馈和经营动作接入公共候选提交。
- `scenes/people/people_panel.tscn`：主游戏已使用的候客及外观面板，发出请求信号，由主界面提交正式动作。
- `scripts/people/generated_person.gd`、`scripts/providers/http_person_provider.gd`、`scripts/divination/generated_cases.gd`：原创人物包校验、独立后台传输与专属案例投影。
- `server/ai/gateway.py`、`server/ai/person_generation.py`、`server/ai/model_request_policy.py`：可选本机网关及同构规则，不持有或修改游戏存档。

A 负责人物与排程，B 负责案例与可披露结果，C 负责统一资源、时钟、存档、界面及最终整合。旧独立原型见[历史说明](archive/people-prototype-history.md)，不再作为启动或待接入清单。

## 当前接入约束

1. 新档及旧档迁移由公共状态层初始化人物命名空间；已保存的身份、钱包、活动接待、时间和案例记录不能重新生成。校验整个存档后才提交。
2. `GameState` 在深拷贝候选内执行人物、经营和案例规则，保存成功后发布。人物 `clock` 与公共 `clock_minutes` 一致，不是另一套时钟。
3. 正常接待使用实际队列项的 `start_arrival`。固定来客、自然客流、介绍和正式回访共用容量及营业时间规则，不能通过开发入口绕过排程。
4. UI 只消费公开队列、已结识人物档案、已披露关系和获准历史；模型只接收限定人设、已知来源和当前话题。完整人物字典、未来到店表和隐藏案例不能直接提供给 UI 或模型。
5. 介绍、协商回访和改期必须有明确同意，并记录实际关系、接待和动作来源；保存失败不能留下半份人物或预约。
6. 模型人物包经过结构校验和绑定原包哈希的独立审核。后台完成信号只提出候选，最新存档再次校验并成功保存后才入档；切档、改配置和取消使旧 token 失效。
7. 共同记忆只来自已提交的交谈和披露。内部共同往事不自动成为玩家已知事实；关联人有自己的视角，不继承主来客的私密材料。
8. 反馈先由 B 授权披露，再记录共同记忆；效果按稳定来源去重。人物规则不直接发放金币、物品、口碑或成长。行为报告解释已记录的游戏内行为，不输出现实人格结论。

人物包字段、配额与边界见[人物生成说明](people-generation.md)。问题与对白联合审核、16 字上限、问题保存和点击校验见[动态后续问题](followup-questions.md)。

## 模型接法

首页「设置」提供直接 Chat Completions 配置：URL、模型名称和 API Key，密钥仅在当前游戏进程使用。也可使用本机网关，客户端使用临时网关令牌，上游密钥只进入网关进程。模型族参数、切换、取消和实测范围见[接口切换说明](api-model-switch.md)。

网关默认监听 `127.0.0.1:8765`。在启动网关的 PowerShell 进程中设置密钥，示例不含真实凭据：

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

上游地址和模型由 `MAGIC_AI_URL`、`MAGIC_AI_MODEL` 配置，支持 HTTP/HTTPS，根地址或 `/v1` 会补全为 Chat Completions 端点。网关模式的游戏进程不应继承 `MAGIC_AI_KEY`；`MAGIC_GATEWAY_TOKEN` 是客户端临时令牌，不是上游 Key。

| 路径 | 当前用途 |
| --- | --- |
| `GET /health` | 网关存活，不证明上游模型可用 |
| `POST /v1/dialogue` | 自由输入先选话题，再生成并独立审核；按钮跳过分类。只投影当前获准资料，通过后保留原文和已审问题 |
| `POST /v1/person-package` | 完整人物、关联人、关系和专属案例的生成与独立审核，返回哈希绑定来源；客户端仍须正式入档 |
| `POST /v1/profile/choices`、`POST /v1/profile` | 兼容的受约束资料选择与自由草稿接口，不代替主游戏人物包流程；草稿不能冒充已核验完整人物 |
| `POST /v1/event-proposal` | 从规则允许的有限候选中提议动作，调用方在最新候选状态中重新验证 |

网关单次上游请求上限为 12 秒；自由对白最多包括分类、生成、审核三次调用，客户端保留原 45 秒总期限、取消及状态校验。网络等待不推进游戏时钟。公网部署、硬件规格和压测没有由本机验证自动覆盖。

## 回归与证据

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/dev/test-people.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/dev/run.ps1 -Test
```

统一 `-Test` 已包含人物规则、主游戏整合、本机 HTTP、真实文件写盘与两进程恢复。测试及模型报告使用 `.tools` 隔离目录，不操作正式存档。具体计数、真实模型范围、图形检查和未验证项统一见[验收文档](verification.md)，不在交接文档重复维护数字。
