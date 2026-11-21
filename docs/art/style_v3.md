# v3 画面规则

目标：传统动画电影的手绘背景，不透明广告颜料画在纸上。保留丰富度与好的光影，但去掉 AI 痕迹；温馨、整洁、有生活感。

- 光线（最重要）：要自然而美丽，不是要少光。只有一个明确主光。白天是左侧窗户进来的午后斜阳，在地板、柜台、层板上投出边缘柔和的窗格形暖色光斑；光穿过玻璃罐、薄叶、布帘时让它们从背后透出暖色；木地板向上反光，层板底部与天花带暖色；窗边可有一道淡淡的含尘光柱（只能一道、要淡、方向与主光一致）；远离窗户的区域是安静的蓝绿色阴影，有柔和渐变，不发黑；暖亮处与冷阴影要有明显对比，所有投影背向窗户。夜晚只有柜台台灯和一盏吊灯两个光源，光在柜台和附近层板聚成暖色光池并随距离渐弱，灯罩因透光而柔和发亮，窗外深蓝暮色给窗边一点冷光，远角暗但可辨认。禁止的只是「无来源或不合物理的光」：光源周围的模糊光晕、多方向乱射的光束、闪点星光、自己发光的物件、每条边都描金光、镜头光斑。
- 物件密度：以 3–5 件为一组成组摆放，组间留空；每层架子约留 1/4 空位；全画面约 25–40 件可辨认物件；全是老街小店真实会有的东西（贴素面空白纸标签的玻璃罐、铁盒、陶罐、几本书、干草药束、小铜秤、藤篮、黄铜把手的木抽屉）。
- 细节分布：细节集中在柜台与中间层架；墙面、天花、角落画得松，看得到笔触；边缘有虚有实。
- 装饰：紫藤至多窗边一枝；不要金色雕花、不要发光水晶、不要对称拱门加花纹。
- 颜色：暖色调但不是整张金橘；用鼠尾草绿、灰蓝绿平衡；饱和度中等。
- 构图：右侧 30%、底部 12% 细节较少，留给 UI。

# v3 自评清单（每项 1 分，8 分以上合格）

1. 看得到手绘笔触，墙面与角落较松。
2. 主光方向明确，光斑形状合理。
3. 暗部偏冷、不发黑。
4. 光都有来源：每一处亮部都能指出对应光源；无光晕、无乱射光束、无闪点、无自发光。
5. 无金色花纹与雕花堆叠。
6. 紫藤至多一处。
7. 物件成组、组间有空隙、层架约留 1/4 空位。
8. 每件物件都认得出是什么。
9. 结构合理：柜脚、书脊、窗格、门框无扭曲融化。
10. 右侧 30%、底部 12% 细节较少。

打分时必须实际打开图片逐项看，写出每项的判断理由，不得默认给分。

# 提示词禁令

提示词中不得出现任何工作室、画家、导演、作品的名称。只描述画法与光线。

# V3_EDIT（改画白日版，输入为 v2 原图）

Repaint this image as a hand-painted background painting for a traditional animated film, made with opaque poster colors on paper. Keep the room layout, camera angle, and furniture positions. Lighting is the most important part of this painting and should feel natural and beautiful. Late-afternoon sun enters through the left window and lays warm, soft-edged, window-shaped patches of light across the floor, the counter top, and the lower shelves, catching the edges of the objects it touches. Where sunlight passes through glass jars, thin leaves, and the cloth curtain, they glow warmly from behind. In the slightly dusty air near the window, a single faint, soft shaft of sunlight is barely visible, running in the same direction as the sun. Light bounces off the wooden floor and gives the undersides of the shelves and the ceiling a warm reflected tint. Areas away from the window fall into calm, cool blue-green shade with gentle gradations, never black. Keep a clear contrast between the warm sunlit patches and the cool shade; all cast shadows point away from the window. Keep the shelves lived-in but tidy: objects grouped in small clusters of three to five with clear space between groups, about a quarter of each shelf left empty, every object an ordinary recognizable item from an old small-town curio shop (glass jars with plain blank paper labels, tin boxes, ceramic pots, a few books, dried herb bundles, a small brass scale, rattan baskets, wooden drawers with brass pulls). Reduce the wisteria to a single branch near the window. Remove all ornate gold filigree, carved ornaments, glowing crystals, and sparkles. Concentrate fine detail around the counter and the middle shelves; paint the walls, ceiling, and corners more loosely with visible brush strokes and soft edges. Muted warm palette balanced with sage green and dusty teal. Keep the right third of the image calm with low detail. No text, no letters, no people. No bloom or halo around light sources, no multiple light rays, no sparkles or twinkles, no objects glowing on their own, no golden rim light on every edge, no lens flare, no bokeh, no depth-of-field blur.

（非 S02 场景：把句中的 counter、shelves 等换成该场景对应物件，其余照用；S04 另加 “Remove every object from the shelves so all shelf boards are empty.”）

# V3_NIGHT（夜灯版，输入为同场景白日定稿）

Same room, same painting style, at night. A warm table lamp on the counter and one small pendant lamp are the only light sources. Their light pools on the counter and nearby shelves and falls off gradually with distance; the lampshades glow softly because light passes through the fabric; nearby objects catch warm highlights and cast soft shadows pointing away from the lamps. The window shows deep blue dusk and lets a faint cool light onto the window side of the room, creating a gentle warm-cool contrast. The far corners are dim but still readable. No halos, no light rays, no sparkles, no objects glowing on their own.

# V3_ITEM（物品，附 S02 v3 定稿作为风格参考）

A single {object} painted in the same opaque poster-color style as the reference image, lit from the upper left by warm afternoon light with a soft, slightly cool core shadow on its right side, standing upright on its flat base, three-quarter front view seen slightly from above, plain flat #FF00FF background, no cast shadow, no text, no halo, no sparkles.
