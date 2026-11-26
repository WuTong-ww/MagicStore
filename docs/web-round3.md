# 第三轮网页版

预览入口为 https://wutong-ww.github.io/MagicStore/preview/ 。推送codex/round3只更新此路径；只有合并main后触发的构建才更新正式入口。当前不会合并或修改main。

Godot固定4.6.3标准版、Compatibility、单线程，无须跨源隔离响应头。第一次安装运行 `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/dev/bootstrap.ps1 -WithWebExportTemplates`，然后运行 `scripts/dev/export-web.ps1 -Variant preview`。需要Python及fonttools 4.60.2、brotli 1.1.0。产物和完整日志在 `.tools/r3-web/builds/preview-optimized/output`。再次本地构建用 `-Attempt local2` 保留上次证据。

构建在隔离stage移除无引用旧场景/预览及旧Noto字体，大图片以0.78质量有损导入；原PNG与导入设置不变。完整霞鹜文楷和等宽数字字体仍嵌入。加载页的Midnight Loading WOFF2由已登记文楷按加载文案生成，随包附OFL，实际SHA记在build-info.json。

开发基线全站351,500,932字节，优化后74,742,410字节，减少78.74%；PCK从313,291,036降至36,532,512字节，WASM保持37,700,666字节。它们是实际导出文件字节，不能等同网络耗时。首次可交互时间待浏览器实测。线上旧正式版185,960,037字节是另一版本，不混作同输入基线。

按2026-11-26用户要求，后续自动部署均携带选定BGM供试听；普通手动构建默认静音，缺曲也静音。对话和案件强制本地固定/备用内容，设置页不接受外部接口或密钥。个人存档不进入构建。预览的user目录为MagicStorePreviewR3，仅挂载对应子目录；正式版保留ZeroHourStore与原/userfs挂载，兼容原有浏览器存档。

本地带音乐：保留个人的 `assets/audio/music/`，运行 `scripts/dev/export-web.ps1 -Variant preview -WithMusic -Attempt local-bgm1`。产物位于`.tools/r3-web/builds/preview-optimized-music-local-bgm1/output`。白天及案件使用玩家指定Sheep，开场Gentle Breeze、夜晚Evening Harmony、结局Fabric Of Life，曲目配置仍在data/audio.json。音乐目录始终忽略。

仓库保持Public。自动部署读取普通Git中的`build-sources/music/r3-music-v1.fernet`，使用用户已授权的Actions secret `WEB_AUDIO_KEY`认证解密；密钥不进入Git、命令行、日志、游戏或Pages，也没有API/账号访问权限。解密库固定cryptography 46.0.3，仅构建使用，不引入Godot插件。密文14,471,948B，SHA256 `88f4f404e46b1a8303be4611d12d01f62514e0b522d3c50c9ae2fafe02b98641`；原音频和明文ZIP始终ignored。解密后校验ZIP及4首逐文件SHA，再导出带`public_web,withmusic`特性的包。构建清单`data/web_audio_build.json`不进入游戏；PCK审计只接受清单内4首，Pages只放最终游戏包。四首音频共10,853,444字节，明文归档SHA256 `3cdcc738cd4044b0d6c92494c84762e51782ff230bc1d1c85f6857e5a567e764`。换曲需同步data/audio.json、构建清单和新版本密文；密钥缺失/错误、密文变化或完整性失败即停止，不以静音包代替。

本地已验证15项加密/归档/导出策略、11项双入口保留策略、44项音频运行及实际Web PCK24项，均零失败。带音乐全站85,817,549B、PCK47,605,824B，静音旧预览为74,729,440B；此处为文件大小，不当作实际下载耗时。密钥本地备份位于ignored `.tools/r3-web/audio-source/web-audio-key.txt`，不要粘贴到审阅包或日志。仅在需要从密文恢复运行曲目时，将密钥作为当前进程环境变量`WEB_AUDIO_KEY`运行`python tools/web_audio.py --decrypt`，随后按上述带音乐命令导出；已有4首匹配的本地音乐可直接导出。

带音乐预览代码091e0fe已由Actions [45848095173](https://github.com/WuTong-ww/MagicStore/actions/runs/45848095173)自动构建并发布成功。实际线上全站85,801,174B、PCK47,588,576B，构建信息music_included=true、source_dirty=false及4首来源摘要均匹配；正式16文件与冻结版本完全一致。Chrome用既有qa存档进入，点击49.51秒后仍在咨询画面显示持续音频活动；不以此替代玩家听感。使用[预览入口](https://wutong-ww.github.io/MagicStore/preview/)，首次点击继续并进入游戏后可试听，音量在设置页调整。本次标准整合一轮仍因未修改的历史schema15迁移门槛失败，专项结果不冒称全套绿，详见R3-WEB-BGM-validation.json。

Actions部署由站点级串行锁覆盖构建到发布；合并前下载并逐文件验证当前站点，仅替换目标子树，并校验另一子树SHA不变。首次恢复清单记录旧正式02d1d423；如果线上已变而清单不匹配，构建会停止，不发布旧站。之后沿用在线site-manifest.json恢复当前双入口。Pages需设GitHub Actions作为来源，并允许codex/round3与main部署；旧codex/web-playtest整站发布需退役。用户已明确授权推送与预览发布，无须重批。2026-11-26运行45805865584构建成功，但环境白名单仅允许main和旧试玩分支，deploy被拒绝；自动审批要求另行明确授权新增精确codex/round3规则，保存前已停止，原规则未改。批准后可在该运行中仅重试失败的deploy，复用已有产物；这不需要第四轮完整测试。

官方参考：[Godot Web导出](https://docs.godotengine.org/en/4.6/tutorials/export/exporting_for_web.html)、[Pages产物](https://github.com/actions/upload-pages-artifact)、[Pages部署](https://github.com/actions/deploy-pages)。最终浏览器与回归结果以审阅包及R3-WEB-validation.json为准。

2026-11-26发布记录：用户已明确授权并保存codex/round3精确规则；运行45805865584第2次尝试部署成功，复用原产物。公开预览总计74,725,663字节，实际下载PCK36,515,344字节且SHA匹配，实包12/0；正式16条清单与冻结版本一致。开发基线体积比较仍保留，不能把文件字节当加载耗时。1080截图异常、长面板滚轮位移和双入口存档隔离仍待最终浏览器复核。
