# 第二轮最终审阅包

2026-11-24，`codex/round2-clean`。11项任务均已处理，CLEAN基线另列。功能、标准测试、实际GUI、人工画面与严格性能分别报告，跨轮／重复目标不累加。G5/G6全绿不追认G4或旧GUI／性能失败为绿。main、旧round2与backup不改写；二进制普通Git，无LFS。

请用[start-game.cmd](D:/MagicStore/start-game.cmd)运行当前源码；`build/windows`旧EXE／zip仍为11月6日版本。来源为各正式results、[PROGRESS](D:/MagicStore/docs/codex/PROGRESS.md)、[UPLOAD_STATUS](D:/MagicStore/docs/codex/UPLOAD_STATUS.md)及计划末尾终态。本包只汇总既有审查，不重新评分，headless／SKIP不代替GPU。

## 1. 总览表

|任务|状态|任务提交|最终标准通过／总数|截图目录|
|---|---|---|---|---|
|CLEAN|完成|`1878b6c／135c26f`|7739/7739，exit0|[A3R](D:/MagicStore/docs/screenshots/round2/A3R)|
|G3|完成，保留入clean|`1878b6c`|恢复7332/7332；clean7739/7739|[G3](D:/MagicStore/docs/screenshots/round2/G3)|
|A3R|部分完成|`7f7a8c3`|8077/8077，第2轮exit0|[A3R](D:/MagicStore/docs/screenshots/round2/A3R)|
|A1R|部分完成|`059baeb`|8362/8362，第3轮exit0|[A1R](D:/MagicStore/docs/screenshots/round2/A1R)|
|A2R|部分完成|`2773499`|8555/8555，第1轮exit0|[A2R](D:/MagicStore/docs/screenshots/round2/A2R)|
|A7|自身专项过，整体部分完成|`c2c37eb`|9154/9154，第2轮exit0|[A7](D:/MagicStore/docs/screenshots/round2/A7)|
|A6|部分完成|`fb43344`|9653/9653，第3轮exit0|[A6](D:/MagicStore/docs/screenshots/round2/A6)|
|A4|部分完成|`f2e0d13`|10278/10278，第3轮exit0|[A4](D:/MagicStore/docs/screenshots/round2/A4)|
|G2|部分完成|`5297418`|11252/11252，第2轮exit0|[G2](D:/MagicStore/docs/screenshots/round2/G2)|
|G4|部分完成|`ea6a4f8`|三轮exit1，未全绿|[G4](D:/MagicStore/docs/screenshots/round2/G4)|
|G5|部分完成，已推送|`888a15d`|14533/14533，第3轮exit0|[G5](D:/MagicStore/docs/screenshots/round2/G5)|
|G6|部分完成，已推送|`94586d1`|15504/15504，第1轮exit0|[G6](D:/MagicStore/docs/screenshots/round2/G6)|

G3原恢复提交`4789a5b`仅作历史脚注，表用clean实际保留提交；[转换记录](D:/MagicStore/docs/codex/results/ordinary-upload-conversion.json)可追。G5 META `df7381f`不代替任务`888a15d`。G6任务`94586d1`已普通Git推送，远端与任务HEAD一致；最终审阅包另作纯文本收口提交。

## 2. 每任务：做了什么、最后未过与关键图

### CLEAN

- 从main重建干净历史，保留已验A3R/G3与正式v2/runtime、字体音效，拒图／加工物隔离。
- 保留分层／再生工具，正式紧凑metadata与本地详审分开；56个v2 SHA保持。
- shell1383/1383（17帧）＋shop718/718（22唯一帧），39帧清理矩阵已审。

**最后未过／范围：**3个退役本地审计缺失明确SKIP；清理通过不签v3艺术。截图沿用原任务。

**关键图：**[front-1280x720](D:/MagicStore/docs/screenshots/round2/A3R/front-1280x720.jpg)；[verified-1920x1080](D:/MagicStore/docs/screenshots/round2/G3/verified-1920x1080.jpg)。

证据：[CLEAN-tools-test-summary.json](D:/MagicStore/docs/codex/results/CLEAN-tools-test-summary.json)。

### G3

- 修邀请推荐／事件反馈兼容，黄金22/22；陈述、线索、预测和真实NPC报告保留来源。
- 失败保存／同action_id重试不重复结算，旧档兼容；修Ogg/Mixer退出弱引用释放。
- 手记70/70（4帧）＋shop718/718（23写），恢复标准7332通过，clean另复验。

**最后未过／范围：**旧标题对比度／当时v2美术是历史共享小项，不沿用更早LFS阻断为恢复终态。

**关键图：**[pending-1280x720](D:/MagicStore/docs/screenshots/round2/G3/pending-1280x720.jpg)；[verified-1920x1080](D:/MagicStore/docs/screenshots/round2/G3/verified-1920x1080.jpg)。

证据：[G3-recovery-tests.txt](D:/MagicStore/docs/codex/results/G3-recovery-tests.txt)。

### A3R

- 修顶栏纸牌、按钮文字、手记真点击和咨询构图；cover与四窗口尺寸已验。
- shell1383/1383（17）＋手记140/140（12）＋shop718/718（22）。
- 51原图＋10JPG已审；最后people两张改字重拍，其余20张shop按真实SHA继承。

**最后未过／范围：**音乐、纸纹／角花未齐；库存／slot／头像旧依赖后来由A2R/A7/A4推进。

**关键图：**[front-1280x720](D:/MagicStore/docs/screenshots/round2/A3R/front-1280x720.jpg)；[front-2560x1080](D:/MagicStore/docs/screenshots/round2/A3R/front-2560x1080.jpg)；[consultation-active-1920x1080](D:/MagicStore/docs/screenshots/round2/A3R/consultation-active-1920x1080.jpg)；[notebook-open-1280x720](D:/MagicStore/docs/screenshots/round2/A3R/notebook-open-1280x720.jpg)。

证据：[A3R-tail-test-summary.json](D:/MagicStore/docs/codex/results/A3R-tail-test-summary.json)。

### A1R

- S02定调后形成17态v3 C，native1672×941，1920×1080为派生。
- 真实mask／补底／单层验收，仅S03沙发、S04闭门、S07水域昼夜共6Li正式，余层静态C。
- 59正式PNG来源与再生链验收；production1502/1502（34）＋shop718/718（22），62帧人工259/310。

**最后未过／范围：**C评分165/170不签全部Li。前台植物／铃／帘等缺层，1099中间证据本地保留。

**关键图：**[s02-before-v2-1280](D:/MagicStore/docs/screenshots/round2/A1R/s02-before-v2-1280.jpg)；[s02-v3-day-1280](D:/MagicStore/docs/screenshots/round2/A1R/s02-v3-day-1280.jpg)；[s03-v3-night-1920](D:/MagicStore/docs/screenshots/round2/A1R/s03-v3-night-1920.jpg)；[s04-v3-closed-night-1280](D:/MagicStore/docs/screenshots/round2/A1R/s04-v3-closed-night-1280.jpg)。

证据：[A1R-v3-validation.json](D:/MagicStore/docs/codex/results/A1R-v3-validation.json)。

### A2R

- 九件真实新图经magenta／alpha／底宽support加工256→64共18PNG，未复用拒绝绘本。
- ItemVisual独立映射，修三尺寸角标／paste元数据；正式源强验SHA／尺寸／alpha／support。
- 对照255/255（16）＋shop718/718（22），44帧人工203/220；9件88/90，14真实调用。

**最后未过／范围：**书签／树脂小图识别弱。仅指定incoming raw缺失可明确SKIP，现存坏raw／正式缺文件仍失败。

**关键图：**[items-64-1280](D:/MagicStore/docs/screenshots/round2/A2R/items-64-1280.jpg)；[items-128-1920](D:/MagicStore/docs/screenshots/round2/A2R/items-128-1920.jpg)；[items-256-1920](D:/MagicStore/docs/screenshots/round2/A2R/items-256-1920.jpg)；[market-v3-1920](D:/MagicStore/docs/screenshots/round2/A2R/market-v3-1920.jpg)。

证据：[A2R-v3-validation.json](D:/MagicStore/docs/codex/results/A2R-v3-validation.json)。

### A7

- 原生层板替代木箱slot，统一crop投影、底部支点／微旋／接触阴影／程序纸纹。
- hover纸签、点击上提、堆叠／数量纸条／resize命中；保存后信号去重，关柜隐藏。
- shelf940/940（19）＋shop710/710（22），47帧人工225/235；另12组200%接触诊断过。

**最后未过／范围：**0/1/9/30是render-only压力样本，不保存假库存；当时旧人物／装饰跨任务项未过。

**关键图：**[empty-night-1280](D:/MagicStore/docs/screenshots/round2/A7/empty-night-1280.jpg)；[nine-day-1920](D:/MagicStore/docs/screenshots/round2/A7/nine-day-1920.jpg)；[thirty-night-1920](D:/MagicStore/docs/screenshots/round2/A7/thirty-night-1920.jpg)；[shelf-lines-F3-1920](D:/MagicStore/docs/screenshots/round2/A7/shelf-lines-F3-1920.jpg)。

证据：[A7-validation.json](D:/MagicStore/docs/codex/results/A7-validation.json)。

### A6

- 确定风场／Spring／支点sway／流水及货架反应接保存后事件；静态门／沙发零旋转，不摇C。
- 流水双相同向scroll与岸环保护；正式4pair＋8无shader controls过，alpha／羽化保持。
- 偏好回滚／可选铃音drain已验；preview508/508、34PNG与已审轮SHA相同，shop710/710，53帧人工245/265。

**最后未过／范围：**前台Li、生产铃音／粒子区缺；严格perf最终70项1fail，不能由9653或固定帧录像覆盖。

**关键图：**[front-day1920](D:/MagicStore/docs/screenshots/round2/A6/front-day1920.jpg)；[water-day1280](D:/MagicStore/docs/screenshots/round2/A6/water-day1280.jpg)；[water-night1920](D:/MagicStore/docs/screenshots/round2/A6/water-night1920.jpg)；[settings-reduced1280](D:/MagicStore/docs/screenshots/round2/A6/settings-reduced1280.jpg)。

证据：[A6-validation.json](D:/MagicStore/docs/codex/results/A6-validation.json)。

### A4

- 139部件＋人台、十层gradient-map／五态／有限缓存／本地捏脸，schema6；林preset独立。
- 只取最后已提交NPC消息mood；同档真实24NPC逐ID保存重开24/24，失败保存不抢先换外观。
- 最终portrait393/395（15PNG，2fail）＋shop694/694（22），37PNG＋6JPG全开，人工175/185。

**最后未过／范围：**两灰白selected-tab失败；body4纸楔／台阶、720p头部构图、旧林笔触partial。

**关键图：**[people-24-96px](D:/MagicStore/docs/screenshots/round2/A4/people-24-96px.jpg)；[five-moods](D:/MagicStore/docs/screenshots/round2/A4/five-moods.jpg)；[editor-colors-1920x1080](D:/MagicStore/docs/screenshots/round2/A4/editor-colors-1920x1080.jpg)；[random-consultation-1280x720](D:/MagicStore/docs/screenshots/round2/A4/random-consultation-1280x720.jpg)。

证据：[A4-validation.json](D:/MagicStore/docs/codex/results/A4-validation.json)。

### G2

- 家族库／schema7、实际到门配额／已预约保留／三成员事务与本人goal，原创占位库默认关闭。
- 模型只取公开改写身份／口吻／边界；原作／原名／私图／屏蔽原文不出wire，审核及回退同保护。
- HTTP消费者48／wire256／16请求；family114/115（2PNG）＋shop694/694（22），30帧人工141/150，历史4图另16/20。

**最后未过／范围：**第二关系需scroll，首屏1fail；专属内容／接线未齐，不宣称付费模型或完整故事质量。

**关键图：**[family-partial-1280x720](D:/MagicStore/docs/screenshots/round2/G2/family-partial-1280x720.jpg)；[family-partial-1920x1080](D:/MagicStore/docs/screenshots/round2/G2/family-partial-1920x1080.jpg)；[people-1280x720](D:/MagicStore/docs/screenshots/round2/G2/people-1280x720.jpg)；[front-1280x720](D:/MagicStore/docs/screenshots/round2/G2/front-1280x720.jpg)。

证据：[G2-validation.json](D:/MagicStore/docs/codex/results/G2-validation.json)。

### G4

- 15商品／18材料／15配方＋4变体／3采集点及人口扩充，旧身份／批次／accepted／结算不重算。
- 七kind组合逐component保存效果／来源；线索和关系走合法本案G3，真实报告才加NPC反馈；新traffic次日生效。
- 26新原生→52正式PNG，合35件70alpha；shop1544/1544（30）＋content138/138（12），48帧人工223/240。
- 单种子均衡连续30日封存：40＋2340服务＋1080销售−886采购−12研发＝2562，最低37、最大日净增160／库存净值25。

**最后未过／范围：**三full失败；后15日增1538，未证长期平衡／180扩展。普通首访揭边缺，关系专项始于合法已揭历史。

**关键图：**[workshop-mint-quality-1920](D:/MagicStore/docs/screenshots/round2/G4/workshop-mint-quality-1920.jpg)；[market-source-quantity-1920](D:/MagicStore/docs/screenshots/round2/G4/market-source-quantity-1920.jpg)；[night-committed-weather-1920](D:/MagicStore/docs/screenshots/round2/G4/night-committed-weather-1920.jpg)；[use-result-source-1280](D:/MagicStore/docs/screenshots/round2/G4/use-result-source-1280.jpg)。

证据：[G4-validation.json](D:/MagicStore/docs/codex/results/G4-validation.json)。

### G5

- 三世七片段、固定／家族／普通槽，看到／解读／核实分记，refuted后另留verified。
- schema9／可信cause／独立5%有效报价永久绑定；真实普通客60→18，七服务共42币／42精力／105游戏分钟。
- 三张v3古代图形成六正式PNG，真实四状态load与公共顺序修复；旧档／原source不改。
- GPU441/441（8）＋shop1544/1544（30）；旧失败3＋最终8＋shop30＋6JPG＝47帧，人工204/235。

**最后未过／范围：**未知烟雾仅半透明占位；纵向滚动非三世同屏／独立连线画布；旧头像／tabs／标题／数量布局留债。

**关键图：**[past-unknown-1280x720](D:/MagicStore/docs/screenshots/round2/G5/past-unknown-1280x720.jpg)；[past-first-vision-1920x1080](D:/MagicStore/docs/screenshots/round2/G5/past-first-vision-1920x1080.jpg)；[past-refuted-1280x720](D:/MagicStore/docs/screenshots/round2/G5/past-refuted-1280x720.jpg)；[past-three-eras-verified-1920x1080](D:/MagicStore/docs/screenshots/round2/G5/past-three-eras-verified-1920x1080.jpg)。

证据：[G5-validation.json](D:/MagicStore/docs/codex/results/G5-validation.json)。

### G6

- 成功保存记录派生六维／样本／指标／缺口与12娱乐称号，无新持久计数、不升schema9；旧report兼容。
- 依据只公开合法来源；paid的at/order先于预测，未披露失误不判错，缺渠道／基线／机会保观察中。
- 古纸页实际定位history，任意ID拒绝，无visit候客页内展开；保存失败／重试／重放／重开不多计。
- 三组authored真实derive不同称号，非真实经营；GPU121/121（6）＋shop1544/1544（30），42帧人工190/210，6JPG1611390B。

**最后未过／范围：**成交仅推介有限代理，未记未成交推介；旧头像／灰tabs／部分标题未齐，标准绿不覆盖此限制。

**关键图：**[report-inquiry-1280x720](D:/MagicStore/docs/screenshots/round2/G6/report-inquiry-1280x720.jpg)；[report-commerce-1280x720](D:/MagicStore/docs/screenshots/round2/G6/report-commerce-1280x720.jpg)；[report-balanced-1280x720](D:/MagicStore/docs/screenshots/round2/G6/report-balanced-1280x720.jpg)；[report-balanced-1920x1080](D:/MagicStore/docs/screenshots/round2/G6/report-balanced-1920x1080.jpg)。

证据：[G6-validation.json](D:/MagicStore/docs/codex/results/G6-validation.json)。

**G4三轮原失败保留：**full1 exit1，已汇总20组2093/2093，止于旧Shop.rules夹具processed_actions缺失；full2 exit1，Godot13356/13356、协议117/117，art236/238（旧18图oracle／预算539065>500000）；full3 exit1，已汇总46组5642/5642，止于旧v5 profiles.keys顺序断言，无该target终态总数。档内24身份集合等未变支持顺序假阳性，但无失败时迁移后内存导出，未跑full4。art尾批240＝238pass／1fail／1skip；junction允许环境1/1另列，非240全绿。[详情](D:/MagicStore/docs/codex/results/G4-implementation.md)。

G4经济仅`one_continuous_30day_run`：2063调用＝2033日内尝试（含131拒绝）＋30边界，1932提交／clock43080。192接待／117服务／162销售／55使用／0采集为观测，四现金列独立账簿核；六输入和day15 checkpoint封存。恢复仅day16完、day17局部；原180扩展未完／强门槛未改，安全停止−1非180通过，曲线不含G3赠礼经济。[单30日](D:/MagicStore/docs/codex/results/G4-economy-validation.json)／[曲线](D:/MagicStore/docs/codex/results/G4-economy-first30.svg)。

G5三标准轮exit1、1、0：先修旧generated-case合成host版本（原80保留），再修真实旧traffic整档与schema9比较（仅副本剔cause/past_lines，原盘SHA不变，101/101）。GPU1为220项1fail／3PNG；公开排序134/3→134/134、新四源128/128与真实load/hash21/21后，GPU2才441/441。完整14533＝13906 Godot＋117协议＋254 art＋256 HTTP wire（16请求）。[历史](D:/MagicStore/docs/codex/results/G5-finite-validation.json)。

G6完整15504＝14877 Godot＋117协议＋254 art＋256 HTTP wire，16请求、零引擎错误警告。GPU1真实27项1fail／0PNG；布局修后有限UI843/843（虚拟几何非GPU），实际GPU2才121/121／6PNG。headless schema18／0PNG及窄目标不加进图形或完整数。[有限历史](D:/MagicStore/docs/codex/results/G6-finite-validation.json)／[最终画面](D:/MagicStore/docs/codex/results/G6-visual-review.json)。

## 3. 美术定稿与四次上限

正式采用[style_v3.md](D:/MagicStore/docs/art/style_v3.md)的不透明广告颜料／可见笔触、可解释左上暖光、蓝绿冷影、朴素物件与UI留白；取代旧绘本／水墨方向。候选逐项、场景／物品最终分见第9节。源评分不代替游戏人工检查。

A4的139部件中79数值、60描述，不含人台，不能编统一139总分，也非79过60失败。唯一所选attempt4为mouth_01_smile且root过；body visibility4为同一native attempt2加工，接缝仍partial，非第四次生图。[原审查](D:/MagicStore/docs/codex/results/A4-art-selection-review.md)。

**已选v3资源没有“四次后仍<8却强定稿”记录。**A1R／A2R／G4相关列表为空；G5三图各attempt1。旧拒绝绘本候选1四次连接失败无图不混作现存v3候选1。拒图与连续attempt保留本地，未去饱和／删opaque边或放宽alpha换过。

## 4. 我做的决定：情况→选择→回退

|情况|选择|改回／继续|
|---|---|---|
|旧分支约1.2GB拒图／中间物|main重建clean，普通Git，仅定稿／runtime／≤6JPG|旧远端／backup不改；策划手动删，56v2保持。|
|v3定调|S02候选2修订后扩17C，新夜依自身day|保actualprompt／refs／SHA，追加revision不覆盖历史。|
|Li夹背景／残影|只6Li正式，其余C静态，不摇背景或实心烟假动效|真实精扣／补底再独审，失败证据保留。|
|A6缺素材／严格perf失败|空资源诊断、减少动态偏好，保passed=false|合法素材／标定后新实测，不降阈值／拿录像代性能。|
|A4衣领冲突|唯一body4 best且partial，不再body5|旧body备份＋receipt可回查，人工精修，不建按衣身体系统。|
|关系／模型隐私|仅公开本人goal／合法本案事件，正向白名单|补公开揭示或正式内容，不用rel_id绕私图。|
|G4三轮耗尽／经济|保三fail，完成单30日，额外180未完|未来另任务测长期／多策略，不拼全绿／伪summary。|
|G5概率／付费|独立5%、有效报价永久绑定、6币×7片段|新definition/costs版本调新实例；关active_versions停新绑定，旧v1／23币仍读。|
|G6缺记录|最新20结束访，成交代理，缺口null|调JSON并升policy_version或回旧report，不回写存档／补历史。|

## 5. 待确认

- **请在GitHub上删除远端codex/round2分支以释放空间**。由策划手动执行；本代理没有删远端、force或改写main。
- 三首音乐须合法包／许可；G4长期收入／消耗、G5的5%／6币／七片段是否最终平衡，待策划定。
- 烟雾／三世总览、前台Li／铃音／粒子、接缝／旧人物／页签／标题的精修优先级待定，不扩新系统。

## 6. 需要人工：素材、prompt、路径

|对象|缺口|prompt／路径／规则|
|---|---|---|
|日／夜／咨询音乐|旧下载429、续跑TLS EOF，文件／许可未得，静音fallback|prompt不适用；存assets/audio/music/day.ogg、night.ogg、consultation.ogg；[音乐待补](D:/MagicStore/docs/third-party.md)按作者／URL／曲目／许可／SHA登记，不假CC0／独立再分发。|
|S01/S02动层|云叶藤牌／草铃帘炉夹天空窗墙、补底残影；C无烟|actualprompt/ref_paths/attempts：incoming/a1r_v3/S01/generation_receipt.json、S02/receipt.json；[分层报告](D:/MagicStore/docs/codex/results/A1R-v3-scene-groups/S02.md)。|
|S03–S07动层|灯帘杯汽、草汽、街叶帘、树草需精扣／补底|同assets/_incoming各景receipt；[S05/S06](D:/MagicStore/docs/codex/results/A1R-v3-scene-groups/S05-S06.md)与V3_EDIT，不用新文覆盖actualprompt。|
|书签／树脂及六弱材质|64px用途／材质歧义，名称动态辅助|a2r_v3/generation_final.json；g4_v3/<id>-generation-attemptN.json；中央G4_item_v3参数。|
|body4／旧林|01/12纸楔，03/04/14台阶，旧笔触未统一|中央portrait_asset_id的prompt/source_raw；[body4](D:/MagicStore/assets/portraits/v3/v3r1/parts/body/body_01.png)／[旧林](D:/MagicStore/assets/portraits/npc_lin_neutral.png)，旧字节留incoming。|
|G5烟雾／三图|未知只半透明；古代图不要恢复水墨指令|scripts/divination/past_life_graph.gd；[三图native.actual_prompt](D:/MagicStore/docs/codex/results/G5-art-review.json)及中央；assets/past_lives/v3/era1_native.png至3_native.png。|
|A6铃音／粒子|框架在，production实配空|data/ui/motion.json chime_audio／particles.regions，补合法音／实区重验，不拿点击ogg代铃音。|

完整精确prompt、输入／ref SHA、实尺、processing及runtime aliases可从tracked [中央manifest](D:/MagicStore/assets/ART_ASSET_MANIFEST.json)共享表无损展开，不靠ignored详审才能重建。正式参考[style_reference.png](D:/MagicStore/assets/generated_scenes/v3_final/style_reference.png) SHA `0e6a45af456b9453896629c04bec45ea5b3631f64cd752be2b3194b2d60f1097`。

## 7. 已知风险与技术债

- A6 Iris Xe／Compatibility严格perf70项1fail；mean／p99、CPU子范围达标不覆盖frame max，600帧Movie Maker不是性能证据。[实测](D:/MagicStore/docs/codex/results/A6-performance.json)。
- A4 GUI393/395、G2 114/115保留；body4接缝、720p头部构图、旧林／缩略头像、灰tabs／标题／数量布局partial。旧关系烘字图仅撤引用，非重画通过。
- G4三full失败／人工223/240不消失；单30日后半增1538，未证长期上限、多策略、完整15日续段或G3赠礼经济。
- G5人工204/235、G6 190/210仍有未过；滚动可达不等于三世同屏。G6三组authored非真实长程经营，未成交推介／联系机会未记录，不能补0或拿NPC人格评分。固定声明：“只描述本局可追溯的经营行为，不是 MBTI 或人格测验。”
- raw／mask／Bi／拒图／JSONL／大PNG截图不formal；A1R1099证据有[迁移索引](D:/MagicStore/assets/_incoming/a1r_v3_processing_evidence/relocation-index.jsonl)。56v2 SHA保持；旧source／回退字节留存。
- 容量分期：CLEAN初始81,098,416B<150MB；A1R单次119,811,515B触100MB审查，确认正式白名单，但累计不再称<150MB。G4新增3,128,672B，G5新增19,862,857B，G6六JPG1,611,390B。现中央497438B／364记录／91copies、余2562B，后续须先无损紧凑与预算审查。

## 8. 下一步建议（最多五条）

1. 用start-game.cmd验当前源码，避旧EXE；零客日合法，普通离线客与联网原创生成门槛分开。
2. 先定G4收入／消耗、G5概率／成本、G6未成交推介口径，再以新版本数据验证，不回写历史。
3. 优先人工统一旧人物、接缝／页签／标题，补Li、合法音乐／铃音和烟雾，沿原来源／像素门槛复验。
4. 长期平衡另开多种子／策略与恢复专项，保单30日和180未完事实。
5. 总监按本包审阅，再决定源码导出与合并；策划处理旧远端空间，旧失败／partial及原回执保留。

## 9. v3改向：逐项候选与最终评分

评分沿原root／生成者实看记录。十项：①笔触／松角；②主光；③冷暗不黑；④可解释光源无伪光；⑤无金纹；⑥紫藤≤一处；⑦成组密度留空；⑧物件可辨；⑨结构；⑩UI低细节。独立物品⑦／⑩按透明余量。完整理由保原JSON，本包不新评分。

### S02三候选与修订

|项|候选1首轮|候选2首轮|候选3首轮|候选2修订|
|---|---|---|---|---|
|1 可见笔触及松墙角|1 墙柜宽笔|1 墙角木柜干笔|1 松墙颜料块|1 墙柜色块清楚|
|2 主光与光斑|1 左窗暖斑|1 斜阳窗格斑|1 日光地面斑|1 柜架软边窗格斑|
|3 冷暗部不黑|1 右墙灰蓝绿|1 门洞冷青|1 灰蓝绿可读|1 墙门洞灰蓝绿|
|4 光源可解释且无光效伪影|1 左窗无光晕|1 暖边有来源|1 窗光无自发光|1 罐柜光对应左窗|
|5 无金纹雕花|1 木架无金纹|1 朴素木框|1 无金纹堆叠|1 木框无金雕花|
|6 紫藤至多一处|0 顶挂紫束疑第二处|0 顶紫束疑第二处|0 紫束重复风险|1 唯左窗紫藤、褐干草|
|7 成组留空|1 罐书分组|1 三五件留空|1 分组有空隙|1 层板约四分之一空|
|8 物件可辨|1 罐书盆可辨|1 秤罐书篮可辨|1 书罐盆可辨|1 铃帘陶炉也可辨|
|9 结构合理|1 门窗层板连续|1 柜架门拱完整|1 门窗连续|1 架拱瓶帘结构完整|
|10 右30%底12%低细节|1 右墙底部松|1 右第三留白|1 留白；另有破纸框|1 右墙底柜低细节|
|总分|9/10|9/10|9/10|10/10|

首轮并列，选2因主光窗格、普通物件和架间留空最清楚；3另有破纸外框。修订把顶部改褐干草并补铃／帘／陶炉，10分定稿。actualprompt／候选在assets/_incoming/a1r_v3_pilot，逐项完整理由[原评分](D:/MagicStore/docs/codex/results/A1R-v3-art-review.json)。

### 17态场景最终C

|状态|①–⑩|分数|保留扣分|
|---|---|---|---|
|S01 day|1111111111|10/10|十项过|
|S01 night|1111111111|10/10|十项过|
|S01 closed|1111111111|10/10|十项过|
|S02 day|1111111111|10/10|十项过|
|S02 night|1101111111|9/10|天花／高架接近黑，冷影不足|
|S03 day|1111101111|9/10|窗藤之外靠枕仍有紫藤图案|
|S03 night|1111101111|9/10|窗藤之外靠枕仍有紫藤图案|
|S04 day_open|1111111111|10/10|十项过|
|S04 day_closed|1111111111|10/10|十项过|
|S04 night_open|1111111111|10/10|十项过|
|S04 night_closed|1111111111|10/10|十项过|
|S05 day|1111011111|9/10|左前书封细金卷纹|
|S05 night|1111011111|9/10|左前书封细金卷纹|
|S06 day|1111111111|10/10|十项过|
|S06 night|1111111111|10/10|十项过|
|S07 day|1111111111|10/10|十项过|
|S07 night|1111111111|10/10|十项过|

合165/170，最低实际9；native1672×941，runtime1920×1080。C高分不签Li，实际仅6Li过。

### 35物品最终分

|批次／物品|①–⑩|分数／attempt|保留扣分|
|---|---|---|---|
|A2R 月见草|1111111111|10/10 · 2|十项过|
|A2R 山泉水|1111111111|10/10 · 2|十项过|
|A2R 白水晶砂|1111111111|10/10 · 1|十项过|
|A2R 月光树脂|1111111011|9/10 · 3|灰褐树脂与石块难分|
|A2R 定心香|1111111111|10/10 · 2|十项过|
|A2R 醒神药水|1111111111|10/10 · 1|十项过|
|A2R 澄心晶|1111111111|10/10 · 1|十项过|
|A2R 纸纹书签|1111111011|9/10 · 1|64px像纸条，书签身份弱|
|A2R 银叶书夹|1111111111|10/10 · 1|十项过|
|G4 蜂蜡块|1111111011|9/10 · 2|64px也像皂块|
|G4 棉线团|1111111111|10/10 · 2|十项过|
|G4 干薄荷|1111111111|10/10 · 1|十项过|
|G4 海盐|1111111111|10/10 · 1|十项过|
|G4 磨砂小瓶|1111111111|10/10 · 1|十项过|
|G4 松针束|1111111011|9/10 · 3|64px与草束混淆|
|G4 艾叶|1111111111|10/10 · 1|十项过|
|G4 芦苇茎|1111111111|10/10 · 1|十项过|
|G4 河泥陶团|1111111011|9/10 · 2|灰泥与石块难分|
|G4 旧铁片|1111111011|9/10 · 2|金属与纸片质感近|
|G4 蜂蜜小瓶|1111111111|10/10 · 2|十项过|
|G4 旧铜钥匙|1111111111|10/10 · 1|十项过|
|G4 蓝玻璃片|1111111011|9/10 · 2|64px需名辅助分蓝石|
|G4 暗红线结|1111111111|10/10 · 1|十项过|
|G4 专注蜡烛|1111111111|10/10 · 1|十项过|
|G4 迎客香囊|1111111111|10/10 · 1|十项过|
|G4 缓心护符|1111111111|10/10 · 1|十项过|
|G4 细察晶片|1111111011|9/10 · 1|浑浊晶片像卵石|
|G4 和谈绳结|1111111111|10/10 · 1|十项过|
|G4 清风线香|1111111111|10/10 · 1|十项过|
|G4 晚间茶包|1111111111|10/10 · 1|十项过|
|G4 安稳石|1111111111|10/10 · 1|十项过|
|G4 舒缓蜡烛|1111111111|10/10 · 1|十项过|
|G4 清醒药水|1111111111|10/10 · 1|十项过|
|G4 理绪茶包|1111111111|10/10 · 1|十项过|
|G4 相伴香包|1111111111|10/10 · 2|十项过|

原9件88/90、新26件254/260；native1254×1254，256／64派生。A2R14真实调用；G4 35调用含2网络失败。逐项完整理由[A2R评分](D:/MagicStore/docs/codex/results/A2R-v3-art-review.json)／[G4评分](D:/MagicStore/docs/codex/results/G4-art-review.json)。

### G5三图、A4混合证据与前后

|图|①–⑩|分数／attempt|保留项|
|---|---|---|---|
|era1|1111110111|9/10 · 1|约10–15件，未达通用25–40密度|
|era2|1111111111|10/10 · 1|十项过|
|era3|1111111111|10/10 · 1|十项过|

G5合29/30，各1次；native1672×941→Lanczos cover1920×1080，倍率1.1483253588516746，crop[0,.25,1672,940.75]，不是原生1920。[评分／actualprompt](D:/MagicStore/docs/codex/results/G5-art-review.json)。A4仍是79数值＋60描述，不能补139总分；第4次嘴图已过，body4加工接缝partial非4次生成失败。

**同窗口前后：**[S02 v2／1280](D:/MagicStore/docs/screenshots/round2/A1R/s02-before-v2-1280.jpg) → [S02 v3／1280](D:/MagicStore/docs/screenshots/round2/A1R/s02-v3-day-1280.jpg)。G5未知→核实是同NPC不同真实进度，非同一时点A/B或三世同屏。旧v2源不删，actualprompt／连续attempt／拒图／回退字节保留，缺数值不补造。

## WEB 独立追加

后续独立请求，实验试玩部分完成；三轮完整回归均失败，浏览器实操未验。[公开入口](https://wutong-ww.github.io/MagicStore/)已部署，CI／HTTPS证据及限制见[发布回执](results/WEB-deployment.json)与[计划](plans/WEB.md)。不改上文11任务结论。
