# 零点杂货铺 · COVER 第一段

日期：2026-11-27。分支：`codex/cover`。基线：`origin/codex/round3`，`ee576ca0660804a86bb3a652ff3f75244272d039`（远端读取确认）。本段只新增封面素材与制作工具，尚未接入游戏或网页。

## 原图、版本与登记

使用内置 `image_gen`，提示词版本 COVER-v1；未使用 CLI 或外部 API。A、B 各成功生成一次，首次调用均遇到连接错误后原提示词重试成功，未进行美术重画。没有外部图片输入；制作前查看既有 v3 S01/S02 夜景，并在提示词描述它们的材质、笔触和配色。

| 素材 | 文件 | 实际原生尺寸 | 处理 |
|---|---|---|---|
| A 店外黄昏（主版） | `assets/cover/key_art_a_2560x1440.png` | **1672×941** | 复制生成器原始 PNG 字节，未裁切、未放大 |
| B 柜台近景（备选） | `assets/cover/key_art_b_2560x1440.png` | **1672×941** | 复制生成器原始 PNG 字节，未裁切、未放大 |

文件名按任务指定保留，**文件名的 2560×1440 不是实际分辨率**。生成器未提供请求的 2560×1440，返回近 16:9 的 1672×941（比例误差约 0.053%），原始字节完整保留。1920×1080 合成图按交付尺寸重采样，属于排版输出，不宣称原生插画达 1920×1080。原图不含标题、副标题、签名或水印。

原始生成文件：
- A：`exec-74017e9b-228a-43e8-b69f-1263c83e5d9f.png`
- B：`exec-29f8b76f-eba0-4ba0-8433-53ba849b19e9.png`

源字节 SHA256、每张导出图的实际尺寸与 SHA256 见 [完整文件清单](../../tools/cover/file_inventory.md)。本次目标明确禁止修改 `assets/ART_ASSET_MANIFEST.json` 和 `docs/third-party.md`；本页暂存生成与外部资源登记，合并时统一登记。也未修改 `docs/features.md`；本页的“产出与用途”记录本次功能增量。未修改任何既有文件。

## 插画提示词

以下是成功调用的完整原文，也分别保存在 `tools/cover/prompt_a.txt` 与 `prompt_b.txt`。

### A · COVER-v1

```text
Use case: illustration-story
Asset type: text-free game cover key art A, full bleed landscape 16:9, requested native 2560x1440 pixels; use the largest available native 16:9 output if that exact size is unavailable.
Primary request: A small two-storey old stone and timber curio shop on the corner of a quiet cobbled lane at blue hour, just after rain. The shop sits on the right half of the picture, seen at eye level from a slight three-quarter angle. Its arched front window and half-open green wooden door are lit from inside with warm lamplight; the light spills out in soft-edged shapes onto the wet cobblestones, which reflect it gently. Through the window you can see shelves of jars and a counter with a small oil lamp left burning, a teapot, and three tarot cards laid face-down. A single branch of wisteria hangs over the door; a plain wooden hanging sign with no writing sways from an iron bracket. Across the lane on the far left, a small bus-stop bench with a folded paper bread bag on it. The upper-left third of the picture is open sky: deep blue fading to a faint warm band near the rooftops, a thin crescent moon and a few small stars, kept calm and empty for a title. Puddles, a few fallen leaves, potted herbs by the step. Quiet, warm, inviting, slightly melancholy, as if someone left the light on for whoever comes next.
Style/medium: hand-painted background painting for a traditional animated film, made with opaque poster colors on paper, visible brush strokes and soft edges, natural and beautiful light with a clear source, warm interior lamplight against cool blue dusk, cool blue-green shadows never black, muted warm palette balanced with sage green and dusty teal, lived-in but tidy, detail concentrated at the focal point and painted more loosely toward the edges, matte paper texture, no text, no letters, no logo, no signature, no watermark, no bloom, no halo around lights, no light rays, no sparkles, no lens flare, no bokeh, no glossy surfaces, no ornate gold filigree
Style continuity: aged stone, timber framing, muted sage shutters, ochre terracotta roof tiles and softly painted cool blue dusk as in this project's v3 S01/S02 scenes. Opaque brushy background painting, never photorealistic.
Composition constraints: genuinely calm open sky across upper left for five large Chinese title characters added later by code; keep the building on the right. Bottom foreground is calm cobblestone with no key objects, to allow a future 120px progress bar. Blank sign and blank jar labels. NO typography of any kind.
```

### B · COVER-v1

```text
Use case: illustration-story
Asset type: text-free game cover key art B, full bleed landscape 16:9, requested native 2560x1440 pixels; use the largest available native 16:9 output if exact size unavailable.
Primary request: A close view across an old wooden shop counter at night, seen from the shopkeeper's side. On the counter: a small brass oil lamp casting a warm pool of light, an open old notebook with a ribbon bookmark and two pages neatly cut out near the spine, three tarot cards in a row with the middle one turned face-up showing a simple star design, a ceramic teacup with faint steam, a small music box with its lid open, and a paper bread bag. Behind the counter, a window shows a cool blue rainy lane with one warm street lamp far away. The upper third of the picture is a quiet, softly lit plaster wall with a few hanging dried herb bundles, kept calm for a title. Warm light falls off naturally toward the edges; everything else rests in cool blue-green shade.
Style/medium: hand-painted background painting for a traditional animated film, made with opaque poster colors on paper, visible brush strokes and soft edges, natural and beautiful light with a clear source, warm interior lamplight against cool blue dusk, cool blue-green shadows never black, muted warm palette balanced with sage green and dusty teal, lived-in but tidy, detail concentrated at the focal point and painted more loosely toward the edges, matte paper texture, no text, no letters, no logo, no signature, no watermark, no bloom, no halo around lights, no light rays, no sparkles, no lens flare, no bokeh, no glossy surfaces, no ornate gold filigree
Style continuity: same opaque brushy background painting, ochre warm lamp pools, aged wood and sage/dusty teal plaster as this project's v3 shop scenes. Not photorealistic.
Composition constraints: upper third genuinely calm low-detail plaster wall for a title to be added later in code. Group notebook, cards, cup and music box in the lower two thirds. Notebook pages MUST be blank with no writing, just two clearly cut paper stubs near the spine; middle tarot card has one simple star pictogram, other cards are face-down, no lettering. All labels blank. NO typography of any kind.
```

## 字体来源与授权

三款标题字体均从 Google Fonts 官方 `google/fonts` 仓库的 `main/ofl/` 目录直接下载，保留上游 TTF，不子集化、不改字体文件。许可证全文一并放在 `assets/cover/fonts/*-OFL.md`，仅扩展名改为 Markdown 以固定 LF 换行。仓库既有 `.gitattributes` 已设置 PNG、TTF 为普通 Git 二进制并停用 LFS filter，本次沿用。

| 标题字体 | 作者／版权主体 | 页面 | 官方仓库 | 授权 | TTF SHA256 |
|---|---|---|---|---|---|
| 志莽行书 Zhi Mang Xing | The Zhi Mang Xing Project Authors (2018) | [Google Fonts](https://fonts.google.com/specimen/Zhi+Mang+Xing) | [google/fonts](https://github.com/google/fonts/tree/main/ofl/zhimangxing) | SIL OFL 1.1 | `644e0cae9b40f0b10ab729a01bd32032e3973bac22be3dccae01bf6ae7fde969` |
| 马善政楷书 Ma Shan Zheng | The Ma Shan Zheng Project Authors (2018) | [Google Fonts](https://fonts.google.com/specimen/Ma+Shan+Zheng) | [google/fonts](https://github.com/google/fonts/tree/main/ofl/mashanzheng) | SIL OFL 1.1 | `6d2546bb189c732a8ca29af9e22457b152387d158aa459e4ac2ce1e51788b7fb` |
| 龙藏体 Long Cang | The Long Cang Project Authors (2018) | [Google Fonts](https://fonts.google.com/specimen/Long+Cang) | [google/fonts](https://github.com/google/fonts/tree/main/ofl/longcang) | SIL OFL 1.1 | `e5bf2c3f24ef2327c6f136d8f73e2f9dfdf44896fdbeb35a9515f44777bb91bc` |

实际下载 URL：
- `https://raw.githubusercontent.com/google/fonts/main/ofl/zhimangxing/ZhiMangXing-Regular.ttf`
- `https://raw.githubusercontent.com/google/fonts/main/ofl/mashanzheng/MaShanZheng-Regular.ttf`
- `https://raw.githubusercontent.com/google/fonts/main/ofl/longcang/LongCang-Regular.ttf`
- 各目录下的 `OFL.txt` 对应本包 `{字体技术名}-OFL.md`，原始版权署名完整保留；许可证 SHA256 见完整清单。

印章与副标题复用仓库已有 `assets/fonts/LXGWWenKai-Regular.ttf`（霞鹜文楷，[作者 LXGW 官方项目](https://github.com/lxgw/LxgwWenKai)，SIL OFL 1.1，原许可证 `assets/fonts/LXGWWenKai-OFL.txt`），SHA256 为 `2d73eea94ad808999d90c0000c239a84a33b09d4bc6ab6c5b8bbf1eda8a7fc8b`，没有新增或替换该文件。

官方网络获取成功，未使用离线回退目录。若后续重新获取失败，可把上游同名字体放在 `D:/MagicStore_downloads/fonts/` 再复制到 `assets/cover/fonts/`；始终核对来源和授权，禁止静默替换字体。

## 标题参数与复现

依赖：Python 3.9+、Pillow、numpy；单次审计额外使用 fontTools。入口：

```powershell
python tools/cover/make_title.py
python tools/cover/make_title.py --check
```

生成与审计是两个独立模式。生成模式不修改两张原画 PNG。配置 `tools/cover/title_layout.json` 的 `version: 1` 由 `validate_layout()` 校验，检查五字顺序、字距、旋转范围、颜色、字体来源、尺寸、裁切范围和质量参数，失败时先停止再写出文件。

- 横排文字严格为“零点杂货铺”，三款透明 PNG 均宽 1600px，分别高 359／369／332px。首选字体另出 400×1492 的右上竖排，以及带竖排标题的载入备选图。
- `em: 360`、`advance_em: 0.88`；`glyphs` 中五字的 `dx/dy` 是母版像素位移，`angle` 是 Pillow 正向角度，均在 ±3° 内。修改 JSON 即可逐字调字距、位置与转角。
- 墨色 `#2B1E16`。固定随机种子 271127；笔画内部颜色最多 ±5% 变化；干笔遮罩由方向性细纹、局部斑块、笔画边缘及细收笔区域共同控制，避免均匀打洞。
- 透明标题只含墨字和印章。落在插画上时才叠加 4px、60% 纸白柔边，以及偏移 (3,3)、模糊 6px、25% 暖棕投影；缩小副标题边缘为对应的一半参数。
- 小方印朱红 `#B5654D`，白字“零點”，霞鹜文楷，边缘随机磨损，旋转 −3°。
- 副标题严格为“客人带来的，是一段还没说完的故事”，霞鹜文楷，墨褐，目标字号为标题高度的 1/6。默认不添加英文。窄幅与方形图按可用宽度等比缩小副标题。
- 未发现 `title_handwritten_scan.png`，因此没有生成 `title_handwritten.png`。后续放入扫描后再运行同一脚本，会去除纸底、保留笔画形状、施加相同墨色与印章并输出透明 PNG/WebP；不会用生图工具写标题。

## 产出与用途

| 产出 | 布局 |
|---|---|
| `loading_1920x1080.png` | A 铺满，标题 (84,170)，标题高 184px（屏高 17.04%）；底部 120px 无新增文字、图标或进度条 |
| `capsule_1200x630.png` | 以店门及亮灯窗为视觉中心重新取景；左上标题高 151px（23.97%） |
| `capsule_630x500.png` | 窄幅裁切，标题上方，店门居中偏右 |
| `square_1024.png` | 聚焦门与亮窗，保留半幅吊牌；上方居中两行“零点 / 杂货铺” |
| `compare/loading_{zhimangxing,mashanzheng,longcang}_1920x1080.png` | 相同插画与位置，逐字体独立标题和副标题，供策划对比 |
| `title_{zhimangxing,mashanzheng,longcang}.png` | 三款 1600px 宽透明标题 |
| `title_zhimangxing_vertical.png`、`loading_vertical_1920x1080.png` | 右上竖排备选 |
| `review/style_comparison_{a,b}.png` | 每张插画与 S01、S02 三图并排 |
| `review/font_comparison.png` | 三字体合成图并排 |
| `review/*_300w.png`、`review/thumbnails_300w.png` | 全部合成图的真实 300px 宽检查图 |

每张 PNG（包括原图、标题、对比板、缩略图）都有同目录同名 WebP，质量 85；透明标题保留 alpha。`assets/cover/.gdignore` 将本阶段独立宣传素材排除于 Godot 导入，避免生成与当前运行场景无关的导入文件。完整清单与哈希在 `tools/cover/file_inventory.md`。审阅结论、唯一一轮检查结果和需要人工的事项见 [COVER 审阅包](../codex/review/COVER.md)。

工具与记录文件：`tools/cover/make_title.py`、`title_layout.json`、`prompt_a.txt`、`prompt_b.txt`、`file_inventory.md`；`docs/art/cover.md`、`docs/codex/review/COVER.md`；`assets/cover/.gdignore`、`review/asset_check.txt`、`review/game_tests.txt`、`review/shop_ui.txt`、`review/title_migration.txt`。图像和字体的逐项清单在上表所链接的清单文件中，日志不作为插画资源登记。

