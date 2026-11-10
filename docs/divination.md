# B 组交接 · 问卜、术式和事件

本模块基于 Godot 原型。费用、时长、人物与案例文案使用联调配置。各术式按下列规则取牌、起课或排盘，再把所得牌面、卦象或宫位转成可追问的案例提示。

| 术式 | 规则与输入 |
| --- | --- |
| 塔罗 | 78 张韦特体系牌，三张不放回，逐张确定正逆位。可选「过去的影响、现在的处境、可能的发展」或「处境、阻碍、建议」。按图像、牌位和正逆位推想。牌面参考 [韦特原著中的史密斯插图](https://en.wikisource.org/wiki/Pictorial_Key_to_the_Tarot)，解读为游戏原创。 |
| 雷诺曼 | 36 张 Petit Lenormand，随机双牌或三牌线。双牌按主牌与修饰读，三牌线读中心牌与左右相邻组合。[Rana George 牌册](https://www.usgamesinc.com/files/attachments/1326/RGL42_book.pdf) |
| 梅花易数 | 年月日時法按农历年支、月、日、时取上下卦和动爻。物数法以物数取上卦、时支数取下卦，两数合取动爻。按动爻所在卦分体用，并列互卦与变卦。[《梅花易数》卷一](https://zh.wikisource.org/zh-hant/%E6%A2%85%E8%8A%B1%E6%98%93) |
| 易经 | 三枚钱正反各按 3、2 计，六掷自下而上。6、7、8、9 分别为老阴、少阳、少阴、老阳。老阴老阳翻转组成变卦，64 卦采用通行卦序和自写提示。[三钱起卦说明](https://www2.kenyon.edu/Depts/Religion/Fac/Adler/Reln270/hexagrams-consulting.pdf) · [《周易》卦序](https://ctext.org/book-of-changes/yi-jing/zhs) |
| 小六壬 | 从大安起正月，农历月上起日、日上起时，记录月、日、时三次落宫。选巳、未、酉三个短期时点，用案例约见日或当前店铺日期起课。[《玉匣记》所录六壬时课](https://x.8s8s.com/shengxiao/23/15179.html) |
| 现代占星 | 读取出生时刻、时区和经纬度，算热带黄道本命盘、上升与整宫宫位。比较报价后第 30 或 90 天同一时刻的日月和八个行星点，取合、六合、刑、拱、冲五种相位中偏差在 3° 内的最近三组。[整宫制](https://www.astro.com/astrology/in_house1_e.htm) · [JPL 行星近似位置](https://ssd.jpl.nasa.gov/planets/approx_pos.html) · [月亮摄动和冥王星近似](https://stjarnhimlen.se/comp/ppcomp.html) |
| 八字 | 立春换年、交节换月，晚子时算次日。用出生地标准时间排年月日时四柱，按日主取十神，显示所选柱藏干和流年地支的六合或六冲。[四柱计算参考](https://github.com/6tail/lunar-python/blob/master/lunar_python/Lunar.py) |
| 紫微斗数 | 用农历生年月日时安命身宫，命宫干支定五行局，按农历生日安紫微与天府两系十四主星。加入昌曲辅弼以排四化。流年以太岁支起流年命宫，按年干起四化。闰月上半月按本月、下半月按次月，晚子时算次日。[命身宫与五行局](https://github.com/SylarLong/iztro/blob/main/src/astro/palace.ts) · [十四主星](https://github.com/SylarLong/iztro/blob/main/src/star/majorStar.ts) |
| 前世技法 | 游戏叙事术式。旧物是初见媒介，独立证物决定能否核实猜测。 |

店铺历表从 2026-11-10 开始，使用 UTC+08:00。农历月首表由 `scripts/dev/generate-lunar-calendar.ps1` 离线生成。出生日期及行运日期支持 1902–2050。节气使用太阳视黄经近似计算，星盘使用上述近似星历，临近交节或宫位边界时可能与专业排盘有差异。[.NET 中国农历](https://learn.microsoft.com/en-us/dotnet/api/system.globalization.chineselunisolarcalendar?view=net-10.0) · [太阳位置计算](https://gml.noaa.gov/grad/solcalc/calcdetails.html)

## 接入边界

| 环节 | 契约 |
| --- | --- |
| A 给 B | 在接待候选上调用 `DivinationSession.add_case(state, visit, case_id, schedule_event, context)`。可给 `context.public_npc`（`name`、`role`）、`profile_id`、`subject_id`、`target_name` 和 `chart`。出生资料使用本地 `birth`（如 `1996-03-14T06:40`）和 `utc_offset_minutes`（如 `480`）。占星另需 `latitude`、`longitude`，可给 `birthplace` 供显示。通过话题授权后可见。B 用稳定人物 ID 保存前世进度，A 维护来店频率、人物生成、关系和记忆。 |
| A 的对话候选 | 现有 `talk` 请求增加 `case_id`、`allowed_intents`、`allowed_clue_ids`、`allowed_branch_ids` 和按意图分组的 `allowed_effects`。按钮可额外传 `topic_id`。返回仍用 `intent`、`clue_ids`、`reply_text`，可附 `branch_id`。GameState 按当前案例与前置校验，并以 `action_id` 关联有效记录。 |
| C 给 B | 共享时钟、已学术式、钱包、物品账、交易和使用记录。联调版用本地适配层验证这些字段。正式接入时由 C 替换结算与学习实现，复用 B 的报价、术式结果和案例条件。 |
| B 给 A | `divination_feedback_queue()` 提供到期事件、最早可反馈分钟、披露模式和可披露内容。A 排定实际回访，匹配来客后用 `receive_feedback` 披露。 |
| B 给 A/C | `divination_effects("A")` 或 `divination_effects("C")` 返回按接收方分开的持久建议。接收方按 `effect_id` 去重，保留 `event_id`、`visit_id`、`prediction_id` 和 `npc_id`，按有效期应用。 |
| B 和 C 的商品联动 | `divination_demands()` 提供 `demand_id`、`event_id`、`effect_key`、`deadline` 及产生需求的建议。C 在库存事务候选上调用 `DivinationSession.link_item_use(state, visit, item_use)`，传 `event_id`、`effect_key`、`item_use_id`、`item_id` 和 `transaction_id`。匹配案例且在事件时点前才能记录，B 在判定结果时读取实际使用。 |

UI 通过 `player_snapshot()` 和 `divination_view()` 读取可见数据。完整 `snapshot()` 是引擎及测试入口。隐藏世界事实、未披露事件结果和前世标准答案留在本地规则层，不进入对话请求或玩家手记。

## 动作与存档

所有动作沿用 `action_id`、`expected_version` 及写盘成功后才发布状态的约定。报价和付款绑定稳定的 `service_id` 与接待。失败时可重试同一报价，已完成服务按该 ID 重看原结果。兼容入口 `reading` 返回本次接待首次塔罗服务的已存结果。

新结果保存 `medium`（实际牌阵、钱面、卦象、落课或盘面）及 `signals`（主题、方向、原始来源和追问）。每项报价绑定案例中的 `question_id`，提示按所问生成。塔罗和雷诺曼额外保存当时已发现的相关线索和逐牌推想（`inquiry`）。玩家可以把自己的解释记成待验证假设，也可另行提交正式预测。重看保留当时的原记录。

同一顾客、案例和问题的提示一起参加手记对照。玩家可以用一种术式，也可以在每次结算后继续为同一题选其他术式。费用、精力和时间逐项结算。旧档中没有绑定问句的记录归入案例主问题。重复主题可出现同向或不同提示，案情由玩家结合材料核实。

| 动作 | 输入 |
| --- | --- |
| `quote_service` | `method_id`、`option_id`、`payment`（`coins` 或 `item`），部分术式接收整数 `parameter`。可传本案 `question_id`，省略时使用主问题。 |
| `settle_service` / `cancel_service` | `service_id`。 |
| `learn_method` | `method_id`。 |
| `note_hypothesis` | `text`；保存当时可见的线索引用。 |
| `record_prediction` | `text`、`subject_id`、`expected`（`met` 或 `missed`）、`condition`、`window_start`、`window_end`。同一事件保留一次正式预测。 |
| `give_advice` | `advice_key`，记录原话、接受与否；到期另记实际行动。 |
| `buy_case_item` / `use_case_item` | 联调商品交易和使用。使用引用同一笔交易，须在事件前进行。 |
| `receive_feedback` | `event_id`，核对当前接待人物、最早反馈时间和披露许可。 |
| `interpret_past` / `verify_past` | 前者传 `link_id` 与可选 `text`，后者传 `interpretation_id`。验证需要补充片段。 |

新版存档使用 `schema_version = 2`。读 v1 时只在内存初始化 B 数据，保留原接待、人物金币、资源、时钟、历史及原牌面。下一次成功业务动作才写 v2，v1 备份仍可恢复。旧接待没有追溯生成的预测、反馈或前世记录。

## Windows 试玩与复跑

从根目录运行 `start-game.cmd`，新建独立店铺。在前台选择案例。在「塔罗报价」或「全部术式」里先选问题，再选术式、操作及报酬。结算后可用「继续为这题选术式」增加解读，也可查看案例手记。解读页先讲看到什么、可以怎么想和接下来能核对什么。用「展开术语和规则」查看原始记录。前台「术式研习」列出学习成本和前置，休息或次日恢复精力。进阶盘面先在咨询区「征求出生资料」。

| 验收 | 可复跑路线 |
| --- | --- |
| B1 · 通过 | 林照晚邀请案点「邀请上写了什么」，再自由输入「核对侧门」。查看手记中的来源、线索和分支。完成一次金币三牌塔罗，再用书签支付另一项服务。中断或读档后可继续待收款报价并重看已结算的三张牌。 |
| B2 · 通过 | 对照开场猜测与邀请附言核实的事实。用「案情与线索」保存假设，再在「预测与建议」提交一次对外预测，检查对象、条件、时段和原话。没有回信线索时，照晚会拒绝先发消息的建议。 |
| B3 · 通过 | 完成塔罗后结束接待，从前台研习雷诺曼。次日再接待照晚，使用「三张牌排成一行」，然后打开「案例手记 → 案情与线索 → 跨术式对照」。查看提示后可展开「对照来源」。进阶术式先授权出生资料，再按界面选日期、出生时间或主题。 |
| B4 · 通过 | 预测「约见时段会说上话」。询问回信后建议先发消息，结束接待并打烊，次日请照晚回来，在案例手记听取反馈。另开档试「暂缓赴约」可见偏离及复盘。「把信留给前台」会延期且证据不足，第三天可听取。「侧厅私下聊」可发生但不会披露。选择直接赴约时，核对侧门或记录用香均可改变结果。 |
| B5 · 通过 | 学会易经和前世技法，在前台选「林照晚 · 旧物案」或普通、参考来客样例。问旧物后选择「看旧物里的片段」，再去前世手记选自己的解释。回术式选择「去旧档找证物」，取得材料后亲自核实。可先用不正确的解释看反证，也可结束接待后在下一天重新来访核实。 |

邀请案按游戏时钟判定。采纳的建议与实际行动各自留档。预约时点已过时，玩家手记只显示等待反馈，收到来客披露后才显示证据与评估。联调赠礼进入本地物品账，信任、转介绍、口碑、复盘成长和限时客流提供带引用的建议给 A/C。

`powershell -NoProfile -ExecutionPolicy Bypass -File scripts/dev/run.ps1 -Test` 运行 B1–B5 隔离存档、原型与 provider 回归、游戏界面操作和两进程续档。图形检查可用固定引擎执行 `--path . --script res://tests/ui_capture.gd`，截图写入 `.tools/ui-captures/`。测试均使用独立存档目录。

术式规则验证包括观梅占、小六壬落宫、四柱立春、紫微安星示例，以及抽牌不重复、同一服务重看和跨术式提示来源。

当前版本通过完整 `-Test`、29 项术式规则核验与两进程续档。Windows 图形验收通过 333 项检查，覆盖九项术式的白话解读、规则折叠、玩家判断及同题加选和对照。
