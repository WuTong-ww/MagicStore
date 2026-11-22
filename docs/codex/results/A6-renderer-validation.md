# A6 动态渲染与关闭验收（部分完成）

2026-11-22。本记录汇总已发生的目标、GPU读回和独立审查，不预填最终full。
renderer作者报告自己的实现与实测；root接点/事件及媒体工具的独立审查范围另列。
缺素材、严格性能失败与尚未完成的验收不合并成“全部动态通过”。

## 最终实际能力

| 范围 | 已实现/已验证 | 当前生产边界 |
| --- | --- | --- |
| 共享风场 | 固定seed、展示时钟、低频FastNoiseLite、平均25秒阵风与横向延迟；室内15%、门风60%、rainy增强 | 原Wind/Spring目标100/100；真实前台可摇Li仍缺 |
| sway / pendulum | 支点距离平方权重、原生幅度上限、数学阻尼弹簧；室内总角≤3°、室外末端≤画宽1.5% | 合成fixture证明处理器能力，未把背景或缺失前台物体冒充独立动层 |
| flow | 手动time、固定原alpha、近/远8邻岸边保护、有限双相同向滚动 | 正式S07昼夜Li实际GPU第二轮通过；S03沙发/S04门保持static |
| A7货架 | 入库12原生px落下/轻弹、两邻0.5°扰动、取出不动画待销毁节点；base+selection+motion统一pose与命中 | 沿用真实提交版本去重；partial取出清旧drop，减少动态即时半幅 |
| 事件 | 事务局部collector、写盘成功后净化发布；Main global notify一次再局部响应 | 初始/new/load静默，失败/动作重放不播放；async/reentrant/legacy实际目标277/277 |
| 粒子 | 内置CPUParticles2D/程序纹理，配置预算≤60，reduced立刻销毁存活节点 | 40粒子技术fixture通过；所有production区域空，实际0粒子 |
| 偏好/音频 | 实际ReducedMotionCheck持久化保留audio；失败回滚且GameState不变；可选铃音、真实Mixer drain | Main目标31/31；正式chime_audio仍空，现有notify.ogg仅生命周期fixture |

所有展示/物理参数取现有JSON；未更改经营存档schema。图层仍由SceneVisual拥有
纹理、z、fade、native crop及cover投影，动态组件不平移整张水图/C或改写资源像素。

## 实际RED→GREEN，按证据范围分开

| 阶段 | 实际结果 | 说明 |
| --- | --- | --- |
| 缺组件 | 1检查/1预期失败 | 实施前由唯一引擎通道记录；不是parse错误代替语义RED |
| 首次边界 | 2检查/1失败 | indentation parse错误，保留失败，不计三业务缺陷已复现 |
| 三原始缺陷 | GUI35/5→35/2→35/0 | active reduced未半幅、partial取出旧pose、speed>0/distort0不滚动；另两项为首编译长帧时tween未启动的fixture等待 |
| 可选音频 | headless41/4→43/0 | nonempty missing诊断、真实stream播放/去重/销毁；中间类型注解parse失败未计GREEN |
| 真正关闭/设置 | headless45/2、28/3→49/0、31/0 | 不猜30帧；无UI/Music voice仍等chime实际释放，外持handle超时/回滚/释放重试 |
| 正式Li第一轮 | GUI508/508，但pixel false | 4个时间对比均shore_rgb_changed；alpha/透明/羽化不变，不能凭GUI检查数称像素通过 |
| 凹角/长时修复 | 同GUI目标82/5→82/0 | 一次shader修复成功，未用掉第二次尝试；大凹角、近邻小缺口、正式ROI晚周期冻结均实际RED |
| 正式Li第二轮 | GUI508/508、pixel true | 同阈值4时间pair+8无shader同LINEAR control全通过；20Main PNG+10技术RGBA留本地 |

最后两组GUI为Windows Compatibility / Intel Iris Xe，exit0，无ERROR/WARNING。
headless49明确SKIP旧4项GPU检查；不能把49或31扩称图形验收。82包含新增
实际GPU采样与正式ROI，不能与同名headless计数相加成一套全量测试。

随后full round1在shop_ui触发Godot dummy编译器的内置sampler参数ERROR并中断，
不能算完整通过。独立复现虽为687断言/0失败、进程exit0，日志仍有2条ERROR。
helper直接读取TEXTURE的中间尝试也失败，最终只把同样采样内联进fragment，
不改算法、材质门控或四冻结JSON。修后shop_ui headless687/687、SceneMotion
headless49/49和GUI82/82均exit0、0错误警告；四个正式ROI PNG及全部目标指标
SHA/数值与修前完全相同。它们不是完整预览等价证明，root另做正式复核；
旧round2 receipt保持原源码绑定，不改写为新shader。最终full2结果仍未预填。

本地日志：`.tools/art/a6/renderer-semantic-green.log`、
`renderer-audio-semantic-red.log` / `renderer-audio-final-green.log`、
`renderer-shutdown-semantic-red.log` / `renderer-shutdown-first-green.log`、
`renderer-settings-first-red.log` / `renderer-settings-first-green.log`、
`renderer-flow-regression-red.log` / `renderer-flow-correction-attempt1.log`。
这些历史失败保持原样，不重写为后续成功。

## 水域岸边与时间算法

正式runtime Li为1920×1080，uniform来自A1R crop：1672×940.5 native；当前
speed=4、distortion=3、noise_frequency=0.02、edge_fade=8。

第一轮所有alpha字节相同，1,781,056个透明像素与9,949个羽化像素RGB也零变；
但凹角x1285–1290/y706–710有4–8个opaque岸像素变化，max RGB达8。四方向远
采样会漏过凹角及近处小缺口，故不改checker，而在shader加入：

- `near = max(TEXTURE_PIXEL_SIZE, fwidth(UV))`，在非分支控制流先求导。
- 近邻8方向任一alpha<1便冻结该像素RGB；远8方向按现有edge_fade减弱位移。
- 透明/羽化直接取原色，输出始终使用原始alpha；每相越界或低alpha采样回退原色。

旧scroll在418秒整幅周期前把大块水纹推离mask。正式固定ROI
`Rect2i(1440,800,288,128)`的36,864个像素在417/417.5秒实际GPU读回全同；
不是凭少量半幅边缘有变就称整片仍流动。

新算法仅用既有参数，未新增或改动四份冻结配置：

```text
L = max(edge_fade_px, min(native_width,
        1 / max(noise_frequency, 1/native_width)))
p = fract(time * speed * motion_factor / L)
offset_A = p * L
offset_B = (p - 1) * L
w = smoothstep(0, 1, p)
RGB = mix(safe_sample(A), safe_sample(B), w)
```

当前L=50native px、正常周期12.5秒。两相沿同方向移动，端点的活动相位offset
都为0且速度相同；smoothstep端点一阶导数为0，噪声使用连续绝对时间。这里的
C1是UV路径/交叉权重的周期接缝性质；纹理量化和安全mask回退不能被数值截图
扩大为“每个复杂RGB像素对所有时间均可微”。

新正式ROI在417/417.5秒：

| period | 变化像素 | max byte | mean byte | p99 byte |
| --- | ---: | ---: | ---: | ---: |
| day | 36,136 | 31 | 1.987567 | 9 |
| night | 34,546 | 9 | 1.199662 | 5 |

12.5秒新接缝的实际8bit结果：

| period | epsilon(s) | max | mean | p99 | 变化像素 |
| --- | ---: | ---: | ---: | ---: | ---: |
| day | .001 | 1 | .016683 | 1 | 1,504 |
| day | .0005 | 1 | .010064 | 1 | 939 |
| night | .001 | 1 | .009431 | 0 | 723 |
| night | .0005 | 1 | .005624 | 0 | 449 |

减半epsilon后的mean比约0.603/0.596，受8bit量化影响，不要求像素数严格减半。
合成仿射纹理在5秒wrap的对称一阶残差0 byte；epsilon .125/.0625的mean差值
2.0/.666667、max4/2。源码端点性质与这些实际读回一起报告，不以其中任一项
单独证明完整连续性。原RED ROI/旧shader保存在
`.tools/art/a6/renderer-flow-red-evidence/`；新指标在`renderer-flow-horizon.json`。

正式第二轮使用原helper阈值：

| period | pair | alpha max | shore RGB变化 | interior变化 |
| --- | --- | ---: | ---: | ---: |
| day | 0→1s | 0 | 0 | 267,482 |
| day | 417.5→418.5s | 0 | 0 | 266,306 |
| night | 0→1s | 0 | 0 | 263,396 |
| night | 417.5→418.5s | 0 | 0 | 259,461 |

8个同LINEAR无shader原图control比较也全部passed，alpha最大差0、透明/羽化/
岸边RGB零变。该long pair是长期时刻抽样，12.5秒新接缝由上面的独立目标采样，
不嫁接为helper原本就覆盖的时间。第二轮最终日志508项；receipt保存时为507项，
最后一项是receipt可写检查，不隐瞒计数位置差异。

## 真实事件、音频与还原

collector只在事务局部，成功写盘后固定候选save/version，再state_changed和
净化事件；async await前不保存collector，重入不借新全局version。legacy排队
别名退休不发假离店。Main先去重global Wind notify，再交当前局部组件。

`shutdown()`同步停止处理/弹簧/粒子/player并清stream；`shutdown_async()`随后
等待当前及旧mixer WeakRef，超时/轮询复用ShopAudio已有audio JSON。Main在
普通音频drain前先await它，外持真实playback会失败、恢复_closing并用已有文案，
释放后可重试。没有用click替代正式铃音。

绑定保存原material/rotation，解绑/场景销毁恢复；背景/fade/z仍属SceneVisual。
货架pose不回写布局或业务。设置fixture用隔离cfg与真实隔离new/load动作，原Wind
对象保持完整后恢复处理标志；预览恢复其保存的路径/偏好/展示时钟/天气/处理标志。
全部正式资源及列明代码/配置/font SHA在预览前后核对。四冻结JSON SHA未变，
旧receipt保持旧source SHA，第二轮独立记录新shader，不伪造历史绑定。

## 录像与独立工具复审

前台源AVI实际184,139,666 bytes，600个原始MJPEG视频chunk；599次post-draw
callback加实测Writer offset1，由容器独立证明600帧/1920×1080/60fps/10秒。
指定wait动作实际保存成功并发布1个guest_entered。前台联动标记仍false，缺
树/花/铃/帘Li与铃音，不以录到静态画面声称完整美术联动。
原AVI的RIFF声明长度比实际少70 bytes，探针明确记录并按实际字节检查子chunk；
没有改写源header，也不把成功转码扩称原AVI已完成全部格式规范验证。

压缩[front-day.mp4](../../screenshots/a6/front-day.mp4)实际15,308,798 bytes，
SHA256 `791e7a44826cfb79a5ab06dcf7284987b21d1396938a913b9ff2fb352f3a7c53`。
使用现有Windows MediaTranscoder；无新依赖。独立stdlib MP4 parser从vide轨
stsz/stts得到600/600样本、600000/60000=10秒、60fps。它没有H264全解码，
没有解释edit-list呈现映射；原AVI仅另解码了5个指定JPEG帧。不能把固定步长
Movie Maker当实时帧率或把容器证据当最终播放/逐帧美术验收。

只读复审未发现当前实际输入/调用中的新阻断：capture核4冻结配置与header，
压缩发布受预算约束；MP4 parser检查box父子边界与stsz/stts长度/计数一致；
preview helper在写diff前拒绝report/diff与receipt、sample、control、preview及
protected输入碰撞，并绑定正式昼夜source SHA/crop/参数/factor1/LINEAR。
其原先的输出碰撞风险和跨尺寸旧隐藏settings dialog风险由owner修复。
这些是非本人代码的只读审查，不声称我独立重跑工具、编码或GUI。

## 技债与明确未通过

- 前台独立Li/cleanplate、正式风铃音仍缺，生产粒子区域全空；不重启旧v2层或
  摇整张C补足。后续补素材仍需新的真实来源/独立图审。
- 严格实机性能保留**63检查/1失败、exit1**。S04 baseline/enabled/reduced最大
  wall帧28.376/18.427/23.720ms；enabled S07/S04更新elapsed最大2.183/2.020ms，
  超2ms。mean/p99好不能覆盖max失败。
- 该唯一性能轮早于最终shader，含6条已修源码警告，未重测当前快照。CPU口径
  只含持续SceneMotion.step+Wind._process，排除signal callback、A7重排、GPU；
  原CSV另列stimulus wall。没有GPU独立时间、长时热稳定或全Main压力通过结论。
- 此报告不预填A6最终full，也不沿用A7的9154/9154。最终截图选择与逐帧美术
  评分、最终全套及普通Git提交由root另行记录。

正式第二轮的flow算法快照SHA256：
`680db7bbfd1b3444345efe770847eac3caf9e8a921b3dad5b08be3a0954a0c69`。
当前等价内联修复后的shader SHA256：
`10f393d19c45de4aee87822334a8fb27e38d59d9117cc7147c842cfd7b7bcd70`。
对应82-check目标：
`4b272b34099e40fb0ffa9dde94c0eecc2f40c37976ba9cc9406b7a54ae5ef53c`。
只读root接点独审见本地`root-integration-review.md`；我本人的关闭实现由另一
reviewer记录在`renderer-close-review.md`，不互相冒称作者独立审自己的代码。
