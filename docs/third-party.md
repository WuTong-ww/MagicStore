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
