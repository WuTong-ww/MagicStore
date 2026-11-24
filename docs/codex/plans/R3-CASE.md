# R3-CASE：按钮提问、牌示与推理板

用户授权无人值守实施。前置 LOOP 已以 89b7334（部分完成）和 0667a49 推送 origin/codex/round3；默认日程、迁移、图形专项通过，标准第三轮只有旧 traffic 历史比较漏排 daily_loop 而失败。此任务先补该兼容夹具，再随新 schema 完整复核。

## 目标与方案

沿用咨询室整幅底图、沙发遮罩和 A4 头像，在上方叠纸面推理板；默认不要求打字。一次案件三轮按钮问答、五张牌选三张、三个推理格、两至三个建议；错误推理继续产生后果。保留现有五类记录和 G3 invitation 真相、事件、反馈、npc_lin_friend 推荐规则。第一份案件为 fixed_invitation；其余固定剧情由下一任务加入同一格式。

数据/规则/UI 三路独立实现，root 拥有 GameState 与旧测试兼容。美术优先复用现有牌背和装饰图，其余牌面用 Godot 控件画装饰并动态叠名字，禁止把数字与文字烘入图。牌桌按可用视窗高度缩放，1280×720 与1920×1080可用。

## 共享接口（实现前先定）

- `CaseSchema.load_all(catalog: Dictionary) -> Dictionary`：以 id 索引已验证定义。`validate_definition(value: Variant, catalog: Dictionary) -> bool`。固定/备用/以后 AI 共用。
- 定义字段：id/version/legacy_case_id/question/truth、deduction_slots[3]（id/title/answers[3–4]{id,text}/correct_answer/unlock_evidence）、questions[3][3]（id/text/answer/evidence_ids/requires_familiarity/legacy_topic_id 可选）、evidence[6]（id/text/type/slot_ids/legacy_clue_ids 可选）、cards[5]（deck_id/text/slot_id）、advice[2–3]（id/text/requires_deductions/legacy_advice_key/reaction/mood）、outcomes（完整 G3 event 规则），数值/文案/UI copy 全在 data/。
- 三轮中的每一轮至少一个零熟悉度可用问题，任何基础路径均有相关材料解锁三个推理格；证词/误导不升级成世界事实。公共投影不标出“误导”，只显示其证词来源。牌示是独立 tool_clues。
- `DeductionBoard.create(state, visit, definition) -> Dictionary`，私有状态放 case.board：definition_id/version/hash、phase（questions/cards/deduction/closed）、round、questions_asked、evidence_ids、tool_clues、card_order、flipped_indices、attachments、answers、eliminations、extra_question_used、closure。`handle(state,visit,case,action,data,definitions)` 返回 success/message/result/minutes。
- `GameState.case_board_view() -> Dictionary`：当前案件公共投影，disabled 时 `{enabled:false}`。启用时 enabled/id/title/question/phase/round/questions（id,text,enabled,reason）/evidence（id,text,kind,slot_ids）/cards（index,revealed，翻开后才有deck_id/name/text/image）/slots（id,title,unlocked,candidates{id,text,enabled},selected,attached_ids）/advice（id,text,enabled）/can_extra_question/can_eliminate/closed/stars/reaction/copy。不得包含 truth、correct_answer、未翻牌身份、私有世界结果。slots 的 slot_ids/候选不得透露正确性。
- 动作：case_question(question_id)、case_extra_question(question_id)、case_flip_card(card_index)、case_attach_evidence(evidence_id,slot_id)、case_choose_answer(slot_id,answer_id)、case_eliminate(slot_id)、case_close(advice_id)。全部经 GameState.execute_action_async，成功保存后动画；客户端不提交星数或正确性。
- 三次基础翻牌免费精力但每次10分钟；额外牌10精力且需雷诺曼；梅花可排除一个错误候选。三轮提问各5精力/5分钟；一次再问10精力。精力不足仍能基本问答，不跨日卡死。时间/次数/效果配置化。
- 牌序首次创建后保存；同ID、不同ID重复同张、重载不重抽。相关材料挂入后解锁候选；选答保存在玩家假设渠道，结案前可改。
- case_close 在一个 candidate 内以已完成推理写入合法 G3 prediction 与 advice、case.stars=max(1,正确格数)、反应对话与mood，不伪造付费服务。允许完整board作为预测的明确替代前置。星数仅由后端计算；延迟后果仍由 Events 和晨信处理。
- `CaseView.project()` 可附 board，但 UI 用专门白名单 getter；启用设置“自由提问”默认false，在咨询区显示旧对话输入，推理板继续可用。设置内容存档且经动作提交。
- schema 11：新板与自由提问设置；旧案 board={} 保持旧界面，不重算既有事件或重发奖励。旧存档内存迁移，下一成功动作才写盘。引入 SaveService.CURRENT_SCHEMA 作为当前版本断言来源，保留历史 fixture 版本常量。

## 分工

1. 数据 owner：case_schema.gd、data/cases/index.json、fixed_invitation.json、data/cases/rules.json 与各自校验/数据测试。明确最后 shared JSON 形状并通知 core/UI。G3 invocation 对象保持原样，invitation三个建议映射 message/attend/wait。
2. 核心 owner：deduction_board.gd、session.gd、case_view.gd、case_save.gd、save_service.gd、必要 past_lines 上限、核心三分支/迁移/失败重试/投影隐私测试。不要编辑 GameState/UI/data owner 文件。
3. UI owner：case_board.gd、data/ui/case_board.json、consultation.gd 挂载与默认隐藏输入、main.gd 设置入口与成功后反应，必要 drag token/slot 子控件、UI测试与截图/录像harness。与 core 仅通过上述 getter/action 契约。
4. root：GameState加载/新动作/迁移/公共getter/设置接线、旧 schema 夹具的 additive 比较修正、旧测试当前版本常量、run.ps1新测试入口、docs、全测/独审/录像/JPG/提交推送。

## 验证与风险

先跑真实 RED 再实现。三建议分支实际走完：最佳消息 sent、确认入口后赴约 arrived、等待 waited，原 G3 金样本仍全过；全错选答也能结案、1星继续。检查所有新动作保存失败无候选泄漏、同ID重试/重放不重复、旧档原字节不写、牌序重载一致、看板不含答案/未公开事实。

测试三轮基础问题可完成、低精力可继续、三牌与技能额外牌上限、材料错误目标反馈、改选、非法 ID/越权阶段拒绝。图形脚本双尺寸逐张开；20–40秒操作录像保留在.tools，仅提交3张关键帧JPG，总截图不超过6张。自评即时视听反馈、无输入等待、至少两类判断、错误仍有后果，3–6分钟人类阅读与决策节奏；脚本快路径不能冒称人工时长实测。

最多三轮标准完整 run.ps1 -Test。LOOP旧比较兼容修正必须包括当前所有新增namespace，继续验证全部历史字段和原字节，不能删减断言。全部结果如实记入 REVIEW_PACKET_R3，完整通过后重新核定 LOOP状态。

## 实际收口

功能、三建议、低精力/截止、保存重试/重放、迁移及双尺寸均已实现并专项验证。独立复审Critical0/Important0/Minor0；六JPG1594709B、本地31.8667秒真实操作录像，详见results/R3-CASE-validation.json。标准第1轮在旧fixture覆写原invitation事件时失败，仅改独立测试case承载临时规则；第2轮15716报告检查零失败后被沙箱localhost权限拒绝；第3轮获受控提权，326源文件未变，15796报告检查/2失败，止于HTTP core真实reply/online模式断言。原协议专项曾全部通过，不能替代标准失败。按目标三轮上限记部分完成，禁止full4，提交后继续STORY并在下次集成全测复核。恢复原OFL许可LF字节及精确路径-text，未改变授权内容/登记SHA。
