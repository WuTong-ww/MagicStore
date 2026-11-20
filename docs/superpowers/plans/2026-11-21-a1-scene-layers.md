# A1 七场景底板与可互动图层实施记录

**目标：** 将七场景改为 2560×1440 日夜底板，独立透明物件与动态控件共用坐标，去掉烘焙空白 UI。

**依据：** 用户任务 A1 的完整场景、STYLE、时间、分层及验收要求；工程 AGENTS.md。

**架构：** data/shop/visuals.json 维护场景映射、日夜资源、物件矩形及热区；共享 Godot Control 统一进行 16:9 等比映射与 0.6 秒交叉淡入。显示取已保存的 GameState snapshot，不增加存档字段。

**约束：** Godot 4.6.3 stable 标准版、GDScript、Compatibility；不引入插件；图像不包含文字、人物、标签或 UI。按用户最终指示，PNG 使用普通 Git 管理；提示词、版本、来源及 SHA256 登记到美术清单。

- [x] 生成并核对 15 张底板候选：S01–S07 day/night 与 S01 closed；保持右 30%、底 12% 低细节（实际1672×941）。
- [x] 生成并核对 13 张透明物件切片：S02 五张、S04 四张、S05 三张、S06 一张。
- [x] 实现 scenes 配置、校验、共享坐标映射；前台、经营页和咨询区接入新底板。
- [x] 根据已提交游戏时钟选择日夜，09:00 与 18:00 边界；22:00 仍用夜灯、22:01 后 S01 打烊；非营业的凌晨用打烊版。
- [x] 保持场景 Control 实例，使动作后 refresh 可交叉淡入；保存失败不变更显示。
- [x] S04 GridContainer 动态格子：空格切片、物品图、名称与数量控件，保留出售/使用入口。
- [x] 旧运行裁图与生成裁图移入 assets/_legacy/，更新历史清单与说明，不删除。
- [x] 新增配置非法输入、坐标映射、时段边界、淡入与库存显示测试；运行完整 run.ps1 -Test。
- [x] 图形运行 tests/integration/shop_ui.gd；检查 1280×720 和 1920×1080 截图，并补充日夜/打烊图形证据。
- [x] 更新 docs/features.md 与资源登记，审阅实际差异后回报。

分工：底板 S01–S03、底板 S04–S07、运行时配置与测试并行；主工程师生成其余切片、整合资源、归档旧图并做完整验证。现有其他任务未提交改动保留。

待确认：最终美术审美验收由策划确认；生成器实际像素与透明度须核验，不用放大图片冒充原生分辨率。

## 变更文件

- `assets/generated_scenes/v2/S01_day.png` 至 `S07_night.png`、`S01_closed.png`：15 张底板候选。
- `assets/generated_scenes/v2/slices/`：S02 门/帘幕/信件/开关灯、S04 开合门/空格/抽屉、S05 研钵/空瓶/天平、S06 货篮，共 13 张透明 PNG。
- `assets/_legacy/`：22 张旧裁图和旧运行图归档，保留原内容与 Godot 导入标识；1920×1080 旧主图仍在原生成目录。
- `.gitattributes`、`assets/ART_ASSET_MANIFEST.json`：新图和归档图的普通 Git 二进制规则、提示词、版本、真实像素及校验和。
- `data/shop/visuals.json`：场景、时段、切片矩形、热区矩形、可选透明边源区域、柜格显示配置。
- `scripts/shop/scene_visual.gd`：共享等比映射、切片叠绘、真实尺寸源区域检查、0.6 秒交叉淡入。
- `scripts/ui/shop_front.gd`、`scripts/ui/consultation.gd`、`scripts/shop/shop_screen.gd`：接入新场景，前台配置热区和柜内 GridContainer。
- `tests/integration/scene_visuals.gd`、`tests/integration/scene_asset_acceptance.gd`、`scripts/dev/run.ps1`：功能回归、图形补充截图和独立严格素材验收。
- `docs/features.md`、`docs/ART_ASSET_GUIDE.md`、`assets/_legacy/README.md`：当前行为、候选限制与旧资源说明。

## 验证重点

17:59 到 18:00 的真实动作：保存失败时白日与时钟均不变；保存成功后保留场景实例并淡入夜灯。测试同一坐标映射下的真实点击、九种库存的格内文字边界、连续同帧刷新、非法列数与越界源区域。S01 的 22:01 打烊截图是标明的纯渲染夹具，拍摄后恢复完整已提交快照，不作为业务时钟动作证明。

内置生图未遵守指定输出像素，已实际核验为 1672×941。用户明确选择继续内置候选、将原生 2560×1440 列为未完成；未调用 API/CLI，也未脚本放大。独立素材验收保持原标准，不降低测试要求以让候选通过。

- [ ] 补齐原生 2560×1440 底板并通过高清验收（用户明确接受保留此项未完成）。

最终图形验证：Windows / OpenGL Compatibility，shop_ui 706检查0失败、23截图；scene_visuals 236检查0失败、11截图。独立严格素材验收57检查中42通过、15失败，失败全部为底板原生尺寸不足；28份素材提示词/版本/SHA256/实际尺寸审计通过。

额外画面观察：原有主导航与页首按钮存在文字裁切，本次未修改全局ui_kit或主导航；A1经营页内的交易按钮已局部修正。此项适合后续独立UI任务。

## 截图索引

图片目录为 `.tools/c-ui-captures/`；以下主场景截图均由要求的 `tests/integration/shop_ui.gd` 在 Windows Compatibility 实际渲染生成。

| 场景 | 1280×720 | 1920×1080 |
|---|---|---|
| S01 店外 | [exterior-1280.png](../../screenshots/a1/exterior-1280.png) | [exterior-1920.png](../../screenshots/a1/exterior-1920.png) |
| S02 前台 | [front-1280.png](../../screenshots/a1/front-1280.png) | [front-1920.png](../../screenshots/a1/front-1920.png) |
| S03 咨询区 | [consultation-1280.png](../../screenshots/a1/consultation-1280.png) | [consultation-1920.png](../../screenshots/a1/consultation-1920.png) |
| S04 储物柜 | [inventory-1280.png](../../screenshots/a1/inventory-1280.png) | [inventory-1920.png](../../screenshots/a1/inventory-1920.png) |
| S05 工坊 | [workshop-1280.png](../../screenshots/a1/workshop-1280.png) | [workshop-1920.png](../../screenshots/a1/workshop-1920.png) |
| S06 原料商店 | [market-1280.png](../../screenshots/a1/market-1280.png) | [market-1920.png](../../screenshots/a1/market-1920.png) |
| S07 采集 | [gathering-1280.png](../../screenshots/a1/gathering-1280.png) | [gathering-1920.png](../../screenshots/a1/gathering-1920.png) |

`scene_visuals.gd` 补充截图：

- [九格库存1280](../../screenshots/a1/a1-inventory-open-1280.png)、[九格库存1920](../../screenshots/a1/a1-inventory-open-1920.png)
- [合柜1280](../../screenshots/a1/a1-inventory-closed-1280.png)、[合柜1920](../../screenshots/a1/a1-inventory-closed-1920.png)
- [单件库存1280](../../screenshots/a1/a1-inventory-single-render-only-1280.png)、[单件库存1920](../../screenshots/a1/a1-inventory-single-render-only-1920.png)
- [17:59白日](../../screenshots/a1/a1-exterior-day-1920.png)、[18:00淡入中间态](../../screenshots/a1/a1-exterior-transition-1920.png)、[18:00夜灯](../../screenshots/a1/a1-exterior-night-1920.png)
- [前台夜灯](../../screenshots/a1/a1-front-night-1920.png)、[22:01打烊（纯渲染夹具）](../../screenshots/a1/a1-exterior-closed-render-only-1920.png)

其他辅助验收：[候客1280](../../screenshots/a1/people-1280.png)、[候客1920](../../screenshots/a1/people-1920.png)、[设置1280](../../screenshots/a1/network-1280.png)、[设置1920](../../screenshots/a1/network-1920.png)、[交易后库存](../../screenshots/a1/market-after-trade-1920.png)、[物品图集](../../screenshots/a1/catalog-icons-64px.png)、[零客日前台1280](../../screenshots/a1/zero-guest-front-1280.png)、[零客日前台1920](../../screenshots/a1/zero-guest-front-1920.png)。

两脚本共进行 34 次截图保存，采集页在同一路径覆盖一次，最终为 33 个唯一 PNG 文件。

## 最终回归结果

`powershell -NoProfile -ExecutionPolicy Bypass -File scripts/dev/run.ps1 -Test` 最终退出码 0：48 组 Godot 汇总共 5157 项检查，Python 90 项测试，全部通过。完整日志为 `.tools/a1-final-test.log`。图形日志为 `.tools/a1-shop-ui-final.log`（706/0）和 `.tools/a1-scene-visuals-graphical.log`（236/0）；严格素材验收日志为 `.tools/a1-asset-acceptance.log`（57 检查，15 个原生尺寸失败）。

测试环境曾阻止本机回环连接（Python WinError 10013、Godot RESULT_TIMEOUT、夹具没有收到请求），因此最终使用允许 127.0.0.1 的执行环境运行同一完整命令，未改网络源码或测试时限。期间另出现一次未持续复现的认证拒绝连接重置，单例复核和最终全套均通过；一次原有候客弹窗尺寸检查也在独占图形复跑中通过。排查记录在 `.tools/a1-http-probe.log`、`.tools/a1-person-auth-recheck.log`。

代码和候选接入验收已完成，原生 2560×1440 和最终美术验收保留为未完成；旧素材继续归档保留。
