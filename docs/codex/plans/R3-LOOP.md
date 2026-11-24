# R3-LOOP：顺序接待

用户已授权无人值守执行；实现沿用 Godot 4.6.3 / GDScript / Compatibility。目标是晨信 → 1 位案件客和 1–2 位小委托客 → 夜间结算 → 次日，无候客等待。旧实时客流保留，通过配置恢复。

## 方案与边界

采用独立 DailyLoop 模块，不重写 People 的实时导演。GameState 提交候选状态，保存成功才发布。新增 schema 10；1–9 档只在内存迁移，不重命名、不重置人物、钱包、历史动作或活动接待。R3-CASE 的推理与星数随后接入，当前沿用既有咨询与商品库存。

默认 data/daily_loop.json.enabled=true。GameState.daily_loop_config 可供旧规则测试明确关闭；关闭时原分支照常可测。配置、中文文案、人数、精力与时间均放 JSON 并校验。

## 接口

- GameState.daily_loop_view()：仅返回 enabled、phase（morning/reception/closing）、day、completed、total、next_guest（公开 name/role）、letters（已披露 name/text）、summary（stars/coins/reputation/notes/monologue）、copy。不得输出 truth、未披露事件、内部 profiles。
- 新动作 read_morning_letters、next_customer、close_shop；next_day 在顺序模式只可由 closing 进入新日。
- next_customer 在同一候选内激活唯一下一位 arrival，再复用 PeopleBridge.start。end_visit 只推进当前位，不自动开始下一位。
- 晨信复用 Events.can_report/disclose，存已披露报告；禁止伪造实体回访。旧反馈调度与后台 admission 在顺序模式关闭。
- 所有动作走 execute_action_async / _preflight / _commit，失败不显示候选，重试同 ID 不重复。

## 执行与验证

1. 第 0 步：忽略 Cozy Tunes/ 与 assets/audio/music/，确认零追踪；原样封存目标附录至 docs/story/fixed_cases.md。
2. 先新增真实行为测试，确认默认新档缺少顺序流程而失败；实现 DailyLoop、迁移、动作、保存校验及旧流开关。
3. 前台沿用纸抽屉，显示晨信/进度/结算；隐藏等待、休息、耐心与任意选客；保存后导航咨询。
4. 覆盖完整日循环、立即下一位、100 精力与低精力可继续、保存失败/重试/重放、中途载入、旧档内存迁移、晨信不泄露与效果一次结算。
5. 旧实时专测显式关闭新模式，保留历史夹具与断言；只更新当前 schema 期望。
6. 最多三轮完整 run.ps1 -Test；运行 shop_ui.gd 及 R3 双尺寸图形截图，逐张打开；只提交至多六张 JPG。
7. 更新 features、PROGRESS 与验收结果，全绿才提交 [R3-LOOP] 并普通 push codex/round3。

## 重点复核

晨信只投影已公开报告；新模式所有后台与耐心路径关闭；旧活动接待可结束；一次动作写失败不推进 cursor/日界；同 ID 重放不重复结算；新日不被时钟耗尽卡住。

## 自主决定

- 原工作区含 WEB 未提交工作，保持原样；原生工作区创建成功但 Git 无法在沙箱访问且跨盘移动失败，改在可写 D:/MagicStore/.tools/round3 建立独立工作区并重新挂接。
- LOOP 仅建立日程与节奏，完整三轮提问、翻牌、星数与固定剧情按后续任务接入。

## 最终验收（部分完成）

- 三轮标准测试：第1/2轮在确认审查问题后主动中止；第3轮exit1，已完成2858检查零失败，停于旧traffic迁移比较。原模块独立复跑101检查、1失败。
- 诊断：旧比较漏排除新增daily_loop；真实加载探针显示仅新增该键，移除后历史字段全等、原档字节不变。按三轮上限不再重跑本任务，随R3-CASE schema兼容修夹具并整体复核。
- 核心103/103、迁移/模式98/98、独立guards57/57、七天最终66/66、独审49/49；UI110/110、GPU116/116六帧；旧shop GPU1544/1544三十帧。所有专项不替代标准全套。
- 正式证据 results/R3-LOOP-validation.json；六JPG位于 docs/screenshots/round3/R3-LOOP，共1,644,303B，全部逐张打开。
- 已知后续：星数/笔记奖励由CASE/STORY接入，非首日主案暂沿用archive，小委托使用原购物；当前不声称五案通关。
