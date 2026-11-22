# 第二轮 v3 续跑进度

最新恢复点：2026-11-22，分支 `codex/round2-clean`，A7任务提交 `c2c37eb`。本文件只列当前状态，重建过程旧记录在 `history/clean-rebuild-progress-20261122.md`，不得据旧运行中session重复启动任务。

任务ID｜状态｜提交｜一句话说明
---｜---｜---｜---
CLEAN｜完成｜1878b6c、135c26f｜从main重建干净历史，完整7739/7739，初始新增二进制81,098,416B，已普通Git推送。
G3｜完成｜1878b6c｜保留总监通过的邀请推荐修复，干净基线全绿复验。
A3R收尾｜部分完成｜7f7a8c3｜四项程序修复；完整8077/8077；51原图及10JPG已审，音乐/v3装饰及后续美术依赖仍缺。
A1R v3｜部分完成｜059baeb｜17态C与六层实图正式接入，完整8362/8362、62帧审阅；缺失分层和后续物品/头像依赖如实保留。
A2R v3｜部分完成｜2773499｜九件18图去背及来源验收通过，完整8555/8555，44帧审阅；旧架子/A4跨任务项保留。
A7｜部分完成｜c2c37eb｜原生层板替代木箱、确定布局/交互/去重信号；完整9154/9154，47帧及12接触诊断已审，旧人物十项留A4。

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

## A6 最终验收完成，待登记实际提交

- 第3轮full9653/9653（Godot9372/gateway94/art187），exit0、0ERROR/WARNING，所有进程已收terminal。不要重跑full或poll17865旧session。
- Wind100、事务事件277、motion49headless/82GUI、设置31、性能schema24、preview schema7强制入口。旧A1R断言现验声明sway材质，同时保留四尺寸cover/pivot/零rotation；79/79。
- 正式preview第1轮岸环失败后修近远8邻/双相滚动；第2/3轮508/508及4pair+8control通过。最终34PNG与root已看round2 SHA全相同，另根已看14技术图、六JPG、五录像关键帧、7个shopchanged；53窗口/关键帧通用245/265，其余旧帧严格SHA继承。
- 录像第3次独立AVI600帧/1920/60/10秒，WinRT MP4 15,308,798B，独立stsz/stts600/10秒；不冒称完整H264解码。首帧文字渐显、旧NPC/人物列表/问号装饰等不通过留后续。
- 性能两轮IrisXe实测63/1、70/1均false，原1800行CSV/JSON保留，≤2ms与每帧60fps尖峰未达标。缺前台Li/铃音、production粒子区空，故A6部分完成。完整代码与进度不是外部原因卡死，继续第二阶段。
- 新增二进制16,869,797B只六JPG+一MP4，manifest305473B、56v2 SHA不变。计划/逐项矩阵/results/features/ART_PIPELINE齐；A6任务提交后META写实际hash并普通Git推送clean。
- 下一未开始任务 **A4 v3**。只读预检.tools/art/a4-preflight.md已写：schema6/身份哈希迁移、五态mood审核全链、139部件+人台、现代小镇居民与左上暖光、regen显式portrait组。先读手册A4和style_v3，写正式计划后实施，再G2→G4→G5→G6。当前未到最终审阅包停止条件。
