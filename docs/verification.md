# 本次验收记录

日期：2026-11-06（Asia/Shanghai）。Windows 本机，Godot `4.6.3.stable.official.7d41c59c4` 标准版；实际图形输出 `OpenGL API 3.3.0 - Build 31.0.101.4502 - Compatibility - Intel Iris Xe Graphics`。

工程现已迁至 `D:\MagicStore`。迁移后已重新运行全部测试、导出并验证两个旧存档；默认启动脚本将数据留在 D 盘。迁移清单与兼容路径说明见 `migration.md`。

## 已运行且通过

| 检查 | 结果与边界 |
| --- | --- |
| `scripts/dev/bootstrap.ps1 -WithExportTemplates` | 下载官方引擎与模板、核验锁定 SHA256、提取 Windows 模板，版本匹配 |
| `scripts/dev/run.ps1 -Test` | 完整脚本退出码 0，最终非沙盒运行无引擎 ERROR |
| `--headless --path . --import` | 完整工程导入、脚本解析、资源引用通过 |
| `tests/smoke.gd` | 57 项通过：新建、多档隔离、接待/重入、自由输入/线索去重/澄清、费用原子候选提交、重复动作/新ID重试、资源不足、休息、下一天、读取、损坏/缺失/备份恢复 |
| `tests/provider_contract.gd` | 48 项通过：无效字段/未授权线索拒绝、候选意图本地校验、上下文边界、异步 BUSY、等待不耗时、过期版本/切档回复拒绝 |
| `tests/ui_capture.gd` headless | 63 项通过：界面动作分发、前台/咨询来回、原牌面、历史、中文字符串和换行不自动提交、按钮/输入框边界 |
| 同一 UI 脚本图形模式 | 68 项通过，实际渲染五张截图；已经查看 1280×720 前台/咨询、1920×1080 咨询画面，中文及布局正常 |
| `tests/restart.gd -- write` / `-- read` | 两个独立 OS 进程：已付款未结束接待的资源、原牌、对话及动作记录一致；重试不收费 |
| `scripts/dev/run.ps1 -Export` | 成功生成 `build/windows/ZeroHourStore.exe`，内嵌 PCK；无须编辑器 |
| 独立 Windows 可执行文件 | 本机实际启动且看到中文存档选择；通过窗口操作新建，随后观察到咨询、问题回复、线索、已付费星星牌与金币60/精力75/顾客40的界面 |
| 离线交接包复用 | `MagicStore-source.zip` 与 `MagicStore-environment-win64.zip` 解压到干净 `.tools/reuse-check`，直接运行其中的 `run.ps1 -Test`，全部检查通过；无需再次下载 |

窗口自动化期间检测到用户输入后重新读取窗口状态；独立包后续接待与付款由实时窗口结果确认，没有把自动化脚本未执行的点击计作自身操作。完整接待/结束/重启规则的自动验收在源工程的真实 Godot 进程中执行。

## 发现并修复

- 固定标签自动换行导致头尾占满高度：固定标签关闭换行，压缩间距，重新检验两种分辨率。
- 可变中文字体默认字重过细：共享 Theme 使用 FontVariation，设置实际支持的 OpenType `wght` 标记为 400。
- 损坏 JSON 使用静态解析产生引擎错误日志：改为 `JSON.new().parse()` 并返回可读错误，恢复路径不再抛引擎错误。
- 安装脚本重复展开会与运行中的引擎冲突：已存在正确版本时跳过解压，仍验证版本。

## 未验证及已知限制

- 未完整手工验证微软拼音/搜狗等输入法的候选窗口、选词上屏；已验证中文显示、显式发送和换行不提交。请按 README 在常用输入法下补验。
- 未在第二台电脑、其他 GPU/DPI 或干净 Windows 虚拟机上运行。源包/环境包可复用不等于所有硬件均已验收。
- 未模拟机器断电、硬盘满或 OS 在每一步替换时终止。测试包含提交前写入失败注入、结构损坏、缺失与备份恢复；Windows 文件替换不是数据库事务，恢复可能回退动作。
- 未提供跨进程同时写同一存档的互斥锁；单实例使用。
- 执行包未签名，未进行代码签名及商店分发验证。

早期受限沙盒读取 Windows 系统证书库产生环境错误；最终检查在授权环境重跑通过，游戏不使用网络。图形截图检查与 headless 逻辑结果分开记录，不以脚本通过冒充人工画面验收。

## 复现命令

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/dev/run.ps1 -Test
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/dev/run.ps1 -Export
# 图形检查脚本只用 .tools 下独立存档，截图写 .tools/ui-captures
& '.\.tools\godot\Godot_v4.6.3-stable_win64_console.exe' --path . --script res://tests/ui_capture.gd
```

本次涉及的源文件以 README、docs/contracts.md、docs/team.md 目录表为准；`.tools`、`build`、个人存档和引擎缓存全部排除于 Git。
