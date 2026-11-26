# 第三轮网页版

预览入口为 https://wutong-ww.github.io/MagicStore/preview/ 。推送codex/round3只更新此路径；只有合并main后触发的构建才更新正式入口。当前不会合并或修改main。

Godot固定4.6.3标准版、Compatibility、单线程，无须跨源隔离响应头。第一次安装运行 `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/dev/bootstrap.ps1 -WithWebExportTemplates`，然后运行 `scripts/dev/export-web.ps1 -Variant preview`。需要Python及fonttools 4.60.2、brotli 1.1.0。产物和完整日志在 `.tools/r3-web/builds/preview-optimized/output`。再次本地构建用 `-Attempt local2` 保留上次证据。

构建在隔离stage移除无引用旧场景/预览及旧Noto字体，大图片以0.78质量有损导入；原PNG与导入设置不变。完整霞鹜文楷和等宽数字字体仍嵌入。加载页的Midnight Loading WOFF2由已登记文楷按加载文案生成，随包附OFL，实际SHA记在build-info.json。

开发基线全站351,500,932字节，优化后74,742,410字节，减少78.74%；PCK从313,291,036降至36,532,512字节，WASM保持37,700,666字节。它们是实际导出文件字节，不能等同网络耗时。首次可交互时间待浏览器实测。线上旧正式版185,960,037字节是另一版本，不混作同输入基线。

公开构建不带音乐，缺失音乐会静音；保留音效。对话和案件强制本地固定/备用内容，设置页不接受外部接口或密钥。个人存档不进入构建。预览的user目录为MagicStorePreviewR3，仅挂载对应子目录；正式版保留ZeroHourStore与原/userfs挂载，兼容原有浏览器存档。

本地带音乐：保留个人的 `assets/audio/music/`，运行 `scripts/dev/export-web.ps1 -Variant preview -WithMusic`。产物位于带-music后缀的隔离目录，仅供本地；不上传Git或Pages。白天及案件使用玩家指定Sheep，曲目配置仍在data/audio.json。音乐目录始终忽略。

Actions部署由站点级串行锁覆盖构建到发布；合并前下载并逐文件验证当前站点，仅替换目标子树，并校验另一子树SHA不变。首次恢复清单记录旧正式02d1d423；如果线上已变而清单不匹配，构建会停止，不发布旧站。之后沿用在线site-manifest.json恢复当前双入口。Pages需设GitHub Actions作为来源，并允许codex/round3与main部署；旧codex/web-playtest整站发布需退役。当前授权已包含推送与预览发布，无须再次请求。

官方参考：[Godot Web导出](https://docs.godotengine.org/en/4.6/tutorials/export/exporting_for_web.html)、[Pages产物](https://github.com/actions/upload-pages-artifact)、[Pages部署](https://github.com/actions/deploy-pages)。最终浏览器与回归结果以审阅包及R3-WEB-validation.json为准。
