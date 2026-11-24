# MagicStore · 零点杂货铺

一个本地运行、自动保存的 Godot 2D 神秘学小店游戏。**工程入口是本目录的 `project.godot`**，主场景 `scenes/main.tscn`。当前已整合人物客流、问卜案例与经营系统：七处场景、采购和采集、顾客赠料、研发制作、商品效果、学习成长、账簿，以及可取消和回退的 HTTP 对话。原始构想见 `docs/游戏介绍.md`，当前操作与验收见 [功能清单](docs/features.md)。

当前内容、数值配置和已验证范围见[功能清单](docs/features.md)。

第二轮续跑使用 `codex/round2-clean`，素材使用普通 Git 文件。已否决的绘本图及中间产物仅保留本地，当前正式场景为v3；原v2保留作输入和回退。重建范围与体积检查见[上传状态](docs/codex/UPLOAD_STATUS.md)；`main` 保持不变。

此前针对林照晚的 84 次真实交谈，以及最终 14 次平均等待 3.14 秒的测量范围，见[早期对白实测](docs/live-dialogue-evaluation.md)。原创新人物与四模型切换另行验证，结果见[新来客流程](docs/people-generation.md)及[接口切换验证](docs/api-model-switch.md)，不能将林照晚的旧数据视为所有模型与人物的表现。

新增[原创新来客流程](docs/people-generation.md)：后台并发生成完整人设与专属案例，独立审核后入档并安排到店；支持熟人介绍、正式回访和跨次共同记忆。并发与客流配额留在后台配置，游戏只呈现人物和经营流程。

咨询区支持[随谈话更新的后续问题](docs/followup-questions.md)：模型和对白一起返回2–3条建议，经审核后成为可点击的问题；结合已知线索继续推进，不固定重复同一排菜单。

## 环境与启动

网页试玩采用独立的 `codex/web-playtest` 分支，通过 GitHub Pages 发布。浏览器要求、玩法入口、存档及联网限制见[网页试玩说明](docs/web-playtest.md)。首次加载需下载资源；不配置模型也能体验本地对白和普通经营。Claude 实际试玩需有能读屏、点击和输入的浏览器操作工具。

双击根目录 `start-game.cmd` 运行游戏，或 `start-editor.cmd` 打开编辑器。路径由脚本所在目录解析，可在 `E:\MagicStore` 或其他目录运行；存档、日志、缓存和临时文件均留在当前工程目录。

源码更新后请使用上述启动器；`build/windows` 的 EXE 与 ZIP 只有重新导出才会更新。普通来客无需联网，但每日客流允许为零，游戏时间只随成功动作推进；零客日可打烊进入下一天，再用「等一会儿」等候。联网原创来客还需有效接口、独立审核通过和未来到店名额，配置接口不会额外增加当日客流。

协作成员统一使用 **Godot 4.6.3 stable 标准版**，实际引擎输出 `4.6.3.stable.official.7d41c59c4`。GDScript，Compatibility/OpenGL，Windows x86_64。版本、官方下载地址和 SHA256 锁在 `scripts/dev/toolchain.json`。无需 .NET 或额外运行库。

```powershell
git clone https://github.com/WuTong-ww/MagicStore.git
cd MagicStore
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/dev/bootstrap.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/dev/run.ps1 -Editor
# 或直接运行游戏
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/dev/run.ps1
```

首次脚本联网下载官方引擎；游戏默认使用离线对话，也可在首页「设置」中填写 AI 接口 URL、模型名称及 API Key。仅该脚本进程使用 ExecutionPolicy Bypass，不修改系统策略。下载校验失败会停止。也可以手工从 [Godot 4.6.3 官方归档](https://godotengine.org/download/archive/4.6.3-stable/) 下载标准 Windows x86_64 引擎，解压到 `.tools/godot`，在编辑器“导入”中选择 `project.godot`，按 F6 运行主场景或 F5 运行工程。

引擎位置：`<工程目录>/.tools/godot/Godot_v4.6.3-stable_win64_console.exe`。编辑器设置使用 `_sc_` 便携模式，留在 `.tools/godot/editor_data`。同伴无需采用相同绝对路径。中文字体随源代码提供，不依赖系统字体。

## 本次美术资源接入（2026-11-20）

七个主场景、林照晚三态肖像、术式示例图、证物/收据/关系/报告 UI 资源已加入 `assets/`，并接入对应 Godot 页面。具体资源键、F01–F24 对应入口、Windows 启动步骤与未完成边界见 [美术资源与可操作界面接入说明](docs/ART_ASSET_GUIDE.md)。新资源首次打开工程时由 Godot 自动导入。

## 游戏操作

打开存档簿新建店铺（不会覆盖旧档），或选择已有记录继续。在前台接待实际候客队列中的来客，进入咨询区后可点击问题或输入中文。回车发送，Shift+回车换行，也可点击“发送”按钮。首页设置可配置在线接口；未配置或核验失败时使用获准的本地话题，界面显示实际对话模式。

询问邀请、回信能获得两条线索。塔罗报价时选择本次问题，从 78 张牌中抽取三张。翻牌后会看到牌面、结合问题和已知线索的推想，以及能继续核对的细节。可把自己的解释记为待验证假设，之后免费重看原牌阵和当时的解读。用其他术式问同一个问题后，可在案例手记查看跨术式对照。回前台、继续咨询、关闭重开均可恢复。结束接待后可查看经历，次日回访沿用 `npc_id` 并生成新 `visit_id`。

全部成功动作自动写盘，成功保存后才更新资源和显示结果；失败会提示并保留旧状态。不要同时运行多个游戏进程操作同一存档（当前不提供跨进程锁）。

## 当前初始配置

| 项目 | 值 |
| --- | --- |
| 店长起始金币 / 精力上限 | 40 / 100 |
| 林照晚基础预算 | 60，跨日保留，不自动补充 |
| 三牌塔罗 | 顾客付 20 金币，店长收 20，精力 −25，时间 +30 分钟 |
| 每次成功交谈 | 时间 +5 分钟，包括澄清；不消耗金币或精力 |
| 休息 | +60 分钟，精力 +30，上限 100；满精力不执行 |
| 营业时段 | 每日 09:00–22:00，动作不能越过打烊时间 |
| 下一天 | 到次日 09:00，精力回满；必须先结束接待 |

这些基础数值配置在 `data/content.json`，并非最终平衡值；人物客流、经营商品和成长另有各自的数据配置，见[功能清单](docs/features.md)。现实打字、阅读、动画和网络等待不推进时钟。上表的基础顾客预算可支付三次该项服务，余额不足时仍可交谈或结束接待；实际来访由人物排程和统一客流规则决定。

## 存档与恢复

正式存档使用 `user://saves`。默认通过根目录启动入口或 `scripts/dev/run.ps1` 启动时，实际位置为 `<工程目录>/.runtime/appdata/ZeroHourStore/saves`；日志同样位于 `.runtime`，测试使用 `.tools/test-*` 隔离目录。启动脚本只调整子进程环境，退出后恢复，不修改 Windows 的全局环境变量。

独立试玩包请使用随包的 `StartGame.cmd`，数据保存在解压目录内。绕过启动入口而直接运行引擎或 `ZeroHourStore.exe`，Godot 仍会采用系统 `%APPDATA%`，可能写入 C 盘，因此本机默认使用启动脚本。

每个存档独立 JSON，含 `schema_version`、各类稳定 ID、状态版本、对话、牌面、已处理动作。保存封装使用 payload 字符串及 SHA256，先写临时文件并校验，保留 `.bak` 和保护备份 `.bak.guard` 后替换。SHA256 用于检出意外损坏，不是防作弊或加密。

损坏文件不会静默清空，也不会自动新建覆盖。存档簿中选择“从备份恢复”，阅读确认提示；恢复会回退恢复点后的动作，原损坏文件以 `.corrupt.*` 保留。找不到备份时可新建另一个存档继续，保留原文件待排查。Windows 的文件替换和断电恢复边界详见 `docs/contracts.md`；没有声称数据库级事务或断电零丢失。

## 检查与导出

```powershell
# 导入、逻辑、provider、两个独立进程的重启验收
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/dev/run.ps1 -Test
# 首次补齐匹配版本的导出模板（完整官方模板下载体积较大，仅提取 Windows）
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/dev/bootstrap.ps1 -WithExportTemplates
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/dev/run.ps1 -Export
```

测试进程重定向 APPDATA/LOCALAPPDATA 到 `.tools/test-*`，测试本身再使用 `test-runs`、`test-restart` 独立目录，绝不覆盖正式 `saves`。失败返回非零退出码。以下为引擎命令参考；默认请使用上面的脚本，使运行数据也留在工程目录：

```powershell
& '.\.tools\godot\Godot_v4.6.3-stable_win64_console.exe' --headless --path . --import
& '.\.tools\godot\Godot_v4.6.3-stable_win64_console.exe' --headless --path . --script res://tests/smoke.gd
& '.\.tools\godot\Godot_v4.6.3-stable_win64_console.exe' --headless --path . --export-release 'Windows Desktop' build/windows/ZeroHourStore.exe
```

导出使用 `export_presets.cfg` 的 Windows Desktop，模板位于 `.tools/templates`；产物 `build/windows/ZeroHourStore.exe` 内嵌 PCK，无需 Godot 编辑器。发布时一并附带字体许可证和第三方说明。执行包未签名；不修改系统安全设置。具体已运行检查、画面检查及未验证项见 `docs/verification.md`。

手工验收：新建 → 前台 → 接待 → 一个问题按钮 → 中文输入并回车发送 → Shift+回车换行 → 确认塔罗 → 检查双方金币/精力/时间 → 返回/继续原接待 → 关闭重开/读档检查原牌 → 结束 → 查看经历 → 休息/下一天 → 再次接待 → 切换另一存档。另请用自己常用输入法检查候选词确认不会误发，在 1280×720、1920×1080 检查布局。

## 离线交接包

构建产物放在 `build/`（均不提交 Git）；具体文件是否存在取决于已运行的打包命令：

- `MagicStore-source.zip`：完整工程源文件、字体、文档、测试与脚本。
- `MagicStore-environment-win64.zip`：固定引擎、Windows 模板与许可证；解压到源码目录，和现有目录合并后即可离线开发。不要执行 bootstrap 重新下载，直接用 `run.ps1 -Editor` / `-Test` / `-Export`。
- `MagicStore-windows.zip`：直接试玩包，解压后运行 `StartGame.cmd`，存档与缓存留在解压目录。

源码和环境可重打包：`powershell -NoProfile -ExecutionPolicy Bypass -File scripts/dev/package.ps1 -WithEnvironment`。GitHub 拉取源代码加在线 bootstrap 是日常协作方式；离线环境包供网络受限的同伴单独传递，避免把大型二进制放进 Git 历史。

主游戏统一使用 `start-game.cmd` / `project.godot`。早期独立人物演示入口已撤除，开发历史见[原型历史说明](docs/archive/people-prototype-history.md)。历史测试报告和本地证据保留，不作为当前入口。

## 协作与范围

仓库使用 `main` 作为默认分支。引擎、导出模板、缓存、构建产物、测试存档和密钥都被 `.gitignore` 排除。`.gd.uid` 和资源 `.import` 设置随源码保留，团队拉取后可重新导入工程。

目录与分工见 `docs/team.md`，场景树、信号、动作及 provider 示例见 `docs/contracts.md`。A/B/C 已通过公共状态、时钟和存档整合。本地规则来客继续使用既有案例；后台模型创作的来客拥有独立人设与专属案例。正式人物美术仍可由内容组扩充。HTTP 同时支持直接 Chat Completions 和 A 的网关：生成器结合人物、来访和共同记忆写对白，单独核验通过后保留模型原文；未通过时回退。客户端直接连接 AI 时，API Key 仅在运行内存中使用；选择 A 的网关模式时，上游密钥仍只放代理服务端。

占位 SVG 是本工程原创可替换资源；中文字体为 [Google Fonts Noto Sans SC](https://github.com/google/fonts/tree/main/ofl/notosanssc)，许可证随附 `assets/fonts/OFL.txt`。来源及本机文件校验值见 `docs/third-party.md`。
