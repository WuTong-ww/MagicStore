# 模块协作与交接

仓库入口是根目录 `project.godot`，主场景为 `scenes/main.tscn`。统一使用 Godot 4.6.3 stable、GDScript 和 Compatibility。原始构想见[游戏介绍](游戏介绍.md)，当前七处场景、人物、问卜与经营范围见[功能清单](features.md)。

职责沿用项目分工：A 人物与排程，B 问卜与案例，C 经营、公共状态和最终整合；具体维护人由团队填写。环境与验收由各模块协作完成。

| 模块 | 主要目录 | 当前责任 |
| --- | --- | --- |
| 人物与来访 | `scripts/people/`、`data/people/`、`scenes/people/` | 身份、客流、关系、共同记忆、预约、反馈排程及行为记录 |
| 问卜与案例 | `scripts/divination/`、`data/divination.json`、`docs/divination.md` | 术式、案例、已知资料、预测与事实区分、反馈授权及专属案例投影 |
| 经营与公共状态 | `scripts/shop/`、`scripts/core/`、`scripts/save/` | 统一钱包与时钟、库存商品、候选事务、幂等、完整存档校验和迁移 |
| 界面与素材 | `scenes/`、`scripts/ui/`、`themes/`、`assets/` | 七处场景、人物面板、动态短问题、确认流程、布局及资源许可 |
| 模型传输 | `scripts/providers/`、`server/ai/` | 直连或网关、生成与独立审核、取消和旧回包隔离、授权回退；不持有存档写权限 |
| 环境与验收 | `tests/`、`scripts/dev/`、验收文档 | 工具链锁定、隔离回归、模型范围记录、图形检查、导出和包体审核 |

## 公共边界

`GameState` 是业务状态与时钟的最终权威，`SaveService` 负责完整存档验证和文件读写。人物、经营与案例模块在候选副本中运算；UI 只提交动作和读取公开视图，不直接改金币、精力、时钟或文件。模型候选必须通过审核和本地权限校验，不能直接授权资源或隐藏事实。

改变动作、信号、存档、错误码或 provider 输入输出前，先更新[公共契约](contracts.md)，再同步调用方、实现及回归。NPC、物品、线索和卡牌稳定 ID 是旧档引用，不能随文案或素材替换而随意改名。当前已支持多个固定来客与原创生成来客，扩展时须同时考虑人物、案例、来源、排程和迁移。

`project.godot`、`export_presets.cfg`、`.gitignore` 和工具链锁文件的变更需共同确认影响。使用相同具体引擎版本，不各自自动升级。素材记录来源与许可；中文字体随工程提供，`.gd.uid` 和资源 `.import` 随源码保留，`.godot/` 缓存不提交。

## 第一次拉取

```powershell
git clone https://github.com/WuTong-ww/MagicStore.git
cd MagicStore
powershell -ExecutionPolicy Bypass -File scripts/dev/bootstrap.ps1
powershell -ExecutionPolicy Bypass -File scripts/dev/run.ps1 -Test
powershell -ExecutionPolicy Bypass -File scripts/dev/run.ps1 -Editor
```

引擎、模板地址和 SHA256 位于 `scripts/dev/toolchain.json`，工具放在忽略的 `.tools/`。导出前运行 `bootstrap.ps1 -WithExportTemplates`，再执行 `run.ps1 -Export`。平时使用 `start-game.cmd` 进入主游戏；已撤除的独立演示入口仅在[历史说明](archive/people-prototype-history.md)记录。

## 每次交接

1. 从最新公共基线建立小分支，例如 `codex/people-return`、`codex/case-feedback`、`codex/shop-effects`，避免同时编辑同一公共状态或界面文件。
2. 写清模块范围和接口影响，跨模块改动由对应维护人配合，不能只改调用方或只改存档字段。
3. 运行适合改动的测试及必要的统一 `run.ps1 -Test`。界面另外检查两种目标分辨率及真实交互；headless 不代替画面、输入法或实际模型验收。
4. 提交前检查 `git diff --check`、`git status --short`，不提交个人存档、密钥、`.tools/`、`.runtime/`、`.godot/` 或 `build/`。
5. PR 说明具体触发动作、行为变化、验证和未验证范围；涉及存档时说明迁移与失败恢复，涉及 UI 时附实际画面。
6. 合并后重新拉取并验证，冲突需保留双方实际意图，不能以整文件覆盖破坏公共协议或数据保护逻辑。

测试均使用隔离目录，`SaveService.fail_next_write` 仅供确定性测试。真实玩家存档不能用于破坏性测试；备份恢复和删除必须经游戏确认流程。

## 后续内容扩充

储物、工坊、采购、采集、成长、实际客流和模型对话均已有主游戏实现，不能再列作空白待接入模块。后续按具体玩法扩展内容、素材、报告和案例，并补迁移与验收。更广泛的随机世界、正式美术、远程运维及更多硬件平台以对应实现和证据为准。

直连 API Key 仅在游戏进程内使用；网关的上游 Key 留在服务端进程。离线功能不要求在线密钥。实测保留模型、输入、保存和界面等待范围，不把某次全部在线当成永不超时或永不误判的保证。
