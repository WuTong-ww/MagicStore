# 第二轮 v3 续跑进度

2026-11-21用户恢复目标，策划否决绘本风「太冷清」。新分支codex/round2-clean从main e27441b重建；原codex/round2与其远端18da84a不改写、不删除。本地备份codex/round2-backup-20261121指向18da84a。

## 当前恢复点

正在第1步CLEAN：逐路径取用后按可独立验收边界形成A3R/G3共享基线、A1R工具链两个干净提交；禁止把18da84a整体cherry-pick或merge为祖先。

- A2R未提交69个路径已逐字节备份，物品图移入assets/_incoming/a2r_v2_rejected/；代码、JSON、补丁也在该目录worktree内。A2R v3时再复用去背/check_alpha/bottom_y/64流程。
- 原incoming、v3_real、runtime/v3_real、runtime/v3均保留本地但忽略；a1r_pilot已改名a1r_pilot_rejected。旧原始截图在.tools/clean-rebuild/preserved/docs/screenshots/round2。
- 56个assets/generated_scenes/v2文件SHA未变；新分支尚无任何被拒目录被追踪。
- 当前只恢复A3R基线101路径，6张关键JPG（质量85）。首轮全套因本地备份.import重复UID中止；已为本地拒图目录加.gdignore。第二轮完整测试在跑，日志.tools/clean-rebuild/A3R-full-tests-round2.log，session61378。不要与此时未恢复的G3/A1R混淆。
- A3R真实图形检查由a3r_consultation执行，根工具链与manifest瘦身代理只写独立工具或.tools临时输出，未进入生产。

下一步：A3R基线全套/真实图形→按CLEAN.md记录并提交；恢复G3路径全套并提交；恢复A1R工具路径、压缩manifest及可选本地审计入口全套并提交。新增二进制<150MB、单提交>100MB需先审计；count-objects与blob报告写UPLOAD_STATUS。完成第1步后推送clean，再做A3R收尾→A1R v3→A2R v3→A7→A6→A4→G2→G4→G5→G6。

**最新恢复点（覆盖前述早期过程）**：早期A3R独立回放三轮已停止（UID备份、旧音频退出、误拆G3断言）；为了不回退已审代码，现完整组装4789a5b的A3R/G3共享基线，并取18da84a最终gateway容量释放修复。生命周期归回A3R责任但首提交统一为共享基线。当前BASE完整测试session14193，日志.tools/clean-rebuild/BASE-full-tests-round1.log，已过UI烟测/事件等前半，尚未声称全套通过。tests/integration/round2_shell.gd的原图输出改为.tools/round2/A3R。a3r_consultation在跑冻结基线真实图形并逐图检查，将只更新6JPG。A1R工具尚未restore，但独立tools/art/local_audit.py与test_local_audit.py已新增并冻结，13/13 Windows原生junction实测、0skip，暂不要随首BASE误stage。manifest提案在.tools/clean-rebuild/output/ART_ASSET_MANIFEST.json（68246B），JSONL也在output，正式manifest尚未替换。下一步BASE绿→体积报告→首干净提交；之后restore_stage.py A1R_TOOLS并适配local audit/compact readers，全套绿→第二干净提交→推送clean。两个新提交此前均未创建。

任务ID｜状态｜提交｜说明
---｜---｜---｜---
CLEAN｜进行中｜—｜main新基点，不带入旧大图历史；尚未声称完整测试通过。
G3（原成果）｜完成，待干净重建复验｜原4789a5b｜总监通过邀请推荐回归。
A3R（新收尾）｜待执行｜—｜热区牌/精力文字/手记遮罩与关闭按钮/咨询构图/缺音乐处理。
A1R v3｜待执行｜—｜仅用原v2图编辑，先S02三候选实际逐项评分。
A2R v3、A7、A6、A4、G2、G4、G5、G6｜待执行｜—｜依用户新顺序。

所有后续素材以用户v3新提示词为准；候选/中间不提交，只有通过自评的定稿与运行副本可进入新分支。详细审计JSONL仅本地；每任务最多6张JPG，原图放.tools。最终REVIEW_PACKET追加v3改向，并在待确认提醒策划手动删除远端codex/round2释放空间。

**BASE最新终态**：session14193已exit0，Godot7246/7246（62计数组）+Python94/94=7340/7340，0错误/警告。文本证据results/CLEAN-base-full-tests.txt。当前仅待图形逐图报告和体积检查后首个干净提交；A1R工具链还未正式恢复。原进度/上传/审阅全文已保存在history/round2-v2-*，避免旧结论冒充v3当前结果。
