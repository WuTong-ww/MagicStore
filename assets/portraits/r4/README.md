# 第四轮配饰挂载

`headphones-face_01.png` 至 `headphones-face_06.png` 是同一张选定耳机画稿按六个脸型锚点做的确定性仿射挂载；`scarf-back.png` / `scarf-front.png` 是两张独立透明画稿，分别放到颈后和胸前。全部为 768×1024 原生画布中的绘制层，原有 v3 部件不覆盖。

`data/people/appearance_parts.json` 的 `anchors.faces` 按六张实际脸图标定 crown、ear_l、ear_r、neck_base、chin。`rendering.version=3` 的 `attachments` 给出各脸型贴图路径、SHA、完整耳罩测量区域、头梁分层界限与围巾结区域，元数据由 GDScript 和 Python 双方校验。`portrait_render_plan.gd` 仍兼容 v1/v2 渲染策略，便于读取第三轮与刘海修正前对照；存档外观 version=2、10 个部件 ID 和颜色不变。

排序为 `hair_back → scarf_back → body → outfit → scarf_front → face_shape … headband → hair_front → accessory`。围巾两个绘制实例共用已存的 accessory_07；耳机 accessory_14 也分为两次绘制：y<300 的头梁在刘海后，耳罩/下支架在前。耳机不压、不裁、不替换前后发，全部原生 RGBA 像素保留；刘海可自然遮住头梁的一部分或大部。不得为显示头梁而制造额外露出的头皮。帽子隐藏/压发规则未更改。实时控件和 CPU 合成都消费同一个渲染计划。

来源：本任务通过内置 `image_gen.imagegen` 生成耳机、前片、后片各一次，没有重做。提示词、原稿 SHA/原生尺寸、挂载矩阵/裁切框、输出 SHA、版本登记在 `assets/ART_ASSET_MANIFEST.json`。原稿在忽略的 `.tools/r4-b/generated/`，不提交候选或原始下载包。`tools/art/build_r4_portraits.py` 只清除低 alpha 的孤立碎点、缩放及定位，不手绘新内容；需相应原稿和 prompts.json 才能复现同样输出。

验收工具 `tools/check_portrait_clipping.py` 测量实际 alpha 加权耳罩中心，误差必须 ≤6px，检查头梁锚点确实有绘制像素；围巾后片经所有后续层合成后，可见像素必须 ≤自身 5%，并额外遍历 16 套衣服；实测结区中心在颈根以下，前片图形不越过下巴。矩阵覆盖 6 脸×12 前发×10 后发×15 配饰（含无配饰）=10,800 项，仍记录原排斥关系。

`tests/people/portrait_r4.gd -- --capture` 生成真实 GPU 六人对照图，前提是 `.tools/r4-b/baseline` 为未修改的 ee576ca 工作树且已导入；`--headphones-review` 另生成四种刘海的修正前后图，需保存的修正前配置 `.tools/r4-b/headphones-before-config.json`。初图样本错误、用户批准补图及后来主动要求修复刘海穿模的历史均在审阅包记录，不伪称从未重拍。`tools/art/r4_anchor_overlay.py` 输出锚点调试图。图位于 `docs/screenshots/round4/B/`；源 SHA、测试与人工试听事项见 B 线审阅包。
