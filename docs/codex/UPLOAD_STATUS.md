# codex/round2-clean 上传状态

## WEB 独立实验试玩：已部署、部分完成（2026-11-24）

实际feature `2b4ec419fc56d285b5cafe3647a41ef42e33e379`、workflow修复 `02d1d423aba4741c929acb1b2542a818ff939ef9` 已普通push至codex/web-playtest。成功CI45322600343部署 https://wutong-ww.github.io/MagicStore/ ，build-info绑定02d1d42；HTML／JS实际全SHA，大文件只HEAD／Range，浏览器未验。首次CI45321775777失败保留；生产provider／游戏规则无变化，完整三轮exit1及尾段HTTP3fail不因部署成功变绿。尾段现complete=true／exit1，最终分域与14log SHA／415源码零变见WEB-validation；只补文本META，不新增二进制，不触发docs以外的新CI。

发布前远端已实读main=e27441b51a4415777971cf2d8142ce4c725437e5、round2-clean=2b34ecb558bcfb95eb5f0648882120147f8cbec6、旧round2=18da84a23b287fbb7be506b50e3778b727850f3a；最终push后再核。以下初版／体积说明按当时快照保留，当前终态以上段及WEB-deployment为准。

分支codex/web-playtest基于2b34ecb，main／round2-clean／旧round2均不改写。完整三轮都exit1；第3轮90个已完成summary共14170检查、0 reported failures后，默认环境HTTP夹具30秒超时，未完成HTTP及尾段不填全绿总数。按三轮上限授权部分完成实验发布，不开full4。生产游戏规则／provider无变化，四HTTP夹具保留原断言／阈值；独立有限检查与原生634包烟测、GPU1544／30张分域记录。

初始暂存体积快照相对2b34ecb新增唯一blob830062B，二进制仅2张质量85 JPG合计622504B；后补验收／发布文本不计入该初始快照，二进制不再新增。禁止目录0、中央497438B保持，详见results/WEB-size-inspection.json。Cozy Tunes与用户音乐包未追踪、不提交、不删除、不移动；build/web不进Git，只作为Pages artifact。

已启用Pages workflow与仅允许codex/web-playtest的部署环境；实际任务commit／push、CI和公网文件结果将在发布后补记。原生两JPG人工8／10，旧林笔触未齐；浏览器工具因URL识别不可靠停止，WebGL／IndexedDB／Claude实操不签通过。

实验初版发布时独立尾段仍进行，回执complete=false；HTTP442项／3失败保留，mood／family未达，不能据更早一次513＋wire256通过抹除本次失败。PERSON64、People359及Python117分别通过；尾段终态另用纯文档META更新，不跑full4。

最新状态（2026-11-23）：G4任务ea6a4f8已普通Git推送到codex/round2-clean；三轮上限部分完成，当前META仅补实际hash与体积。首段2026-11-21为历史建分支记录。

G4发布字节核查：为四个已记录SHA的CSV／SVG／JSON回执设置精确路径-text属性；生成SVG的路径行尾空格和回执CRLF按原字节保留。四文件暂存对象和checkout过滤结果均与原文件相等，diff检查exit0；游戏源码／测试／数据冻结不变，1201路径仅.gitattributes这一项发布元数据变化。二进制依旧3,128,672B，无LFS，见results/G4-publication-integrity.json。

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

## G4 最终收口补记（单30日证据已完成，待任务提交）

标准完整三轮均exit1，按三轮上限提交部分完成；限定图形1544/1544与138/138、人工223/240、素材环境单例1/1分别保留，不拼成全绿。手册所需的一条真实30日已封存并独立导出：40→2562、最低37，四现金列与JSONL／实际B+C账簿闭合；root已实开SVG对应预览。停止回执见`results/G4-economy-stop.json`，原会话72701主动停止−1，原自拟180日未完成；恢复仅第16日完成及第17日局部，不签完整续段等价。

最终1201源码路径逐SHA／bytes仍0差异，56个原v2保持，中央361记录／499845B，六封存经营输入SHA保持，见`results/G4-source-freeze.json`。最终追加物仅文本JSON／CSV／SVG，二进制仍3,128,672B。现金后15天增加1538，长期积累／其他策略覆盖仍列风险，不能把单条报警线通过当完整经济平衡。

提交本体的精确unique blob数／字节和实际hash将在任务提交后的META补记；本段不提前宣称已推送。main／旧round2／本地backup仍保持。

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

## A6 提交前体积（2026-11-22）

- 完整第3轮9653/9653（9372+94+187），exit0、0错误警告。正式preview第3轮508/508且4pair+8control通过，34PNG与已审round2相等；53窗口/关键帧通用245/265，旧人物与启动渐显等缺口保留，性能两次实测仍false。
- 新增唯一二进制 **16,869,797B**：六质量85 JPG合计1,560,999B与MP4 15,308,798B。小于100MB；原AVI/候选/.tools审计0追踪。56个v2 SHA不变，manifest305,473B。
- clean累计新增二进制 **223082716B**。原CLEAN脚本仍因new_binary_total及each_clean_commit_binary FAIL；初始81.1MB和后续A1R119.8MB已单独检查，不谎称累计<150MB。结果见results/A6-size-inspection.json。
- 本地对象包含旧备份，不是A6上传流量；普通Git，不用LFS；main/旧远端round2不改。最终包仍需请策划手动删除GitHub旧round2释放空间。

```text
count: 5270
size: 294.46 MiB
in-pack: 4064
packs: 2
size-pack: 1.12 GiB
prune-packable: 2053
garbage: 3
size-garbage: 15.24 MiB
```

## A4 提交前体积（2026-11-23）

- 完整最后第3轮10278/10278（9940+107+231），exit0、0错误警告；正式portrait393/395保留两页签失败，shop694/694。24真实顾客同档重开24/24，root37最终PNG与六JPG全看，通用175/185；不把headless通过说成图形全绿。
- 新增唯一二进制 **10,703,272B**：140正式头像PNG（含人台）9,775,102B，六质量85 JPG合计928,170B。小于100MB；候选、原生、中间图和逐源详审0追踪。56个v2 SHA保持，manifest499,605B。
- clean累计新增二进制 **233,785,988B**；暂存快照新增unique blob共 **243017677B**。原CLEAN helper仍因new_binary_total及历史each_clean_commit_binary两项FAIL，原始阈值／失败未改；初始CLEAN与后续A1R正式资源的区别见前文，A4没有把中间物带入。禁止路径0，A4截图6JPG。见results/A4-size-inspection.json。
- 本地对象包含旧备份，不等于本次上传量；普通Git无LFS，main／旧round2不改。此快照先于本小型文本证据追加，不影响二进制字节。

```text
count: 5668
size: 304.73 MiB
in-pack: 4064
packs: 2
size-pack: 1.12 GiB
prune-packable: 2053
garbage: 3
size-garbage: 15.24 MiB
```

## G2 提交前体积（2026-11-23）

- 标准完整第2轮11252/11252、exit0、零错误警告；shop694/694、家族GUI第三轮114/115如实保留。
- 本任务新增唯一二进制 **1,531,178B**，只有六张quality85 JPG；没有新增图源、候选、PNG、中间物或详审进入Git。单任务远低100MB，禁止路径0，全部截图任务各≤6张。
- manifest **499,605B**，56个v2原输入SHA逐项保持；G2普通Git上传，LFS过滤器保持停用，main／旧round2不动。
- clean累计新增二进制 **235,317,166B**，本次暂存快照新增unique blobs共 **245373769B**。原CLEAN helper仍因累计new_binary_total与历史A1R的each_clean_commit_binary FAIL；原始阈值与结果没有修改，不把历史累计误报为G2新增过量。见results/G2-size-inspection.json。
- 本地对象包括旧backup，下面不是本次上传流量。快照先于少量最终文本追加，二进制计数不受影响；完整测试与最终提交状态另见PROGRESS。

```text
count: 5812
size: 306.53 MiB
in-pack: 4064
packs: 2
size-pack: 1.12 GiB
prune-packable: 2053
garbage: 3
size-garbage: 15.24 MiB
```

G2实际提交／推送补记：5297418已普通Git推送，55个相对父提交新增unique blobs共 **2,363,202B**，其中六JPG二进制 **1,531,178B**。这是任务提交本体的精确值，后续记录hash的META文本不计入该值。原始预提交snapshot／历史累计FAIL原样保留。

## G4 暂存体积（2026-11-23，经济专项仍运行）

- 当前202条暂存路径相对HEAD产生201个新增unique blob，共 **5,530,038B**；二进制 **3,128,672B**，仅52张通过自评的物品PNG（1,410,584B）和六张quality85 JPG（1,718,088B）。小于100MB，没有候选／中间图／本地详审进入Git。后续验证文本、CSV和SVG尚未计入此快照，最终任务提交后再补精确值。
- 中央清单 **499,845B**／361记录；全部56个原v2路径的SHA保持。禁止追踪路径为0，截图均为真JPG且各任务≤6张；普通Git，LFS过滤器仍停用。
- clean累计二进制 **238,445,838B**，暂存快照新增unique blobs累计 **251,019,958B**。原CLEAN报告仍保留累计150MB与历史A1R单提交检查两项FAIL，不能把历史累计量说成G4本次超标，也不改阈值抹去失败。原始对象详单只留本地，精简报告见`results/G4-size-inspection.json`。
- G4三轮标准完整均exit1，最后v5外观迁移次序断言未通过，按三轮上限保留部分完成。实际GPU 1544/1544与138/138、人工48图223/240另列，不替代完整绿。此处暂存供体积审查，**尚未提交／推送G4**，仍等待真实正式经济专项结束；main、旧round2及本地backup不动。

本地Git对象含旧备份，并非本次上传流量：

```text
count: 6051
size: 310.23 MiB
in-pack: 4064
packs: 2
size-pack: 1.12 GiB
prune-packable: 2053
garbage: 3
size-garbage: 15.24 MiB
```

## G4实际任务提交／上传

- ea6a4f8f0ade6589fa5605e301cd18a66612ac01已普通push，实际exit0；远端d6a0847→ea6a4f8。212文件，相对父提交211个新增unique blobs共5,693,761B；58个二进制3,128,672B。后续META文本不计入任务本体。
- 普通OpenSSL首试SSL_ERROR_SYSCALL；单命令http.sslBackend=schannel复试成功，未关证书验证、未改持久配置、无force/main/旧round2改动。
- 实际提交对象计数（含旧备份，不是网络上传量）：

`	ext
count: 6110
size: 310.44 MiB
in-pack: 4064
packs: 2
size-pack: 1.12 GiB
prune-packable: 2053
garbage: 3
size-garbage: 15.24 MiB
`

## G5 发布检查（2026-11-24）

G5按三轮上限部分完成，完整第3轮14533/14533／exit0；GPU441、shop1544通过，47帧人工204/235，未知烟雾与旧头像等未通过项如实保留。实际任务提交888a15dae680a482c8502ef61664508ed0bbd0ef已普通Git推送，远端0d9c0bb→888a15d；无LFS／无强推。最终任务79路径，额外只加发布文本，二进制仍19862857B。

相对已推送0d9c0bb，本次新增二进制19,862,857B＝六定稿PNG18,983,166B＋六质量85 JPG879,691B，低于100MB；无候选／incoming／详审／原PNG截图入Git。中央497438B、364记录／91运行副本；v2全部56SHA不变。该预发布暂存快照77路径／新增唯一blob21,462,975B；随后仅文本元数据另记，不把旧累计美术历史说成<150MB。检查报告results/G5-size-inspection.json。

本地git count-objects（包含旧备份／大图对象，不是上传量）：

```text
count: 6227
size: 329.69 MiB
in-pack: 4064
packs: 2
size-pack: 1.12 GiB
prune-packable: 2053
garbage: 3
size-garbage: 15.24 MiB
```

## G6 发布检查（2026-11-24）

G6部分完成；完整第1轮15504/15504、GPU121/121、shop1544/1544，全部exit0。42帧实开通用检查190/210，成交代理与旧头像等残项保留。任务提交hash及普通push结果在最终收口补记。

相对已推送df7381f，本次暂存34路径／34新增unique blobs共2,055,866B；二进制1,611,390B，仅六张quality85 JPG，低于100MB。后补size报告及上传文本不改变二进制量。禁止追踪路径0；中央清单497438B，原v2全部56SHA不变；原始PNG、候选与本地详审未入Git。精简报告results/G6-size-inspection.json。历史累计量不改写为小于150MB。

本地Git对象（包含旧备份，不是本次上传量）：

```text
count: 6290
size: 331.29 MiB
in-pack: 4064
packs: 2
size-pack: 1.12 GiB
prune-packable: 2053
garbage: 3
size-garbage: 15.24 MiB
```

## G6实际提交／普通上传与终态

- 任务94586d1e48ece5a16969b14b2590211552d9f672已普通push，实际exit0，远端df7381f→94586d1；使用命令级Schannel／HTTP1.1，未关闭证书验证或改变持久配置。
- 实际任务36路径，相对父提交36个新增unique blobs共2,082,670B；其中六JPG二进制1,611,390B。相对预发布34路径仅追加size与上传文本；后续最终审阅包／进度收口均为纯文本。
- 完整15504/15504与图形结果已封存。最终REVIEW_PACKET随本次纯文本收口提交发布；主分支、旧round2和本地backup保持，旧远端删除仅列待策划确认。
