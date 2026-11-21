# A1R regen3 独立复审问题修正

## 改动

仅改 `tools/art_pipeline.py` 与 `tests/art/test_compact_regen.py`。

1. 所有场景 generation task 会将资产 JSON 中的 `regeneration_constraints` 原文追加到 prompt 末尾；该字段若提供必须为非空字符串。S04 的空架、open/closed 内容由 root 写入四张 C 资产行，代码不硬编码场景文案。
2. 正式 group=scenes、文件名 C.png 必须提供有效 scene_id 与 day/night/closed period；S04 还必须显式 state=open/closed。完整身份删空也在 compact manifest 校验阶段报 ValueError，不会落到可立即生成的白日 EDIT。旧 v2 文件名 fallback 保留。
3. 显式 group=slices 的 operation 仅允许 extract_layer／inpaint_cleanplate；拼错、generate 或缺失均报 ValueError，禁止降级到独立 imagegen 透明物件。已有两种操作仍走 needs_mask_review 离线链。

没有修改 wrapper、中央 manifest/visuals、引擎代码或图片；没有开Godot、执行Git、full、commit或push。

## RED → GREEN

- 生产代码未动时先新增5个语义测试。RED：compact 共30 tests，12个断言失败（含场景、状态、缺字段和错误操作subtests），0 error；复现全部三项缺陷及constraints类型校验缺失。
- 最小生产修正后重新运行：

```text
python -m unittest discover -s tests/art -p test_compact_regen.py -v
30 passed / 0 failed / 0 error / 0 skipped

python -m unittest discover -s tests/art -p test_art_pipeline.py -v
35 passed / 0 failed / 0 error / 0 skipped
```

首轮三项修正结果为 **旧60项 + 新5项 = 65/65 全绿**。随后独立实际输入复验发现下述循环变量遮蔽，已追加真实形状回归并修正；以最终66/66结果为准。

日志：`.tools/clean-rebuild/A1R-v3-regen3-RED.log`、`A1R-v3-regen3-GREEN.log`。

## 最终真实inputs反例修正与复核

独立复审使用真实S02/night资产发现：验证函数在读取asset path后，用 `for path in asset['inputs']` 覆盖了同名变量，造成后续C.png身份检查实际检查最后一张参考图。上一轮fixture不含inputs，未覆盖该实际形状。

先新增night C带 `inputs=[style reference]`、删除scene_id/period/state的negative回归，RED：31 tests中仅该新例失败，0 error。然后生产代码仅将这处循环变量改为input_path（两行），未改其他位置。

最终限定测试重新运行：

```text
test_compact_regen.py: 31 passed / 0 failed / 0 error / 0 skipped
test_art_pipeline.py: 35 passed / 0 failed / 0 error / 0 skipped
总计：66/66
```

日志：`A1R-v3-regen3-inputs-RED.log`、`A1R-v3-regen3-inputs-GREEN.log`。

并只读核对root的 `.tools/art/v3/regen-scenes-final.json`：17个scene task身份唯一，S04四项prompt逐字附加当前JSON的空架及OPEN/CLOSED约束；8个夜图＋S01闭店，共9份依赖均指向同scene/state的新版前态，全部can_generate=false，参考目标也对应正确路径。未覆盖中央manifest或重写队列。

独立复审代理随后实际复验同一manifest：带inputs删身份现报ValueError、typo operation报ValueError，四约束与九依赖均正确，未见剩余阻断。独立报告 `.tools/art/v3/final-code-review.md` 和 `final-independent-probes.log` 已冻结。

## 范围与后续

- root负责把 regeneration_constraints 写入四张 S04 C 行并运行 full round2。
- 只修队列与校验，不把人工mask复核变成全自动。旧mask/审计仍不能批准新C，离线产物/runtime对应关系保持上一轮修正。
- 正式显式 slices 严格拒绝未知操作；旧v2按文件名推断的兼容输入不受本次正式行校验影响。
