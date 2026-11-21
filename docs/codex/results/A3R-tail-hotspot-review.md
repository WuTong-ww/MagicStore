# A3R 收尾：热区半透明古纸小牌

状态：已完成本项并冻结，等待 root 统一 full / graphics。未提交、未推送、未生图。

## 文件

- `scripts/shop/scene_visual.gd`：保留 `Hotspot_*` Button / `HotspotLabel_*` Label 接口、原点击 rect 与 cover 投影。Label 自带 StyleBoxFlat，宽度为完整文字加 padding；抽屉遮挡仍按含 padding 的整牌矩形判断。
- `data/ui/hotspots.json`：20px 墨褐字、半透明古纸底（0.88）、hover/focus 深纸色（0.96）、1px 灯金边、6px 圆角、横12/纵6 padding、4px 视口安全距；全部有实际加载校验。移除浅色文字描边，只让背景半透明。
- `tests/integration/scene_visuals.gd`：新增 JSON 负例、四尺寸整牌/完整文字、实际鼠标 hover/exit、键盘 focus、点击 rect 不漂移、纸边被遮时整牌隐藏/恢复、状态快照不变；保留既有真实热区跳转与场景/柜子回归。

## 测试数据

Godot 4.6.3 stable / Compatibility。APPDATA、LOCALAPPDATA、TEMP/TMP 都仅对测试进程指向 `.tools/hotspot-*` 隔离目录；不使用玩家档案。

- RED：旧实现 **335 检查 / 27 失败**，退出1；明确缺纸底与 hover/focus 纸牌样式。最终 RED 日志无 SCRIPT ERROR。
- 最终 headless：**438/438 通过**，退出0，0失败。
- 最终图形：**455/455 通过**，退出0，**15 张真实截图**；Windows / OpenGL Compatibility / Intel Iris Xe。四张本项纸牌截图，其余11张由原专项保留的场景/柜子流程产生。
- 配置负例：非法色、NaN alpha、负 padding、非整数边宽、空 tooltip 格式均拒绝。
- 独立只读审阅：theme_audio 未发现可证 P1/P2；root 已打开800与1920截图并确认清晰无截字。

日志：
- `.tools/clean-rebuild/A3R-hotspots-red.log`
- `.tools/clean-rebuild/A3R-hotspots-green.log`
- `.tools/clean-rebuild/A3R-hotspots-graphics.log`

## 逐图自查

这四张是使用正式 v2 前台的独立热区组件图形 fixture，不是整套 A3R 业务页面验收。root 后续统一截图覆盖真实顶栏、抽屉、咨询与手记。

| 实际截图 | 铺满 | 文字完整 | 控件动态文字 | 本项前景配色 | 热区纸牌专项 |
| --- | --- | --- | --- | --- | --- |
| `.tools/clean-rebuild/hotspot-captures/front-800x600.png` | 通过 | 六牌完整、无截字 | 通过 | 古纸/墨褐/灯金统一 | 圆角、全牌在视口内 |
| `.tools/clean-rebuild/hotspot-captures/front-1280x720.png` | 通过 | 通过 | 通过 | 通过 | 通过 |
| `.tools/clean-rebuild/hotspot-captures/front-1920x1080.png` | 通过 | 通过 | 通过 | 通过 | 通过 |
| `.tools/clean-rebuild/hotspot-captures/front-2560x1080.png` | 通过 | 通过 | 通过 | 通过 | cover裁切后整牌仍完整 |

最终四张均实际打开查看。捕获前仅把测试鼠标移至中性位置，避免上一窗口尺寸留下的原生 tooltip 出现在截图；生产 tooltip 行为保留。

## 交接

不需要待确认设计项。本项无已知未完成；root 负责最终全套、全页面图形、features/计划与提交。没有修改 `main.gd`、`round2_shell.gd`、`round2_shell_edges.gd` 或 `visuals.json`。
