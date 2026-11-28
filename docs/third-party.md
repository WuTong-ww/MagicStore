# 素材与第三方许可

网页版加载页使用既有霞鹜文楷的本地WOFF2子集，构建时由fontTools生成并改名Midnight Loading；作者、来源URL、OFL及源TTF SHA沿用下方文楷登记。没有加入另一套外部字体，派生文件SHA逐包记录于build-info.json，并分发原OFL。源字体不裁剪，Godot界面继续嵌入完整文楷及等宽数字字体。

## 引擎

Godot Engine **4.6.3.stable.official.7d41c59c4**，MIT。官方引擎与 Windows 模板源自 https://github.com/godotengine/godot/releases/tag/4.6.3-stable 。

`GODOT-LICENSE.txt` 和 `GODOT-COPYRIGHT.txt` 是该 release tag 的官方许可与第三方声明，分发游戏与离线环境时一并携带。完整组件说明见 https://godotengine.org/license/ 。

下载压缩包及模板 SHA256 记录于 `scripts/dev/toolchain.json`；安装脚本强制校验下载内容，未使用来历不明的镜像。校验值为本次官方 HTTPS 下载的实际哈希，不声称独立签名认证。

## 中文字体

`assets/fonts/NotoSansSC.ttf` 为 Google Fonts 仓库的 `ofl/notosanssc/NotoSansSC[wght].ttf`，SIL Open Font License 1.1；同目录 `OFL.txt` 保留完整版权与许可文字。

来源：https://github.com/google/fonts/tree/main/ofl/notosanssc 。文件 SHA256：`A3041811A78C361B1DE50F953C805E0244951C21C5BD412F7232EF0D899AF0DA`。本工程使用 FontVariation 固定 400 字重，字体完整随工程分发，无需安装到操作系统。

## 项目占位资源

`assets/shop_front.svg`、`consultation.svg`、`portrait_lin.svg`、`card_back.svg`、`icon.svg` 为本次工程制作的原创矢量占位图；林照晚、案例、对白与牌面解释为本次原创开发内容。未复制影视或其他游戏人物。根仓库未替团队选择整体开源许可证；对外开放源代码许可由仓库所有者决定，第三方许可继续独立适用。

不含在线 AI、密钥、客户资料、账号配置或真实存档。


## 本次新增原创 AI 美术素材（2026-11-20）

`assets/generated_scenes/`、`assets/portraits/`、`assets/ui/` 中的七个场景背景、林照晚表情、人物设定参考、术式插画和 UI 图集由本项目使用 OpenAI 图像生成工具按《零点杂货铺》已确认的水彩手绘、羊皮纸、旧木、苔绿与暖金风格生成并裁切整理。素材清单见 `assets/ART_ASSET_MANIFEST.json`，接入和运行用途见 `docs/ART_ASSET_GUIDE.md`。这些素材不是从影视、小说插画或其他游戏提取的角色图；NPC 参考稿用于本项目原创角色造型，不代表已绑定到具体随机 NPC。

`assets/items/inventory-atlas-v2.png` 为原项目已有的原创商品/原料图标图集，仍由 `data/shop/visuals.json` 映射到统一 `item_id`；本轮没有复制或替换第三方商品图标。

## A3R 字体与界面音效（2026-11-21）

霞鹜文楷：作者 LXGW；上游字形来自 The Klee Project Authors / Fontworks。来源：[官方仓库](https://github.com/lxgw/LxgwWenKai)，下载 [Regular TTF](https://raw.githubusercontent.com/lxgw/LxgwWenKai/main/fonts/TTF/LXGWWenKai-Regular.ttf)，许可 SIL Open Font License 1.1。保留原始字体与完整许可，不做子集、字形修改或单独售卖。

| 文件 | SHA256 |
| --- | --- |
| `assets/fonts/LXGWWenKai-Regular.ttf` | `2D73EEA94AD808999D90C0000C239A84A33B09D4BC6AB6C5B8BBF1EDA8A7FC8B` |
| `assets/fonts/LXGWWenKai-OFL.txt` | `CB973995026E28C931886A1D127397152187E03E53B2F71864E86CEE8C25E54A` |

界面音效：作者 Kenney；来源 [Interface Sounds 1.0 官方页](https://kenney.nl/assets/interface-sounds)，Creative Commons Zero（CC0 1.0）。从官方免费包抽取以下六个未修改的 Ogg 文件，仅重命名；许可保留于 `assets/audio/KENNEY-LICENSE.txt`（SHA256 `F7966C773BBED0ECA6A9C75081C44A178B38EAE112724DBB5FDFBD4192D118A9`）。

| 项目文件 | 原包文件 | SHA256 |
| --- | --- | --- |
| `assets/audio/ui/click.ogg` | `Audio/click_001.ogg` | `ccfb7fa0cccdd9faec0eb16033c732b1e308d139d80f799161495d58f7adcdb9` |
| `assets/audio/ui/page.ogg` | `Audio/scroll_001.ogg` | `320c6aafb2c7a503eae508dc443b72d7f7c0a317bfd16813157ed400cd04cf16` |
| `assets/audio/ui/confirm.ogg` | `Audio/confirmation_001.ogg` | `063564703b6094d70718a3e787a55cc9141611e4ecd6b6637f8828f79b4a8c3a` |
| `assets/audio/ui/cancel.ogg` | `Audio/back_001.ogg` | `07db973f79f6ae0f2edc34561e7592e24d0577455919fb602cb8ecc0da991dcf` |
| `assets/audio/ui/coin.ogg` | `Audio/drop_001.ogg` | `692ee3a6f1821402ca649ff735bee9591dc4846c8098fc7d6a90fd15fa57c1af` |
| `assets/audio/ui/notify.ogg` | `Audio/bong_001.ogg` | `d21d0f0b782445db579d11e2506b24cd1ac9d664ee33aeaf807761aa7b6fd710` |

## R3-TITLE 入店提示

R3-TITLE 入店提示复用上表已有的 Kenney `Audio/bong_001.ogg`（项目文件 `assets/audio/ui/notify.ogg`，SHA256 `d21d0f0b782445db579d11e2506b24cd1ac9d664ee33aeaf807761aa7b6fd710`），新增 `entry_chime` 播放键；未新增、编辑或复制音频素材。原 CC0 来源、作者和许可继续适用。自动化检查覆盖实际 Ogg 播放与关闭释放，人工听感验收另列。

本任务本地录像解码与关键帧提取使用 FFmpeg `7.1-essentials_build-www.gyan.dev`：作者 FFmpeg developers，Windows 构建来自 www.gyan.dev；该实际构建的 `-L` 输出为 GPL-3.0-or-later，参见 [FFmpeg 许可说明](https://ffmpeg.org/legal.html)。可执行文件 SHA256 为 `2ce797a0f88d7f067180338fb227f7b1928ea727bd9a4d7a1d022f7c52af71a3`。

工具取自 [ImageIO 官方上游](https://github.com/imageio/imageio-ffmpeg) 的 [imageio-ffmpeg 0.6.0 Windows wheel](https://files.pythonhosted.org/packages/2c/c6/fa760e12a2483469e2bf5058c5faff664acf66cadb4df2ad6205b016a73d/imageio_ffmpeg-0.6.0-py3-none-win_amd64.whl)，包装作者为 imageio contributors，包装许可 BSD-2-Clause（不替代内含 FFmpeg 的 GPL）；wheel SHA256 为 `02fa47c83703c37df6bfe4896aab339013f62bf02c5ebf2dce6da56af04ffc0a`。工具与包装仅保存在 ignored `.tools`，游戏与公开资源包不分发它们；未修改系统 PATH。

## A3R 待补音乐

指定来源为 [Cozy Tunes + Cozy FX](https://pizzadoggy.itch.io/cozy-tunes)，作者 Pizza Doggy。2026-11-21 官方页面可读取，先前实际下载请求返回 HTTP 429；v3续跑再查官网及免费领取页仍可读取，但本机获准联网后的下载入口请求遇到TLS EOF，仍未取得三首音乐及完整包内许可，因此本仓库**没有收录或伪造这些音乐**，也没有音乐文件 SHA256。最新访问证据见 docs/codex/results/A3R-music-retry.json。

`data/ui/audio.json` 的 day/night/consultation 三个路径为空并标记 missing；播放器保留 Music 总线、时钟切换与交叉淡入流程，缺文件时安静回退。人工补齐路径分别为 `assets/audio/music/day.ogg`、`night.ogg`、`consultation.ogg`。补入前须核验当时包内许可并登记曲名、来源和 SHA256；遵守手册约束：不得作为素材单独再发布、不得训练 AI、音乐不得进入任何模型请求。当前未取得的许可不被冒称为 CC0 或 OFL。


## R3-MUSIC：本地 Cozy Tunes（2026-11-25）

作者 Pizza Doggy；[官方来源](https://pizzadoggy.itch.io/cozy-tunes)。官方当前 `License Agreement.pdf` 标注 2026-11-01，上传 ID 20743451，SHA256 `6416675b7f0696a8be0a9eea57e0dd441b815ee5dce6501f6aaff43be2713e88`。它是带限制的定制协议，允许项目内使用/修改，限制独立素材再分发与 AI 用途，不按无条件 CC0 登记。历史本地原包的取得版本许可尚未证明，留人工核对。原音乐、转换产物和许可 PDF 仅保存在 ignored 本地，均不随公开源码或默认导出发布；音频未进入模型。

前述 A3R 下载失败是当时历史；本轮来源为用户指定的本地原包。`data/audio.json` 登记全部 21 首源 SHA/时长；以下是实际接入的五首（q6 Vorbis，仅本地构建）。

曲目｜原源 SHA256｜本地运行文件 SHA256
---｜---｜---
Gentle Breeze.ogg｜`65f71595d14ed5fabb814e995fe5f8d931b061f64fbda532e7ab86d7ebfa05da`｜`c60d89ffe727557f468b67bce2e69acbfc28582e46dd2299f6dbde5587721c1b`
Sunlight Through Leaves.ogg｜`f9adb44e02947ab36a34300c30243b88d1c9fa6f80d52a5f6fe7bf54561d6799`｜`22f73ad96ed7423dc6724fb83bfd9b0e84cace613e8b4006b7ffbbd9eca4f682`
Evening Harmony.ogg｜`71701ca53aa31d375d5544e590aec818a8326765f98d884c130c7b30e09da43c`｜`510f98c59b8afcc35156b5547e954503e2556e09481a9b5732f3d146c4528d97`
Whispering Woods.ogg｜`93597af7f6ae1cbf6b0bf68caa931d45dc8695a3baaf5910b402336ce8a76f0a`｜`36e92a197df575a721456c79bf81648c04125ca4ef11731a77d5ba6c493c3013`
Fabric Of Life.ogg｜`8622ec2d6391153a52fe53cfc278a53fa62bf03a46ca6215df98a57f63f5f573`｜`3ceb034e9527818c3c62bcaf1b0ad77276609d6e5aa497aae27a42b175693721`

转码工具继续使用上文登记的 ImageIO/FFmpeg 7.1；仅执行本地解码/编码，不将音乐输入生成、评估或训练模型。文件名初选不等于人工试听；授权与听感复核由项目持有人保留。

2026-11-25 玩家试听后指定白天营业与案件接待改用 `Sheep.ogg`，原五首转换文件保留本地。追加原源 SHA256 `306ef172d216f5cebc3a2cefd7cd1df32860a32f6251b4d2737676ac80396b53`；本地 q6 文件 `assets/audio/music/sheep.ogg` SHA256 `1435a3ac15adce7dba6086078c8c3214ee90eb9e294a2c54566ece7698243080`。同一来源、作者与定制许可，不进入公开仓库/默认构建。

2026-11-26用户要求每次自动部署携带BGM供试听，并明确保持仓库公开。沿用上述Pizza Doggy来源与定制许可，选中4首运行曲目共10,853,444B（Gentle Breeze、Sheep、Evening Harmony、Fabric Of Life），逐首SHA见上述表及`data/web_audio_build.json`。构建源ZIP的SHA256为`3cdcc738cd4044b0d6c92494c84762e51782ff230bc1d1c85f6857e5a567e764`，原始素材、明文ZIP与OGG不入Git；只有Fernet认证加密后的14,471,948B密文入普通Git，SHA256 `88f4f404e46b1a8303be4611d12d01f62514e0b522d3c50c9ae2fafe02b98641`，解密密钥另存用户已授权的Actions secret。公开Pages仅分发项目内游戏包，不提供单独素材归档。此项替代前述“默认部署无音乐”的构建选择，不改作者许可或历史版本核对状态；没有将音频输入模型。

构建加密使用Python Cryptographic Authority及贡献者的[cryptography](https://pypi.org/project/cryptography/46.0.3/)，许可Apache-2.0或BSD-3-Clause；[Fernet协议及实现说明](https://cryptography.io/en/46.0.3/fernet/)。CI固定46.0.3，[官方源码包](https://files.pythonhosted.org/packages/source/c/cryptography/cryptography-46.0.3.tar.gz)SHA256 `a8b17438104fed022ce745b362294d9ce35b4c2e45c1d958ad4a4b019285f4a1`（官方PyPI元数据核对）。本机Python3.9.1不受该新版本支持，密文以既有3.3.1的同一Fernet格式生成并完成认证解密往返；未修改系统Python。它仅是构建工具，游戏不打包该库或密钥。

## R3-POLISH 等宽数字字体

数字及ASCII标点使用本项目从霞鹜文楷等宽 Regular v1.530 制作的子集，作者 LXGW / The Klee Project Authors；[固定版本原字体](https://raw.githubusercontent.com/lxgw/LxgwWenKai/v1.530/fonts/TTF/LXGWWenKaiMono-Regular.ttf)，[原许可](https://raw.githubusercontent.com/lxgw/LxgwWenKai/v1.530/OFL.txt)，SIL Open Font License 1.1。原字体SHA256 `895ce1d2fa00d5ca3bec0329d38e3190454f4b5fa7b4733f491c419faf9753a1`，仅保留U+0020–U+007E的95字形，统一原有500 advance；衍生字体改名Midnight Numeric以避开保留名称，原版权通知完整保留。

项目字体 `assets/fonts/MidnightNumeric-Regular.ttf`（30944B）SHA256 `ff3dd9fce45675922f803bae772f0260e4fe126031862a0262a2c0bdcafde8d0`；完整许可 `assets/fonts/MidnightNumeric-OFL.txt` SHA256 `1a25e35da1031c6c3436fde545bb9cb5aca954e9873afe510c834b8b79bd21a0`。中文继续使用前述完整霞鹜文楷，两个FontFile均关闭系统字体回退；未向系统安装字体。

## 第四轮 B2 界面音效（2026-11-28）

作者：Kenney Vleugels（Kenney.nl）。来源包：[UI Audio](https://kenney.nl/assets/ui-audio)、[Interface Sounds](https://kenney.nl/assets/interface-sounds)、[RPG Audio](https://kenney.nl/assets/rpg-audio)。官方页面及包内 License.txt 均标 CC0 1.0；原始 ZIP 仅存工作区临时下载目录，未提交。三份许可证完整内容保存在 assets/audio/ui/r4/LICENSE-*.md，仅规范为LF换行。

处理：取开头至多330ms、转单声道44.1kHz、6kHz低通、头尾5ms淡入淡出、40ms短窗K加权响度约−20 LUFS、Vorbis q4。硬币三候选额外2.2kHz低通；非广播节目R128测量。所有33份运行音效共179498字节。来源包/原文件SHA256、处理参数、音调/起音/响度指标见 data/ui/audio.json 的 sound_catalog，复现选择见 tools/audio/r4_selection.json。未作真人听感签收。

| 文件 | 原文件 | 来源 | SHA256 |
|---|---|---|---|
| assets/audio/ui/r4/click.ogg | click1.ogg | [Kenney](https://kenney.nl/assets/ui-audio) · CC0-1.0 | fc012018bf38d91f38ef5ab1252a3fac76a1b174aaea89c76f52011c411f56c3 |
| assets/audio/ui/r4/click_alt1.ogg | rollover5.ogg | [Kenney](https://kenney.nl/assets/ui-audio) · CC0-1.0 | b3870b4ac334b24153211844f7b959623423a2128429d143380b140ef77ce9b0 |
| assets/audio/ui/r4/click_alt2.ogg | rollover4.ogg | [Kenney](https://kenney.nl/assets/ui-audio) · CC0-1.0 | 7d0a737b1dd80735e056385650b06857702825a36e1a297a47cb72de2b5f1039 |
| assets/audio/ui/r4/page.ogg | bookFlip1.ogg | [Kenney](https://kenney.nl/assets/rpg-audio) · CC0-1.0 | 3d037b37326d78e653b94d0e68247973a60e1ae1b628943fa2d99c6a3a4958cd |
| assets/audio/ui/r4/page_alt1.ogg | bookOpen.ogg | [Kenney](https://kenney.nl/assets/rpg-audio) · CC0-1.0 | 91cc5f9c3310346c896bdeccfa546c2841d07aaafe1b457918b08e8e2c0fc705 |
| assets/audio/ui/r4/page_alt2.ogg | bookClose.ogg | [Kenney](https://kenney.nl/assets/rpg-audio) · CC0-1.0 | f0cb3a3d8687b210e8666d71239f8ee282db97747bc0f9967e6014ea6476686c |
| assets/audio/ui/r4/coin.ogg | handleCoins2.ogg | [Kenney](https://kenney.nl/assets/rpg-audio) · CC0-1.0 | 133ed3485ed629e85f8314be5d274a14d6b759478bf0ed2124c18489229ad201 |
| assets/audio/ui/r4/coin_alt1.ogg | metalLatch.ogg | [Kenney](https://kenney.nl/assets/rpg-audio) · CC0-1.0 | e767f6dd134a494a7ee79ec6d9869911065817ec13d7727d49f9f2e1df9bf6f8 |
| assets/audio/ui/r4/coin_alt2.ogg | metalClick.ogg | [Kenney](https://kenney.nl/assets/rpg-audio) · CC0-1.0 | 9f956a1713d12b59a9b4d6bd0f89010a98a05c57c500acc73194a95845292905 |
| assets/audio/ui/r4/confirm.ogg | bookClose.ogg | [Kenney](https://kenney.nl/assets/rpg-audio) · CC0-1.0 | f0cb3a3d8687b210e8666d71239f8ee282db97747bc0f9967e6014ea6476686c |
| assets/audio/ui/r4/confirm_alt1.ogg | rollover4.ogg | [Kenney](https://kenney.nl/assets/ui-audio) · CC0-1.0 | 7d0a737b1dd80735e056385650b06857702825a36e1a297a47cb72de2b5f1039 |
| assets/audio/ui/r4/confirm_alt2.ogg | back_004.ogg | [Kenney](https://kenney.nl/assets/interface-sounds) · CC0-1.0 | fc066bde4f3374480d9c7cda502be73a8182f41aab2cf98489ce40ded38fa01f |
| assets/audio/ui/r4/cancel.ogg | rollover5.ogg | [Kenney](https://kenney.nl/assets/ui-audio) · CC0-1.0 | b3870b4ac334b24153211844f7b959623423a2128429d143380b140ef77ce9b0 |
| assets/audio/ui/r4/cancel_alt1.ogg | back_002.ogg | [Kenney](https://kenney.nl/assets/interface-sounds) · CC0-1.0 | 8718c66007dfb2ae3c6f4e2fe5dd93f56bd6cc2a65b963dffa6740e37f79a500 |
| assets/audio/ui/r4/cancel_alt2.ogg | cloth3.ogg | [Kenney](https://kenney.nl/assets/rpg-audio) · CC0-1.0 | 508f3712d0c6d089ed95feef43a16deaad518e3330e941ecd4906e2d7a054d6b |
| assets/audio/ui/r4/notify.ogg | glass_003.ogg | [Kenney](https://kenney.nl/assets/interface-sounds) · CC0-1.0 | 34ef49791d9ba48c901be4ee8dd8c696bcd1f2285b6448fd85a62c0a790992f8 |
| assets/audio/ui/r4/notify_alt1.ogg | metalPot1.ogg | [Kenney](https://kenney.nl/assets/rpg-audio) · CC0-1.0 | ce9aaaf8d7ef8e7739a20544d0fa6c08f78d2cc0d4e14f11acd0d189f400fe04 |
| assets/audio/ui/r4/notify_alt2.ogg | metalPot2.ogg | [Kenney](https://kenney.nl/assets/rpg-audio) · CC0-1.0 | d9f6d0e4e9d4a8699bd035a6a270d631fb7722e212714049d32b1c4b7e4daba2 |
| assets/audio/ui/r4/stamp.ogg | bookPlace1.ogg | [Kenney](https://kenney.nl/assets/rpg-audio) · CC0-1.0 | 7f234ff06b1674517e2de6aba15e693ebc9aa80fa866b0f2e9cec3f060e6397d |
| assets/audio/ui/r4/stamp_alt1.ogg | bookPlace3.ogg | [Kenney](https://kenney.nl/assets/rpg-audio) · CC0-1.0 | c4998106e50052d19860ef6636db0dfe43c4be3024d6e057ceca83b757e38016 |
| assets/audio/ui/r4/stamp_alt2.ogg | bookClose.ogg | [Kenney](https://kenney.nl/assets/rpg-audio) · CC0-1.0 | f0cb3a3d8687b210e8666d71239f8ee282db97747bc0f9967e6014ea6476686c |
| assets/audio/ui/r4/card_flip.ogg | bookFlip1.ogg | [Kenney](https://kenney.nl/assets/rpg-audio) · CC0-1.0 | 3d037b37326d78e653b94d0e68247973a60e1ae1b628943fa2d99c6a3a4958cd |
| assets/audio/ui/r4/card_flip_alt1.ogg | bookOpen.ogg | [Kenney](https://kenney.nl/assets/rpg-audio) · CC0-1.0 | 91cc5f9c3310346c896bdeccfa546c2841d07aaafe1b457918b08e8e2c0fc705 |
| assets/audio/ui/r4/card_flip_alt2.ogg | cloth4.ogg | [Kenney](https://kenney.nl/assets/rpg-audio) · CC0-1.0 | 6dfc01d33c41a3a060aa527d6f3dedd8f0e37ca1f8b88d217e1dd9bbc12896aa |
| assets/audio/ui/r4/card_slide.ogg | cloth2.ogg | [Kenney](https://kenney.nl/assets/rpg-audio) · CC0-1.0 | 47589a21f73041f36e043625643aab39559d9bae050340bc71652bbfa55036c4 |
| assets/audio/ui/r4/card_slide_alt1.ogg | scroll_003.ogg | [Kenney](https://kenney.nl/assets/interface-sounds) · CC0-1.0 | 1c5f43f76ba661ccec6e26f53c50c55e62941d02687abccab6f5e1a6a0c39beb |
| assets/audio/ui/r4/card_slide_alt2.ogg | cloth3.ogg | [Kenney](https://kenney.nl/assets/rpg-audio) · CC0-1.0 | 508f3712d0c6d089ed95feef43a16deaad518e3330e941ecd4906e2d7a054d6b |
| assets/audio/ui/r4/paper.ogg | bookPlace3.ogg | [Kenney](https://kenney.nl/assets/rpg-audio) · CC0-1.0 | c4998106e50052d19860ef6636db0dfe43c4be3024d6e057ceca83b757e38016 |
| assets/audio/ui/r4/paper_alt1.ogg | cloth4.ogg | [Kenney](https://kenney.nl/assets/rpg-audio) · CC0-1.0 | 6dfc01d33c41a3a060aa527d6f3dedd8f0e37ca1f8b88d217e1dd9bbc12896aa |
| assets/audio/ui/r4/paper_alt2.ogg | bookPlace2.ogg | [Kenney](https://kenney.nl/assets/rpg-audio) · CC0-1.0 | ec10ab70fd1d1af44f39b93071e4cc6832b4b2f6f2a86b5c4746ad66e374abbb |
| assets/audio/ui/r4/wood.ogg | bookClose.ogg | [Kenney](https://kenney.nl/assets/rpg-audio) · CC0-1.0 | f0cb3a3d8687b210e8666d71239f8ee282db97747bc0f9967e6014ea6476686c |
| assets/audio/ui/r4/wood_alt1.ogg | bookPlace1.ogg | [Kenney](https://kenney.nl/assets/rpg-audio) · CC0-1.0 | 7f234ff06b1674517e2de6aba15e693ebc9aa80fa866b0f2e9cec3f060e6397d |
| assets/audio/ui/r4/wood_alt2.ogg | rollover4.ogg | [Kenney](https://kenney.nl/assets/ui-audio) · CC0-1.0 | 7d0a737b1dd80735e056385650b06857702825a36e1a297a47cb72de2b5f1039 |

每个用途一个主选和两个候选；若相同源与相同处理在不同用途复用，输出字节相同且来源逐份登记，不伪称不同录音。

## 第四轮 B1：Rider–Waite–Smith 1909 原版牌面

- 作者 Pamela Colman Smith（1878–1951），Rider & Company，1909 Pam-A 原版；上游元数据标注 Public Domain。本项目只采用原始历史画作，不采用现代 U.S. Games 扫描。
- 固定来源：[mixvlad/TarotCards，840b84d012c6b74dc1634fa2d00d1b21f5b28093](https://github.com/mixvlad/TarotCards/tree/840b84d012c6b74dc1634fa2d00d1b21f5b28093/tarot/rider-waite)。其当前 metadata.json / SOURCES.md 实际注明 [Steve P. 的 1909 Pam-A 修复扫描](https://steve-p.org/cards/RWSa.html)，与任务书中的 Wikimedia 描述不同，按真实来源记录。仓库的 MIT 仅适用于其代码，画作依据独立的公有领域标注。
- 仅 78 张 `full-png` 牌面，封套和其他牌组未使用。每张源 Git blob、源 SHA256 与输出 SHA256 完整列于 `assets/oracle/rws/provenance.json`。
- 处理：安全裁白边、饱和度 −10%、轻微暖色，等比容纳到 360×617（7:12 的最近整数），双线性缩小与固定 0.7px 抗锯齿，WebP quality 80 / method 6。保留原图内容、原版标题和边框；详情与复现方法见 `assets/oracle/rws/README.md`。
