# 第四轮 C 线进度

## 工作目录准备（2026-11-27）

- 原目录：D:/MagicStore，原分支 codex/web-playtest。
- 原状态：未跟踪 Cozy Tunes/、github-pages.zip。按明确要求排除 Cozy Tunes/，未读取、移动或纳入备份。
- 已执行 stash push -u -m r4-prep-backup-2026-11-27（路径排除 Cozy Tunes/）。stash：02dfe28ce694ecfa25879c30e125cbcd74f3280f。
- stash show --stat --include-untracked：github-pages.zip | Bin 0 -> 201272486 bytes；1 file changed, 0 insertions(+), 0 deletions(-)。
- stash 卡在 diff-index --cached --binary 收尾，核对原文件与 stash 第三父提交的 blob 均为 a080524bbd86c35fb03602e4b09a643c1fd3a356 后，仅结束本次三个 Git 进程，restore --staged 清除暂存标记；原 ZIP 另存 .tools/r4-prep-backup-2026-11-27/github-pages.zip。stash 保留。
- fetch origin 完成。codex/round3 已被 .tools/round3 worktree 占用，该 worktree 干净；在那里 pull --ff-only：Already up to date。基线 ee576ca。
- ls-remote --heads origin codex/r4-ui 无输出。已在 D:/MagicStore 从 origin/codex/round3 建立 codex/r4-ui。
- 本线不修改 features.md、PROGRESS.md；由本进度与审阅包交接。截图输出目录按任务 C4 的明确要求视为允许的生成产物例外。

## 界面设计约定

应用 frontend-design 技能。沿用现有纸色 #F3E9D6、墨色 #3B2A1E、柔纸 #E2D2B4、朱印 #B5654D、金色 #C99A4B；使用工程已有中文字体。步骤条只表达顺序，蜡封只标记唯一主动作，证据与问题仍采用现有纸手记。布局为顶部步骤、中央当前内容、右下固定主动作。已审核与任务指定的纸张和蜡封方向一致，不另造装饰或资源。

## R4-C1

已实作五步导航、固定主按钮与缺项说明、证据点击替代、逐格状态、建议确认／客人反应／公开结果页，以及首案可关闭引导。引导关闭和笔记已读采用既有动作回执，不增加存档字段；保存失败不更新结果。

前置剧情选择放入来意页，补问与工具使用独立可返回纸页，避免遮挡必要选择。保留已完成步骤回看；完成提问和翻牌后仍需按明确的下一步按钮。

独立 C1 快照的本轮专用测试 97 项通过、0 失败；完整测试存在已确认的边界外基线失败，按本次六项例外提交。此前画面自检已生成 1280×720、1920×1080 流程图；修正后只做测试确认，不重截图。

## R4-C2

已实作 B 线 card_art.json 可选索引、纸色牌名回退、7:12 牌面、保存成功后的 0.35 秒翻牌与牌示滑出、70% 屏高放大。没有新增或修改图片。专用牌面测试 15 项通过、0 失败；完整测试存在已确认的基线失败，按本次六项例外提交。

## 本次发布条件与例外

用户于 2026-11-27 明确授权：

> 先把 C1–C4 提交并推送到 codex/r4-ui。六份已确认的基线失败作为本次全绿门槛的例外，在审阅包写清证据；C5 等 Chrome 恢复后继续，不要改 main。

本提交累计纳入 C1–C2。本阶段专用运行器 115 项通过、0 失败，日志 .tools/r4-c2-final-ui.log。代码逐文件与已通过的阶段验证快照比对一致（49 个非文档文件）。仅文档补入本次例外说明，不重跑或重截图。

完整运行器仍记为未完成／退出 1，不列为全绿。六项原始基线失败、472 项已完成检查中的 28 项失败、另 3 处脚本错误，以及未完成 acceptance 的单项失败，均在审阅包提供源 Git blob、日志 SHA256 和失败摘录。没有修改受保护测试或 scripts/dev/run.ps1。

本阶段将以 [R4-C] 提交并普通推送 codex/r4-ui；不改 main、codex/round3 或发布工作流，不使用强制推送。C5 等 Chrome 连接恢复后继续，采样准备留在本机工作区，尚无性能结论。
