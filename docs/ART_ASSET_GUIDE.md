# 美术资源与可操作界面接入说明（2026-11-20）

本说明对应本次交付的 `MagicStore-main_with_artpack.zip`。这是正式 Godot 工程资源包，不是独立网页 Demo。所有动态数值、文字、按钮和交易结果仍由 Godot 与 `GameState` 负责；AI 生成图只作为场景底图、角色肖像和 UI 装饰素材，避免把动态文字烘焙进图片。

## 1. 七个主场景与运行资源

| 编号 | 游戏入口 | 运行时图片 | 分辨率 | Godot 接入 |
|---|---|---|---|---|
| S01 店面外观 | 底部导航「店外」；启动后存档簿之前 | `assets/scene_exterior.png` | 900×600 | `scripts/shop/shop_screen.gd`，`exterior` 页面 |
| S02 第一人称前台 | 底部导航「前台」 | `assets/shop_front_scene.png` | 900×600 | `scripts/ui/shop_front.gd`；右侧来客选择、档案和接待按钮仍为动态控件 |
| S03 一对一咨询 | 接待来客后自动进入；或导航「咨询区」 | `assets/consultation_banner.png` | 900×300 | `scripts/ui/consultation.gd`；问题、输入、报价、术式、手记和结束接待均走现有动作 |
| S04 储物柜 | 底部导航「储物柜」 | `assets/scene_inventory.png` | 900×600 | `scripts/shop/shop_screen.gd`；新增开/合柜与原料/商品筛选，出售和使用沿用现有逻辑 |
| S05 商品工坊 | 底部导航「工坊」 | `assets/scene_workshop.png` | 900×600 | `scripts/shop/shop_screen.gd`；登记需求、研究配方、制作均沿用现有逻辑 |
| S06 原料商店 | 底部导航「原料商店」 | `assets/scene_market.png` | 900×600 | `scripts/shop/shop_screen.gd`；新增买入/卖出页签和数量选择，调用 `procure_item` / `sell_material` |
| S07 外出采集 | 底部导航「采集」 | `assets/scene_gathering.png` | 900×600 | `scripts/shop/shop_screen.gd`；两个独立采集点：河畔小径、林缘草地，消耗时间/精力并写入同一库存 |

每个场景另有 `assets/generated_scenes/` 下的 1920×1080 主图、900×600 的 3:2 裁图和 900×300 的 3:1 裁图。S02 的运行裁图专门裁掉了概念图右侧空白客人卡，避免与真实 Godot 侧栏重复；S03 运行时使用沙发与矮桌的横幅裁图。

## 2. 已接入的角色与术式素材

- 林照晚三态：`assets/portraits/npc_lin_neutral.png`、`npc_lin_hesitant.png`、`npc_lin_relieved.png`。前台与咨询区按本次接待的可见对话文本切换表情；没有根据未知剧情自动揭示表情。
- 角色设定素材：`assets/portraits/npc_character_reference_sheet.png` 和 `npc_reference_01..06.png`。这些是后续 NPC 美术扩展的设定稿，不会擅自按名字给随机 NPC 绑定错误性别或身份。
- 前世片段气氛图：`assets/portraits/past_life_scene.png`，在前世手记页展示；片段身份与关联结论仍由原有规则决定。
- 术式视觉：`assets/ui/tarot_sample_triptych.png`、`tarot_star.png`、`tarot_hermit.png`、`tarot_temperance.png`、`lenormand_symbols.png`、`xiaoliu_grid.png`、`astrology_wheel.png`、`bagua_board.png`、`four_pillars_frame.png`、`ziwei_palace_frame.png`、`evidence_cards.png`。塔罗三张示例牌在匹配牌名时显示插画；雷诺曼、小六壬、占星、梅花/易经、八字和紫微各有对应示意图，实际排盘数据仍由程序化卦线、轮盘、四柱和紫微宫位控件生成。

## 3. 商品、原料、证物和通用 UI

- 商品与原料继续共用 `assets/items/inventory-atlas-v2.png`，映射由 `data/shop/visuals.json` 维护，商品/原料定义由 `data/shop/catalog.json` 维护；商店、储物柜、工坊不会各自复制库存。
- `assets/ui/receipt_widgets.png` 用于本次接待商品账目；`evidence_cards.png` 用于案例手记；`relationship_graph.png` 和 `report_notebook.png` 用于人物关系与经营风格报告页面。
- `navigation_states.png`、`status_widgets.png`、`service_transaction_widgets.png` 是完整的 UI 参考图集；`coin_icon.png`、`energy_icon.png`、`time_icon.png`、`reputation_icon.png` 已用于主界面状态栏。实际按钮状态、队列、输入和报酬数值仍由 Godot 原生控件动态绘制。
- 全部资源索引：`assets/ART_ASSET_MANIFEST.json`。

## 4. F01–F24 对应的可操作入口

| 镜号 | 当前游戏入口/操作 |
|---|---|
| F01 看见店铺 | 启动先展示 S01 店外，再弹出存档簿 |
| F02 开档/续玩/备份 | 存档簿：新建、继续、刷新、备份恢复、删除确认 |
| F03 捏脸 | 候客与人物档案窗口底部：脸型/发型/服装选择并保存；当前保存为稳定外观键，完整部件式实时合成预览仍需后续接入角色部件库 |
| F04 等客/客满 | 前台候客状态、人物窗口队列、等待和预约操作 |
| F05 认识顾客 | 队列与档案显示来意、推荐人、熟悉度、信任、生日、星座、MBTI、性格、偏好和已知记忆 |
| F06 请入咨询区 | 选择来客后「请入咨询区」；林照晚肖像与咨询室图已接入 |
| F07 约定报酬 | 咨询区「塔罗报价/全部术式」选择支付方式，结算后才揭示结果 |
| F08 提问回应 | 中文输入框、问题按钮、处理中状态、重试/本地回应路径沿用现有 Provider 逻辑 |
| F09 使用术式 | 九种术式共用问卜工作台；塔罗/雷诺曼/梅花/易经/小六壬/占星/八字/紫微/前世均沿用现有规则与控件 |
| F10 整理线索 | 案例手记「案情与线索」，区分陈述、证物、术式线索和个人假设 |
| F11 预测建议 | 案例手记「预测与建议」，记录对外预测和来客回应 |
| F12 前世片段 | 案例手记「前世手记」，展示片段图、解释和核验入口 |
| F13 购物/登记需求 | 咨询区「商品与账目」；工坊在接待中登记需求 |
| F14 开储物柜 | 储物柜页新增开/合柜、全部/原料/商品筛选，数量与来源仍来自同一库存 |
| F15 研究制作 | 工坊页登记需求后，结束接待，再研究并制作 |
| F16 采购/出售原料 | 原料商店新增买入/卖出页签、数量选择和库存不足禁用态 |
| F17 外出采集 | 两个采集地点独立按钮；消耗精力和时间，所得进入同一库存 |
| F18 使用商品 | 储物柜/咨询商品账目中的「店长使用」或「记录来客使用」 |
| F19 学习术式 | 前台「术式研习」；学习费用和前置条件仍由原规则决定 |
| F20 休息/打烊 | 前台休息与下一天按钮，使用原共享时钟 |
| F21 等待反馈 | 案例手记中的事件状态与反馈入口 |
| F22 回访后果 | 原 NPC ID 再次到店，复用人物档案和历史记录 |
| F23 家族关系 | 人物档案关系记录与关系图装饰；仅显示已揭示关系 |
| F24 经营风格 | 人物窗口「本局观察」和经营报告；样本不足时保持提示状态 |

## 5. Windows 启动与实际游玩

1. 解压整个 `MagicStore-main_with_artpack.zip`，不要只复制 `assets` 文件夹；`project.godot` 必须与 `start-game.cmd` 位于同一工程根目录。
2. 首次运行需要联网下载固定版本 Godot 4.6.3：在工程根目录运行 `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/dev/bootstrap.ps1`。下载文件会按 `scripts/dev/toolchain.json` 的 SHA256 校验。
3. 下载完成后双击 `start-game.cmd`。需要打开编辑器则双击 `start-editor.cmd`。
4. 游戏启动先显示店外和存档簿。新建店铺后回到前台；顶部状态条显示金币、精力、游戏日期时间。底部导航可进入七个场景。
5. 首轮推荐操作：前台选顾客 → 请入咨询区 → 选问题/中文输入 → 塔罗报价并结算 → 案例手记留预测 → 结束接待 → 工坊登记需求/研究/制作 → 原料商店采购 → 采集 → 储物柜查看库存 → 休息/下一天 → 等回访。
6. 游戏动作仍经 `GameState.execute_action_async` 保存；不要把 PNG 拖到运行中的游戏目录以外，也不要改存档 JSON 来模拟库存或关系。

## 6. 本次范围边界与验证说明

本次接入的是场景底图、肖像、术式和 UI 装饰素材，以及对应页面控件/数据动作接线。生成场景图是合成背景板，不是已自动分离的门、灯、窗、桌面独立图层；营业/打烊、数量、排队、交易、事件等状态由动态 UI 显示。NPC 设定稿作为美术库参考；除林照晚外，尚未把随机 NPC 逐个映射到独立肖像，避免头像与持久化身份错配。玩家捏脸当前保存外观键，完整头发/脸/衣服部件式实时合成仍需单独接入。

本次容器没有安装 Godot 4.6.3 可执行文件，故未在此环境运行 Godot 图形启动或全量 `run.ps1 -Test`。已做资源路径、PNG 尺寸、JSON 配置、引用文件和 ZIP 完整性检查；请在 Windows 第一次启动时由 Godot 自动导入新 PNG，并按 `scripts/dev/run.ps1 -Test` 做正式引擎验收。
