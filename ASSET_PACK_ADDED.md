# Art pack integration handoff

本文件对应 `docs/ART_ASSET_GUIDE.md`。七个主场景背景、林照晚三态、术式插画、证物/收据/关系/报告图集已加入 assets，并接入 Godot 页面。

Windows 使用：首次执行 `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/dev/bootstrap.ps1` 下载并校验 Godot 4.6.3；随后双击 `start-game.cmd`。游戏启动显示 S01 店外和存档簿，创建/读取存档后进入前台。

本轮没有修改存档结构和主要经营/占卜规则；新增第二个采集点 `woodland_glade`，仍走原 `gather_material` 动作和共享库存。完整镜号映射、操作流程和未完成边界见 `docs/ART_ASSET_GUIDE.md`。
