1. # AGENTS.md — 零点杂货铺

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
   9. 按用户2026-11-21新指令：.png/.ogg/.ttf等二进制文件使用普通Git上传，不使用Git LFS；.gitattributes须停用对应LFS过滤器。不得改写main。
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
