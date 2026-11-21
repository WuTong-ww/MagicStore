# A3R 收尾：手记窗口与咨询构图

状态：源码冻结。仅处理分配的第 3、4 项与第二轮实际图形发现的烘字装饰；未运行全套、未提交或推送。

## 文件与行为

- `scripts/divination/workbench.gd`：案例手记改为无原生边框的纸面窗口；纸面右上 `✕`、底部返回和原生关闭请求均隐藏窗口及遮罩。遮罩是 Main 下的全窗口夜青半透明控件，包含顶栏，退出时清理。业务标题属性与所有案例、反馈、历史选择、支付接口保留。
- `data/ui/workbench.json`：窗口尺寸、留白、字号、关闭文案及遮罩颜色/z 全部配置化，提供有限整数、范围、简体文案与半透明颜色校验。
- `scripts/ui/consultation.gd`、`data/ui/consultation.json`：对话框最大宽 1100 并居中；四种窗口保持输入、建议和脸部可见。普通、紧凑和窄窗座位向中央偏右调整。
- `data/shop/visuals.json`：仅 S03 正常座位 x 与咨询回退座位同步，未改场景资源或版本。
- `tests/integration/round2_consultation.gd`：保留原交互/脸部回归，增加四尺寸宽度上限、居中、来客偏右及非法宽度元数据检查。
- `tests/integration/event_notebook_ui.gd`：保留 G3 实际预测/未披露/反馈/只读原案断言，添加四尺寸遮罩、纸内关闭、状态不变、真实指针关闭回归。PNG 输出仅 `.tools/round2/G3/`。

## 第一轮 RED → GREEN

| 专项 | RED | GREEN | 日志 |
|---|---:|---:|---|
| 咨询四尺寸 | 48 项，11 失败 | 48/48 | `A3R-tail-consultation-red.log`、`A3R-tail-consultation-first.log` |
| 手记 headless | 65 项，3 失败 | 111/111 | `A3R-tail-notebook-red.log`、`A3R-tail-notebook-first.log` |

日志均在 `.tools/clean-rebuild/`。

## 第二轮实际图形问题与修正

1. 根代理首轮 Windows 截图测试为 135 项、4 个关闭失败。仅补子窗口 mouse motion 后仍 140 项、4 失败，保留了原断言，未用信号替代真实图形输入。
2. 临时诊断 `.tools/clean-rebuild/diagnose_notebook.gd` 在同一个真实按钮证明：直接向嵌入 Window 注入 motion 时 `gui_get_hovered_control()==null`，按钮虽收到 press/release，但没有触发点击。改从父 root 视口注入、加上 Window 位置后，hover 精确命中 `NotebookClose`，同一按钮关闭成功。日志 `A3R-tail-notebook-input-diagnosis.log`。生产关闭回调无误，最终修复仅为测试夹具的真实嵌入路由。
3. 逐张打开原资产确认 `evidence_cards.png`、`receipt_widgets.png` 含英文标题，`four_pillars_frame.png`、`ziwei_palace_frame.png` 是含烘焙中文的空白示意图。删除 `_casebook`、`_shop` 的装饰横幅及 past/bazi/ziwei 对这些示意图的引用。未删除资产，保留动态事实、陈述、线索、假设、实际图牌和术式结果控件。
4. tarot/lenormand/xiaoliu/astrology/bagua 与前世场景均逐张查看，无标题烘字，保留原引用。新增装饰引用回归先得到 116 项、5 失败，再为 116/116：`A3R-tail-notebook-banners-red.log`、`A3R-tail-notebook-second.log`。

## 最终真实图形验证

- Godot 4.6.3 stable，Windows Intel OpenGL / Compatibility，路径 `D:/MagicStore`，隔离 APPDATA/LOCALAPPDATA/TEMP 为 `.tools/test-a3r-tail/`。
- 最终命令：`.tools/godot/Godot_v4.6.3-stable_win64_console.exe --path D:/MagicStore --rendering-method gl_compatibility --script res://tests/integration/event_notebook_ui.gd`。
- session 12389，exit 0，**140/140，12 张 PNG**，日志 `.tools/clean-rebuild/A3R-tail-graphics-notebook-third.log`。四尺寸 `✕` 实际点击全部关闭手记与遮罩，关闭前后 GameState 快照相同，原生关闭路径同样通过；无错误/警告。
- `.tools/round2/G3/` 包含原 G3 pending/verified × 1280×720/1920×1080 共 4 张，以及 frame-open/frame-closed × 800×600/1280×720/1920×1080/2560×1080 共 8 张。四组开/关 SHA 均不同。
- 本代理已额外打开最终 `frame-open-800x600.png`、`frame-closed-800x600.png`、`verified-1920x1080.png`：关闭符号在纸内右上，无重复原生标题；遮罩实际含顶栏，关闭恢复原场景；手记没有原英文横幅，预测/实际说法/验证状态和各类记录分别显示。全部图片最终逐图审阅由根代理统一进行。

## 待确认与局限

- 本次无需要拍板的问题；不改经营动作、存档结构或对话模型数据。
- 旧 v2 来客立绘与场景仍有画风差异，此次只改布局，留给 A1R/A4 资源。
- 音乐、纸纹角花和被移除装饰的新 v3 无字资源按既定资源任务补充；缺失时当前 UI 可正常运行。
- 全套测试、shop_ui 与 shell 最终截图由根代理统一跑；本专项结果不代替全套验收。
