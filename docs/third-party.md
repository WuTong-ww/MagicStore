# 素材与第三方许可

## 引擎

Godot Engine **4.6.3.stable.official.7d41c59c4**，MIT。官方引擎与 Windows 模板源自 https://github.com/godotengine/godot/releases/tag/4.6.3-stable 。

`GODOT-LICENSE.txt` 和 `GODOT-COPYRIGHT.txt` 是该 release tag 的官方许可与第三方声明，分发游戏与离线环境时一并携带。完整组件说明见 https://godotengine.org/license/ 。

下载压缩包及模板 SHA256 记录于 `scripts/dev/toolchain.json`；安装脚本强制校验下载内容，未使用来历不明的镜像。校验值为本次官方 HTTPS 下载的实际哈希，不声称独立签名认证。

网页试玩同样使用该官方 Godot 4.6.3 release 的 `Godot_v4.6.3-stable_export_templates.tpz`，作者 Godot Engine contributors，MIT及上述第三方声明。抽出的 `templates/web_nothreads_release.zip` SHA256为 `1446F79DC12F60CE5D244C39FB6628EC298337CA5C4F91A16491FEEA72AA1BC9`；整包仍按toolchain.json校验。Web发布目录附六份现有引擎／字体／音效许可，运行文件的实际SHA与来源commit另写build-info.json；不把导出引擎当作本工程原创素材。

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

## A3R 待补音乐

指定来源为 [Cozy Tunes + Cozy FX](https://pizzadoggy.itch.io/cozy-tunes)，作者 Pizza Doggy。2026-11-21 官方页面可读取，先前实际下载请求返回 HTTP 429；v3续跑再查官网及免费领取页仍可读取，但本机获准联网后的下载入口请求遇到TLS EOF，仍未取得三首音乐及完整包内许可，因此本仓库**没有收录或伪造这些音乐**，也没有音乐文件 SHA256。最新访问证据见 docs/codex/results/A3R-music-retry.json。

`data/ui/audio.json` 的 day/night/consultation 三个路径为空并标记 missing；播放器保留 Music 总线、时钟切换与交叉淡入流程，缺文件时安静回退。人工补齐路径分别为 `assets/audio/music/day.ogg`、`night.ogg`、`consultation.ogg`。补入前须核验当时包内许可并登记曲名、来源和 SHA256；遵守手册约束：不得作为素材单独再发布、不得训练 AI、音乐不得进入任何模型请求。当前未取得的许可不被冒称为 CC0 或 OFL。
