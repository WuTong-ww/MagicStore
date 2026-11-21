# codex/round2-clean 上传状态

2026-11-21按用户指令从main e27441b重建；当前整理中，尚未推送。旧远端codex/round2（18da84a）保持不动，本地备份codex/round2-backup-20261121。

只取用代码、测试、数据、文字证据、字体音效和正式v2/runtime/v2。被否决的绘本图、incoming、中间物与大批PNG截图不进入新提交。截图只用质量85的JPG，每任务最多6张。Manifest目标<500KB，逐层审计JSONL仅本地。

## 提交前体积检查

待暂存每个任务范围后生成：git count-objects -vH（此数包含原分支、本地备份和旧大图对象，不能当新分支体积）；从main以来所有新增唯一blob大小、其中新增二进制大小、最大blob、追踪截图数及禁止目录检查。新增二进制目标<150MB，单提交>100MB先审计。

## 复验

A3R基线首轮因备份.import重复UID中止，已给本地拒图目录加.gdignore；第二轮完整测试进行中。全部三组干净范围完整测试通过并通过体积检查后才推送codex/round2-clean。不得强推，不合并main。

## 远端保留事项

旧codex/round2含约1.2GB被否决图与中间产物，不能因新建干净分支就声称已释放远端空间。**请策划最终在GitHub手动删除远端codex/round2分支以释放空间**；本代理不删除该远端分支。


## BASE staged snapshot

Git size review: **PASS**

- Base: `e27441b51a4415777971cf2d8142ce4c725437e5`; HEAD: `e27441b51a4415777971cf2d8142ce4c725437e5`.
- New unique blobs: **82653183 B**; binary: **81098416 B** / <150000000 B.
- Current HEAD commit binary: 0 B; pending index commit binary: 81098416 B (each <=100000000 B).
- Maximum new blob: 25928940 B `7f8f031dc5c6c5ba1913d93c36d4667c1e311cea` assets/fonts/LXGWWenKai-Regular.ttf.
- Prohibited tracked paths: 0; manifest: 73519 B / <500000 B.
- Round2 screenshots: A3R=6, G3=4; each tracked screenshot must be real JPG, <=6 per task.
- Failed checks: none.

Committed clean history and staged tree only; unstaged and untracked working files are excluded. No index/tree/ref writes were performed.

Local Git storage (includes old local backups; **not** upload bytes):

```text
count: 4616
size: 159.60 MiB
in-pack: 4064
packs: 2
size-pack: 1.12 GiB
prune-packable: 2053
garbage: 3
size-garbage: 15.24 MiB
```

This is the pre-commit staged snapshot; the small text report files themselves are added afterwards. Binary totals are exact and unchanged by those text-only additions.


## CLEAN final staged snapshot

- Required tests: 7739/7739, exit 0; three optional retired image audits explicitly skipped when local JSONL is absent. No artwork approval implied.
- Graphic checks: round2_shell 1383/1383 (17 frames); shop_ui 718/718 (22 current frames). Root review: 39-row matrix in results/CLEAN-visual-review.md.
- Preserved v2 originals: all 56 SHA256 unchanged.
- New unique blob bytes: 83714531; new binary bytes: 81098416 (<150000000); this pending toolchain commit adds 0 binary bytes.
- Manifest: 68246 bytes (<500000). Forbidden index/history paths: 0. Screenshots: A3R 6 JPG, G3 4 JPG, quality 85.
- Measurement: staged snapshot before adding these small text reports; binary totals remain exact.

`	ext
count: 4662
size: 159.76 MiB
in-pack: 4064
packs: 2
size-pack: 1.12 GiB
prune-packable: 2053
garbage: 3
size-garbage: 15.24 MiB
`

Local storage above includes old backups, not upload volume. Final size evidence: results/CLEAN-tools-size.json. Clean push is the next action; old remote round2 and main stay unchanged.
