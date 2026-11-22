# codex/round2-clean 上传状态

2026-11-21按用户指令从main e27441b重建；已普通Git推送codex/round2-clean（最新任务提交059baeb，A1R v3）。旧远端codex/round2（18da84a）保持不动，本地备份codex/round2-backup-20261121。远端main核验仍为e27441b。

只取用代码、测试、数据、文字证据、字体音效和正式v2/runtime/v2。被否决的绘本图、incoming、中间物与大批PNG截图不进入新提交。截图只用质量85的JPG，每任务最多6张。Manifest目标<500KB，逐层审计JSONL仅本地。

## 提交前体积检查

待暂存每个任务范围后生成：git count-objects -vH（此数包含原分支、本地备份和旧大图对象，不能当新分支体积）；从main以来所有新增唯一blob大小、其中新增二进制大小、最大blob、追踪截图数及禁止目录检查。新增二进制目标<150MB，单提交>100MB先审计。

## 复验

A3R基线首轮因备份.import重复UID中止，已给本地拒图目录加.gdignore。最终按共享基线与分层工具两个范围整理，完整测试7739/7739、39帧审阅矩阵和体积检查通过后已推送codex/round2-clean。不得强推，不合并main。

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


## A3R tail pre-commit (2026-11-22)

- Full required tests: 8077/8077, exit 0; optional retired local audits explicitly skipped (3).
- Graphics: shell1383/1383, shop718/718, notebook140/140; 51 raw frames and 10 quality-85 JPGs reviewed.
- Pending commit new binary: 2227634 B; clean-history new binary total: 83326050 B. Manifest 68246 B; forbidden paths 0; current screenshot counts A3R=6, G3=4.
- Final evidence: results/A3R-tail-size.json. This staged size snapshot precedes small text report additions only.

## A1R v3 提交前体积复查（2026-11-22）

- 完整测试8362/8362，exit0；实际生产图形1502/1502、shop718/718。62张原帧/最终JPG已逐项审查，任务按部分完成收口。
- 暂存快照新增唯一blob共207,154,082B；从main以来新增二进制203,137,565B。**本次A1R新增二进制119,811,515B（59个新唯一二进制blob）**，全部属于59个明确通过的PNG路径及6个关键JPG路径，未包含候选/拒图/mask/B_i/逐层receipt。
- 超过单提交100MB检查线后已暂停提交、逐OID/路径复查。新增PNG全是17态C、6个合格B_all、6个Li及运行副本和风格参考；重复内容按Git blob去重。1,099个中间文件、1,048,783,624B均保留在ignored incoming，禁止追踪目录0。
- 原CLEAN专用脚本仍输出FAIL（new_binary_total与pending_commit_binary），没有篡改其阈值或把原始结果改成绿。第1步干净重建的<150MB已以81,098,416B完成；此处是之后新增正式v3图，用户全程规则为>100MB先检查，本次已完成该检查，不代表重新满足初始150MB预算。
- Manifest229,143B，所有151正式文件实际SHA/栅格尺寸强制校验；原v2 56文件SHA仍一致；LFS过滤器0；截图A1R=6、A3R=6、G3=4，均质量85 JPG。
- 证据：results/A1R-v3-size-inspection.json；原CLEAN脚本完整快照只保留本地.tools/clean-rebuild/A1R-v3-size.json。下面count-objects包含旧备份与旧大图对象，不能当本次上传流量。

```text
count: 4905
size: 275.11 MiB
in-pack: 4064
packs: 2
size-pack: 1.12 GiB
prune-packable: 2053
garbage: 3
size-garbage: 15.24 MiB
```

本快照先于本段及小型文本报告的暂存，二进制字节不会因这些文本追加变化。不删除旧远端round2，尚未释放其空间。

A1R实际提交059baeb已普通Git推送成功（origin/codex/round2-clean从523692d前进到059baeb）。未使用LFS，未改main或旧round2。

## A2R v3 提交前体积（2026-11-22）

- 完整8555/8555，exit0、0ERROR/WARNING；GUI255/255与718/718。18正式PNG（437003B）及六张质量85 JPG已root打开，原始候选与审计仅本地。
- 本次新增唯一二进制 **1623228B**，小于100MB检查线；从main以来正式clean历史累计 **204760793B**，不谎称小于初始150MB。原CLEAN脚本仍因累计new_binary_total和历史A1R each_clean_commit_binary输出FAIL，保留原结果；初始CLEAN81.1MB及A1R119.8MB逐图检查已在上文说明。
- Manifest **303113B**；禁止追踪路径0，A2R截图6；旧atlas三原生文件仅移legacy，未新增重复图；原v2全部56文件SHA一致。二进制普通Git，无LFS。
- 实际169资源SHA/尺寸与18alpha强制验证全过。体积快照results/A2R-v3-size-inspection.json；.tools/clean-rebuild/A2R-v3-size.json保留原CLEAN检查报告。下面本地对象含旧备份，不能当本次上传量。

```text
count: 5104
size: 276.78 MiB
in-pack: 4064
packs: 2
size-pack: 1.12 GiB
prune-packable: 2053
garbage: 3
size-garbage: 15.24 MiB
```

本段及小型文本证据最后暂存不会改变二进制字节。未删除旧远端round2，尚未释放它占用的空间。

## A7 提交前体积（2026-11-22）

- 最终完整9154/9154，exit0、0错误警告；第三轮shelf940/940及shop710/710。47窗口帧通用225/235（旧人物十项留A4），12组200%接触通过；只提交六张质量85 JPG。
- 本次新增唯一二进制 **1,452,126B**，全部六JPG，小于100MB；旧slot复制到legacy但SHA与已追踪v2完全相同，Git不新增该图blob。原v2全部56文件SHA未变。
- clean正式历史累计新增二进制 **206,212,919B**；manifest **304,408B**；禁止追踪路径0。原CLEAN脚本因累计预算与历史A1R大提交仍输出FAIL，未篡改原阈值；初始CLEAN<150MB和后续>100MB检查的区别见上文。A7没有新增候选/中间PNG或视频。
- 证据：results/A7-size-inspection.json；原完整报告只本地.tools/clean-rebuild/A7-size.json。下列本地对象包含旧备份，不是本次上传流量。

```text
count: 5181
size: 278.38 MiB
in-pack: 4064
packs: 2
size-pack: 1.12 GiB
prune-packable: 2053
garbage: 3
size-garbage: 15.24 MiB
```

普通Git、LFS过滤器停用；main和旧远端round2不改，旧分支空间尚未释放。此快照先于小型文本追加，不影响二进制字节。
