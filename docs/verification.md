# 咨询输入快捷键验收

本轮：2026-11-16，Windows、Godot 4.6.3。咨询输入框回车（含小键盘）发送，Shift+回车在光标处换行并支持替换选中文字；发送按钮仍可使用。提示同步更新为“回车发送 · Shift+回车换行”。

- 新键盘界面回归：headless **49/49**、实际Windows图形 **51/51** 通过。经真实焦点与Viewport键鼠事件派发，验证中文多行原样到达provider并保存、一次发送仅推进5分钟、长按/松键/忙碌不重发、空白及超500字不提交、写盘或provider失败保留草稿、鼠标重试可成功。已加入统一测试入口。
- 既有界面烟测 **316/316**、动态追问界面 **38/38** 通过。此次只运行相关定向回归，未将上轮全量检查当成本轮重测。
- 1280×720、1920×1080实际截图均已查看，输入框、发送按钮及快捷键提示完整可见，输入中文保持18号字号。截图位于隔离目录 `.tools/chat-keyboard-ui/keyboard-1280.png` 和 `keyboard-1920.png`。
- 输入法组词期间拦截发送及编辑器换行，携文字的提交事件继续交给编辑器；依据[Godot TextEdit IME接口](https://docs.godotengine.org/en/4.6/classes/class_textedit.html#class-textedit-method-has-ime-text)及Windows后端处理核查。合成Unicode键盘事件验证了中文文字保存，未模拟或实操系统输入法候选窗口，不作真实IME验收承诺。

新release实际启动及内嵌PCK **90/90** 检查通过，包含真实焦点派发回车/小键盘回车各保存一次、Shift+回车实际换行且不改游戏状态、echo不重发。EXE SHA256：`8045d37bd274328a78d6be0e9618be82cbd11674397008b609fe4728b4627d55`。定向日志：`.tools/chat-keyboard-ui/headless-validation.log`、`graphics-validation.log`、`.tools/chat-keyboard-ui-smoke.log`、`.tools/chat-keyboard-followup-ui.log`；release日志：`.tools/chat-keyboard-export-build.log`、`-smoke.log`、`-scenes.log`。

本轮使用本地夹具与隔离存档，未调用真实模型接口，正式玩家存档未参与验证。以下保留上轮URL兼容及更早版本的历史快照。

---

# HTTP 地址兼容与 URL 自动补全验收（快捷键调整前快照）

本轮：2026-11-16，Windows、Godot 4.6.3。支持 `http://36.140.146.31:23501/v1` 自动补为 `http://36.140.146.31:23501/v1/chat/completions`；域名、公网/内网IP、端口及括号IPv6同样适用。根地址和 `/v1/chat` 也会补全，完整端点和代理路径前缀保留。说明见[接口地址与模型切换](api-model-switch.md)。

- 设置、对话传输、后台人物传输及Python上游统一使用同构规则。预览与失焦只检查格式，不发网也不改配置；应用时再次校验。规范化后相同端点可以保留当前密钥，更换端点仍须重新填写，非法URL保留原配置和游戏状态。
- 最终 `scripts/dev/run.ps1 -Test` 退出码 **0**：**3283项Godot检查（41套）+90项Python测试，共3373项全部通过**，测试日志无引擎ERROR、SCRIPT ERROR或Traceback。三组两进程恢复及200店测试夹具分布单列，不重复计数。
- URL纯规则187项，前台HTTP与后台人物HTTP合计506项（含前述187项）通过；验证HTTP公网配置、根地址与版本地址补齐、同端点空密钥复用、未知路径/非法端口/控制字符拒绝，以及实际本地HTTP生成、独立审核、人物创建与零重定向。Python新增9项并入90项全套，含CLI配置及真实本地请求路径验证，未改对白或事实审核规则。
- 新设置UI无界面45项、Windows实际图形69项通过，已查看720p/1080p有效补全及错误提示四张截图。地址和反馈文字完整，应用/取消/本地对话按钮在窗口内可见。初次新增Note的自动换行曾撑高窗口，现已固定计算宽度；不靠测试强压窗口掩盖。全程确认预览没有HTTPRequest节点。
- 对用户给出的地址做了不带鉴权头的Python检查与原生Godot HTTP检查。`/v1`补全及完整地址均成功到达服务鉴权层，返回**401**；没有发送此前PJLab密钥，也没有将401视为模型推理成功。对应服务的鉴权和模型推理仍需要其有效凭据，本轮不作已验证承诺。

最新release实际启动及内嵌PCK **84/84** 检查通过，含新URL资源、规范化及后台同端点、无网络预览、弹窗控件可见范围。EXE SHA256：`65eccfd25491bfb6bedeb7941e7e6845c8e90005116f2fd3f57eadabf96dcdd9`。最初导出探针将请求高度445误当成最终像素高度，已改为1280×720下实际可见边界判断，保留首轮探针记录，未为探针修改业务布局。

主要证据在隔离`.tools`：`api-url-final-regression.log` / `api-url-final-regression-summary.json`、`api-endpoint-python-regression.log`、`api-settings-ui/url-*.png`、`url-compat-unauth-probes.json`、`url-compat-native-probe.json`及`c-export-build.log` / `c-export-smoke.log` / `c-export-scenes.log`。无鉴权探测与本地带合成密钥测试分开记录；正式存档未参与验证，实际API Key不进入源码或包。

以下保留前几轮清理、人物和模型对话的历史快照，旧计数及EXE指纹不代表本轮URL版本。

---

# 项目整理与演示清理验收

本轮：2026-11-16，Windows、Godot 4.6.3。主游戏入口为 `start-game.cmd` / `project.godot`，编辑器入口为 `start-editor.cmd`。

- 删除独立人物演示的启动命令、PowerShell启动器、场景、脚本及UID、专用演示测试共6个文件，同时移除测试和源码包入口引用。真实支付模块从 `demo_economy.gd` 改为 `economy.gd`，保留原UID及支付、库存和记账功能。
- 正式人物配置不再包含联调家族模板，默认家族抽样概率为0；模板及原8%分布场景仅由 `tests/people/fixtures/family_reference.json` 显式注入。200个正式新店跨3日验证没有刷出联调家族，原家族机制仍以独立夹具验证。
- 正式案例配置不再预植3位联调人物或其钱包。已有存档需要的旧人物身份/出生盘放在 `data/compatibility/divination_guests.json`，仅按该档已有ID补入局部目录，切档不会残留。3张旧单卡记录放在 `data/compatibility/legacy_cards.json`，用于原ID读取校验；正式抽牌仍用完整78张牌。
- 前台移除旧开发环境变量绕过排程的路径，始终展示真实队列。回访台词去掉开发演示说明。素材参考原稿统一命名为 `inventory-reference.svg/png`，当前图集及来源记录保留，引用同步更新。
- 删除 `.tools/demo-people-appdata`、`demo-people-localappdata`、`demo-people-temp` 三处演示缓存及4个旧素材导入缓存；正式 `.runtime` 和玩家存档未修改。测试资料保留在 `tests/`，当前文档使用真实主游戏流程，早期原型仅保留一份[历史概述](archive/people-prototype-history.md)。

最终 `scripts/dev/run.ps1 -Test` 退出码 **0**：**3029项Godot检查（39套）+81项Python测试，共3110项全部通过**，日志无引擎ERROR/SCRIPT ERROR/Traceback。三组两进程恢复、200店分布另列，不重复计数；分布测试的作品人物由测试夹具注入，不代表正式游戏仍有演示人物。新清理回归16项、旧人物兼容30项、正式人物配置11项均包含在总数中。

最新release实际启动及内嵌PCK **73/73** 检查通过，验证演示入口缺失、新游戏不注入演示角色/家族、支付模块/素材新路径、兼容单卡与正式78牌。EXE SHA256：`4970f314d074c7483ac8bb6dca1bd892c5ef7a450826a6fa32ca9f778134f6ce`。

证据在隔离 `.tools/project-cleanup-final-regression.log` / `project-cleanup-final-regression-summary.json`、`project-cleanup-import.log` 与 `c-export-build.log` / `c-export-scenes.log` / `c-export-smoke.log`。本轮无真实模型请求；以下保留的模型实测和旧EXE指纹属于各自历史快照，不冒充本次重测。

---

# 动态短问题与中途切模型验收（演示清理前快照）

本轮：2026-11-16，Windows、Godot 4.6.3。操作与实现见[动态后续问题](followup-questions.md)，真实请求详情见[接口切换验证](api-model-switch.md)。以下是本轮最终16字版本的结果；后文另保留上一轮人物创建和次日客流验收。

- 最后冻结源码统一 `scripts/dev/run.ps1 -Test` 退出码 **0**：**2980 项 Godot 检查（37套）+81 项 Python 测试，共3061项全部通过**，测试日志没有引擎ERROR、SCRIPT ERROR或Traceback。三组两进程存档恢复和200个种子客流分布另列，不与显式检查数重复相加。
- 新建议问题策略86项、核心真实存档整合29项通过；兼容旧三字段、16字上限、坏建议单独剔除、授权方向与实际事实分离、问题与对白联合审核及指纹绑定、问题不授予线索、原子保存/失败回滚/读档恢复/跨接待隔离均覆盖。Python新增18项，包含真实本地网关协议。
- 模型策略38、HTTP传输41、核心设置42、直接接口73、暂时恢复43、后台人物HTTP60项通过。验证全流水线最多一次同阶段重试及原45秒期限、Retry-After、认证和审核不重试、取消退避、切模型换密钥、旧serial不影响新请求，以及复制的推荐后缀/末尾排版反斜杠规范化。以上均为隔离的本地服务，不冒充真实上游结果。
- 短问题新UI：headless38项、实际Windows渲染40项通过，原生成角色图形回归55项通过。已查看1280×720和1920×1080截图：16字边界样例保持18号字体，分别最多两行/单行；实际模型问题更短。相同ID而文字改变能重新绑定，busy阻止重发，旧回调不能串到另一位来客。
- 真实PJLab四模型通过实际设置窗口切换，每次切换后的首轮都在线回复并返回2–3条建议；5次真实模型问题按钮点击均完成交谈，实际等待中的GLM请求取消后切回DeepSeek、继续对话和读档通过。API Key只在第一次设置时填写，后续留空保留；设置没有改变当前接待。
- 最终11次真实交谈全部动作成功、均已得到HTTP200：**9条模型原文，2次因无来源反复查看习惯而审核拒绝后安全回退**。严格脚本的“每轮在线/每轮保留模型问题”要求有4项未达，保留非零退出和原报告，不声称所有真实语义检查都通过。其他按钮绑定、短文本、收费、切换、取消和读档断言通过。
- 最终22条获批模型问题平均**9字**、最长**13字**；33个实际UI问题全部≤16字。11次动作等待平均11.603秒、中位3.072秒、2.133–41.353秒，包括两次回退、生成/审核/保存与两个无界面帧；同机有本地回归并行。GLM仍可能长等待，这不是模型纯生成速度或稳定排名。
- 独立逐句检查未发现实质隐藏信息提前披露；一处纸页晾干过程描写作为轻微语义解释边界保留。V1的无据次数修饰及话题泛指歧义、V2的标签误拒均有原报告；修正没有放松主对白事实保护，也没有重抽世界事实。有限样本不构成任意模型输出的绝对保证。

最新Windows release已重建，真实EXE启动与内嵌PCK **67/67** 检查通过，包含联合审核、17字过滤、16字按钮和保存、最多一次恢复及旧serial隔离。EXE SHA256：`759d9710152361dac45edd5d7acb0e82af64e0eff82cf63ee05e5af337c2758a`。

主要证据在隔离`.tools`：`followup-final-regression.log` / `followup-final-regression-summary.json`；`live-followup-models-v1.json` / `live-followup-models-final-v2.json`保留早期问题；最后为`live-followup-models-final-v3.json` / `-qa.json`；短问题截图在`followup-questions-ui/short-questions-*.png`，旧长问句截图另存`pre-short-28char-*`；导出为`c-export-build.log` / `c-export-smoke.log` / `c-export-scenes.log`。真实报告不含鉴权头、API Key或原始推理，不进入交付ZIP；测试不触及正式玩家存档。

复现真实场景需事先在当前进程提供`MAGIC_LIVE_API_URL`和`MAGIC_LIVE_API_KEY`，再执行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/dev/run-live-model-switch.ps1 -FollowupQuestions -ReportName live-followup-models.json
```

以下为上一轮人物生成、次日来客与整合验收记录；其中旧的2850计数、11/11接口结果和旧EXE指纹不代表本轮动态短问题版本。

---

# 上一轮人物生成与客流整合验收（历史快照）

该轮日期：2026-11-16；Windows、Godot 4.6.3 stable。当前功能见[功能清单](features.md)，人物创建、跨次来访和质量范围见[原创新来客](people-generation.md)，四模型切换及等待时间见[接口验证](api-model-switch.md)。

## 上一轮冻结快照

- 统一入口 `scripts/dev/run.ps1 -Test` 退出码 **0**：**2787 项 Godot 检查（33 套）+ 63 项 Python 测试，共 2850 项显式检查全部通过**，没有 `SCRIPT ERROR` 或引擎 `ERROR`。另有三组两进程存档重启恢复、200 个固定种子客流分布测试通过，单独记录，不加入上述数字。
- 人物创建规则 99、生成案例 80、真实 GameState 人物整合 132、客流容量 27、开门来客规则 12 与整合 46、资料与引用保护 127 项通过。覆盖真实批准包入档、身份冻结、专属案例、同人物新来访、介绍与回访来源、关系隐私、候客离店补位、跨日读档、失败写盘回滚，以及有来源/无来源的地域经历和固定习惯表达。
- 模型请求策略 38、HTTP 传输 41、核心状态 42、直接接口 73、后台人物 HTTP 60 项通过；均为本机 HTTP 假服务。覆盖四模型请求参数、完整 JSON 与围栏、截断/仅推理拒绝、同 URL 留空密钥、取消旧模型、迟到回复、状态不变、背景并发上限、生成后独立审核及独立写盘。Python 63 项覆盖网关与人物创建镜像规则；网关模式未用真实上游全流程复测。
- 原有经营、术式、商品、钱包、存档删除和 A/B/C 交叉引用也包含在这次完整回归。正式玩家存档未参与测试。整合检查的分支执行数量可能随合法回访排程变化；总数来自这次实际日志，不累加此前轮次。

## 实际模型与图形

- DeepSeek 真正创建 6 组人物与关联人，用时 **93.006 秒**，后台最大同时请求数 2；独立审核不通过的草稿没有入档。创建未满目标的早期失败记录保留。
- 修复后使用同六份原包重放，没有再次请求创建。实际覆盖两位主来客、一位联系人及一次正式跨日回访：18 次发网对白，17 次保留模型原句、1 次安全回退，另 2 次未解锁请求在发网前拒绝；43/43 检查通过。动作平均等待 **3.807 秒**，中位 3.162 秒，范围 2.122–9.909 秒；全十二案例公开投影审计 128/128。有限人工检查和具体回忆提示范围见人物报告。
- 四模型最后切换复测 **11/11 在线并保存**：DeepSeek → GLM 5.3 → GLM 5.3 Flash → Qwen → DeepSeek，同一接待内包含按钮和自由输入；结束接待后次日 09:00 有新顾客，实际接待、在线对话与读档通过。11 次平均 **2.891 秒**，中位 2.445 秒，范围 1.112–7.306 秒。此前 GLM 仍出现约 42 秒成功和约 45 秒超时，不能用最终短样本掩盖上游波动。
- 逐句检查曾发现无来源的出行自嘲、地域熟悉程度和固定日常习惯，已加强生成/审核提示与来源检查并复测。此前报告未改写；最后的新人及切换回复未发现新的明显事实冲突或隐藏材料提前泄漏。独立模型审核仍可能误判，这些检查不构成任意输出的绝对保证。
- 人物与设置图形脚本 **57 项**、新开门/前台等待图形脚本 **62 项**通过，实际查看了 1280×720 和 1920×1080 的设置、咨询、档案、空店和有人店画面。准备人数、并发、配额和审核过程不在游戏中展示；中文大小保留，新增操作不遮正文。720p 前台下方操作仍通过原滚动区访问。图形计数单独记录，不与完整无界面回归重复相加。

全部等待从 `main.run_action` 到保存及两个无界面处理帧结束，不含显示器或人为点击延迟；新人复测当时同机并行本地完整回归。四模型仅为顺序少量同题样本，人物创建和完整回访质量复测只覆盖 DeepSeek，不能作四模型质量或速度排名。

## 上一轮交付与证据

最后业务源码已重新导出 Windows release，实际 EXE 无窗口启动以及内嵌 PCK **53/53** 资源和策略检查通过，包含最后固定习惯保护规则。EXE SHA256：`fd6f69c21ec45b263ede87f01f54085cdac1a3b6424decfe5053538ac7d5af05`。图形验收来自源工程的实际渲染，导出包另作启动和资源验证。

主要证据均在隔离的 `.tools`，不进入源码或试玩 ZIP：

- `people-generation-final-regression.log` 与 `people-generation-final-regression-summary.json`：最后完整回归。
- `live-people-generation-final-v5.json`：实际六组创建；`live-people-generation-final-v7.json` / `-qa.json`：同包对白复测；`live-people-generation-final-v6-public-projection-qa.json`：十二案例公开投影。
- `live-model-switch-baseline.json`、`live-model-switch-final.json`、`live-model-switch-glm-followup.json`、`live-model-switch-final-v2.json`：保留原问题；`live-model-switch-final-v3.json` / `-qa.json`：最后切换与次日实测。
- `generated-people-ui/`、`opening-front-ui/`：图形截图；`c-export-build.log`、`c-export-scenes.log`、`c-export-smoke.log`：最后导出验证。

API Key 只在内存使用，不写入文档、代码、存档或包。源码包和试玩包由显式文件白名单生成，排除 `.tools`、`.runtime`、测试与玩家存档。当前仍未在第二台电脑或其他 GPU/DPI 上验收，也未新增跨进程同时写同一玩家存档的支持。

更早的单人物原型、独立人物演示、存档与Windows导出验证仅保留于[原型历史概述](archive/people-prototype-history.md)。旧绝对路径、早期命令和旧测试表不再作为当前验收指引；上述近期模型与人物实测仍按各自快照和输入范围保留。
