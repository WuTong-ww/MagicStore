# 零點雜貨鋪 · Codex 實作指揮手冊

2026-11-21 更新（含第二輪：A1、G1 驗收）

## 現況診斷

骨架已經很完整，缺的主要是「內容量」與「美術落地品質」，而不是系統。倉庫（commit e9d787b，Godot 4.6.3）已有：共用時鐘與精力、9 種術式與學習樹、AI 對白＋獨立審核＋回退、原創新來客後台生成、回訪沿用 npc_id、推薦人、預約與耐心離店、商品研發／製作／採集／原料商店、七個場景與存檔備份。以下是逐條對照需求文件後確認的落差（皆已在原始碼中核對）。

| 優先 | 落差 | 證據（檔案） | 對應 Prompt |
| --- | --- | --- | --- |
| P0 | 場景圖把空白牌匾、格子、面板「畫死」在背景裡，與動態 UI 對不齊 | assets/generated_scenes/S04、S05、S06 | A1 |
| P0 | 執行時背景只有 900×600，在 1920×1080 會被放大糊掉 | scripts/shop/shop_screen.gd SCENE_ART | A1 |
| P0 | 商品圖集去背失敗，邊緣有紅黃雜色；平塗向量風也和水彩場景不搭 | assets/items/inventory-atlas-v2.png | A2 |
| P0 | 實際遊戲 UI（彈窗、案例手記）仍是深灰預設樣式，與概念圖差距大 | themes/midnight.tres、docs/screenshots | A3 |
| P0 | 除林照晚外，隨機 NPC 沒有任何頭像；捏臉只存外觀鍵，沒有部件合成 | ART_ASSET_GUIDE.md 第 6 節、people.gd _appearance | A4 |
| P1 | 人物設定稿 7 人臉型、髮色、眼睛幾乎一樣，且全員古裝；但來客職業是插畫師、園藝師等現代職業 | npc_character_reference_sheet.png | A4 |
| P1 | 不可能出現零客日：natural_min=1，且 plan_day 的上限 clamp 下限為 1；到店時間均勻隨機，沒有「集中爆單」 | data/people/templates.json、people.gd plan_day | G1 |
| P1 | 作品參考家族：正式資料 family 為空、family_percent=0；程式只支援單一家族、只連 members\[0\]↔members\[1\]、目標問題寫死 | people.gd ensure_family | G2 |
| P1 | 事件結算寫死在「邀請案」：advice_key 只認 message/attend/private/note；archive 案沒有事件 | scripts/divination/event_rules.gd _resolve | G3 |
| P1 | 內容量偏少：3 商品、4 原料、3 配方、2 手寫案例、1 位固定 NPC、2 段前世；姓名池 8×8、職業 6 種、性格 4 種 | data/shop/catalog.json、data/divination.json、templates.json | G4 |
| P2 | 前世系統只有「看片段→以證物核實」一步，沒有跨世關係網與多段累積 | workbench.gd _past_notes、divination.json past_profiles | G5 |
| P2 | 經營風格報告只數「提問／建議／服務」三類次數 | people.gd style_report | G6 |
| P2 | 無音效與背景音樂；字型只有 Noto Sans SC，缺少溫度 | assets/fonts | A3 |
| P2 | 倉庫 155 MB，大量 PNG 直接進 Git 歷史 | .gitattributes | Prompt 0 |

我沒有在這個環境實際跑 Godot（沒有引擎），所以「畫面實際長怎樣」以倉庫內截圖與程式為準；請讓 Codex 每輪跑 shop_ui.gd 截圖回報。

## 第二輪：A1、G1 驗收與新方向（2026-11-21）

G1 達標。A1 的程式架構可以留用（日夜切換、熱區與切片都由 visuals.json 驅動），但畫風要重定方向，且有 4 個畫面 bug。以下依 commit e27441b 的截圖與素材核對。

| 項目 | 結論 | 證據 |
| --- | --- | --- |
| 零客日、客量分布測試 | 通過；零客日前台有「去採集／研習／制作」建議 | docs/screenshots/a1/zero-guest-front-1280.png |
| 零客日的來客下拉選單 | 小瑕疵：空選單仍顯示，應隱藏 | 同上 |
| 主導航與頁首按鈕 | Bug：所有截圖中按鈕都是空白橢圓，沒有文字（Codex 自己也記錄了但未修） | 全部 a1 截圖底部 |
| 前台熱區標籤 | Bug：「原料商」「店」「来客信」被截斷 | front-1280.png |
| 場景框在面板裡；諮詢區只剩一張小縮圖 | 與你的新要求衝突 → A3R | consultation-1920.png |
| 底圖實際 1672×941，不是 2560×1440 | 生圖工具上限；鋪滿 1920×1080 只需放大 1.15 倍，手繪風下可接受 | ART_ASSET_MANIFEST.json |
| 畫風 | 過度細節、到處紫藤與金光、典型 AI 奇幻插畫感 → A1R | assets/generated_scenes/v2/ |
| 架上物品像不同圖層 | 原因見下 → A7 | a1-inventory-open-1920.png |

**架上物品為什麼看起來不在同一層**

- 每個格子是另外生成的立體木箱切片，透視、光源都跟櫃子不同，等於在櫃子前面又疊了 9 個箱子。
- 物品還是 A2 之前的平塗向量圖示，和水彩底圖是兩種筆觸。
- 物品懸空在格子中央：沒有落在層板上、沒有接觸陰影，也不跟日夜光線變色。
- 名稱與「数量 1」直接壓在格子邊框上，文字和木線條打架。

### 美術方向 v2：手繪、少即是多

取向從「奇幻概念圖」改為「繪本插畫」：不透明水彩（gouache）加色鉛筆線稿，看得到筆觸，東西少、留白多。第一輪 Style Bible 的色票、字型、人物規則仍然有效，只替換下列畫面規則。

- 筆觸看得見：平塗色塊加乾筆邊緣，線條略不均勻、可以斷筆，透視可以稍微歪。
- 每張畫只留 1 個視覺重點；道具數量減半，牆面、地板大片留白。
- 調色盤限 6–8 色、降飽和；陰影用偏冷的色，不是調暗。
- 光線柔和漫射：禁止發光暈、光束、鏡頭光斑、景深模糊、金色描邊。
- 紫藤只在店外與前台窗邊出現一處，其他場景不再掛。
- 審圖時逐項找 AI 痕跡：過度對稱、花紋堆疊、看不出是什麼的小物件、結構不合理（櫃腳、書脊、窗格）、塑膠光澤、金光。

老實說，純生圖很難完全去掉 AI 感。最有效的做法是先有一張人手繪的定調畫（自己畫或委託），之後所有生圖都用它做風格參考；或生圖後由美術修繪。沒有美術的話，A1R 先只做 S02 一張試點，你點頭後再批量。

### 動態效果設計

所有動態由同一個「風場」驅動：基礎微風加上隨機陣風。同一陣風會讓窗外樹葉、室內吊掛植物、簾幕依序反應，看起來有因果；開門、放物品等事件則給附近物件一個「推力」。動幅保持很小，不搶 UI；設定裡可關「減少動態」。

| 物件 | 怎麼動 | 觸發 | 做法 |
| --- | --- | --- | --- |
| 窗外樹葉、藤蔓 | 以枝條根部為軸擺，越往末端擺幅越大；陣風時整片同向偏移再回彈；偶爾一兩片葉子飄落，邊落邊翻 | 持續，風場 | 頂點 shader（正弦＋噪聲，依高度加權）；落葉用 CPUParticles2D |
| 室內吊掛植物、乾燥花束 | 很輕的鐘擺，週期 3–4 秒、擺幅 1–2° | 開門的風 | 阻尼鐘擺 |
| 門上風鈴 | 擺動並響一聲，慢慢停下 | 客人到店、離店 | 鐘擺＋音效，擺幅隨推力 |
| 吊燈 | 微擺；夜間火光輕微明暗 | 開門；夜間持續 | 鐘擺＋亮度噪聲 |
| 簾幕 | 下襲波動；有人經過時向一側掀起再落回 | 進出諮詢區 | 位移 shader＋彈簧 |
| 香爐煙、茶杯熱氣 | 上升、隨風彎曲、逐漸散開 | 持續 | 流動噪聲 shader |
| 窗邊灰塵 | 慢慢漂浮 | 白天 | 少量粒子 |
| 架上物品 | 放入時落下輕彈；相鄰瓶罐以瓶底為軸微晃後停住 | 入庫、取出 | 旋轉彈簧，支點在底部 |
| 店外吊牌 | 以鉸鍊為軸擺動，陣風時吃力較大 | 風場 | 鐘擺 |
| 溪水（採集） | 水面流動、偶有反光；草叢搖晃 | 持續 | UV 捲動 shader＋同樹葉 shader |
| 雨天（接 G1 天氣） | 窗上雨絲、地面水窪漣漪，風場加強 | 天氣＝雨 | 粒子＋shader |

做法前提：會動的東西必須是獨立圖層。生圖很難直接產出對齊的分層，所以採用「先生整張 → 把要動的物件按遮罩挖出來存成透明圖 → 用局部重繪把底圖上的空位補好」，這樣图層一定對齊。

### 第二輪任務順序

1. **A3R 全螢幕介面殼＋修 bug**：只動程式，用現有 v2 底圖先跑起來，取代第一輪的 A3。
2. **A1R 畫風重設**：先做 S02 試點，**停下來等你審**，通過後再批量。
3. **A2R 物品圖**：用 A1R 定稿的風格重做，取代第一輪的 A2。
4. **A7 架上擺放**：等 A2R 完成。
5. **A6 動態系統**：等 A1R 的分層素材。

玩法線照舊接著做 G3，可以跟 A3R 並行。A4（頭像）排在 A1R 之後，提示詞風格詞要改用 v2。

### A3R 全螢幕介面殼

```text
任务 A3R：场景铺满整个游戏画面，UI 改为浮在场景上的轻量层；并修复 A1 遗留的画面 bug。本任务取代原 A3，原 A3 的字体、双主题、对话气泡、状态栏、音乐与音效各点一并做完。

先修 bug：
1. 主导航与页首按钮在所有截图中都是空白椭圆，没有文字。查 scripts/ui/ui_kit.gd 与 themes/midnight.tres 的尺寸/内边距/字号，找出根因再修，不要逐个按钮硬写宽度。加一个测试：遍历所有可见 Button，断言文字完整可见（文字最小宽度 ≤ 按钮内宽）。
2. 前台热区标签被截断（原料商/店/来客信）：标签宽度由文字自动决定，热区点击范围与标签位置分开配置。
3. 零客日时隐藏空的来客下拉选单。

全屏布局：
4. 场景底图与切片层铺满窗口（cover 缩放，参考画布 1920×1080）。非 16:9 时以中心裁切，并在 visuals.json 为每个场景配置 safe_rect（热区与重要物件必须在内）。热区、切片、物品位置全部走同一个坐标变换。
5. 运行时底图：生成器上限是 1672×941，由导入脚本用 Lanczos 放大到 1920×1080 作运行副本，源图保留；在清单中标明「运行副本，放大 1.15 倍」，不得写成原生。
6. 去掉所有包住场景的卡片边框。UI 分三层：
   - 顶栏：高 52px，夜青 80% 不透明度，左店名、右状态（金币/精力条/口碑/日期时间/候客数）。
   - 右侧抽屉：古纸面板，宽 420px，可收起为右缘一枚小书签；展开/收起 0.25 秒滑动。前台默认展开（来客卡），储物柜/工坊/商店在选中物品时展开详情。
   - 底部码头：居中一排「图标＋两字」小按钮（店外/前台/咨询/柜子/工坊/商店/采集/档案），高 64px，半透明。热区能到的地方，码头只是备用入口。
7. 咨询区改为「视觉小说式」：全屏小客厅场景，来客半身像合成在沙发上（visuals.json 配置座位锚点与缩放，头像底部被沙发靠垃遮住的遮罩切片放在头像上层）；底部 1/3 为古纸对话框（含历史滚动、建议问题、输入框）；术式、案例手记、商品账目放右侧抽屉分页。沙发上没人时显示空场景与「还没有来客」。
8. 所有长文字面板均为古纸底。不得再有大片深色卡片盖住场景。
9. 1280×720、1920×1080、2560×1080（超宽）、800×600 四种窗口各截一次前台、咨询、储物柜。

验收：场景在所有尺寸都铺满无黑边；任何按钮文字完整；热区点得到；咨询区来客坐在沙发上；截图回报。
```

### A1R 畫風重設（先試點、等審核）

```text
任务 A1R：按「美术方向 v2」重做场景，并把会动的物件拆成独立图层。分两阶段，第一阶段完成后必须停下等策划确认。

阶段一：试点
1. 写 docs/art/style_v2.md：规则、色板（7 色）、AI 痕迹检查清单（见下）。
2. 只生成 S02 前台白日版，3 个候选，放 assets/_incoming/a1r_pilot/。用下方 STYLE_V2 与 NEGATIVE。
3. 自审：对每张候选按检查清单逐项打勾，写进回报。然后停止，等策划选定一张（或提供自己手绘的定调图）。

阶段二：批量（策划确认后）
4. 以定稿图作为风格参考图，生成 S01–S07 白日/夜灯与 S01 打烊版。夜灯版用定稿图做图生图调光，保持构图一致。
5. 分层：每个场景按下表把会动的物件拆出。做法：在整张图上画遮罩 → 按遮罩扣出透明 PNG（边缘羊化 1px）→ 对底图同一遮罩外扩 6px 做局部重绘，补出背后的墙面/天空。扣出的图保持与底图同尺寸同位置，保证对齐。
   - S01：树冠、藤蔓、吊牌、云
   - S02：窗外树叶（与窗内分开）、窗边藤蔓、干花束、风铃、帘幕（左右各一）、香炉
   - S03：吊灯、帘幕、茶杯、沙发靠垫遮罩层（给 A3R 的来客像用）
   - S04：柜门开/合、吊灯；层板上不画任何物品
   - S05：吊挂的干草、蒸汽口
   - S06：门外街景树叶、布帘
   - S07：前景草丛、树冠、水面区域遮罩
6. 每个层在 visuals.json 登记：z 序、支点（按源图像素）、动态类型（sway_shader / pendulum / flow / static）、参数。A6 会读这些字段。
7. 旧 v2 图移到 assets/_legacy/v2/。

STYLE_V2（每张必加）：
gouache picture-book illustration, visible brush strokes and dry-brush edges, slightly wobbly hand-drawn colored-pencil outlines, simplified shapes, slightly imperfect perspective, limited palette of seven muted colors (cream, warm grey, walnut brown, sage green, dusty teal, faded plum, ochre), soft diffuse daylight, cool-tinted shadows, generous empty wall and floor space, only a few props, one clear focal point, calm and quiet, matte paper texture, no text, no people

NEGATIVE：
glow, bloom, light rays, god rays, lens flare, bokeh, depth of field blur, gold filigree, ornate carvings, glossy or plastic surfaces, hyper-detailed clutter, photorealism, symmetrical fantasy composition, wisteria everywhere, text, letters, UI, labels

S02 场景主体：
first-person view from behind a plain worn wooden counter in a small curio shop, a simple open shelf on the left with a few jars and books, a doorway with a plain green cloth curtain in the middle, a window on the far left with a tree outside, an empty warm plaster wall on the right third, a single small potted plant and a ceramic dish on the counter

检查清单（每项是/否）：可见笔触；道具少于 15 件；有大片留白；无发光/光束；无金色花纹；无结构错误（柜脚、书脊、窗格、门框）；无看不出是什么的小物件；右侧 30% 低细节；色数在 7 色之内。
```

### A2R 物品圖（取代 A2）

```text
任务 A2R：用 A1R 定稿的风格重做全部商品与原料图。原 A2 的流程（check_alpha.py、品红背景去背、每件独立 PNG、visuals.json 映射、旧图归档）全部保留，只改以下几点：
1. 提示词模板：
   "a single {object} drawn as a gouache picture-book illustration, visible brush strokes, slightly wobbly colored-pencil outline, muted palette matching the reference image, seen from slightly above at a three-quarter front angle as if standing on a shelf, sitting upright on its flat bottom, soft diffuse light from top left, no shadow, plain flat #FF00FF background, centered, fills 80% of height, no text"
   并附上 A1R 定稿图作为风格参考。
2. 物品必须「站得住」：底部平，底边贴近图片下缘。写工具检测每张图不透明像素的最低行，记录为 bottom_y 与底宽，写入 visuals.json（A7 用）。
3. 不自带阴影；阴影由 A7 在运行时加。
4. 每件物品另存一张 64px 的小图标版（用于账簿与列表），由大图缩小并加强轮廓，不另外生成。
```

### A7 架上物品擺放

```text
任务 A7：让储物柜里的物品看起来「真的放在架子上」。依赖 A1R（空层板底图）与 A2R（新物品图与 bottom_y）。

现状问题：每格叠了一个另外生成的立体木箱切片（S04_slot.png），透视和光源与柜子不同；物品悬空在格子中央；名称与数量压在边框上。

要做：
1. 删除 S04_slot 切片的使用（文件移到 _legacy）。不再用 GridContainer 格子。
2. visuals.json 为 S04 配置 shelves：每层一条「层板线」{y, x_start, x_end, depth_scale, light_tint_day, light_tint_night}，坐标按源图像素标定（写一个调试叠加层画出线条，按 F3 开关）。
3. 摆放算法：物品按类别与获得顺序从左到右排在层板线上；物品的 bottom_y 对齐层板线（往下压 2px，避免微缝）；间距按底宽加 16–24px 随机微调（以 item_id 为种子，稳定）；每件微旋 ±1.5°，大小按 depth_scale。放不下就换下一层，全满时右侧抽屉列表显示剩余。
4. 数量：不写数字。数量 1–3 时叠放同样数量的副本（后面的往左上偏 10px、稍暗），大于 3 时显示 3 件加一个手写小纸条「×N」。
5. 接触阴影：每件物品下方放一个模糊椭圆阴影纹理（宽为底宽 110%，高 12px），正片叠底 35%。
6. 光线统一：物品层 modulate 使用层板的 light_tint（白日/夜灯各一组）；所有场景层之上再加一层全屏纸纹（正片叠底 8%），让底图与物品在同一张纸上。
7. 名称：架上平时不显示文字。鼠标悬停时，层板前缘垂下一个手写纸标签写名称；点击后物品轻微上提 6px，右侧抽屉展开详情（出售/使用）。用途颜色角标只在抽屉中显示。
8. 空柜：层板就是空的，不显示虚线占位框。
9. 预留 A6 的钩子：每件物品是一个可旋转节点，支点在底部中点；入库、取出发出信号。

验收：空柜、1 件、9 件、30 件四种库存各截图（白日/夜灯）；放大到 200% 检查物品底边与层板无缝无悬空；重开存档排列不变。
```

### A6 動態系統

```text
任务 A6：做场景动态系统，按「动态效果设计」表实现。依赖 A1R 的分层与 visuals.json 动态字段。只用 Godot 内置功能，Compatibility 渲染可用。

架构：
1. WindField（autoload）：风速 = 基础微风 + FastNoiseLite 低频波动 + 随机阵风（平均 25 秒一次，持续 2–4 秒，先升后降）。阵风从屏幕左侧向右传播，物件按 x 坐标延迟响应。室内物件只受室外风的 15%，开门时短暂提到 60%。天气（G1）为雨时基础风加强。
2. 三种动态类型，全部读 visuals.json：
   - sway_shader（树叶、藤蔓、草、帘幕下摆）：顶点/片元偏移 = 风速 × 振幅 × 距支点距离的平方权重 + sin(时间 × 频率 + 位置相位)。支点那一端纹丝不动。
   - pendulum（风铃、吊灯、干花束、吊牌、架上物品）：用 GDScript 自写阻尼弹簧 θ'' = −kθ − cθ' + 风力矩 + 冲量，不用 RigidBody。参数 k、c、最大角度按物件配置。架上物品放入时从上方 12px 落下带一次轻弹，并给相邻两件 0.5° 冲量。
   - flow（烟、蒸汽、溪水）：UV 滚动 + 噪声扭曲，烟向上并按风向弯曲。
   粒子：落叶、灰尘、雨丝，用 CPUParticles2D，每场景同时存在的粒子 ≤ 60。
3. 事件接入：客人到店/离店 → 门风 + 风铃响；进出咨询区 → 帘幕掀起；入库/取出 → 架上物品弹跳。均经信号，不改游戏状态。
4. 动幅约束：室内物件最大摆角 3°，干花束等 1–2°；窗外树叶末端位移 ≤ 1.5% 画面宽；不能有持续的快速抖动。
5. 设置项「减少动态」：关闭粒子、风切为极弱、事件弹跳保留但振幅减半。写入设置文件，不进存档。
6. 性能：场景不可见时暂停其动态；在集显笔电上 1920×1080 稳定 60fps，动态系统每帧 ≤ 2ms。写一个性能测试场景记录帧时。
7. 确定性测试：给定种子与时间序列，摆角与风速可复现；阻尼后 5 秒内回到 0.1° 以内。
8. 录一段 10 秒前台白日 + 一次客人到店的画面（Godot Movie Maker 模式输出），放 docs/screenshots/a6/。

验收：视频里能看到阵风从窗外传到室内的先后顺序；客人到店时风铃、干花、帘幕依次响应；开启「减少动态」后画面基本静止；帧时达标。
```

## 美術方向 Style Bible

建議保留現有「紫藤、舊木、苔綠、暖金的水彩手繪」大方向，它已經夠溫馨；要修的是一致性與人物的生活感。一句話定調：**「夜裡還亮著一盞燈的舊街小店：暖光、紙質、植物，和老客留下的小東西。」**

**畫風關鍵詞（所有生圖 prompt 共用）**：手繪水彩＋細墨線、暖色光源、紙紋質感、低飽和底色上點綴金色、柔和邊緣光、有生活痕跡的雜物（無序但不表塊）。參考語境：Coffee Talk 的「一對一夜話」節奏、Strange Horticulture 的櫃台第一人稱氛圍、吉卜力式的小鎮空間細節——只參考氛圍，不描摹任何作品畫面或角色。

**色票**（UI 與生圖共用，寫進 theme 常數）：

| 用途 | 色名 | HEX |
| --- | --- | --- |
| 頁面底／內容面板 | 古紙 | #F3E9D6 |
| 面板深層／分隔 | 乳茶 | #E2D2B4 |
| 主文字 | 墨褐 | #3B2A1E |
| 次文字 | 枯木 | #7A6450 |
| 外框 chrome（頂欄、導航） | 夜青 | #1F3A3D |
| 主強調、按鈕描邊 | 燈金 | #C99A4B |
| 無害輔色、植物 | 苔綠 | #6E7F4F |
| 神秘學點綴 | 藤紫 | #9C86B8 |
| 警示、前世 | 胭脂 | #B5654D |

**關鍵決定：長文字一律放在古紙面板上，夜青只用在外框。** 現在的深青半透明面板配大量中文會有閱讀疲勞；案例手記、對話、檔案都應該像「翻開一本手帳」。

**字型**：標題與對白用「霞鶺文楷」（手寫感、溫度高），數值、按鈕、小字保留 Noto Sans SC。對白 20–22 px，內文 18 px，次級不低於 16 px。

**場景規則**

- 每張場景只交「乾淨底板 clean plate」：不含任何空白牌匾、文字格、面板、人物。可互動的櫃格／抽屜改用獨立切片疊上。
- 主圖 2560×1440，執行時至少 1920×1080；UI 會覆蓋的區域（右側 30%、底部 12%）畫面要「低資訊量」，但不能是空白。
- 每場景做 2 個時段變體：白日（過 09:00）與夜燈（過 18:00），用遊戲時鐘切換；另加 S01 打烊版。

**人物規則**

- 來客是現代小鎮居民：針織、工作圖裙、西裝外套、學生制服、雨衣……只用配件暗示職業（花店的剪刀、修燈師的螺絲起子）。古裝只用在前世片段。
- 強制差異：年齡 16–75、臉型、膚色、體型、髮色、眼鏡／痣／雀斑等特徵都要分散；輪廓剛影就能分辨是誰。
- 頭像畢一用半身、第三人稱微俯視、同一個頭部錨點（畫布 768×1024，眼線在 y=360），表情層 5 種：平静、微笑、猶豫、吃驚、低落。
- 作品參考 NPC：只用氣質、色系、配件做彩蛋（例如寄人籬下的詩人配竹葉書籤），不複製任何影視劇照、演員長相或官方造型。

**商品與原料**：改用「水彩小物件」，與場景同一筆觸；256×256 透明 PNG，每件單獨檔案，錯開去背。形態用輪廓區分（藥水＝圓底瓶、水晶＝尖簇、香氛＝香座），用途用角標顏色區分（物理＝胭脂、心理＝藤紫、環境＝苔綠）。

場景版式與人物參考畫板見：https://claude.ai/artifact/L5wx4VF2gtUbkQ19aHXgap

## 素材來源

場景、人物、商品建議繼續自己生圖（風格才統一）；以下是可以直接拿來補強的開源資源，全部可商用。每一項都要登記到 docs/third-party.md。

| 用途 | 資源 | 授權 | 注意 |
| --- | --- | --- | --- |
| 標題與對白字型 | [霞鶺文楷 LXGW WenKai](https://github.com/lxgw/LxgwWenKai) | OFL-1.1 | 簡體文字可選 GB 版；字型檔大，可用子集化 |
| 塔羅牌面 78 張 | [Rider–Waite–Smith 1909 掃描（Wikimedia Commons）](https://commons.wikimedia.org/wiki/Category:Rider-Waite_tarot_deck) | 公有領域 | 美國為 1929 前出版、歐盟已過作者死後 70 年；整套整理參考 [mixvlad/TarotCards](https://github.com/mixvlad/TarotCards)。建議做水彩調色濾鏡後用 |
| 雷諾曼 36 張 | Dondorf 「Wahrsage-Karten」（約 1870–1911）與 [Wellcome Collection 1825 圖版](https://wellcomecollection.org/works/sj9yh24s/items?canvas=3) | 公有領域 | 請自行確認各掃描檔的標註；Bridgeman 等商業圖庫的掃描不可用 |
| UI 小圖示 | [game-icons.net](https://game-icons.net/about.html) | CC BY 3.0 | 必須在一處署名作者；單色 SVG，可用燈金色著色 |
| 按鈕、翻頁音效 | [Kenney Interface Sounds](https://kenney.nl/assets/interface-sounds)、[UI Audio](https://www.kenney.nl/assets/ui-audio) | CC0 | Godot 版本可從 AssetLib 安裝 |
| 背景音樂 | [Cozy Tunes（pizzadoggy）](https://pizzadoggy.itch.io/cozy-tunes) | CC0，加作者附帶限制 | 不可當成自己的素材再發佈、不可用來訓練 AI；遊戲內使用沒問題。對話模型永遠不接觸音樂檔。「你自己決定價格」，若要 Extra 版至少 2 美元 |

沒有找到、需要你確認的一項：《女帝的日常》的組合頭像素材庫。那是別人的商業資源，只能參考「分層組合」的做法，部件本身要自己畫或生。A4 Prompt 就是這套做法。

## 使用方式與 Prompt 0（共通規則）

先把 Prompt 0 的內容存成倉庫根目錄的 AGENTS.md（Codex 每次都會自動讀取），之後每個 Prompt 開一個新任務、開一個分支。第一輪建議順序是 A1 → A2 → A3 → G1 → G3 → A4 → G2 → G4 → G5 → G6；A1、G1 已完成，之後請改看上方「第二輪任務順序」。A 系列和 G 系列可以交給不同的 Codex 任務並行，但同一個系列內要依序。每輪結束，把 Codex 的回報與截圖貼回給我，我來審。

```markdown
# AGENTS.md — 零点杂货铺

## 你的角色
你是本工程的实作工程师。策划与技术总监会逐次给你一个任务。一次只做该任务的范围，不顺手重构无关代码。

## 硬性规则
1. 引擎固定 Godot 4.6.3 stable 标准版，GDScript，Compatibility 渲染。不引入 C# 或第三方插件，除非任务明说。
2. 所有会改变状态的操作，必须经 GameState.execute_action_async，保存成功后才更新显示；重试同一 action_id 不可重复结算。
3. 存档结构若变更：提升 schema_version，写迁移函数（旧档在内存迁移，下一次成功动作才写盘），并新增迁移测试。不得破坏既有存档。
4. 数值、内容、概率一律放 data/ 下的 JSON，代码中不写死文案或数值。每个新 JSON 都要有校验函数。
5. 世界事实、顾客陈述、工具线索、玩家假设、对外预测是五种不同记录，不得合并。未披露的世界事实不得发给对话模型。
6. 游戏内文字一律简体中文。技术 ID 默认不显示。
7. 美术资源只作底图与装饰，任何数字、名字、状态都由 Godot 控件动态绘制，不烘焙在图里。
8. 新增的外部资源必须在 docs/third-party.md 登记来源 URL、授权、作者与 SHA256；自生成的图在 assets/ART_ASSET_MANIFEST.json 登记提示词与版本。
9. 新增 .png/.ogg/.ttf 等二进制文件走 Git LFS（先在 .gitattributes 加规则）。
10. 不确定的设计问题，写进回报的「待确认」而不是自行决定。

## 每次任务完成前必做
- powershell -NoProfile -ExecutionPolicy Bypass -File scripts/dev/run.ps1 -Test 全绿。
- 若动到画面：运行 --script res://tests/integration/shop_ui.gd，把 .tools/c-ui-captures 下 1280×720 与 1920×1080 截图列在回报中。
- 更新 docs/features.md 对应段落。

## 回报格式
1. 做了什么（文件清单）
2. 测试结果（通过/失败数）
3. 截图路径
4. 待确认
5. 已知未完成
```

## 美術與 UI 系列

生圖提示詞用英文（圖像模型對英文控制力較好）。如果你的 Codex 環境沒有生圖工具，就由你在自己的生圖工具裡跑這些提示詞，把產出放進 assets/_incoming/，再讓 Codex 接續後半段。

### A1 場景重生：乾淨底板＋可互動切片

```text
任务 A1：重做七个场景底图，去掉烘焙的空白 UI，并把可互动物件拆成独立图层。

背景：assets/generated_scenes/S04、S05、S06 把空白牌匾、格子、右侧面板画在了背景里，和动态控件对不齐；运行时只用 900×600，大屏模糊。

要做：
1. 为 S01–S07 各生成 2560×1440 的干净底板（白日版），再生成夜灯版；S01 另加打烊版。统一风格前缀见下方 STYLE。底板内不得有任何文字、空白标签、界面框、人物。
2. 右侧 30% 与底部 12% 会被 UI 覆盖，该区域保持低细节（墙面、帘幕、暖光模糊）。
3. 可互动物件另出透明切片：S02 门、帘幕、信件、台灯（开/关）；S04 柜门开/合、单个空格、单个抽屉；S05 研钵、空瓶、天平；S06 货篮。每个切片单独 PNG。
4. 在 data/shop/visuals.json 新增 scenes 区块：每个场景的 day/night 底图路径、切片路径、切片在 2560×1440 坐标系中的矩形，以及热区矩形。shop_front.gd 的 _add_hotspot 与 shop_screen.gd 的 SCENE_ART 改为读该配置，不再写死。
5. 根据游戏时钟切换：09:00–17:59 白日，18:00–22:00 夜灯，打烊后 S01 用打烊版。切换用 0.6 秒交叉淡入。
6. S04 储物柜的格子改为 GridContainer 动态生成，每格用「单个空格」切片作底，放物品图与数量；数量和物品名由控件绘制。
7. 旧的 900×600 裁图移到 assets/_legacy/，不删除，直到新图通过验收。

STYLE（每张图必加）：
hand-painted watercolor illustration with fine sepia ink linework, cozy small-town mystic curio shop, warm lamp light, soft paper grain texture, muted parchment and aged wood palette accented with antique gold, moss green and wisteria purple, lived-in clutter with personal objects, gentle rim light, no text, no letters, no UI elements, no blank labels, no frames, no people

场景主体（接在 STYLE 后）：
S01: exterior of a two-storey old stone and timber shop on a quiet cobbled lane at dusk, round arched display window glowing, wisteria over the door, potted herbs, a hanging crescent-moon sign with no text, wide composition, 16:9
S02: first-person view from behind a worn wooden counter, shop interior with shelves of jars and books on the left, a green velvet curtain doorway at center leading to a private room, wooden apothecary drawers at right, counter top in foreground with a brass lamp and small dish, right third kept calm and softly lit
S03: intimate consultation nook, deep green sofa facing a low round table, tasselled table lamp, cushions, a small brass astrolabe and teacups, curtains half drawn, view from the reader's armchair, quiet and private
S04: front view of a tall wooden storage cabinet with open shelves and rows of small drawers, empty shelves (items will be added in game), wisteria at top edges, a doorway to a stockroom at far right
S05: top-down three-quarter view of a crafting workbench, empty clear area in the middle for UI, mortar and pestle, brass scales, glass vials, dried herbs hanging above
S06: inside a small materials market stall, baskets and crates along a counter, hanging dried herbs, a doorway to a sunny street behind
S07: a riverside footpath at the edge of a small town, stone bridge, wildflowers, crystals among moss by the water, morning light
夜灯版接："same scene at night, warm interior lamplight, deep teal shadows, a few fireflies or moths near lamps"

验收：1920×1080 下画面无糊、无重叠的空白牌匾；热区点得到；切换时间时白日/夜灯切换正确；截图回报。
```

### A2 商品與原料圖重做（已由第二輪 A2R 取代）

```text
任务 A2：废弃 inventory-atlas-v2 大图集，改为每件物品一个透明 PNG，风格与场景统一。

问题：现图集去背失败，边缘有红黄杂色；平涂矢量风与水彩场景不搭。

要做：
1. 先写 tools/check_alpha.py：扫描 PNG 的半透明边缘，若边缘像素饱和度>0.6 且色相在红/黄区间占比>2%则报错。纳入 run.ps1 -Test。
2. 为 catalog.json 的每个 item 生成 256×256 透明 PNG，放 assets/items/<item_id>.png。生成时先输出纯色 #FF00FF 背景，再用色键去背并向内收缩 1px、羊化 1px，最后跑 check_alpha.py。
3. 物品提示词模板：
   "single {object} game inventory icon, hand-painted watercolor with fine sepia ink outline, soft warm lighting from top left, subtle paper texture, three-quarter view, centered, fills 80% of canvas, plain flat #FF00FF magenta background, no shadow on background, no text"
4. 形态靠轮廓区分（药水＝圆底烧瓶，水晶＝尖簇，香氛＝香座与烟），用途不画在图里，由 UI 角标显示：物理＝#B5654D、心理＝#9C86B8、环境＝#6E7F4F。
5. visuals.json 改为 item_id → 单独文件路径；商店、储物柜、工坊的取图全部改读这里。旧图集移到 assets/_legacy/。
6. 在 64×64 与 128×128 下各截一张对照图回报。

验收：check_alpha.py 全部通过；所有页面物品图来自同一配置；64px 下轮廓可辨。
```

### A3 UI 主題重做（已由第二輪 A3R 取代）

```text
任务 A3：把实际 UI 做到接近 assets/frontdesk_concept_reference.png 的质感，并解决长文字可读性。

要做：
1. 字体：加入 LXGW WenKai（OFL-1.1，来源 https://github.com/lxgw/LxgwWenKai）作标题与对白字体，Noto Sans SC 保留给数值、按钮、小字。可用字型子集化控制体积。登记 third-party.md。
2. 拆成两套 Theme：
   - chrome.tres（顶栏、底部导航、侧栏外框）：夜青 #1F3A3D 底，灯金 #C99A4B 1.5px 描边，圆角 10。
   - paper.tres（对话、案例手记、档案、所有弹窗内容）：古纸 #F3E9D6 底，墨褐 #3B2A1E 字，乳茶 #E2D2B4 分隔。
   颜色集中在 scripts/ui/palette.gd 常量，两套 theme 从这里取值。
3. 用 NinePatchRect 做可伸缩边框：纸面板（带轻微纸纹与角落藤蔓花纹）、金边按钮（普通/悬停/按下/禁用四态）、标签页。素材用生图得到：
   "seamless aged parchment paper texture, subtle fibers, warm cream color, very low contrast, tileable, no stains in center"
   "ornate thin antique gold corner flourish with tiny wisteria leaves, on flat #FF00FF background, symmetric, for a UI panel corner"
4. 对话气泡：顾客在左（纸底，小头像），店长在右（乳茶底），系统提示居中斜体。线索获得时在气泡下方出现小印章式「新线索」。
5. 状态栏：金币/精力/口碑/日期时间/候客数，精力用条状显示，低于 25% 时变胭脂色。
6. 背景音乐：从 pizzadoggy 的 Cozy Tunes（https://pizzadoggy.itch.io/cozy-tunes）选 3 首：白日、夜灯、咨询区各一，转为 .ogg，按游戏时钟交叉淡入切换；做 AudioBus「Music」与音量设置。third-party.md 写明其附带限制（不可作为素材再发布、不可训练 AI），音乐文件不得进入任何模型请求。
7. 音效：加入 Kenney Interface Sounds（CC0）中 6 个文件：点击、翻页、确认、取消、金币、通知；做一个 AudioBus 「UI」与音量设置。
8. 全部动态文字在 1280×720 下不得裁切；弹窗宽度最大 960px。

验收：对照概念图截图并列三组（前台、咨询、案例手记）；任何页面不再出现 Godot 默认灰色弹窗。
```

### A4 分層組合頭像與捏臉

```text
任务 A4：做一套分层组合头像系统，让每个随机顾客有稳定、不重复的外观，并支持玩家捏脸。

技术方案：
1. 画布 768×1024，半身、稍侧 3/4 视角。锁死锚点：双眼中线 y=360，面部中轴 x=384，肩线 y=700。
2. 图层顺序（从下到上）：hair_back → body（肤色）→ outfit → face_shape（肤色）→ features（痣/雀斑/皱纹）→ eyes_{expr} → brows_{expr} → mouth_{expr} → hair_front → accessory（眼镜/发饰/耳环/帽）。
3. 肤色与发色不单独出图：部件以灰阶+线稿产出，用 shader 做「灰阶映射到调色板」（gradient map），发色 8 种、肤色 6 种、服装主色 10 种。这样部件量少、组合多。
4. 第一批部件数：脸型 6、眼型 8（每种 5 表情：平静/微笑/犹豫/吃惊/低落）、眉 6、嘴 6（每种 5 表情）、前发 12、后发 10、服装 16（现代生活装：针织、工作围裙、西装外套、学生制服、雨衣、卫衣、旧式长大衣……）、配件 14、年龄特征 4（青少年/成人/中年线条/老年白发与皱纹）。
5. 生产方式：先生成一张「光头人台」基准图并定稿，之后所有部件都用该图做局部重绘（inpainting），掩码只盖住该部件区域，确保对齐。每个部件导出为同画布尺寸的透明 PNG，不裁切。写 tools/check_parts.py 检查画布尺寸与锚点区域是否有像素。
   基准提示词："character portrait base mannequin, half body, slight three-quarter view, neutral expression, bald head, plain grey tank top, hand-painted watercolor with fine sepia ink lines, soft warm light from top left, flat #FF00FF background, centered, eyes at 35% from top"
6. 新建 data/people/appearance_parts.json：部件表、调色板、互斥规则（帽子与高马尾互斥等）、年龄与部件的允许表。
7. scripts/people/portrait.gd：输入 appearance 字典与表情键，返回合成后的 Control（各层 TextureRect + 调色 shader）。缓存合成结果为 ImageTexture。
8. people.gd 的 _appearance 改为从部件表抽取，并计算与已有 NPC 的「轮廓差异分」（前发+后发+配件+发色属于主要轮廓），分数太低则重抽，最多 20 次。外观一经生成就随 npc_id 永久保存。旧档的 face_01 等键要迁移映射。
9. 生成式人物：person_generation 写入的「外貌描述」由程序映射到部件（年龄、发长、眼镜等关键字），而不是让模型选部件 ID。
10. 表情切换：咨询中对白返回时附带一个受限的 mood 字段（neutral/smile/hesitant/surprised/sad），由审核流程一并校验；本地对白用话题配置的默认表情。
11. 捏脸界面：左侧实时预览，右侧分页（脸/发/服/配件/颜色），「随机」按钮。固定 NPC（林照晚）保留预设立绘，不走组合。

验收：随机生成 24 个顾客拼成一张对照图，缩小到 96px 仍能一眼分辨不同人；存档重开外观不变；各表情切换无错位。
```

## 玩法補完系列

G3 是其他所有內容擴充的前提：事件結算沒有資料驅動之前，多寫案例、家族都無法產生「建議→後果」。

### G1 客流：零客日、集中到店

```text
任务 G1：让每日客流真正「不固定」，允许零客日与集中到店的爆单。

现状：data/people/templates.json arrival.natural_min=1；people.gd plan_day 中 upper 被 clampi(...,1,12)，故自然客至少 1 位；到店时刻在营业时段均匀随机。

要做：
1. 客量改用「期望值 + 分布」：expected = base + 口碑加成 + 经验加成 + 限时客流加成 + 星期修正（周末/工作日）+ 天气修正（可先用简单随机天气：晴/阴/雨），实际客量用泊松分布抽取（种子可复现）。所有系数进 templates.json。
2. 允许 0。opening_guest 仅在第 0 天保证一位新手客。零客日前台显示专门文案与建议（去采集/研习/制作），而不是空白。
3. 到店时刻改为「波峰混合」：午间、傍晚两个高峰加底噪；另加 burst 事件（概率可配）：口碑传开、群体转介绍、节日时，3–5 位在 30 分钟内到店。burst 来源要写入 arrival.source 与顾客卡。
4. 候客满员时：新到的客人按性格与紧急度决定「门外等/留下预约请求/直接走」。直接走的要记入流失统计并降低该人 return_bias。
5. 前台候客栏显示每人的「耐心」可视化（沙漏图标三档）。长耗时行动（学习、制作、采集）确认前提示「将有 N 位候客可能离开」。
6. 写分布测试：模拟 2000 天，断言零客日占比、爆单日占比落在配置目标区间（默认目标：零客日 5–12%，超过候客容量的日子 3–8%）。更新 tests/people/distribution.gd。

验收：分布测试通过；旧档的已规划日不重算；零客日前台有内容。
```

### G3 事件結算資料驅動化（先做）

```text
任务 G3：把 scripts/divination/event_rules.gd 的事件结算从「邀请案专用」改为通用规则引擎。

现状：_resolve() 写死了 advice_key（message/attend/private/note）、changed_entrance、confirmed_venue；archive 案没有 event。

要做：
1. 在 divination.json 的每个 case.event 下定义：
   - advice_options：[{key, label, requires_clue?}]
   - world_facts：隐藏事实及其取值范围
   - rules：按顺序匹配的条件表，每条 {when:{advice, accepted, fact:{id:value}, branch, item_effect, relationship_min:{rel_id:n}, personality_in:[...] }, outcome}
   - outcomes：{id:{outcome, evidence, feedback(delayed/immediate/never), delay_minutes, text, effects[]}}
   - effects 支持：trust、familiarity、npc_relationship(rel_id, delta)、reputation、gift(item_id, qty)、referral(template或npc_id)、traffic_boost(minutes, amount)、review_growth、unlock_topic。
2. event_rules.gd 重写为：读取规则 → 第一条匹配生效 → 写 outcome → 按 effects 生成待处理效果（仍走现有 _effect 与去重 ID）。邀请案用新格式重写后行为必须与现在完全一致：先为旧逻辑写「黄金测试」记录所有分支的输出，再重构。
3. 反馈时间：反馈可用时间 = 事件发生时间 + delay，再交给 A 的 schedule_feedback 按性格、行程、关系决定实际回访或不回。未反馈时 evaluation 保持 pending，不得自动判失败。
4. 反馈披露分级：evidence=sufficient 才披露实际结果；partial 只披露顾客感受；none 不披露。玩家手记分开显示「对外预测」「顾客实际说法」「是否已验证」。
5. generated_cases.gd：生成案例从三套「事件模板」中拣一套套用（联系某人 / 去某处做某事 / 要不要做某个决定），模型只填写文本槽，不得自定规则。模板放 data/divination/event_templates.json。
6. 为 archive 案补一个 event，用新格式。
7. 新增校验：每个 case 的每个 advice 至少可达一个 outcome；每个 outcome 至少被一条规则引用。

验收：黄金测试与全部旧测试通过；archive 案可从建议走到反馈；生成案例三类模板各跑一个完整流程。
```

### G2 作品參考家族庫

```text
任务 G2：把「作品参考家族」从单一样例扩展为可配置的家族库。

现状：people.gd ensure_family 只读 config.family 一个字典；关系只建 members[0]↔members[1]；goal 的问题文案写死；正式配置 family 为空、family_percent=0。

要做：
1. 新建 data/people/families/ 目录，每个家族一个 JSON。字段：template_id、source_work、reference_note（策划备注，不进游戏）、rarity（rare/epic）、background、members[]（各自 reference_character、改写后姓名、身份、生日、MBTI、性格、说话习惯、口头禅、信息边界、外观部件固定值、彩蛋物件）、relationships[]（任意成员对，kind、closeness、tension）、member_goals[]（每人的初始问题，可指向家族内另一人）、entry_conditions（最低口碑/天数/已学术式/前置家族成员信任）。
2. 配置分开：首次触发概率 family_trigger_percent、同时活跃家族上限、每家族每日新登场上限、同时段上限、特殊回访率。统计要分「家族触发次数」与「特殊成员到店次数」，分布测试断言特殊成员到店占全部到店 ≤ 配置上限（默认 12%）。
3. 抽家族时只从满足 entry_conditions 的家族中抽；实例化一次后整个关系网保存在该存档，成员分批登场。已登场成员从此走普通回访流程，沿用 npc_id。
4. 对话模型拿到的是「改写后的人设 + 口吻 + 边界」，不得提供原作角色名、原作台词。审核规则增加：对白中不得出现原作人名、不得引用原文（建一份屏蔽词表）。性格还原靠人设字段的详细度，不靠提原作。
5. 家族内关系变化：G3 的 npc_relationship effect 可以改任意家族内关系；档案页只显示已揭示的关系。
6. 不要自行创作家族内容。只建一个占位家族 family_placeholder.json 用于测试（3 人，原创），并在 docs/families.md 写出策划填写指南。策划会另外提供《红楼梦》《暮光之城》等家族文件。
7. 旧存档的 family_red_mansion_demo 实例要能迁移为新格式。

验收：占位家族 3 人分批登场；关系网 3 条边均可变化；分布测试通过；屏蔽词审核有测试。
```

### G4 內容擴充：商品、原料、人物池

```text
任务 G4：扩充经营内容与普通顾客模板，并把商品效果做成可组合的规则。

要做：
1. 商品效果类型扩展（catalog.json effect.kind）：attribute（精力等）、option（解锁追问）、event（写入 G3 规则可读的 item_effect）、patience（提升候客耐心）、clue（揭示一条可揭示线索）、relationship（顾客与第三人亲密度微调，需事件配合）、traffic（店内香氛小幅客流加成）。每种效果都要有「使用记录 → 反馈引用」的关联。
2. 商品到 15 种（形态：药水/水晶/香氛/护身符/茶包/蜡烛；用途：物理/心理/环境交叉），原料到 18 种（采购 8、采集 6、顶客赠送/隐藏 4），配方 15 个。另加「变体配方」：同一商品用不同原料组合制作，品质不同。
3. 新增采集点 1 个（夜间开放的「铁道旧库房」或同等设定），有时段与天气条件。
4. 「顾客需求 → 研发灵感」：登记缺货需求时记录需求标签（如「睡不好」「不敢开口」），配方表用标签匹配，匹配到的配方变为可研究。未登记过的配方在工坊中显示为「还没有灵感」。
5. 普通顾客模板扩充：姓 40、名 120（男女中性分组）、职业 40（写入工作时段，供回访行程用）、性格原型 16（一 MBTI 一种，含耐心、回访偏好、对建议的偏好：喜欢具体步骤/喜欢被倾听/喜欢直说）、年龄段 5。对建议的偏好要影响 G3 中 accepted 的概率。
6. 所有新文案写为简体，放 JSON，不写进代码。为每个新物品生成图（套 A2 流程）。

验收：经营规则测试覆盖每种 effect.kind；一张「配方—原料—来源」对照表输出到 docs/economy.md；模拟 30 天金币曲线不崩（既不无限增长也不快速归零）。
```

### G5 前世跨世關係網

```text
任务 G5：把前世从「单次片段+核实」扩展为可累积的跨世故事。

要做：
1. 新建 data/past_lives/：每个「前世线」定义若干世（朝代/地点氛围、该世身份）、参与的今生 npc（可为固定、家族成员或「任意普通客槽位」）、片段列表（vision / evidence / echo）、正确解读与误读选项。
2. 「看到」与「理解」分开记录：片段入手是一条记录；玩家解读是另一条，状态 unverified/verified/refuted。错误解读可以被后续证物推翻。
3. 前世手记页做成一张「世代图」：纵轴为世，节点为已知身份，只显示已得片段；未知部分用烟雾遮罩。
4. 普通客可通过低概率与条件被绑定到「任意槽位」的前世线；绑定后永久保存。
5. 前世的问题与今生的问题分开：案例标注 cause=present/past/both，只有 past/both 的案例用前世技法才有有效片段，否则得到「看不到与此有关的前世」。
6. 前世片段插图用古风水墨＋水彩、整体褐金色调、人物只给背影或侧影，提示词套 A1 STYLE 并加："memory fragment, sepia and faded gold wash, soft vignette, figures seen only from behind or in silhouette, ancient Chinese setting"。

验收：一条 3 世的占位前世线可从第一片段走到全部验证；误读可被推翻；世代图截图。
```

### G6 經營風格報告

```text
任务 G6：把 style_report 从「三类次数」升级为有依据的娱乐性经营风格报告。

要做：
1. 定义 6 个可观察维度，每个只用已记录的行为：追问深度（每次接待的提问数与自由输入占比）、谨慎度（预测前用了几种术式）、商业倾向（推商品次数）、关系经营（约回访、请介绍）、节奏（平均接待时长与候客流失）、复盘习惯（失误后是否复盘）。
2. 每个维度显示：分数、样本数、「依据」（点开可看到对应的几次接待）。样本不足显示「观察中」。
3. 报告页用「店长手帐」样式，文案由维度组合映射到 12 种「店长类型」称号（如「慢火炖汤型」「翻遍牌堆型」），文案放 JSON。
4. 页面底部固定声明：只描述本局可追溯的经营行为，不是 MBTI 或人格测验。不得输出 MBTI 字母。

验收：用三组假数据（重追问/重商业/均衡）得到不同结果；每条结论都能点开依据。
```

## 驗收清單

每個任務回來後，你自己玩一遍這條路線，再把回報貼給我。

- [ ] 1920×1080 與 1280×720 下，七個場景都不糊、沒有重疊的空白牌匾
- [ ] 過了 18:00，場景切換為夜燈版
- [ ] 案例手記、對話、檔案都是古紙底，連續閱讀 5 分鐘不吃力
- [ ] 連續 10 位新客人，縮圖也能一眼分辨；重開存檔外觀不變
- [ ] 連續跳 20 天，至少遇到一次零客日與一次候客客滿
- [ ] 同一個案例給兩種不同建議（開兩個存檔），得到不同後果與反饋
- [ ] 家族成員 A 來問 B 的事，結果改變 A↔B 親密度，且檔案頁看得到
- [ ] 登記一個缺貨需求後，工坊出現對應的可研究配方
- [ ] 前世誤讀被新證物推翻，世代圖更新
- [ ] 經營報告每條結論都能點開依據，且沒有 MBTI 字母
- [ ] run.ps1 -Test 全綠，舊存檔可正常載入
