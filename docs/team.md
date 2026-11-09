# 四人协作与交接

仓库入口是根目录的 `project.godot`；使用锁定的 **Godot 4.6.3 stable**、GDScript 和 Compatibility。完整背景保存在 `docs/游戏介绍.md`，本轮可运行范围以前台、咨询区和本地开发案例为准。A/B/C/D 是四个维护角色，团队可以自行填入姓名。

| 维护人 | 主要目录 | 当前职责 | 下一批可独立完成的任务 |
| --- | --- | --- | --- |
| A：规则与存档 | `scripts/core/`、`scripts/save/`、`docs/contracts.md` | GameState 权威状态、统一时钟、幂等结算、数据校验、备份恢复 | 为新增业务动作定义前置条件与结果；补存档迁移方案；检查同一动作重试及旧档兼容 |
| B：界面与美术 | `scenes/`、`scripts/ui/`、`themes/`、`assets/` | 主界面、两处场景、中文输入、费用确认、状态展示、布局 | 在保留占位资源路径和接口的情况下替换场景插图；完善交互反馈；复核 1280×720 与 1920×1080 的长文本滚动 |
| C：人物与对话 | `data/`、`scripts/providers/` | 原创人物、案例、话题、线索、示例牌、本地 mock | 扩写林照晚的提问与澄清文案；新增配置话题并声明合法线索；准备第二个案例设计稿，先与 A 确认模型扩展 |
| D：测试与环境 | `tests/`、`scripts/dev/`、README、发布说明 | 引擎锁定、环境恢复、回归验收、Windows 导出、包体检查 | 扩充异常存档与失败写入测试；整理人工验收记录；在另一台 Windows 电脑验证从全新克隆到导出的步骤 |

## 公共文件怎样修改

`project.godot`、`export_presets.cfg`、`.gitignore`、引擎锁文件由 D 维护。新增 Autoload、改主场景或更换引擎版本，先由 A/B/D 一起确定影响，D 再合入；四个人最终必须使用同一具体版本，避免自动升级工程。

`docs/contracts.md` 由 A 维护。改变动作字段、信号、存档结构、错误码、provider 输入输出之前，先更新契约，再分别修改调用方和实现。UI 只提交动作、读取快照和监听信号；不要从 UI 直接改金币、精力、时钟或存档文件。

`data/content.json` 由 C 维护；A 负责对应加载器和校验规则。NPC、线索和卡牌 ID 是旧存档引用，不要随文案改名而修改 ID。新增人物不能只向 JSON 中追加一条：当前框架刻意只验证一个固定 NPC，须由 A 扩展模型、校验与回归测试后接入。

所有素材均需记录来源与许可。替换字体时保留中文覆盖能力；不要依赖某位成员电脑上的系统字体。新增 `.gd.uid` 和资源 `.import` 引用信息应随源文件提交，`.godot/` 是可重建缓存，不能提交。

## 第一次拉取

项目使用 GitHub 仓库 `https://github.com/WuTong-ww/MagicStore.git`。同伴可按以下步骤克隆源码和配置开发环境。

```powershell
git clone https://github.com/WuTong-ww/MagicStore.git
cd MagicStore
powershell -ExecutionPolicy Bypass -File scripts/dev/bootstrap.ps1
powershell -ExecutionPolicy Bypass -File scripts/dev/run.ps1 -Test
powershell -ExecutionPolicy Bypass -File scripts/dev/run.ps1 -Editor
```

引擎与模板下载地址、版本和 SHA256 保存在 `scripts/dev/toolchain.json`；安装脚本将工具放进忽略的 `.tools/`，无需把大体积引擎上传到 Git。需要导出的人运行 `bootstrap.ps1 -WithExportTemplates`，然后执行 `run.ps1 -Export`。具体下载、运行与存档路径见根目录 README。

测试使用独立目录；不要用真实玩家存档调试失败写入。`SaveService.fail_next_write` 只供测试，不能连接到正常界面。备份恢复是用户明确选择的回退操作，恢复点之后的动作可能丢失，验收时要检查提示。

## 每次交接

1. 开工前 `git pull --ff-only`；从最新公共基线建立小分支，例如 `codex/a-save-migration`、`codex/b-consultation-art`、`codex/c-new-topic`、`codex/d-export-check`。
2. 尽量只修改自己维护的文件。需要改其他模块时，在任务说明中列出接口变化，由对应负责人配合；不要四个人同时修改主场景或同一配置文件。
3. 修改后运行 `run.ps1 -Test`。涉及界面或中文输入时，再运行游戏，记录实际窗口尺寸、输入法、点击流程和结果；headless 通过不能记为画面验收通过。
4. 提交前检查 `git diff --check` 和 `git status --short`，确认没有存档、个人路径、密钥、`.tools/`、`.godot/` 或 `build/`。只提交本任务所需源码、配置、资源、许可和文档。
5. 推送自己的分支并创建 PR。请另一位成员复核；描述触发场景、实际行为变化、检查命令及未验证项。涉及存档的 PR 必须说明旧档兼容性，涉及场景的 PR 附实际截图。
6. 合并后其他成员重新拉取、运行测试，再开始下一项任务。冲突保留两边的实际意图，尤其不要用自动“全部采用一侧”覆盖共享协议或已有用户数据保护逻辑。

小 PR 的验收记录可使用：

```text
变更：用户执行什么动作时，新增或修复了什么行为。
范围：修改目录 / 涉及的公共字段或信号。
验证：命令、引擎版本、通过结果；实际看过的界面和输入场景。
兼容：旧存档是否可读，是否需要迁移；资源 ID 是否保持。
未验证：明确剩余事项和接手人。
```

## 后续范围

储物柜、工坊、采购、采集可以由 B 先做界面草图，C 准备最小内容表，A 为一个具体玩法增加规则，D 补对应验收；不要预建大量空 Manager。完整技能树、人物关系、随机或稀有家族、前世、物品支付、正式客流与预测反馈另开迭代，当前固定次日回访不代表正式客流规则。

未来真实 AI 由 C 实现保持结构化契约的 HTTP provider，A 保留资源与存档最终裁决，B 沿用异步动作入口，D 测超时、错误、重复响应与离线回退。正式密钥只放代理服务端；当前工程不需要在线服务或密钥。
