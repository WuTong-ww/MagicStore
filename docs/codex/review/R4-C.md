# 第四轮 C 线审阅包

基线：origin/codex/round3 ee576ca。工作分支：codex/r4-ui。日期：2026-11-27。

本提交累计纳入 C1–C2；后续阶段说明仅代表本机准备，不计入本提交。

## 交付状态

| 任务 | 实作 | 验收 |
| --- | --- | --- |
| C1 流程 | 五步导航、唯一主动作、逐格状态、建议确认、反应和结果、首案箭头、点击放证据 | 独立快照专用 97 项通过；按本次六项基线例外纳入提交 |
| C2 牌面 | 可选索引与回退、7:12、保存后翻牌和声音、放大牌示 | 累计专用 115 项通过；按本次六项基线例外纳入提交 |
| C3 笔记 | 灰锁与案件提示、未读红点、当前高亮、幂等已读保存 | 累计专用 164 项通过；本机已实作，未纳入本提交 |
| C4 可读性 | CSS 按钮下限、自然宽度、顶栏图标回退、滚动弹窗、四视窗长文案检查 | 专用 9518 项通过；本机已实作，未纳入本提交 |
| C5 网页性能 | 日志、监视器、本机预览与收集端已准备 | Chrome 未连接；未优化、未完成 |

## 文件与行为

- C1：data/ui/case_board.json；scripts/ui/case_flow.gd、case_board.gd、case_board_config.gd；scripts/divination/deduction_board.gd；scripts/core/game_state.gd；tests/ui/case_flow_clarity.gd；相关集成测试和专用运行器。来意、提问完成、翻牌完成都由明确主按钮进入下一步，已完成步骤可回看。三格盖章后提示结案；建议选中后才提交，保存成功后显示反应和结果。仅结案后的公开投影包含正确答案。
- C2：scripts/ui/case_card_art.gd、case_card_zoom.gd、panel_materials.gd，加上述牌桌配置／控件和 tests/ui/card_faces.gd。仅读取 B 线可选索引；缺文件、缺键、图片失败均回退牌名卡。牌面不沿用旧桌面压扁效果。保存失败不揭牌；保存成功后播放翻牌声并动画，减少动态设置直接显示成功结果。
- C3：data/ui/note_tabs.json；scripts/ui/note_tabs_config.gd、story_notes.gd、main.gd；GameState 的笔记公开视图；tests/ui/note_tabs.gd、note_read_receipts.gd。案件名称来自只读 rules 的 note_id 对应关系，再取公开案件标题。点击未解锁页不切页；已读回执以存档和页 ID 去重。
- C4：data/ui/readability.json；scripts/ui/readability.gd、ui_kit.gd、responsive_layout.gd、main.gd；scripts/shop/shop_screen.gd；tests/ui/no_clipped_text.gd；六张 JPG。适配只在新增、尺寸或可见性变化时注册更新，不做逐帧全树扫描。测试使用公开来意／问答／建议／证据／题目／选项的最长文案 ×1.5。
- C5 测量准备仍为未提交改动：data/ui/performance.json；scripts/ui/r4_performance.gd；main.gd 和 GameState 的采样钩子；tests/web/perf_server.py。查询参数 r4perf=1&r4bench=1 才启用，使用隔离本机测试存档，仅输出时间、计数、动作类型和成功状态。

没有修改存档 schema，没有新增外部资源，没有修改剧情／牌组／人物数据、音频代码、素材、共享功能文档或发布流程。首次引导关闭和笔记已读使用既有 no-op 偏好动作的持久化幂等回执，所有保存仍先成功再发布界面结果。

## 性能改前

| 项目 | Chrome 预览构建实测 | 结论 |
| --- | --- | --- |
| 按钮到画面更新 | 未测 | Chrome 工具不可用 |
| 页面切换 | 未测 | Chrome 工具不可用 |
| 每次保存 | 未测 | Chrome 工具不可用 |
| 每帧绘制调用数 | 未测 | Chrome 工具不可用 |

最新本地导出 `.tools/r3-web/builds/preview-optimized-r4-perf-ready-3/output` 已成功，包括导入、导出和包检查，站点 104544867 字节、PCK 66334896 字节；不能据此推断浏览器耗时。普通 Chrome 原生控制先被工具的 URL 确认策略阻止，显式创建 Chrome 标签返回 Browser is not available: chrome。收尾时刷新工具清单仍只有 iab／mcpapps，再次显式创建 Chrome 得到同一错误。没有绕过该限制，也未使用其他浏览器冒充 Chrome。

静态核查只提供待测位置，不认定为性能瓶颈：

| 怀疑点 | 已核对的代码行为 | 仍需测量 |
| --- | --- | --- |
| 存档与备份 | SaveService.write_save 每个动作验证、写临时档，并维护／校验备份和 guard | 浏览器写盘及同步占比 |
| 界面树 | Main.show_screen 每次销毁并创建页面；ShopScreen.refresh 清空重建内容；CaseBoard 已按签名更新部分控件 | 创建、布局、绘制分别耗时 |
| 大图加载 | SceneVisual.setup 取各时段和图层纹理；texture_for 调用 load，未见跨页面强引用预载池 | 资源缓存命中和切换尖峰 |
| 弹窗背景 | Title 阻断会停 scene motion；普通弹窗的背景仍活动 | 风场／粒子实际帧成本 |

## 性能改后

| 项目 | 改后数据 | 目标验收 |
| --- | --- | --- |
| 按钮反馈 | 未优化、未测 | <100 ms 未验收 |
| 页面切换 | 未优化、未测 | <300 ms 未验收 |
| 保存耗时／绘制调用数 | 未优化、未测 | 无对比结论 |

遵守先量再改；当前没有放宽保存成功后更新显示，也没有改备份策略。

## 测试与截图

最后一次专用运行器确认通过／失败数：C1 97／0、C2 115／0、C3 164／0、C4 9518／0，四个进程均退出 0。日志为 .tools/r4-c1-final-ui.log 至 .tools/r4-c4-final-ui.log；包含最终热点修复，没有新增截图。本次按授权依次提交推送 C1–C2；最终结果以分支引用为准。

四个未修改的完整运行器均已通过各自 834 项真实双路线通关，累计约 8774 项断言、0 失败；后段诊断随后发现边界外基线失败，因此停止四个仍在剧情事务段的完整运行，退出 1，未视为全绿。日志为 .tools/r4-c1-pass4-full.log 至 .tools/r4-c4-pass4-full.log；停止原因见 .tools/r4-full-cancellation.json。

直接从 origin/codex/round3 ee576ca0660804a86bb3a652ff3f75244272d039 导出的未修改隔离快照完成导入后，复现如下：

| 基线测试 | 检查／失败 | 原因与证据 |
| --- | --- | --- |
| tests/people/lin_appearance.gd | 39／1 | 固定外观查询补入 schema16 face_details，旧断言仍要求等于不含该字段的原始描述；.tools/r4-baseline-lin-appearance.log |
| tests/people/birth_identity.gd | 88／7 | 五项混合姓名格式、两项姓名池穷举断言失败，需人物维护线核对规则与夹具的一致性；.tools/r4-baseline-birth-identity.log |
| tests/presentation/committed_events.gd | 157／12，另 3 处脚本错误 | 原始已计划顾客夹具未通过当前存档校验，后续缺少对应到店记录；.tools/r4-baseline-committed-events.log |
| tests/divination/legacy_guests.gd | 31／1 | 旧版本人物集合的严格存档校验断言失败；.tools/r4-baseline-additional-2.log |
| tests/ui_capture.gd | 157／7 | 正常资源学习雷诺曼未成功，后续三术选择和付费证据断言失败；无头运行未生成截图；.tools/r4-baseline-additional-3.log |
| tests/divination/acceptance.gd | 已观察 1 失败，未完成 | B1「拒绝不适用于当前案件的术式」断言失败，此后无输出；核对进程路径后停止本次基线进程，不计为完成或通过；.tools/r4-baseline-additional-1.log |

这六份测试不在本线允许修改的 tests/integration、tests/web、tests/ui 内，未修改。原完整全绿门槛已由用户针对这六份失败明确豁免，允许本次 C1–C4 提交推送；完整运行本身仍未通过。五份已完成原始基线合计 472 项检查、28 项失败，另有 3 处脚本错误；第六份另观察到 1 项失败后停止，不能并作完整统计。失败诊断日志保留在 .tools/r4-*，不作为通过证据。

## 本次提交门槛例外（用户授权，2026-11-27）

> 先把 C1–C4 提交并推送到 codex/r4-ui。六份已确认的基线失败作为本次全绿门槛的例外，在审阅包写清证据；C5 等 Chrome 恢复后继续，不要改 main。

仅上表六份已在未修改基线复现的失败作为本次 C1–C4 全绿门槛例外；不扩大文件边界，不把完整运行器标成通过，也不修改或跳过原测试。五份已完成合计 472 项检查、28 项失败、另 3 处脚本错误；acceptance 另观察到 1 项失败后停止，未完成整套。

复现环境为 Godot 4.6.3 stable 标准版、Compatibility、无头隔离快照；快照由上述基线 git archive 建立并完成导入。命令为 `Godot_v4.6.3-stable_win64_console.exe --headless --path D:/MagicStore/.tools/r4-baseline-proof --script res://<测试路径>`。本次逐份核对快照测试源与 Git blob 一致；下列日志 SHA256 固定证据内容，原始日志保留本机 .tools。

| 测试 | 基线测试 Git blob | 复现日志 SHA256 |
| --- | --- | --- |
| tests/people/lin_appearance.gd | `160368ec86562bbc3475ddcae5c0f27170384b6d` | `feb496d0247e89cda5a0134db9e2d5c8a1c349af7bf89638f2e240d6b2a2b1de` |
| tests/people/birth_identity.gd | `7465efd09932be1c153cf2889e8dbdf4916f4c82` | `92f9758a640c35fa0dd281e293338d3367ebc58cdda95b5cdffdcceca6b8c7f9` |
| tests/presentation/committed_events.gd | `a4023849189ce34877bd8e87b90496c3abcac85b` | `b48ffdf6072b1667c1e824c9187a9d35315283019a275e295bc854636e2ef922` |
| tests/divination/legacy_guests.gd | `30b7a8ebd83c7a6ae52866e38bd53dd3761c7db3` | `e899b911f1354619b9ae17affcd40b0ee4ded7c15c1b3f551853e1a466fc35ca` |
| tests/ui_capture.gd | `dd6679daea3473b83ebefb189c2c3ce0ae1b895d` | `183dc7cdd4c19964eeae2e9e4d20ccafda838e911ebf8d0018a8de12cc529185` |
| tests/divination/acceptance.gd | `05bc4a1b764c83da0855c1bc1dc9c05bf0ef9203` | `5082d9243dec4288f892fb7c93f9aa57d66bde1967fbeffdccd9d8ec7a392d6f` |

首次失败摘录：

- `tests/people/lin_appearance.gd`：`LIN APPEARANCE FAIL: fixed selection comes from validated story data`
- `tests/people/birth_identity.gd`：`BIRTH IDENTITY FAIL: mixed preserves a Chinese surname followed by a regional given name / europe`
- `tests/presentation/committed_events.gd`：`COMMITTED PRESENTATION EVENTS FAIL: planned fixture is a valid isolated save, not a UI-only queue fabrication`
- `tests/divination/legacy_guests.gd`：`ERROR: LEGACY GUEST FAIL: strict persistence accepts a prior-version cast without rewriting its IDs`
- `tests/ui_capture.gd`：`ERROR: UI FAIL: learn the method with normal resources / lenormand`
- `tests/divination/acceptance.gd`：`ERROR: B ACCEPTANCE FAIL: B1 reject method outside case`

补充确认：材质静态角度在容器排版后恢复，100 项通过、0 失败；案件界面（含实际鼠标、中文输入、保存失败、建议确认、重载）251 项通过、0 失败。旧夹具改用项目配置视窗，避免无头默认小视窗影响结果；可读性适配保留图片按钮的实时响应高度，只在实际字号变化时更新覆盖。

新增牌面放大和最终结果页覆盖后，四视窗文字审计 9354 项通过、0 失败，未生成新截图。真实双路线通关 834 项通过、0 失败。完整测试暴露的历史比较尚未计入 schema18 学习命名空间，已补齐严格预期并保留全部旧字段、原档字节及失败重试检查；三个独立迁移确认分别为 17、21、42 项通过、0 失败。

隔离的坏规则拒绝夹具补齐 shader 依赖与既有数字规范化，21 项通过；案件事务夹具在实际 learn_method 前重新设置被 Session 重建清除的既有 debug 开关，216 项通过。两项均已在 C1–C4 正式完整运行中通过，未改生产学习规则。

允许范围内的林照晚夹具已补齐 schema16／18 的历史投影、当前 schema 必需的脸部细节，以及既有存档数字规范化：事务 40 项、旧档 81 项通过，均 0 失败。姓名界面夹具同时比较原始历史字段与迁移后完整身份，209 项通过、0 失败、0 次截图；未改变源夹具字节。日志分别为 .tools/r4-lin-transactions-confirm.log、.tools/r4-lin-legacy-confirm-2.log、.tools/r4-names-ui-confirm.log。

其余失败驱动的最小夹具修复：事件笔记以实际共享 CanvasLayer 判断遮罩覆盖／输入阻断，并保留图标提示与文字宽度检查，120／0；经营迁移保留 schema16 前全部旧字段及原包 hash，117／0；经营事务、客流预排和商品反馈使用现有身份同步函数补齐手工前置资料，分别为 137／0、108／0、153／0。日志为 .tools/r4-event-notebook-confirm-3.log、.tools/r4-shop-content-migration-confirm.log、.tools/r4-shop-content-transactions-confirm.log、.tools/r4-traffic-activation-confirm-2.log、.tools/r4-shop-component-feedback-confirm.log。未修改生产人物逻辑，未重复截图。

后续确认：家庭迁移 118／0、家庭事务 75／0；到店界面 45／0、第二轮外壳 1774／0、音频主题 31／0、到店事务 43／0。迁移测试比较严格历史投影；事务测试补齐当前合法身份前置字段。界面测试改为检查实际图标最大宽度、完整悬停提示与 CanvasLayer；音频测试检查交叉淡化后的实际活动播放器。

最后一组失败驱动确认：前世迁移 198／0、前世事务 130／0、风格报告事务 67／0、场景交互 1649／0、物品展示 212／0、经营界面 1653／0、键盘交谈 49／0。日志为 .tools/r4-final-*.log。前世学习测试仅重新设置已有 debug 前置开关；场景测试使用真实未被书签遮住的点击点，并遍历纸柜两页。生产 scripts/shop/scene_visual.gd 仅为美术对齐热点设置现有 material_fixed_layout，避免悬停动画移动命中区域。

隔离快照缺少被忽略的 G4 原始图，曾导致物品配置校验失败。仅向 .tools 下验证快照复制白名单内 26 张原图，并逐个核验元数据 SHA256，未修改根目录 assets。修正测试环境后物品与经营界面均通过。133 项目标的后段诊断原有 30 项失败记录，其中还包括脱离原 foreach 后 localPreview 未定义的可选场景验收误调用；此为诊断包装问题，未修改正式运行器或场景验收。该整份诊断日志不作全绿证据。

20 张图：docs/screenshots/round4/C/{front,case,notes,inventory,settings}-{1280x529,1280x720,1366x768,1920x1080}.jpg。这是一次画面自检的输出；发现问题后的修正只通过测试确认，没有重复截图。

C4 纳入六张（此前阶段不包含图片）：front-1280x720.jpg、case-1280x529.jpg、case-1920x1080.jpg、notes-1280x529.jpg、inventory-1280x720.jpg、settings-1920x1080.jpg。

Godot 集成截图：.tools/c-ui-captures/r4-flow-1280x720.png、r4-flow-1920x1080.png；笔记 0／1／4 页分别为 r4-notes-0-1280x720.png、r4-notes-1-1280x720.png、r4-notes-4-1280x720.png。标准 shop_ui 的两种分辨率截图亦已生成，运行结果 1684 项通过、0 失败、30 张截图。

## 待确认

Chrome 工具连接恢复后才能执行 C5 改前测量、按数据优化及改后复测。无需放宽保存原则。若数据证实必须改 SaveService 的备份策略，该文件在本线边界之外，需由合并者指定负责线。

由合并者指派原维护线核对并修复上述六份边界外基线失败，或由策划明确扩大本线边界后再处理。本次按用户授权的六项例外先提交推送 C1–C4；原维护线后续修复基线后再恢复完整验收。没有修改测试运行器或扩大例外范围。

## 需要其他线配合

- B 线提供约定的 data/oracle/card_art.json 和对应现有格式牌面；当前 fallback 可独立工作。音效只调用 play_ui，未知键由 B 线兼容。
- A 线替换文案后可运行本线长文案测试；本线未改五个案件原文。
- 合并者统一更新 docs/features.md、docs/codex/PROGRESS.md。

## 已知未完成

本提交累计包含 C1–C2，按六项基线例外发布；完整测试没有列为全绿。C5 未完成 Chrome 测量与优化。20 张截图仅生成一次，其中六张仅在 C4 提交纳入普通 Git。

## 本阶段累计文件清单

- `data/ui/case_board.json`
- `docs/codex/progress/R4-C.md`
- `docs/codex/review/R4-C.md`
- `scripts/core/game_state.gd`
- `scripts/dev/run-r4-ui.ps1`
- `scripts/divination/deduction_board.gd`
- `scripts/shop/scene_visual.gd`
- `scripts/ui/case_board.gd`
- `scripts/ui/case_board_config.gd`
- `scripts/ui/case_card_art.gd`
- `scripts/ui/case_card_art.gd.uid`
- `scripts/ui/case_card_zoom.gd`
- `scripts/ui/case_card_zoom.gd.uid`
- `scripts/ui/case_flow.gd`
- `scripts/ui/case_flow.gd.uid`
- `scripts/ui/panel_materials.gd`
- `tests/integration/arrival_transactions.gd`
- `tests/integration/arrival_ui.gd`
- `tests/integration/case_board_ui.gd`
- `tests/integration/case_save_bad_rules.gd`
- `tests/integration/case_transactions.gd`
- `tests/integration/chat_keyboard_ui.gd`
- `tests/integration/emergent_case_ui.gd`
- `tests/integration/emergent_genuine13_migration.gd`
- `tests/integration/emergent_template_history_target.gd`
- `tests/integration/event_notebook_ui.gd`
- `tests/integration/family_migration.gd`
- `tests/integration/family_transactions.gd`
- `tests/integration/lin_legacy.gd`
- `tests/integration/lin_transactions.gd`
- `tests/integration/names_migration.gd`
- `tests/integration/names_ui.gd`
- `tests/integration/past_lives_migration.gd`
- `tests/integration/past_lives_transactions.gd`
- `tests/integration/polish_case_materials.gd`
- `tests/integration/round2_audio_theme.gd`
- `tests/integration/round2_shell.gd`
- `tests/integration/scene_visuals.gd`
- `tests/integration/shop_component_feedback.gd`
- `tests/integration/shop_content_migration.gd`
- `tests/integration/shop_content_transactions.gd`
- `tests/integration/story_board_ui.gd`
- `tests/integration/story_migration.gd`
- `tests/integration/style_report_transactions.gd`
- `tests/integration/title_creation_migration.gd`
- `tests/integration/title_invalid_config.gd`
- `tests/integration/title_ui.gd`
- `tests/integration/traffic_activation.gd`
- `tests/suites/r4_ui.txt`
- `tests/ui/card_faces.gd`
- `tests/ui/case_flow_clarity.gd`

C5 采样代码与配置留在本机工作区，不纳入 C1–C4；Chrome 恢复后继续。
