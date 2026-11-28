# 第四轮界面音效工具

原始三套 Kenney ZIP 留在仓库外。`r4_selection.json` 固定来源包 SHA256、所选原文件、剪辑上限和处理参数。构建先验证来源包与内附 CC0 许可证，不联网、不读取任何密钥。

```powershell
python -m pip install -r tools/audio/requirements.txt
python tools/audio/analyze_ui_sounds.py <解压目录> --json .tools/r4-b/raw-sound-metrics.json --csv .tools/r4-b/raw-sound-metrics.csv
python tools/audio/build_ui_sounds.py --sources <保存三套ZIP和同名解压目录的文件夹>
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/dev/run-r4-art.ps1 -Stage B2
```

`analyze_ui_sounds.py` 不改音频，只输出每个候选的时长、能量频谱重心、前5ms峰值比、持续窄带音调占比、峰值和短窗响度。频谱重心明确采用功率加权 FFT；窄带判据合并相邻三个频点，避免音高恰落FFT边界而漏判。

短片段通常不足广播R128的400ms，统一使用40ms K加权门限窗口。约−20 LUFS是此短窗定义下的可复跑目标，不宣称广播节目响度合规。保留原始自然起音，不靠添加长静音满足前5ms判据。对超过330ms的素材只取开头330ms，随后6kHz低通、头尾5ms淡化、归一化并编码Vorbis q4；不截断到小于60ms。硬币三候选额外用2.2kHz低通柔化金属高频；这项附加处理显式写入每份登记。

正式播放使用音效专用随机数发生器，音高0.96–1.04，不消费人物或游戏的随机流。取消声额外降低3dB，提示声降低2dB。默认界面音量0.45；已保存的玩家音量偏好继续有效。

TITLE的独立入店铃 `entry_chime` 保留原来的已登记资源路径和字节，因为现有标题流程会核验该路径。常规 `notify` 使用本轮新主选。旧六份音效文件均保留；本轮通过映射切换日常音效，不覆盖它们。

在Godot编辑器打开 `scenes/dev/audio_preview.tscn` 并按F6，逐项比较主选与两个候选。试听固定音高，保留实际用途的音量差；不会调用游戏动作或改存档。只修改 `data/ui/audio.json` 的 `sounds.<用途>` 为该用途已有候选路径即可换主选，原主选仍保留在三选试听中。

数值筛选与素材文件名不能证明听感已经获批。真人试听保留为策划事项，`human_listened` 当前为false。
