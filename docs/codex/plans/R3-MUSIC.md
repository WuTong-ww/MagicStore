# R3-MUSIC 音乐接入计划

> 执行：使用 superpowers:subagent-driven-development；root 独占 Godot，构建 helper 与只读审查并行。沿用既定目标，无需重新确认设计。

**目标：** 开场、白天、夜晚、案件推理、结局五个音乐场景，1.5 秒交叉淡入；缺音乐静音，音乐仅供本地构建。

**架构：** `data/audio.json` 保存全部 21 首元数据、五槽选曲及候补；MusicCatalog 严格校验并选择，MusicContext 只投影公开状态和实际可见界面。ShopAudio 使用两声部与独立 Music 总线，沿用已有音量设置和 UI/风铃声；Main 仅增加呈现路由。Python 构建 helper 固定 q6 转码，并区分公开无音乐 stage 与显式本地带音乐 stage。

**技术：** Godot 4.6.3 stable / GDScript / Compatibility；Python 3.9；已校验 SHA 的 FFmpeg 7.1 libvorbis。

**规格：** 目标附件 R3-MUSIC；`docs/codex/WEB_ADDENDUM_R3.md`；AGENTS.md。正式基线 `5e22bf72fe28be3cd0ccc96aa03659486f1fd68f`，schema 15，Main d2635fea。完整测试预算已用 1/3，首次通过，不追加轮次。

## 约束与审查重点

- 不改 main，不改世界或存档结构；音量是已有独立呈现设置，保存成功才更新滑杆。
- 保留 TITLE 创建幂等、笔记、模态、双后台 pump、风铃、顶栏字号修复；音乐缺失不能阻断入店。
- 快速 A→B→A、缺曲后切场景、静音/音量中途变化与退出不得留下旧 fade 或资源引用。
- 历史已结局不能代替实际打开结局正文；未结案公开案件板才选推理曲；不读取隐藏事实。
- 公开 stage 无论本地音乐是否存在，排除整个音乐目录；本地带音乐仅显式选择，不覆盖未知输出或原始素材。
- 音频不传模型、不发布公开仓库；文件名初选不等于试听。官方现行许可为带限制的定制协议，记录原包历史许可版本仍待人工确认。

## 步骤与文件

- [x] 1. 将准备稿与当前源码逐 SHA 对齐；先用旧三槽 API 运行功能 RED，保留原日志。
- [x] 2. 安装 `data/audio.json`、`scripts/audio/music_catalog.gd`、`music_context.gd` 与 `tests/audio/music_catalog.gd`、`tests/fixtures/music_fixture.gd`、三个 `tests/integration/music_*.gd`。最小 hunk 接入 ShopAudio/Main，保留其余函数；跑目录、运行时、宿主与原生命周期/风铃目标。
- [x] 3. 安装 `tools/music_build.py` 及 Python 测试；五曲 q6 本地转码。逐曲核对原始 SHA、命令与输出 SHA、OGG CRC/EOS、元数据与整段解码；公共隔离 stage 排除音乐，本地 stage 明确复制。
- [x] 4. 将新目标纳入原 `scripts/dev/run.ps1 -Test`；本地真实 Ogg 目标仅显式 opt-in。逐项关闭独立审查 Important 问题，运行实际 shop_ui 两尺寸并打开截图，提交至多六 JPG。
- [x] 5. 更新 `docs/features.md`、`docs/third-party.md`、审阅包完整 21 曲对照与候补/本地构建步骤；固定源 SHA 后执行标准完整测试，最多三轮，保留失败证据。
- [ ] 6. 生成 `docs/codex/results/R3-MUSIC-validation.json`，准确记录通过数、媒体与限制；普通提交 `[R3-MUSIC]`、推送 codex/round3，回填提交记录，继续 POLISH。

## 验收命令

`powershell -NoProfile -ExecutionPolicy Bypass -File scripts/dev/run.ps1 -Test`

专项使用 `& './scripts/dev/run.ps1' -GameArgs @('--headless','--script','res://tests/integration/music_runtime.gd')` 等数组传参；画面验收使用 `res://tests/integration/shop_ui.gd`。完整测试需要可用的本机回环与 junction 权限；不得为环境错误放宽断言或超时。

## 当前结果

标准full1退出0：24141项检查＋437项Python零失败，953源与素材SHA保持；专项303/0、shop1548/0，六JPG1995753B，默认/带音乐实包22/25项通过。 原mini40与fake21准备证据不替代正式目标，先前失败日志保留。提交推送仍待完成。
