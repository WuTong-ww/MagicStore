# A7 纯布局独立只读审查

2026-11-22。审查者：a7_regression。独立范围仅 `scripts/shop/shelf_layout.gd`、`tests/shop/shelf_layout.gd` 与实际 `data/shop/visuals.json.scenes.S04` / `.tools/art/a7/s04-shelves-proposal.json`；未把本人写的旧测试适配或preview作为独立证据。为追踪类型边界，只读查看SceneVisual调用点和renderer纹理赋值点。未运行测试、Godot、GUI或Git，未修改生产文件。

## 发现

**一项需要修复的调用边界：** `scripts/shop/scene_visual.gd:226` 在新货架分支将 `data.get("items",{})` 直接传给 `ShelfLayout.settings_valid(scene,item_map:Dictionary)`。其前面没有确认顶层items是Dictionary。若合法JSON语法但字段类型错误（例如items为`[]`、`null`或字符串），会在GDScript类型调用边界报错，而不是令配置校验返回false。Core本身的typed API没有问题；调用方应先guard `data.get("items") is Dictionary` 再调用，并加这三类拒绝用例。已即时通知root，由root拥有的SceneVisual修复。本报告快照时尚未复核修复，不能据此写“已解决”。

**非阻断的参数上界债：** `shelf_layout.gd:86/88` 的shadow/paper.texture_size仅检查正整数（最大2147483647），没有较小的渲染资源预算上界。生产128×32/256×256很小且正确；若未来手工误填极大尺寸，校验仍会接受，renderer会据此设置程序纹理尺寸。建议以后加适合项目的尺寸预算及负例，不把这个静态推断写成已经发生OOM或运行失败。

当前实际生产配置与下列布局算法未见其他阻断。

## 逐项核对

| 项 | 结论与依据 |
|---|---|
| 支点/底边 | `_item_valid`要求bbox边界整数、bottom_y=bbox.bottom−1、bottom_left/width在底部bbox内；layout用left+(width−1)/2及实测bottom_y，不偷用PNG中心。pivot.y是层板y+contact_inset=2。支持点随微旋固定。 |
| 原生crop | native_size[1672,941]、crop[0,.25,1672,940.75]与实际S04门层A1R source_transform一致。crop必须有限、正面积且不超native，层板线x/y限制在crop内；layout最终visible_rect还须在crop内。Core输出原生坐标，不混进屏幕分辨率。 |
| 旋转/堆叠装箱 | `_relative_bounds`逐副本旋转完整alpha_bbox四角，优先覆盖软alpha边；每副本偏移是原生−10/−10，旋转在同一底部支点。放置同时满足实际轮廓与支撑底宽最小间距，行满换下层，放不下明确overflow。该变换与renderer的父pivot旋转、Sprite scale/offset顺序一致。 |
| 数量 | 正库存每ID一组，1–3副本对应数量；>3保留真实quantity但copy_count封顶3。0与无效数量不生占位；只是派生显示，不改items。 |
| 获得顺序 | 固定category_order成品→原料→纪念物；同类按首次历史batch数组索引（含已耗尽批次）再item_id。与计划中的售空再购不换历史顺序一致；不按at时间或字典插入顺序取巧。 |
| 确定性/RNG | `_fraction`为显式整数hash，乘33后掩码0x7fffffff，不调用RNG/时钟/OS。有限ID派生gap16–24与角±1.5；同输入可重建。未发现对输入view/config的写入。 |
| unknown items | 正数量但item_map无图的ID进入overflow，不占已有货架位置；不用缺图占位伪装完成，也不会向业务加物品。 |
| 坏数据处理 | Core layout对scenes/items/catalog/shop用_dict降级保护；batches须数组、批次须Dictionary且item_id为String。设置先全校验后几何；NaN/Inf/crop/bbox/逆向层板等拒绝，返回固定entries/overflow空形状。例外是上方SceneVisual调用边界需root加guard。 |
| 实际配置 | 四层y238/375/521/626递增，x278–1045在crop内；scale .45/.47/.49/.51；昼夜tint合法，阴影1.1/12/.35、纸纹.08、抬升6、max3、字体/名签/调试字段齐备；生产额外labels由SceneVisual要求且均非空。提案与实际除root追加labels外一致，活跃layers没有slot。 |

## 测试代码阅读结论

- 有不依赖实现输出的手算oracle：pivot(104.75,502)、support(109.5,200)、rect(100,452,10,50.5)、阴影宽11；三副本union(100,432,30,70.5)。
- 覆盖空/NaN/Inf/负/倒置/非法颜色/格式串/路径/支持数据拒绝；alpha_bbox扩大、0/1/2/3/4/30数量、首历史顺序与重购、字典键重排、unknown overflow、恰好装入/超1px/换层/全满、上宽下窄、crop上越界。
- 旋转角点union有与公式一致的检查，单独手算无旋转oracle及renderer专用target有助于避免全靠同算法互相比。全局RNG不消费、输入深拷贝不变和重复调用一致均有明确断言。
- 没有在本代理回合执行这些测试；不得把阅读当作新增通过计数。SceneVisual顶层items类型负例是本次发现的缺口。
- Core只检查源crop上下边界，不计算“每层上方家具的净高度”；当前九类定稿与现有标定需要以实际GUI/200%检查确认，未来加入更高/更大物件时需复核层板间距。这是几何模型范围说明，不声称当前有穿板。

## 快照

- shelf_layout.gd SHA256 `2c6250d16727464eeb1811f62eda91b28f51fa398373bb34d223d8d6ac9c4d78`
- tests/shop/shelf_layout.gd SHA256 `de8de8dbf306507e20a033c60475f737c096aa34856d67aedd657d9d9f4322ab`
- data/shop/visuals.json SHA256 `48476d089a6211502eef48f380a746a37b7ffd295a62aa43f51a3f8d8597e2c9`
- s04-shelves-proposal.json SHA256 `e2bc52b8edd602e89134908fd2dfe7975b0ec00cc164fd50369a2351767d69d7`

后续代码/参数变化需按新快照复核；这份审查不代替root实际图形验收或完整run.ps1 -Test。
