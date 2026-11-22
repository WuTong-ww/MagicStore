# 第二轮 v3 续跑进度

最新恢复点：2026-11-23，分支 `codex/round2-clean`，HEAD `37b0137`，A6任务提交 `fb43344`。**A4已验收为部分完成，正在提交；完整第3轮session93596已terminal exit0，10278/10278，勿再poll或复跑**。详情见末尾；下一生产任务G2，尚未开始。重建过程旧记录在 `history/clean-rebuild-progress-20261122.md`。

任务ID｜状态｜提交｜一句话说明
---｜---｜---｜---
CLEAN｜完成｜1878b6c、135c26f｜从main重建干净历史，完整7739/7739，初始新增二进制81,098,416B，已普通Git推送。
G3｜完成｜1878b6c｜保留总监通过的邀请推荐修复，干净基线全绿复验。
A3R收尾｜部分完成｜7f7a8c3｜四项程序修复；完整8077/8077；51原图及10JPG已审，音乐/v3装饰及后续美术依赖仍缺。
A1R v3｜部分完成｜059baeb｜17态C与六层实图正式接入，完整8362/8362、62帧审阅；缺失分层和后续物品/头像依赖如实保留。
A2R v3｜部分完成｜2773499｜九件18图去背及来源验收通过，完整8555/8555，44帧审阅；旧架子/A4跨任务项保留。
A7｜部分完成｜c2c37eb｜原生层板替代木箱、确定布局/交互/去重信号；完整9154/9154，47帧及12接触诊断已审，旧人物十项留A4。
A6｜部分完成｜fb43344｜风场/弹簧/正式流水/货架/保存后事件与设置；完整9653/9653，最终508和4pair+8control、53帧已审；前台动层/铃音/严格帧时未完成。
A4｜部分完成｜待记录｜139部件/十层/五态/捏脸/schema6；完整10278/10278、24/24重开一致；页签2fail及接缝/旧装饰等保留，六JPG已审。

## A1R v3 已提交并推送

- 17状态C实际评分165/170，三候选及修订逐项理由在plans/A1R.md。仅沙发遮挡/闭门/水域共6张Li通过，其余三轮后静态保留，任务部分完成。
- 生产已接入v3，59PNG+59导入设置；所有151正式文件实际SHA/尺寸通过；manifest229143B；1099中间物已SHA验证保留incoming。
- 最终完整第3轮session71750已exit0：8362/8362（Godot8130、gateway94、art138），0错误/警告。第1轮RED已修、第2轮快照作废中止，不再poll任何旧session。
- 实际生产图形1502/1502，34帧；shop718/718，22当前帧；root已看56PNG和6JPG并写62行五项矩阵。图片只提交六张质量85 JPG，含v2→v3前后对比。
- 重生成四项缺陷（含inputs遮蔽）已修并独立复验，无剩余阻断；17C/9正确依赖、12派生等待新C和mask审查。来源/像素检查不依赖ignored JSONL。
- 提交前新增二进制119811515B触发100MB检查，已逐OID确认只有合格定稿/运行副本/JPG，无中间物。初始CLEAN<150MB与后续正式美术分开报告，未把203137565B累计量写成<150MB。详见UPLOAD_STATUS。
- A1R实际提交059baeb，已普通Git推送至origin/codex/round2-clean。所有测试进程均结束，无需poll。当前开始A2R恢复调查与计划，不复用被否决物品图。

## 后续顺序

A4 v3 → G2（仅框架/占位家族）→ G4 → G5 → G6。每任务最多3轮，提交前完整测试全绿，每完成提交并推送。A2R旧代码/去背流程在本地 `assets/_incoming/a2r_v2_rejected/worktree/`，69路径已保留；旧图被否决不得复用为正式。

## 不变约束与结束包

- main/origin main保持e27441b；旧远端codex/round2保持18da84a；本地备份codex/round2-backup-20261121不推送。不改写历史、不force、不删除远端分支。
- 二进制普通Git、无LFS；候选/拒图/中间物只在ignored incoming；逐层审计JSONL只本地；每任务截图最多6张quality85 JPG，其余.tools。
- 原v2 56文件不删除不修改。新提交若二进制>100MB必须先审查中间物；本次A1R白名单按HEAD唯一blob约118.46MB，全是通过图，严禁把约1.05GB加工文件带入。
- 需在最终REVIEW_PACKET待确认列「请在GitHub上删除远端codex/round2分支以释放空间」，由策划手动处理；原分支空间尚未释放。
- 全部任务处理过或连续两个任务同一外部原因卡死后，更新REVIEW_PACKET（含v3改向评分/对比/人工项）并推送clean。当前未到结束条件。

## A2R 最终验收与提交

- 完整第1轮8555/8555（8292+94+169），现有PID6012由observer session14157确认exit0；测试进程均已结束，不要重复poll旧session。
- 九件共14次原生生成，18透明图与所有原图已root看过；全18alpha边0%、品红0，bottom_y252；评分88/90，书签/树脂9分的辨识弱点保留。没有4轮后仍低于8分者。
- 角标漂移GUI第1轮修复，第2轮255/255（16帧）+shop718/718（22当前帧）；44帧含6JPG实际审阅/14旧帧SHA等同继承，203/220通用项通过，旧slot/A4缺陷留后续，故部分完成。
- 已显式暂存代码、169正式来源配置、18PNG+18import、legacy六文件迁移、六JPG、评分和逐帧矩阵。原v2 56 SHA不变；manifest303113B，本次新增二进制1623228B，没有候选或审计入Git。
- docs/features和tools/ART_PIPELINE已更新。独立审查无阻断。实际提交2773499已普通Git推送至origin/codex/round2-clean；从A7继续，不重复A2R生图/测试。

## A7 最终验收与A6恢复点

- 实际任务提交c2c37eb，完整最终第2轮9154/9154（Godot8888+gateway94+art172），exit0、0错误警告；session88501已收terminal，不再poll或重复完整测试。
- GUI第1轮metadata Control.to_global错误、第2轮F3第三线低35px均已修；第3轮940/940与shop710/710通过，19+22当前原帧、6JPG共47窗口帧通用225/235，12组200%接触通过。18专项与20shop按实际已看帧SHA相等复用，其余和六JPGroot已打开；旧NPC十项是最后跨任务不通过来源，留A4。
- 四线最终y238/375/486/626，x278..1045；夜间上层调暗。原v2全部56文件SHA不变，slot复制legacy同blob。manifest304408B，本次新增二进制1452126B，只有六JPG；详细见UPLOAD_STATUS。
- 三独审P2（售空残留/溢出重复/坏labels消费）已真实RED后修复并他审关闭；核心74、renderer38、场景915通过。A1R注册工具支持A7新shelves基线又保留旧slot，29/29目标通过。
- 下一个未处理任务是A6。预检已写本地.tools/art/a6-preflight.md（24123B），尚未实施A6，也未新建A6计划。可用真实Li仅六张：S03sofa静态遮挡、S04closeddoor静态、S07water flow；S02无动层，不可摇全C冒充风铃/花束/帘幕。A6应安全跳过缺层并列部分完成，继续做风场/弹簧/货架/流水/保存后信号/减少动态/性能与MovieMaker。
- 当前无full或GPU测试进程。下一步推送c2c37eb及本进度META，然后读A6章节写计划，按原顺序继续，不重复A2R/A7。

## A6 最终验收已提交

- 第3轮full9653/9653（Godot9372/gateway94/art187），exit0、0ERROR/WARNING，所有进程已收terminal。不要重跑full或poll17865旧session。
- Wind100、事务事件277、motion49headless/82GUI、设置31、性能schema24、preview schema7强制入口。旧A1R断言现验声明sway材质，同时保留四尺寸cover/pivot/零rotation；79/79。
- 正式preview第1轮岸环失败后修近远8邻/双相滚动；第2/3轮508/508及4pair+8control通过。最终34PNG与root已看round2 SHA全相同，另根已看14技术图、六JPG、五录像关键帧、7个shopchanged；53窗口/关键帧通用245/265，其余旧帧严格SHA继承。
- 录像第3次独立AVI600帧/1920/60/10秒，WinRT MP4 15,308,798B，独立stsz/stts600/10秒；不冒称完整H264解码。首帧文字渐显、旧NPC/人物列表/问号装饰等不通过留后续。
- 性能两轮IrisXe实测63/1、70/1均false，原1800行CSV/JSON保留，≤2ms与每帧60fps尖峰未达标。缺前台Li/铃音、production粒子区空，故A6部分完成。完整代码与进度不是外部原因卡死，继续第二阶段。
- 新增二进制16,869,797B只六JPG+一MP4，manifest305473B、56v2 SHA不变。计划/逐项矩阵/results/features/ART_PIPELINE齐；实际A6提交fb43344，普通Git推送clean。
- 下一未开始任务 **A4 v3**。只读预检.tools/art/a4-preflight.md已写：schema6/身份哈希迁移、五态mood审核全链、139部件+人台、现代小镇居民与左上暖光、regen显式portrait组。先读手册A4和style_v3，写正式计划后实施，再G2→G4→G5→G6。当前未到最终审阅包停止条件。

## A4 当前进行中（未提交，续跑优先读此）

- HEAD37b0137已推送；A6任务fb43344完成验收，不再重跑。A4正式计划plans/A4.md已写，三owner并行实施核心/UI/protocol-tools；未最终full/Git。下一顺序仍G2→G4→G5→G6，不提前结束。
- 核心appearance_parts42729B/Appearance规则、schema6内存迁移、生成式v2自然描述/hash、安全公开appearance+mood已落。核心最终291/291（首日33、description20、migration115、rules123）clean；首日catalog2先于plan_day，仍保留旧3次RNG且实际day/arrivals不漂。历史schema输入和显式v5fixture保留，11处当前终态改6附why。日志.tools/art/a4/core-ledger.md。
- mood五枚受限/缺neutral、本地JSON默认、审核fingerprint、直连与gateway显式非法拒绝不fallback、成功保存后才显示。Python107/107，Godot45+127+86+41+77+23全绿；真实HTTP fail/retry/replay/disk不泄漏。独审无阻断。
- UI十层Portrait/gradient map/有界cache/PNG导出加载fallback、分页本地draft/真实保存失败及reload、随机客consultation/bubble已落。作者初54/1修presetcontain，独审两P2：相同外观跨save残留和同path换图live缓存；真实58/2 RED→58/0；GUI63/63 IrisXe Compatibility含5GPU检查、0ERROR/WARNING。a7在只读复核关闭；正式24人/五态/双尺寸仍未验。
- Root实际生人台2次，1偏轴拒，2选择；源1086×1448→Lanczos768×1024→canvas(+18,-1)，正式assets/portraits/v3/v3r1/mannequin.png SHA82763469…，raw/prompt在ignored incoming/a4_v3/mannequin。暖灰非严格RGB相等，后续部件流程显式均值灰阶，不伪称原生768/全灰。Root已看2原图和归一化基准。
- 旧imagegen cells322/331/334/351均已完成，不再等待或重生。人台后22次实际部件生成形成10个候选（含两neutral），root已看每张原生及最终10透明图。精确路径/SHA/原生1086×1448/选择attempt/历史/处理配置摘要在.tools/art/a4/round2-selected-candidates.json；只10/139，剩129尚未齐。
- 原型GPU第1轮128/128发现眼睑皮片/肩条，第2轮160/160发现深肤冷灰痣；第3轮160/160、零错误警告、0动作，16帧全部root实际打开。最终眼睛去皮睑、body visibility v2补领口（仅outfit01兼容）、短后发去底噪、mouth/features改skin映射；六肤色/镜腿/左上颜料光通过，未把同一人六色当24顾客或五态验收。对应.tools/art/a4/pilot-round3-assembly-review.md及逐像素对比。
- 最终core appearance规则235/235（包含mouth与features调色负例）；工具限定131/131且新detached v2模板/旧prompt精确重建、clean-checkout重生成P1均独审关闭。A4 full第1次已真实exit1：generation_arrival_slots旧夹具把schema6内people换成catalog1；隔离probe证实原因，只修该夹具plan前启2/normalizeplayer，target30/30绿。其后未到达7integration+HTTP/person/people独立补跑exit0，gateway107/107。两session27586/50368均已收terminal，不再poll。正式139/24/双尺寸与最终full未验。
- 正在扩量：workshop独立builtin六mood队列detached-v2-mood-batch01-queue.json（四eyes01、mouth01笑/犹豫）；a7独立face02..06+brows02队列；outdoors唯一pipeline/config处理owner并准备余队列。三者实际raw自审、每图≤4次/保留attempt；root最终逐图审。模板与guide仅参考而非假称专用maskAPI，不能用已批neutral冒充新表情已批。
- Root已逐透明图批准31parts（含neutral眼嘴）+人台；正式31+1PNG按实际SHA原字节copy，只有29个已齐的单态行approved，eyes/mouth共享行仍pending。中央root已合统一fragment，现201行308078B；旧169行逐字段全等。每资产一行，不用pretty。A7是唯一parts状态editor，root是唯一中央editor，不提前进G2或最终审阅包。
- 首型五态×skin01/05实际GPU最终331/331，21有效PNG在.tools/art/a4/mood-pilot-preview-round1/run-1774599/，root已21/21逐开。此前工具schema数组比较1/1与遗漏本地ImageTexture注册32fail均保留，不算有效画面。语义未批：笑/迟疑96px近neutral，sad嘴2方向对但眼上缘深肤有亮细圈；root已要求5个精确纠正（眼笑闭弧/迟疑侧视/sad去浅线a2、嘴笑提角/迟疑紧抿不对称a3），由workshop真实生成/交outdoors加工再prototype2，不超每源4次。其他新mood扩量暂停，非mood继续，不能技术绿冒充表情通过。
- Root b03六前发已透明逐审/正式；b05六源+front12新955guide attempt2共7实际attempt metadata完整归档，12a2已交processor；b08六嘴+a2尺寸/低落修复共8实际attempt已交processor；b16 back03..08六actual已归档交processor，06高马尾顶部超旧70guide hold，不裁断，其余五先处理。旧cells372/373/388/403/407/412/414已完成，不重复等待或生图。Root所有本人调用raw已看，遗漏输出通过view_image补开。
- 当前精确登记/处理中间证据都在ignored incoming/.tools；canonical pipeline fit只按实际sourceSHA授权，不对未知新图默认放宽.5..2。眼/嘴新态未formal。工具owner正在做保真prefix/suffix参数压缩（实际预算旧方案139约489256B仅余10KB，必须逐字format+SHA不丢字段），新133目标待结果；最终full必须在此之后重跑。当前引擎lane空闲，下一由workshop五纠正后prototype2优先。

### A4恢复追加：首型五态第3轮已实际复核

- R2有效332/332与21/21图root逐开，语义修好但笑眼深肤银弧未过；R3仅再生成眼笑/低落a3（未用a4），有效333/333、零E/W、0动作，`.tools/art/a4/mood-pilot-preview-round3/run-1723284/` root已21/21全部打开及两透明新眼。笑眼银弧消除，低落为克制窄眼+下垂嘴，96px可辨；批准eyes01/mouth01整五态局部，不当作139/24或正式窗口通过。记录`.tools/art/a4/root-mood-round3-review.md`。
- Pipeline实际135/135 green（processing-mask-wrapper-regression.log），源SHA处理mask可扩旧guide边界、原generationmask/refs不改；back06顶裁与front12左裁用实际新mask解决，core RGBA差0。后发06 residue1只清y800以下565背景残料，0..799 byte相同，root已实开批准；不把bob600剪法用到长马尾。正式copy/fragment由outdoors继续，parts状态唯a7、中央唯root。
- Root B18衣服6初次中5拒收（整件商品/低领/无内搭/露臂），真实a2五张已逐开，半身肩700、hood-down/内搭/长袖修正。11次完整元数据`.tools/art/a4/detached-v2-b18-generation-inputs.json`交processor，未宣称衣服拼接通过。B22三配件下一root排他；B21六配件已wake a7，workshop恢复held新mood，各asset最多4实际调用。所有候选raw保留ignored，不提交。
- 最终full仍未跑；第1次full旧夹具失败已修target30/30与未到达后段独跑green，不重复poll已结束session。正式139部件/24真实存档顾客/五态/双尺寸编辑器与shop仍待实际GPU验收。引擎lane当前FREE。

### A4恢复追加：全139已有候选，正式流程尚未结束（2026-11-23）

- 当前HEAD仍37b0137，A4未提交/未推；不要开始G2或最终包。原A3R/G3/A1R/A2R/A7/A6均维持此前已处理结果。G2文件拆分只读.tools/art/g2-file-split.md，G4只读g4-preflight.md/g4-counts.json，未开后续production。
- 正式当前65parts+人台（57approved行），parts SHA1f729d5878383f07c165e6e14b2ccb5890c03b768cb8df3a14dd8bce9e7a9118；后续copy可能再增，恢复时读最新copy/promotion audit。已批准31旧源+首型8新态+front12/back06+8后发年龄+6keep衣+10配件。中央root仅合到211行334558B（42portrait含人台），**其后24正式源还未合中央**；最终一次整合所有140 portrait行，旧169非A4逐字段保持。
- Root逐开35候选与首轮7页，发现旧非01眼浅边/弱态、3嘴方向弱；纠正16旧眼（03/04由workshop，02/05由a7），actual连续史优先：03smile下一3、03hesitant实际只有a1所以下一2，不凭旧summary跳号。B13/B14/B15新18源均实际生成/自看/交processor；B15 sad失败a1保留选a2。Root B14六源metadata detached-v2-b14-generation-inputs.json；B22三配件metadata detached-v2-b22-generation-inputs.json。
- root M02hesitant过宽a1被严格拒，真实a2已归档root-mouth02-hesitant-attempt2-generation-inputs.json，actualSHA c8d5b874…；原queue的描述hash在audited-queue按实际arguments.prompt补正，原queue保留，实际提示词没换。outdoors已合原B06 a1历史且strict过，首次全139候选齐。Root三嘴纠正metadata root-three-mouth-correctives-generation-inputs.json（03sad3/05smile2/06smile3），原生全1086×1448、本人逐开/复制/哈希；两笑上提、sad下垂，已strict过并进入r2。
- 衣首轮466/466四页root全开，09衣缺臂/深V纸洞/10浮领。Root九衣02/03/04/10/12/13/14/15/16全真实a2长袖/内搭，原生全1086×1448、每张实际打开（02工具省略后另view）；metadata root-nine-outfit-correctives-generation-inputs.json，旧a1原metadata保留。六keep05/06/07/08/09/11已正式，01旧正式仍a3（总真实1..3）。旧被否决衣/raw都仅incoming。
- grouped-r2正式局部技术验：UI70/70、衣562/562四页outfit-preflight-grouped-r2/run-2528514、表达1724/1724七页expression-candidate-grouped-r2/run-3017469，全部exit0零E/W，root已11/11全部实开；衣64主/zoom确用body3而非旧body2，16fullcontrol，源像素逐字proof。70态全画、无pending，首型10path/SHA固定；Root另实开07sad透明源，亮条在深lash内为下视眼白，接受。**已授权outdoors exact copy r2配置冻结60非01眼嘴PNG，a7核12共享行全齐后promote**；数据/外观hash不重抽。
- 衣r2九衣缺臂/低领洞/浮领已解，但body3在02/03/04/11/12/13/14/15等领侧仍小直角肤片；root像素probe已排除face01（660..670 alpha0），确body不透明/衣alpha0。outdoors仅最后纯数据visibility4候选（平滑/小收敛），中央颈ROI保持、01可见变化必须明报；再第三轮一次衣4页，仍残选最好标A4部分完成，**不无限修/不造runtimebody变体**。body3尚未覆盖正式body2。Root已实际打开body3源与alpha叠回。
- 配件两肤生产Portrait实装299/299、2PNG accessory-assembly/run-1588125 root全部实开。此前ignored helper3次恒false/0PNG源于作者crop loop多returnfalse，静态修后root授权一次收尾才299，失败日志全留；不冒称前三0帧通过。Root批准02/03/04/05/06/08/10/11/12/14十配件已正式；12自然帽檐略压眉但眼主体在，不机械零交叠。07确遮下颌，outdoors整canvas+60y且fullRGBA对期望差0，新face叠回待root看；13大丝带遮眉1239/眼167不批，**root真实a2小侧发结正在cell514，尚未接结果/归档**；不能再启动重复调用。09胸针新去边与后发09/10新lastrow源root已实际逐开通过，已授权exactcopy3，待审计/中央合并。
- 规则真实修：高尾只映实际back06，不塞长波浪front12；新selection_exclusions限制新generate/draft/真实save动作帽10/11/12+高尾，旧appearance_valid/normalize/旧档hash合法性不动。帽12追加最终rules264/264、migration113/113（生日循环计数随新店档变化，不删断言）、UI70/70全绿、0E/W，旧保存/失败retry/replay有真RED。所有parts自然简体label已补；outfit12旧标签“日常短袖”需改长袖自然名。
- 工具新增exactformal再生（实际211中央42任务prompt逐字SHA全等）、output-only共享编码、sourceSHA限定外围残料/processingmask、旧图保全已独审。最后限定141/141（final-tools-141-green.log）真实green，代码art_pipeline5af3ef2f…3279 /portrait727d228e…b2e27 /checkerad32d6ef…c6；第7个737B真实共文只config新增，不改139generationprompt。a7最终same139保全部字段/refs/actualSHA/169旧行、短format键/短模板alias/39有wrapped同伴exact归并+只清全合并无引用A4模板的内存实算498266B（余1734），**最终07/13/body变化后必须再量并真正落中央，不能拿投影当完成**。后续G4新增图会再占清单空间，需届时实际处理。
- Root直接逐源检查台账root-opened-parts-review.json当前64条，含旧35与新后发年龄/六keep衣/13配件（09旧残边hold）；r2 70态另有实际七页审读。候选索引有-131/-137/-139-snapshot等不可变快照，latest只便利，不代表美术批准。Root已冻结root-candidate-snapshot-421e84e27039.json。所有候选/raw/audit/.tools均ignored，正式PNG/≤6质量85JPG才入Git。
- 下一：接cell514丝带2并真实看/归档→看scarf+60与body4→最多一次衣r3/配件新两件组合复查→copy/promote全部源（或残项明确partial，不假批）→root最终manifest<500k/139检查→正式portrait_preview真实24公开存档身份/5态/双尺寸编辑器与咨询/savefail重开、shop_ui双尺寸/root全部看图/六JPG→最终full（第1次full已修夹具但未整体重跑）→features/结果/计划/体积/56v2SHA/PROGRESS/A4提交+META/push→G2→G4→G5→G6。当前无full进程，workshop已释放r2 lane；不要poll已terminal旧sessions/cells。原生和正式文件都保本地，main/旧远端round2不动。

### A4恢复追加：最终源选择已收口

- cell514已terminal，**不要再wait或重生**。丝带13真实a2原生1086×1448 SHA5d5b62447e0e8f8827cb9d2991bc42b709831f3bef9db40491aa129b77a04548，metadata root-ribbon-attempt2-generation-inputs.json；root已逐开原生、透明源8d6d150c…c7332bb与actual-face-overlay，小侧结不近眼眉、短尾完整，批准exactcopy。围巾07原图整canvas下移60的透明源和actual-face叠回同样已实开批准，下颌与尾完整。
- Body4四页alpha root全开，中央颈ROI/RGB保持，旧直角肤缘明显减少但01两边微小纸楔仍在；选8402f056…5f8c66为唯一身体最好版本，**A4接缝美术partial**。已授权带旧/新SHA收据替换旧body2，workshop只做最后clothes-r3四GPU页，不造body5/不重生01/不按衣runtime变体。引擎由workshop协调，a7状态写与guard互斥。
- 60表达+3cleanup实际exactcopy收据sixty-expression-and-three-formal-copy-receipt.json已出，九衣+围巾收据nine-outfits-and-scarf-formal-copy-receipt.json已出；a7正核15共享行与后续剩余状态（含outfit12自然长袖名）。中央仍root唯一editor，等待最终139完整且精确provenance的压缩proposal；正式24/双尺寸及full仍未运行，不提前宣称全绿或启动G2production。

### A4最新恢复点：全部源与正式图形已收口，等最后full3

- 83required rows全选定，139parts+人台140PNG共9,775,102B；parts SHA44bd63f8cbcf8959ae354c4e86c72ceee55da079deebfeeff2fe2b3b67bc0dab。Root中央已exact写309行/499605B，SHAdbb6bdf16e0ade38eff2f8a937029fa68fa05fa2e2de3869d729efd64bc5fb0b，169旧资源全不变；唯一旧body extra字段差是sha/digest。Rootvalidator/实际生产CLI309全valid；a7真实consumer656/656+11批准copy/50processing receipts来源1954/1954。详审仅local，原492KB native明细已移ignored并导JSONL，未带入results。
- 最后衣r3实际564/564，root四页全看，body4仍01/12微纸楔、03/04/14小台阶→partial，停止新source。围巾下60与小丝带2均已root原生/透明/叠回全部看过，正式copy全齐。
- 正式GUI1真实176/3/0PNG，sampler缺next_day，源139严门槛已过；只修真实wait到closing后next_day，不注入人物。GUI2真实539/539/15PNG、同档24人跨11日重开24/24；root15页全看发现灰纸底和720消息头裁切。GUI3最后两hunk（两TabContainer content用现有paper，transcript100+42+6+6=154），实际395/2/15PNG，24人跨5日重开24/24、139源全过；2fail仅灰白选中tabs，保留断言、不再GUI4。shop同冻结代码694/694，23writes/22unique；root全部37最终PNG+六JPG实开，通用175/185。旧GUI2另15+6变化shop也都root实际看过，16复用图SHA全等。艺术/页签/720只余主像头部、错误toast、旧林笔触和关系装饰烘焙问号列partial，不加修。逐行矩阵在A4计划末尾，official results A4-*，截图六质量85JPG共928170B在docs/screenshots/round2/A4/。
- CLI再生既有前置已实际跑：20guides忽略目录，真正PowerShell regen -Style v3 -Only portraits exit0，140 tasks仅新mannequin1ready，139parts待新基准审核／75 provisional maskreview，0缺mask；不冒称自动全生。两个命令与边界在ART_PIPELINE.md。
- 完整第2轮session11617已terminal exit1，不要poll：transcript154使800600旧shell遮脸。只改visuals.S03.seat_narrow_rect为[1229.4736842105262,136,235.7894736842105,348.3253588516746]，等比.7/横center不变，真实probe11/1→11/11、shell1366/1→1366/1366、consult48/48；800 midpoint129.2344<paper135、top56.6667>header52。1280/1920真实全部几何exact不变，a7独审17/17；所有139源/样式/manifest冻结。新visuals SHA9f5e26cdc9301c4013d968f166a51cee5e76c526582f9c44a4027f9494637b39。
- **Root最终full3 session93596已terminal exit0**：10278/10278（Godot9940+gateway/protocol107+art231），0SCRIPT ERROR/ERROR/WARNING，56v2 SHA全部不变，309正式源/18物品alpha通过，明细results/A4-validation.json。所有源已显式暂存358paths，图片仅140PNG+六JPG，pending index新增二进制10,703,272B；clean累计233,785,988B。原CLEAN helper仍因累计150MB及历史A1R>100MB两检查FAIL，不改阈值、不谎称A4超预算；A4本次远低100MB且禁止路径0，manifest499605B。准备补最终文本/UPLOAD_STATUS再[A4] commit→PROGRESS hash小META→普通push clean。main与旧round2不动；之后严格G2→G4→G5→G6，最后才REVIEW_PACKET。
