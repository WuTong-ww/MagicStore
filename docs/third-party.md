# 素材与第三方许可

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

## R3-POLISH 等宽数字字体

数字及ASCII标点使用本项目从霞鹜文楷等宽 Regular v1.530 制作的子集，作者 LXGW / The Klee Project Authors；[固定版本原字体](https://raw.githubusercontent.com/lxgw/LxgwWenKai/v1.530/fonts/TTF/LXGWWenKaiMono-Regular.ttf)，[原许可](https://raw.githubusercontent.com/lxgw/LxgwWenKai/v1.530/OFL.txt)，SIL Open Font License 1.1。原字体SHA256 `895ce1d2fa00d5ca3bec0329d38e3190454f4b5fa7b4733f491c419faf9753a1`，仅保留U+0020–U+007E的95字形，统一原有500 advance；衍生字体改名Midnight Numeric以避开保留名称，原版权通知完整保留。

项目字体 `assets/fonts/MidnightNumeric-Regular.ttf`（30944B）SHA256 `ff3dd9fce45675922f803bae772f0260e4fe126031862a0262a2c0bdcafde8d0`；完整许可 `assets/fonts/MidnightNumeric-OFL.txt` SHA256 `1a25e35da1031c6c3436fde545bb9cb5aca954e9873afe510c834b8b79bd21a0`。中文继续使用前述完整霞鹜文楷，两个FontFile均关闭系统字体回退；未向系统安装字体。
