# D 盘迁移记录

2026-11-06（Asia/Shanghai），按用户要求将开发工程迁移到 `D:\MagicStore`。

- 初始复制 411 个文件，共 2,509,893,944 字节；逐文件 SHA256 比对一致，清单保存在被 Git 忽略的 `build/migration-manifest.json`。
- 完整保留 Git 历史、origin、main 跟踪关系、源代码、中文字体、引擎、模板、导出包、测试数据和原始介绍。Git 关联 `https://github.com/WuTong-ww/MagicStore.git`。
- 将此前试玩的两个存档及其备份复制到新默认 `D:\MagicStore\.runtime\appdata\ZeroHourStore\saves`，由真实 SaveService 重新读取校验，两个均有效。
- 默认入口为根目录 `start-game.cmd` / `start-editor.cmd`。启动脚本将 APPDATA、LOCALAPPDATA、TEMP、TMP 限定在工程 `.runtime` 内，退出后恢复当前进程环境。测试仍隔离在 `.tools/test-*`。独立试玩包使用 `StartGame.cmd`，数据留在包旁 `.runtime`。
- 迁移后从 D 盘运行完整 `run.ps1 -Test`：57 项核心、48 项 provider、63 项界面和两个独立进程重启检查全部通过。D 盘重新导出成功，独立启动脚本 headless 启动退出码 0。
- C 盘原目录中的实际文件已全部删除，释放约 2.51 GB（2.34 GiB）。为兼容旧工作目录，保留指向 `D:\MagicStore` 的目录联接。通过旧路径访问的文件实际位于 D 盘。

今后直接使用 D 盘目录。不要递归清理旧兼容路径：它现在指向正式工程。绕过默认启动脚本直接打开原始引擎/EXE 时，Godot 仍采用操作系统 AppData；默认入口已避免这一情况，不修改操作系统全局配置。
