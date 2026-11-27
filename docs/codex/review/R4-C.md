# 第四轮 C 线审阅包

基线：origin/codex/round3 ee576ca。工作分支：codex/r4-ui。更新：2026-11-28。

C1–C4 已推送至 codex/r4-ui；C5 本提交完成网页性能优化与前台确认，沿用六项已确认基线失败的例外。本线只更新该分支，不改 main。

2026-11-28 远端只读复核：C1 `13d1628` → C2 `0548212` → C3 `62517d7` → C4 `fefab69`，`origin/codex/r4-ui` 与本机 HEAD 一致；main 仍为 `e27441b`。以上为 C5 前的已发布基点；C5 普通提交推送，最终哈希以分支引用和提交历史为准，没有使用强制推送。

## 交付状态

| 任务 | 实作 | 验收 |
| --- | --- | --- |
| C1 流程 | 五步导航、唯一主动作、逐格状态、建议确认、反应和结果、首案箭头、点击放证据 | 独立快照专用 97 项通过；按本次六项基线例外纳入提交 |
| C2 牌面 | 可选索引与回退、7:12、保存后翻牌和声音、放大牌示 | 累计专用 115 项通过；按本次六项基线例外纳入提交 |
| C3 笔记 | 灰锁与案件提示、未读红点、当前高亮、幂等已读保存 | 累计专用 164 项通过；按本次六项基线例外纳入提交 |
| C4 可读性 | CSS 按钮下限、自然宽度、顶栏图标回退、滚动弹窗、四视窗长文案检查 | 专用 9518 项通过；按本次六项基线例外纳入提交 |
| C5 网页性能 | Chrome 计时、监视器采样、配置缓存、开场预建页面、大图预热、忙碌局部更新与弹窗暂停 | 最终前台 24 次切页均 <300 ms；采样动作等待提示与首次笔记真实反馈均 <100 ms；专用 9573／0，按六项基线例外交付 |

## 文件与行为

- C1：data/ui/case_board.json；scripts/ui/case_flow.gd、case_board.gd、case_board_config.gd；scripts/divination/deduction_board.gd；scripts/core/game_state.gd；tests/ui/case_flow_clarity.gd；相关集成测试和专用运行器。来意、提问完成、翻牌完成都由明确主按钮进入下一步，已完成步骤可回看。三格盖章后提示结案；建议选中后才提交，保存成功后显示反应和结果。仅结案后的公开投影包含正确答案。
- C2：scripts/ui/case_card_art.gd、case_card_zoom.gd、panel_materials.gd，加上述牌桌配置／控件和 tests/ui/card_faces.gd。仅读取 B 线可选索引；缺文件、缺键、图片失败均回退牌名卡。牌面不沿用旧桌面压扁效果。保存失败不揭牌；保存成功后播放翻牌声并动画，减少动态设置直接显示成功结果。
- C3：data/ui/note_tabs.json；scripts/ui/note_tabs_config.gd、story_notes.gd、main.gd；GameState 的笔记公开视图；tests/ui/note_tabs.gd、note_read_receipts.gd。案件名称来自只读 rules 的 note_id 对应关系，再取公开案件标题。点击未解锁页不切页；已读回执以存档和页 ID 去重。
- C4：data/ui/readability.json；scripts/ui/readability.gd、ui_kit.gd、responsive_layout.gd、main.gd；scripts/shop/shop_screen.gd；tests/ui/no_clipped_text.gd；六张 JPG。适配只在新增、尺寸或可见性变化时注册更新，不做逐帧全树扫描。测试使用公开来意／问答／建议／证据／题目／选项的最长文案 ×1.5。
- C5：data/ui/performance.json；scripts/ui/performance_config.gd、packed_ui_data.gd、r4_performance.gd；Main／GameState 计时钩子，UI／经营静态配置加载器与场景纹理缓存，Consultation 忙碌控件和未变化肖像跳过刷新；tests/ui/web_performance.gd、tests/web/perf_server.py、summarize_perf.py 及专用套件。查询参数 r4perf=1 启用日志，另加 r4bench=1 执行自动测量；自动序列使用隔离本机测试存档，仅输出时间、计数、动作类型和成功状态。普通网页仅启用 UI 优化，不上传测量数据。

没有修改存档 schema，没有新增外部资源，没有修改剧情／牌组／人物数据、音频代码、素材、共享功能文档或发布流程。首次引导关闭和笔记已读使用既有 no-op 偏好动作的持久化幂等回执，所有保存仍先成功再发布界面结果。

## C5 最终前台性能对比（2026-11-28）

Chrome 扩展已恢复；本机 Windows、Intel Iris Xe、Godot 4.6.3 Compatibility、Chrome 158.0.8127.37。同一前台标签页、CSS 1280×551，canvas backing 1280×551；两次都核对页面 visible，并通过原生窗口状态确认选中游戏。测量期间没有本线原生测试或导出争用 CPU，未启用 r4detail。使用隔离测试存档、关闭在线对话和生成人物；九个实际保存动作、首次进入与五轮四页面、两次真实导航及首次笔记点击。所有数值均为毫秒，绘制调用数除外。

| 项目 | 改前 | 改后 |
| --- | --- | --- |
| 动作入口到保存后业务结果帧 | 9 次；中位 2985.51，P95 6534.35，最大 6534.35 | 9 次；中位 904.41，P95 1174.85，最大 1174.85 |
| 页面切换到呈现帧 | 24 次；中位 1080.26，P95 3875.07，最大 4679.97 | 24 次；中位 37.71，P95 110.36，最大 199.51 |
| 保存调用 | 9 次；中位 685.94，P95 844.39，最大 844.39 | 9 次；中位 575.08，P95 673.42，最大 673.42 |
| Godot 绘制调用数采样 | 137 次；中位 129.00，P95 189.00，最大 189.00 | 147 次；中位 127.00，P95 163.00，最大 163.00 |
| Godot TIME_PROCESS 采样 | 137 次；中位 1125.41，P95 4134.98，最大 6536.39 | 147 次；中位 112.84，P95 1009.30，最大 1166.28 |

两次真实导航从 pointerup 到呈现：改前 954.11, 957.12；改后 40.99, 25.52。九个同序列动作从处理入口到首个等待提示：改后 9 次；中位 8.57，P95 20.44，最大 20.44。这九个动作由脚本触发，不能据此推断物理输入排队时间；真实输入另测导航与笔记。

首次笔记从 pointerup 到「正在打开笔记…」提示 **13.94 ms**，到完整笔记窗口 **112.38 ms**；已解锁内容可以阅读，未读红点仍等实际回执保存成功后才清除。笔记已读动作自己的保存调用 547.91 ms，动作入口到业务结果 779.56 ms。改前首次笔记点击到保存后结果 2947.55 ms；改前没有独立等待提示计时，不能将该值冒充反馈前后同口径比较。

24 次页面切换均 <300 ms，包含首次咨询 **199.51 ms**；九个动作等待提示与首次笔记真实反馈均 <100 ms。保存后业务结果仍按上表单独报告，未宣称业务落盘也在 100 ms 内。

| 页面 | 改前样本（显示两位） | 改后样本（显示两位） |
| --- | --- | --- |
| 前台 | 1665.69, 1042.19, 975.32, 1000.03, 1070.06, 984.77, 950.49 | 86.67, 37.19, 42.20, 37.09, 41.02, 36.73, 38.23 |
| 储物柜 | 1046.81, 1074.69, 1018.61, 1123.84, 1233.98, 955.26 | 96.08, 22.80, 22.22, 19.48, 24.23, 23.77 |
| 工坊 | 1092.48, 1610.52, 1023.80, 1085.82, 1035.04 | 109.97, 25.91, 27.52, 25.70, 28.70 |
| 咨询 | 4679.97, 3422.38, 3212.38, 3875.07, 3249.30, 3524.61 | 199.51, 110.36, 97.94, 97.22, 95.54, 100.64 |

原始日志 `.tools/r4-c5-before-foreground.jsonl`（185 行，SHA256 `8beb3910de418df80192b4ac9c42e64f104e0c73846d21f2956d0d343a521c8e`）、`.tools/r4-c5-after-release.jsonl`（210 行，SHA256 `574d77fe2eea74b4cef5018cf7ae860e3498ae27e44510a57ccf9703da78eb84`），均只有一个成功完成标记、0 失败行，Chrome 两版均无脚本错误。用 `python tests/web/summarize_perf.py <日志> --output <摘要>` 重算；对九动作比较须排除笔记回执 label=set_free_question。绘制与 TIME_PROCESS 为事件后有限采样，包含笔记操作，窗口长度不同；监视器刷新值可能重复，不能视为持续 FPS 或独立帧预算。缓存保留了流程回看状态，改前重建页面与改后复用页面的最后可见步骤不同，因此末轮咨询绘制负荷也不同；不把绘制数差异全归因于优化。

改前沿用已冻结的 C4 UI 加探针构建 `.tools/r3-web/builds/preview-optimized-r4-c5-before-20261128/output`。最终构建 `.tools/r3-web/builds/preview-optimized-r4-c5-release-20261128/output`：导入、导出、包检查退出 0，站点 104555219 字节，PCK 66345248 字节。16 份运行时代码／JSON 与实际导出源逐字节一致，收据 `.tools/r4-c5-release-source-receipt.json`；源码测量后仅整理本线文档。没有触发网页发布。

| 怀疑点 | 验证和本线处理 |
| --- | --- |
| 同步保存、备份 | 计时覆盖原 SaveService 验证、文件提交和备份，未覆盖后续异步 IndexedDB 同步。scripts/save 在边界外，保持原策略；不将跨次运行的保存差值归因于存储优化。 |
| 界面树、无关刷新 | 网页开场预建四页并复用，隐藏停处理，换档销毁旧页；ShopScreen 相同视图不重建。隐藏人物页不刷新；笔记入口只填笔记，其他人物页按需填充。咨询忙碌仅改可用性；案件板可见时不合成隐藏旧对话头像，真实自由交谈仍更新。首次接待在 show_screen 已刷新后省去同帧第二次刷新，完整案件与主按钮另有断言。 |
| 大图、配置、肖像 | 场景纹理强引用预热；只缓存验证过的不可变 PCK 配置并返回独立副本，原生保留热改。已保存预约的公开外观提前准备，投影只有 npc_id 与 appearance，不包含案件事实或结局，不发送模型。 |
| 弹窗动态 | 普通模态窗口打开后暂停 SceneMotion，最后一个窗口关闭时恢复；测试检查时间确实冻结，没有单独夸大其 Chrome 收益。 |
| 保存前反馈 | 等待提示先得到一帧，再执行原保存。没有预发布候选业务状态；失败不显示结算结果，同 action_id 重试／重放不重复结算。 |

肖像预备开销没有消失：最终日志 prepare:next_guest_portrait 的原始耗时为 656.17, 1.97 ms，计入相应已保存动作的业务结果延迟。开场大图／控件预热时长与常驻内存未单列测量；没有对其他硬件作普遍保证。

此前 `.tools/r4-c5-before-final.jsonl`、`r4-c5-after-final.jsonl` 未核实原生前台选择，只作历史诊断；不再作为本表验收数据。续作首次前台确认 `.tools/r4-c5-after-foreground.jsonl` 曾记录首次咨询 608.57 ms 与笔记真实反馈 12.83 ms，保留失败样本。分段确认 `.tools/r4-c5-consult-profile.jsonl` 验证肖像已预备、隐藏历史开销接近零，同时发现咨询同帧刷新两次；去除重复后仅作上述确认，不重做 C4 JPG。

C5 最终定向 **55／0**；专用全套 **9573／0、退出 0**，日志 `.tools/r4-c5-dedup-ui-suite.log`。覆盖配置拒绝与缓存隔离、隐藏页停处理、换档销毁、模态冻结、首次已读、按需人物页、公开肖像预备、完整首次案件和可用主按钮、保存失败／同 ID 重试／重放、自由对话历史。早期夹具失败日志保留为诊断，不算通过。

规定图形集成 **1683／0**、30 张原生截图，日志 `.tools/r4-c5-resumed-shop-ui.log`。本轮已查看 `.tools/c-ui-captures/front-1280.png`（1280×720）与 `front-1920.png`（1920×1080）各一次；最后去重只作用网页刷新路径，没有重截图。既有前台来客摘要窄栏逐字换行、虽可滚动但可读性不足，仍留作已知项，没有以断言通过掩盖。C4 六张提交 JPG 保持原样。

完整原入口已实际运行，前段 75 份摘要合计 **8774／0**，含真实三路线通关 **834／0**。独立重核 lin_appearance 为 **39／1**，测试 Git blob 与原基线相同，日志 SHA256 与原基线逐字节一致；因此停止本线完整长跑，退出 1。完整入口未完成、未通过，未执行部分不作通过推断；没有修改或跳过原运行器。日志 `.tools/r4-c5-full-test-confirm.log` SHA256 `1973d005ffbc5722d77c90d5ca48d22483060ae130cd36aee165f42967dee5b4`，独立失败 `.tools/r4-c5-lin-baseline-confirm.log` SHA256 `feb496d0247e89cda5a0134db9e2d5c8a1c349af7bf89638f2e240d6b2a2b1de`。首次导入因缺失 web_wheel_pointer.gd.uid 警告退出，已保留 Godot 重建的 UI 元数据，确认运行使用原命令。六项例外的完整证据见下节。

## 测试与截图

2026-11-28 C5 最终专用运行器 **9573／0，退出 0**：流程 100、牌面 15、笔记 37、已读回执 12、文本 9354、网页事务／缓存 55，日志 `.tools/r4-c5-dedup-ui-suite.log`。规定图形集成另为 1683／0。

C5 完整入口中的真实剧情通关亦已通过 **834／0**。三条路线 best／worst／missing_key 分别报告 251／388／193 项检查，于第 7／11／7 个游戏日完成结局，另有 2 项公共检查。原始收据冻结为 `.tools/r4-c5-playthrough-receipt.json`，SHA256 `c75c584ca7f846e62c9d3aee49a32654a03448fabb4987f31edaf52fde74af8d`；不将此单项通过视为完整入口已通过。

最后一次专用运行器确认通过／失败数：C1 97／0、C2 115／0、C3 164／0、C4 9518／0，四个进程均退出 0。日志为 .tools/r4-c1-final-ui.log 至 .tools/r4-c4-final-ui.log；包含最终热点修复，没有新增截图。本次按授权依次提交推送 C1–C4；最终结果以分支引用为准。

四份历史完整入口日志的子测试检查摘要分别累计 8773／0、8773／0、8774／0、8774／0，均包含各自 834／0 的真实剧情通关；后段诊断随后发现边界外基线失败，因此停止四个仍在剧情事务段的完整运行，退出 1，未视为全绿。日志为 .tools/r4-c1-pass4-full.log 至 .tools/r4-c4-pass4-full.log；停止原因见 .tools/r4-full-cancellation.json。原文「双路线」已更正：未修改的 story_playthrough.gd 实际依序运行 best、worst、missing_key 三条路线，其旧文件头的 Two 注释未同步。

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

新增牌面放大和最终结果页覆盖后，四视窗文字审计 9354 项通过、0 失败，未生成新截图。真实剧情通关 834 项通过、0 失败。完整测试暴露的历史比较尚未计入 schema18 学习命名空间，已补齐严格预期并保留全部旧字段、原档字节及失败重试检查；三个独立迁移确认分别为 17、21、42 项通过、0 失败。

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

无新增设计项。2026-11-28 用户恢复目标并回复「继续」，本次据此继续定向修复，并将六份已确认基线失败沿用于 C5 收尾；新增失败不豁免，文件边界与保存成功后显示原则均未放宽。此前循环次数与例外适用范围的等待已解除，不再作为当前阻断。

完整原入口仍未全绿；六份边界外基线由合并者交给原维护线修复后再恢复完整验收，本次未越界改动。

## 需要其他线配合

- B 线提供约定的 data/oracle/card_art.json 和对应现有格式牌面；当前 fallback 可独立工作。音效只调用 play_ui，未知键由 B 线兼容。
- A 线替换文案后可运行本线长文案测试；本线未改五个案件原文。
- 合并者统一更新 docs/features.md、docs/codex/PROGRESS.md。

## 已知未完成

本线 C1–C5 实作与本次允许范围内的确认已完成；完整原入口仍有六项已授权基线例外，未声称全绿。前台摘要既有窄栏可读性、开场时长／常驻内存独立测量、B 线牌面索引与 A 线换文案后的整体验收留作交接。20 张 C4 截图只生成一次，其中六张普通 Git 提交，其余 14 张保留本机，不纳入 C5。

## 本阶段累计文件清单

- `data/ui/case_board.json`
- `data/ui/note_tabs.json`
- `data/ui/readability.json`
- `docs/codex/progress/R4-C.md`
- `docs/codex/review/R4-C.md`
- `docs/screenshots/round4/C/case-1280x529.jpg`
- `docs/screenshots/round4/C/case-1920x1080.jpg`
- `docs/screenshots/round4/C/front-1280x720.jpg`
- `docs/screenshots/round4/C/inventory-1280x720.jpg`
- `docs/screenshots/round4/C/notes-1280x529.jpg`
- `docs/screenshots/round4/C/settings-1920x1080.jpg`
- `scripts/core/game_state.gd`
- `scripts/dev/run-r4-ui.ps1`
- `scripts/divination/deduction_board.gd`
- `scripts/shop/scene_visual.gd`
- `scripts/shop/shop_screen.gd`
- `scripts/ui/case_board.gd`
- `scripts/ui/case_board_config.gd`
- `scripts/ui/case_card_art.gd`
- `scripts/ui/case_card_art.gd.uid`
- `scripts/ui/case_card_zoom.gd`
- `scripts/ui/case_card_zoom.gd.uid`
- `scripts/ui/case_flow.gd`
- `scripts/ui/case_flow.gd.uid`
- `scripts/ui/main.gd`
- `scripts/ui/note_tabs_config.gd`
- `scripts/ui/note_tabs_config.gd.uid`
- `scripts/ui/panel_materials.gd`
- `scripts/ui/readability.gd`
- `scripts/ui/readability.gd.uid`
- `scripts/ui/responsive_layout.gd`
- `scripts/ui/story_notes.gd`
- `scripts/ui/ui_kit.gd`
- `tests/integration/appearance_ui.gd`
- `tests/integration/arrival_transactions.gd`
- `tests/integration/arrival_ui.gd`
- `tests/integration/audio_lifecycle.gd`
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
- `tests/integration/item_visuals.gd`
- `tests/integration/lin_legacy.gd`
- `tests/integration/lin_transactions.gd`
- `tests/integration/motion_settings.gd`
- `tests/integration/music_host.gd`
- `tests/integration/names_migration.gd`
- `tests/integration/names_ui.gd`
- `tests/integration/past_lives_migration.gd`
- `tests/integration/past_lives_transactions.gd`
- `tests/integration/polish_card_choice.gd`
- `tests/integration/polish_case_materials.gd`
- `tests/integration/polish_header.gd`
- `tests/integration/polish_style.gd`
- `tests/integration/project_cleanup.gd`
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
- `tests/integration/title_presence.gd`
- `tests/integration/title_ui.gd`
- `tests/integration/traffic_activation.gd`
- `tests/suites/r4_ui.txt`
- `tests/ui/card_faces.gd`
- `tests/ui/case_flow_clarity.gd`
- `tests/ui/no_clipped_text.gd`
- `tests/ui/note_read_receipts.gd`
- `tests/ui/note_tabs.gd`

C5 本提交的文件还包括 `data/ui/performance.json`、`scripts/ui/performance_config.gd`、`packed_ui_data.gd`、`r4_performance.gd` 及对应 `.uid`、`web_wheel_pointer.gd.uid`、`consultation.gd`、`responsive_config.gd`、`shell_config.gd`、`style_config.gd`、`scripts/shop/content_ui.gd`、`item_visual.gd`、`tests/ui/web_performance.gd`、`tests/web/perf_server.py`、`summarize_perf.py`，以及前述 Main、GameState、场景显示、材料／可读性加载器、套件与两份文档的增量。未纳入额外 14 张本地 C4 JPG。
