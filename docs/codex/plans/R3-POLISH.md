# R3-POLISH 实施计划

> 执行 superpowers:subagent-driven-development；root 独占Godot与浏览器，三个owner按文件/函数边界并行，不整文件覆盖Main。

**目标：** 完成v3界面、字体与图片图标、真实短窗口/网页滚轮和围巾/帽子修复。

**规格：** 目标附件R3-POLISH、`docs/codex/WEB_ADDENDUM_R3.md`第1–3项、`R3-POLISH-design.md`、AGENTS.md。

**基线：** `b93f14f5422d904eee79ed411349ef69c9d395ab`，schema15；MUSIC已完成，Main1c21a72a、双后台pump、稳定创建、音乐/风铃、Title模态与已修字号必须保留。main e27441b不动。标准完整测试预算0/3。

**技术：** Godot4.6.3 stable / GDScript / Compatibility；本地Python字体/alpha检查；内建image_gen只用于四个无字状态图标，不调用付费API。

## 步骤与边界

- [ ] 1. 复核三个准备包与当前基线；先运行实际短尺寸/字体符号/alpha契约RED，原日志保留，不把缺脚本解析失败称功能RED。
- [ ] 2. 嵌入WenKai Mono（官方OFL与真实SHA登记）；统一所有实际主题字体槽，数字等宽；全JSON/GD中文码点扫描100%，图标改SVG/PNG。新配置均有严格validator，任何状态/数量不烘焙到图片。
- [ ] 3. 木顶栏/蜡封主按钮/纸签次按钮/卡片选择，精简操作说明；root整合Main小hunk，保护MUSIC和TITLE契约。四图按v3逐张实看评分≥8，每张最多4次，溯源登记不突破原manifest预算。
- [ ] 4. 1920×1080 + canvas_items/expand；用真实Window/CSS尺寸计算<640阈值、≤45%对话、全高覆盖抽屉、人物上移与最小可用整体缩放。覆盖默认CASE及旧咨询，Title菜单独立安全层，不能只修legacy。
- [ ] 5. 先观测DOM→Godot→scrollbar事件，再最小修真实Web滚轮；嵌套弹窗/侧栏均测试滚轮与边界，不能只拖条或注入滚动值冒称滚轮通过。保留生产stretch进行浏览器验收。
- [ ] 6. 配饰加layer/hides/incompatible_with及校验；共享明确render plan并保护旧appearance.version2/保存ID，围巾分层、帽发接合自然。`tools/check_portrait_clipping.py`枚举14配饰×12前发×10后发及none，禁止空图/泛禁组合假通过；与实际Godot代表渲染核对，纳入标准测试。
- [ ] 7. 实际截图1280×529、1280×720、1366×768、1920×1080、2560×1440；逐图检查全部页/模态/默认案件关键状态。六JPG内选代表五尺寸＋配饰；原shop_ui双尺寸另跑。新资源普通Git、二进制新增<100MB。
- [ ] 8. 独审关闭Important，更新features/PROGRESS/审阅包与结果JSON；标准完整最多3轮，原始失败保留。观察器保护所有原源，单独识别既有测试自产物，不能把生成输出误作产品源码或广泛豁免。
- [ ] 9. 验收后普通提交/推送`[R3-POLISH]`，回填记录，继续CRAFT。未解决设计在待确认明确记录，不倒退已完成任务。

## owner接口

- responsive owner：新metrics/layout配置与validator、Title安全层、咨询/CASE响应式；共享Main/CaseBoard/ShopFront改动交精确hunk由root合并。
- font/icon/style owner：palette/UIkit/themes、字体/图标配置、扫描器、卡片选择与帮助文案；共享文件仅交hunk，不覆盖responsive工作。
- portrait owner：appearance/portrait配置与render plan、alpha checker/测试，原PNG不改、旧ID不改。
- root：四图生成与资源溯源、Main集成、局部Web导出/真实浏览器事件、所有引擎验收、最终记录与Git。

当前：正式实施刚开始，准备包静态/隔离结果不等于本任务通过；没有POLISH完整轮次。
