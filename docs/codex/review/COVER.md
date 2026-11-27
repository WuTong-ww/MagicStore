# COVER · 封面插画与标题审阅包

日期：2026-11-27。分支：`codex/cover`。基线：`ee576ca0660804a86bb3a652ff3f75244272d039`。

制作说明、完整提示词、来源与授权见 [cover.md](../../art/cover.md)，实际尺寸、SHA256 与逐项文件清单见 [file_inventory.md](../../../tools/cover/file_inventory.md)。

本次按目标文件只做一轮集中自检；检查结论完成后填入本页，不追加第二轮检查。

## 插画自评

| 项目（每项 1 分） | A | B | 观察依据 |
|---|---:|---:|---|
| 1. 手绘笔触，边缘虚实 | 1 | 1 | 纸面颗粒、墙面与木材笔触可见，远景与细物边缘有层次 |
| 2. 光源明确，无光晕／光束／闪点 | 1 | 1 | 窗内灯与油灯提供暖光，地面和桌面反光均有来源 |
| 3. 暗部偏冷、不发黑 | 1 | 1 | 远街与阴影为灰蓝、青绿，保留结构 |
| 4. 无文字／伪文字／签名／水印 | 1 | 1 | A 吊牌和罐签为空白；B 笔记本为空页，星形牌无字 |
| 5. 无金饰堆叠，紫藤至多一处 | 1 | 1 | A 仅门头一枝紫藤；B 无装饰性金纹堆叠 |
| 6. 结构合理 | 1 | 1 | 门窗、屋顶、桌面、杯口、三张牌形状均可辨认 |
| 7. 标题留白平静 | 1 | 1 | A 左上天空；B 上方中部灰绿墙面，主要细节在两侧和下方 |
| 8. 一眼是深夜仍亮灯的小店 | 0 | 1 | A 暖窗明确，但天色更接近蓝调黄昏，深夜感较弱；B 窗外夜雨与暖灯关系明确 |
| 9. 与 S01/S02 属于同一作品 | 1 | 1 | 石木、灰绿、赭色、暖灯和冷阴影一致；并排图可复核，A 比原夜景更明亮 |
| 10. 300px 下构图清楚 | 1 | 1 | A 店门、窗与街道分区明确；B 灯、笔记本、杯、牌和音乐盒仍分得开 |
| **总分** | **9/10** | **10/10** | 两张均达 8 分门槛，保留首张成功生成结果，无重画 |

目视还覆盖三种字体对照、四张主合成图、竖排备选及所有 300px 缩略图。五字标题可辨；窄幅和方形版保留店门与暖窗，方形版吊牌只留一部分。B 的切页痕迹在缩略图中不明显，未把这一细节描述为已通过细部叙事验收。副标题在 300px 的宽屏版本中只承担层次，字号不适合全文阅读；本次小图判据为标题和主体清楚。

## 图像对照

- A / S01 / S02：`assets/cover/review/style_comparison_a.png`
- B / S01 / S02：`assets/cover/review/style_comparison_b.png`
- 三款字体合成对照：`assets/cover/review/font_comparison.png`
- 三张完整字体图：`assets/cover/compare/loading_zhimangxing_1920x1080.png`、`loading_mashanzheng_1920x1080.png`、`loading_longcang_1920x1080.png`
- 所有合成图的 300px 检查板：`assets/cover/review/thumbnails_300w.png`，每张另存独立 `*_300w.png`

## 检查与测试

- 素材自检：`python tools/cover/make_title.py --check`，124 项，123 通过、1 项误报。原始结果保留在 `assets/cover/review/asset_check.txt`。
- 唯一一次修正：`thumbnails_300w.png` 是 1320px 宽的多图检查板，原判断误把它当作单张 300px 缩略图；已将检查板从该单项排除。8 张独立缩略图均为 300px。依目标文件限制，修正后未再运行自检，不将修正后的结果冒称为复测全绿。
- `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/dev/run.ps1 -Test`：**失败，退出 1**。32 个已完成计数阶段合计 2248 项通过、0 失败；随后 TITLE 迁移阶段 2 项中 1 通过、1 失败，即已有计数合计 **2249 通过／1 失败**。另有 26 项 Python 单元测试通过。完整回归因此中断，后续阶段未执行。日志：`assets/cover/review/game_tests.txt`；引擎原生失败日志另存为 `assets/cover/review/title_migration.txt`。
- TITLE 失败位置：既有 `tests/integration/title_creation_migration.gd:66` 固定要求 `CURRENT_SCHEMA == 15`、`NEW_GAME_RECEIPT_SCHEMA == 15`、`PRE_TITLE_SCHEMA == 14`。当前基线存档版本已经提升，旧门槛失败。封面分支未修改存档、迁移或测试代码，未为追求全绿改写历史测试。
- 图形 `--script res://tests/integration/shop_ui.gd`：**1400 通过／1 失败**，退出 1，实际 Windows Compatibility 渲染、22 张截图。失败为既有 C7 物品来源校验；基线 `data/shop/visuals.json` 引用的 35 个 `assets/_incoming/a2r_v3/*_source_attempt*.png` 均未随 Git 工作树提供，该目录被忽略。没有降低校验标准或新增范围外的原图。日志：`assets/cover/review/shop_ui.txt`。
- 本次只执行以上一轮，未重跑；唯一代码修正为检查板宽度误报。Godot 导入触及的既有 `.import` 换行与时间戳已恢复，不纳入交付。

### 图形截图路径

独立工作树根目录：`D:/MagicStore/.tools/cover-worktree/`。

- 1280×720：`.tools/c-ui-captures/exterior-1280.png`、`.tools/c-ui-captures/front-1280.png`
- 1920×1080：`.tools/c-ui-captures/exterior-1920.png`、`.tools/c-ui-captures/front-1920.png`
- 其余 18 张同目录。上述截图展示既有游戏场景；第一段封面尚未接入运行时。

## 需要人工／待确认

- 策划选择最终字体。按任务以志莽行书作为当前主版，马善政楷书、龙藏体和竖排仅作备选。
- 插画原生尺寸为 1672×941，生成器没有返回请求的 2560×1440；是否另行获取更高原生分辨率，由策划决定。
- 未提供手写扫描，所以手写标题为条件未触发，不伪造扫描稿。
- 合并时根据 `docs/art/cover.md` 将来源与生成记录统一登记到既有清单；本分支遵循“只新增指定路径”，没有修改中央清单或 `docs/features.md`。
- 既有 TITLE 迁移测试门槛及 C7 本地来源素材的缺失，需要对应任务后续处理；本次不能宣称游戏回归全绿。

## 已知未完成

- 第一段仅产出宣传图和制作源。进度条、游戏接入、网页接入属于后续段落。
- 本轮全量回归在既有迁移门槛失败处中断；未执行其后的测试，未复跑。
