# MagicStore · 零点杂货铺

一个本地运行、自动保存的 Godot 2D 桌面开发案例。**工程入口就是本目录的 `project.godot`**，主场景 `scenes/main.tscn`。原始构想保留于 `docs/游戏介绍.md`。B 组联调版可试玩正式报价、九项术式、邀请案及前世案，使用本地对话和 A/C 样例。操作及验收见 [B 组交接](docs/divination.md)。

当前可玩的内容、演示数值和已验证范围见[功能清单](docs/features.md)。

## 环境与启动

**本机默认工作目录已迁移到 `D:\MagicStore`。** 双击根目录 `start-game.cmd` 运行游戏，或 `start-editor.cmd` 打开编辑器；两个入口都会把存档、日志、缓存和临时文件留在当前工程目录。Git 历史、下载好的引擎、导出模板和交付包均已迁移。旧 C 盘路径仅保留指向 D 盘的目录链接，供当前 Codex 聊天兼容使用，不存放另一份工程。

四人统一使用 **Godot 4.6.3 stable 标准版**，实际引擎输出 `4.6.3.stable.official.7d41c59c4`。GDScript，Compatibility/OpenGL，Windows x86_64。版本、官方下载地址和 SHA256 锁在 `scripts/dev/toolchain.json`。无需 .NET 或额外运行库。

```powershell
git clone https://github.com/WuTong-ww/MagicStore.git
cd MagicStore
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/dev/bootstrap.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/dev/run.ps1 -Editor
# 或直接运行游戏
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/dev/run.ps1
```

首次脚本联网下载官方引擎；随后游戏完全离线。仅该脚本进程使用 ExecutionPolicy Bypass，不修改系统策略。下载校验失败会停止。也可以手工从 [Godot 4.6.3 官方归档](https://godotengine.org/download/archive/4.6.3-stable/) 下载标准 Windows x86_64 引擎，解压到 `.tools/godot`，在编辑器“导入”中选择 `project.godot`，按 F6 运行主场景或 F5 运行工程。

本机引擎：`D:\MagicStore\.tools\godot\Godot_v4.6.3-stable_win64_console.exe`。编辑器设置使用 `_sc_` 便携模式，留在 `.tools/godot/editor_data`。同伴无需采用相同绝对路径。中文字体随源代码提供，不依赖系统字体。

## 原型操作参考

打开存档簿新建店铺（不会覆盖旧档），或选择已有记录继续。前台请林照晚进入咨询区；提问按钮和中文自由输入均可获得回复。输入只通过“发送”按钮提交，Enter 是编辑行为。未知话题会请求澄清；界面明确标注本地开发 Mock。

询问邀请、回信能获得两条线索。新开的塔罗服务从 78 张牌中抽取三张，分别记录牌位、正逆位和牌意。收款后可免费重看同一牌阵。用其他术式取得提示后，可在案例手记查看跨术式对照。回前台、继续咨询、关闭重开均可恢复。结束接待后可查看经历，次日回访沿用 `npc_id` 并生成新 `visit_id`。

全部成功动作自动写盘，成功保存后才更新资源和显示结果；失败会提示并保留旧状态。不要同时运行多个游戏进程操作同一存档（当前不提供跨进程锁）。

## 原型演示数值

| 项目 | 值 |
| --- | --- |
| 店长起始金币 / 精力上限 | 40 / 100 |
| 顾客初始预算 | 60，跨日保留，不自动补充 |
| 三牌塔罗 | 顾客付 20 金币，店长收 20，精力 −25，时间 +30 分钟 |
| 每次成功交谈 | 时间 +5 分钟，包括澄清；不消耗金币或精力 |
| 休息 | +60 分钟，精力 +30，上限 100；满精力不执行 |
| 营业时段 | 每日 09:00–22:00，动作不能越过打烊时间 |
| 下一天 | 到次日 09:00，精力回满；必须先结束接待 |

这些不是最终设计值，统一修改 `data/content.json`。现实打字、阅读、动画和等待 provider 不推进时钟。当前预算支持三次收费，之后仍可交谈、结束；正式预算补给和客流规则留待设计。

## 存档与恢复

正式存档仍使用 `user://saves`。默认通过根目录启动入口或 `scripts/dev/run.ps1` 启动时，本机实际位置为 `D:\MagicStore\.runtime\appdata\ZeroHourStore\saves`；日志同样位于 `.runtime`，测试继续使用 `.tools/test-*` 隔离目录。启动脚本只调整子进程环境，退出后恢复，不修改 Windows 的全局环境变量。此前试玩的两个存档和备份已保留到新默认目录。

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

手工验收：新建 → 前台 → 接待 → 一个问题按钮 → 中文输入并发送 → 确认塔罗 → 检查双方金币/精力/时间 → 返回/继续原接待 → 关闭重开/读档检查原牌 → 结束 → 查看经历 → 休息/下一天 → 再次接待 → 切换另一存档。另请用自己常用输入法检查候选词选词和回车都不误发，在 1280×720、1920×1080 检查布局。

## 离线交接包

本次实际产物放在 `build/`（均不提交 Git）：

- `MagicStore-source.zip`：完整工程源文件、字体、文档、测试与脚本。
- `MagicStore-environment-win64.zip`：固定引擎、Windows 模板与许可证；解压到源码目录，和现有目录合并后即可离线开发。不要执行 bootstrap 重新下载，直接用 `run.ps1 -Editor` / `-Test` / `-Export`。
- `MagicStore-windows.zip`：直接试玩包，解压后运行 `StartGame.cmd`，存档与缓存留在解压目录。

源码和环境可重打包：`powershell -NoProfile -ExecutionPolicy Bypass -File scripts/dev/package.ps1 -WithEnvironment`。GitHub 拉取源代码加在线 bootstrap 是日常协作方式；离线环境包供网络受限的同伴单独传递，避免把大型二进制放进 Git 历史。

## 协作与范围

仓库使用 `main` 作为默认分支。引擎、导出模板、缓存、构建产物、测试存档和密钥都被 `.gitignore` 排除。`.gd.uid` 和资源 `.import` 设置随源码保留，团队拉取后可重新导入工程。

目录与分工见 `docs/team.md`，场景树、信号、动作及 provider 示例见 `docs/contracts.md`。B 组案例在联调环境中可运行。真实 LLM、稀有家族生成、正式客流、储物柜、工坊、采购采集由各组按制作单整合。正式 AI 密钥只放代理服务端。

占位 SVG 是本工程原创可替换资源；中文字体为 [Google Fonts Noto Sans SC](https://github.com/google/fonts/tree/main/ofl/notosanssc)，许可证随附 `assets/fonts/OFL.txt`。来源及本机文件校验值见 `docs/third-party.md`。
