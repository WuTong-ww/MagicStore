# A3R 顶栏精力与字号收尾

本子项完成。只改表现层及对应配置/回归；未修改事务、存档、GameState、退出音频回收或其他代理负责的界面文件。

## 文件与行为

- `scripts/ui/main.gd`：新增 `energy_label`（真实 Label，节点 `EnergyText`）和纵向精力组。按已提交快照及 `content.rules.max_energy` 显示 `energy_format`；精力条及低精力颜色逻辑保留，空存档时数字/条/组一起隐藏。`main.resources` 继续为原 Label。
- 状态 Label 使用可用横向空间与完整换行；删除小窗降至14px的分支。金额、口碑、日期、候客、精力、存档/设置操作统一使用 JSON `status_size=16`。品牌标题保留20px。52px顶栏高度不变。
- `data/ui/shell.json`：新增 `energy_bar_height=12`、`energy_gap=2`；兼容字段 `compact_status_size` 提至16。
- `scripts/ui/shell_config.gd`：字号至少16且为有限整数；布局像素字段拒绝非整数，新精力布局字段同样严格校验。
- `tests/integration/round2_shell_edges.gd`：保留原32项边界与真实点击；增加四尺寸顶栏/字高/按钮/精力检查。真实reading保存失败后数字与条均不提前更新；成功后精力75/100，再真实rest变100/100，证明不是固定示例值。

## 验证

引擎 Godot 4.6.3 stable、Compatibility；隔离 `APPDATA=.tools/A3R-tail-header/appdata`、`LOCALAPPDATA=.tools/A3R-tail-header/localappdata`，未访问真实用户存档。

| 项目 | 结果 | 日志 |
|---|---|---|
| 最小RED（原实现） | 68检查/15失败：无数字、14px分支、操作字号不一、配置过宽 | `.tools/clean-rebuild/A3R-tail-header-red.log` |
| edges headless GREEN | 87/87，exit0 | `.tools/clean-rebuild/A3R-tail-header-green.log` |
| edges真实图形 | 91/91，exit0；四尺寸4张PNG，Intel Iris Xe/OpenGL Compatibility | `.tools/clean-rebuild/A3R-tail-header-graphics.log` |
| 受影响shop_ui | 695/695，exit0，headless无截图 | `.tools/clean-rebuild/A3R-tail-header-shop-ui.log` |
| 音频/字体配置专项 | 29/29，exit0 | `.tools/clean-rebuild/A3R-tail-header-audio.log` |

未运行完整 `run.ps1 -Test`，留由root合并本轮各子项后统一执行。未提交、推送或生成美术。

## 逐图自检

四张原始PNG均已实际打开；不是仅根据尺寸断言宣称视觉通过。截图均为真实100/100状态，另75/100及保存失败路径由真实动作回归覆盖。

| 原图 | 全屏 | 按钮文字 | 长文古纸 | 无烘焙字 | 前景融合 | 本项顶栏 |
|---|---|---|---|---|---|---|
| `.tools/A3R-tail-header/captures/header-800x600.png` | 通过：无黑边/场景卡框 | 通过：顶栏与本帧可见按钮字完整 | 通过：来客说明在古纸 | 通过：金额/候客/精力/按钮字由控件绘制 | 不通过：沿用既有v2灯帘与旧资源，统一画风仍待v3 | 通过：52px高，16px状态/操作字，数字和条完整，无裁切 |
| `.tools/A3R-tail-header/captures/header-1280x720.png` | 通过：cover铺满 | 通过：存档/设置及可见经营按钮完整 | 通过：纸抽屉承载长文 | 通过：未见图中烘焙状态字 | 不通过：旧独立灯帘仍有贴片感，未在本项换图 | 通过：动态100/100完整，字号一致 |
| `.tools/A3R-tail-header/captures/header-1920x1080.png` | 通过：cover铺满 | 通过：所有可见按钮字完整 | 通过：长文在古纸 | 通过：状态字为控件 | 不通过：既有v2前景风格依赖保留 | 通过：同16px与52px，未随大窗改字号 |
| `.tools/A3R-tail-header/captures/header-2560x1080.png` | 通过：超宽无黑边 | 通过：顶栏和抽屉可见按钮完整 | 通过：纸抽屉长文 | 通过：未见烘焙状态字 | 不通过：既有v2前景统一项未重新完成 | 通过：超宽数字/条/操作均完整 |

PNG仅在本地`.tools`；root可在整轮图形验收后选择正式JPG，不将这4张全部追加到Git截图目录。本项通过不代表A1R/v3美术已通过。

## 音乐只读核验

`data/ui/audio.json` 仍可由实际音频配置专项加载；day/night/consultation均 `path=""`、`status="missing"`。三个expected文件 `assets/audio/music/day.ogg`、`night.ogg`、`consultation.ogg` 均不存在，缺文件回退运行正常。Music总线、按场景/时钟选择与交叉淡入接口保留。

手册指定 Cozy Tunes + Cozy FX / Pizza Doggy 仍需人工取得、核验完整包内授权，并登记曲名/来源/SHA后补文件路径。`docs/third-party.md` 的429是既有下载记录，本次未请求下载，也不声称当前HTTP状态；未把音乐标作已取得、CC0或可用于模型训练。

## 待确认与边界

- 本子项无新增待确认设计；未触碰其它代理的热区纸牌、手记遮罩或咨询布局。
- 整体A3R仍有音乐与v3资源缺项；上表前景融合未通过项保留为既有美术依赖。
