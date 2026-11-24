# R3-STORY：五个固定案件与笔记结局

依据 `docs/story/fixed_cases.md` 原文，不修改附录。CASE 完整回归期间只在 `.tools/r3-story/drafts` 准备隔离草稿；CASE 提交后才应用生产改动。每个任务仍独立提交，main与原WEB工作区不动。

## 实现契约

沿用现有G3事件与CASE推理板，新建四个固定案JSON，加四页笔记、固定/相关人物、时间线及剧情对白配置。`fixed_invitation.json`及原invitation事实/事件/反馈/推荐保持原样与原hash；装订伏笔通过单独公开剧情陈述追加。新固定NPC使用既有A4部件固定组合，地域字段与旧origin来源字段分开；林照晚的正式改形象留给LIN。

`StoryContent.install(catalog)`在原目录装好牌组后安装新clue、完整G3模板和guest。所有新JSON分别校验，数据损坏返回非空错误。`CaseSchema.g3_case_id(definition)`以非空legacy_case_id或definition.id统一对应关系；模板补齐安全topic、question/default_question/method_ids，不借generated标志，不改旧档世界事实。

新增schema12的`story`只存实际使用的完成来源、笔记解锁、公开片段、前奏选择和延迟结局/尾声收据，不复制真相。旧CASE迁移明确落到11后再迁12；加载只加内存字段，下一成功动作才写。既有schema11闭合邀请板可按真实来源登记案1，不造旧案板或奖励。旧人物不在加载时批量注入；下一次日程/接待事务才ensure。

每日仍1案件+1至2小委托：第1天林，第2天面包，第3天钥匙（案2已结），第4天八音盒，第6天起案2/4任意星数已结后晴川；超出优先窗口保留积压，不永久错过。报警线索延迟一天，默认最差线在第7天雨夜进入案5。首次可用的新日程设雨，接待动作直接推进到配置夜时，不等待，也不改已保存天气。严格验证story预约来源、人物、案件、日期与序号。

案5开始显示保存后的前奏：缺案3可去沈家取信，同时以该信来源补笔记2而不伪造案3完成；林信任≥2可请她修复，否则自拼时多一次可免费重试的纸片顺序选择。不得声称低信任时林已经说过话。前奏未完成时后端拒绝案件操作，完成后使用原三格。唯一新增UI动作`story_choice(choice_id)`，不接受客户端星数、信任、解锁或正确性。

案2/3/4后果均保留原文，目标顾家信任用明确目标的剧情收据处理。笔记1初始，2案3或补取信，3案4，4真实重逢。电话/直接赴约为各自结局，写信路线在3天后才真正重逢，期间状态仍等待；三线均不悲剧。之后五位人物按小委托位置分日短访，用已公开固定事实，不依赖联网模型。陶书宁作为稳定普通回访人物。

原文差路线例外：八音盒accuse的第三页与半封信须等江远舟的真实补信report已披露再取得；其他分支仍闭案取得。该门槛配置于defer_disclosure_advice_ids，核心验证时间戳及来源，不能靠UI遮挡提前发放。历史中断的Tao/五人短访保留原行，可重新排一次有效预约；有效唯一性按真实已接待与当前名单判断。

## 文件归属与公共接口

- 数据：`data/cases/*`、`data/story/*`、`story_content.gd`、`case_schema.gd`、`catalog.gd`及数据测试。
- 剧情核心：`story_progress.gd`、Session/Board/CaseSave/CaseView及规则/事务测试。
- UI：CaseBoard/consultation/main/PeoplePanel、UI JSON、UI与录像测试。
- root：GameState、DailyLoop、People/Bridge、SaveService版本与验证接线、旧夹具兼容、run.ps1、文档、完整回归/审查/截图/提交。

`GameState.story_view()`仅返回公开进度、已解锁页正文和结局状态；锁页只给页码与通用锁定文案。`case_board_view()`追加`story_lines`与`prelude:{id,text,options:[{id,text,enabled,reason}],blocks_progress}`。UI不直接读取story私有字段。

## 验证与交付

先用新存档最佳/最差真实动作各通关至案5结局，断言每案星数、全部4页笔记、原invitation金样本及npc_lin_friend推荐；差路线一星也继续。另验缺案3、信任两侧、写信三日、雨夜、重载/保存失败/同ID重放不重复。每个JSON坏字段拒绝，旧档原字节与旧身份保持。

双尺寸截图实际检查案2、案5前奏和笔记/结局；20–40秒真实操作录像仅本地，提交其中3关键帧，任务JPG总数≤6。运行shop_ui实窗及标准`run.ps1 -Test`，最多3轮。好玩度检查即时反馈、至少两类判断、错选后果、无输入与无等待，真人阅读时长未实测时明确记录估计范围。独立审查后按实际证据更新features/PROGRESS/审阅包并普通推送codex/round3。

## 当前集成证据

CASE已partial提交ab7a220、META cd78da5普通推送，STORY40文件经三方SHA后应用。原始生产RED1/1；生产导入无ERROR；真实旧CASE11 fixture38768B迁移39/39，自由提问追问的公共投影/visit/action结果/磁盘及失败重试25/25。隔离初稳定三路线559/559早于两项独审修复；修后积压139/139、完整worst/三日/五短访事务295/295。正式生产三路已550/550、源SHA保持，最佳第7天、最差真实写信第11天结局；六份合法阶段存档逐SHA交接UI，未直接改state造画面。GPU/录像及标准全测仍待终态。

CASE最后HTTP断言失败另已确定首帧HTTPRequest内部Timer误扣启动前的raw process step；本任务集成兼容修复保持原绝对总预算，用单调时钟守卫及完整cleanup，新增冷启动/无回调/cancel/dispose回归。正式冷启动RED、dispose重入RED之后，最终原标准HTTP wrapper786/786、0ERROR；原预算和原四测试SHA不变，独审无遗留Critical/Important。此专项成绩不替代本任务后续完整测试。

## 最终验收

最后完整第3轮已exit0，2835.688秒，360源SHA保持：17878报告检查及117+254 Python测试零失败，formal364记录/367文件和alpha70另通过。前两轮仅修旧测试的健康Catalog前置与精确作者目录假设，拒绝、无原型泄漏及历史保持断言完整保留；无full4。

实际双尺寸244/244六PNG、shop1548/1548三十PNG，原生1920×1080影片81/81、1058帧/30fps/35.2667秒；六quality85 JPG共1192972B，其中三个实际录像帧90/650/880，全部实开。产品独审最终0C/0I/0Minor。三路独立生产550/550与完整轮内560/560分开记，均四页齐全、差线可团聚；真人阅读时长/听觉仍待人工。65文件清单与逐组证据在results/R3-STORY-validation.json。普通提交并push后按原序继续LIN。
