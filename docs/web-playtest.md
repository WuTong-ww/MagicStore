# 网页试玩

**公开实验试玩：[https://wutong-ww.github.io/MagicStore/](https://wutong-ww.github.io/MagicStore/)**

实际部署源码为 `02d1d423aba4741c929acb1b2542a818ff939ef9`，初始功能提交为 `2b4ec419fc56d285b5cafe3647a41ef42e33e379`；其后的修复仅分离构建与部署任务。[CI 45322600343](https://github.com/WuTong-ww/MagicStore/actions/runs/45322600343) 已实际成功，匿名HTTPS的build-info、HTML／JS全量SHA及Wasm／PCK长度与前4字节检查通过，见 [发布回执](codex/results/WEB-deployment.json)。大型文件的完整SHA仅为CI公布值，未在公网全量下载复核。

本分支是**实验试玩，部分完成**：三轮标准完整测试均未通过，已达到本次上限，不把有限尾段或导出烟测相加称为全绿。实际浏览器WebGL、刷新存档和Claude操作尚未验证；原生导出包检查与原生画面结果见 [WEB验收回执](codex/results/WEB-validation.json)。

给 Claude 的试玩任务可以直接复制以下文字：

> 请用浏览器操作工具打开 https://wutong-ww.github.io/MagicStore/ ，新建一个名为“Claude试玩”的独立存档，用本地对话体验前台接待、咨询、案例手记与经营入口。不要填写API密钥或删除其他存档。零客日可以打烊进入下一天，再用“等一会儿”推进游戏时间。请记录真实操作步骤、画面和结果，列出阻塞问题及可复现缺陷；如果你的会话没有浏览器操作能力，请明确说明无法实际试玩，不把网页文本阅读当作已玩过。

这是 `codex/web-playtest` 分支的链接试玩入口。后续发布以 GitHub Actions 中 **Web playtest → deploy → github-pages** 的实际部署记录为准。首次加载主要包含约37.7MB Wasm和147.8MB PCK，下载较大；默认不配置模型，使用本地对白。

## 开始游玩

1. 在支持 WebAssembly、WebGL 2.0 的浏览器中打开部署链接，等待资源加载。先点击页面，使游戏取得输入焦点；音频也可能要在首次点击后才开始。
2. 在「存档簿」填写店名，点「新建独立存档」。以后可在同一浏览器选择「继续所选存档」。
3. 在前台接待来客，进入咨询区交谈、使用工具，再查看案例手记。工坊、原料商店和储物柜提供研究、采购、制作、销售与使用入口。
4. 等待操作完成并显示结果后再继续；成功行动会自动保存。游玩中切到其他标签页可能暂停处理，回来后再确认当前状态。

网页使用 Godot 4.6.3 的 Compatibility 导出，需要浏览器实际支持 WebGL 2.0。加载或画面异常时可查看浏览器开发者控制台，并在反馈中附浏览器版本、页面网址、操作步骤及报错，不附密钥。平台要求和输入、音频限制见 [Godot Web 导出说明](https://docs.godotengine.org/en/4.6/tutorials/export/exporting_for_web.html)。

给 Claude 或其他代理试玩时，需要提供**能打开网页、读屏并点击和输入的浏览器操作工具**。仅能请求文本或调用对话 API 的会话不能据此声称已经玩过；应保留实际页面、操作与结果作为证据。

## 本地对白、联网与存档

不配置 AI 接口也能使用本地对白游玩；在设置中可选择「使用本地对话」。这里的离线模式指不依赖模型请求，首次下载网页及资源仍需要网络，也不保证关闭浏览器后能断网重新打开网页。

GitHub Pages 只提供静态游戏文件，不运行 Python 网关或托管模型。自配 AI 时，服务须兼容游戏的请求协议；从 HTTPS 试玩页面访问的服务还必须满足浏览器的 HTTPS、CORS 和预检要求，包括允许实际页面来源、请求方法及 `Authorization`、`Content-Type` 等所需请求头。桌面版能访问的 HTTP 地址不代表网页也能访问；HTTPS 页面访问普通 HTTP 服务可能被浏览器拦截。相关配置见 [接口设置说明](api-model-switch.md)，浏览器限制见 [Godot HTTP/Web 平台说明](https://docs.godotengine.org/en/4.6/tutorials/export/exporting_for_web.html#networking)。联网失败不能当作模型成功，仍以游戏显示的本地回退或错误为准。

浏览器存档保存在该浏览器的站点存储中，使用 Godot 的 `user://`／IndexedDB，不会上传为 GitHub Pages 文件，也不会自动与桌面版、另一台设备或另一浏览器同步。私密窗口、禁用站点存储、清除网站数据或浏览器清理都可能使进度无法保留；保存能力以实际读档结果为准。部署网页不会替玩家备份浏览器存档。持久化限制见 [Godot 浏览器存储说明](https://docs.godotengine.org/en/4.6/tutorials/export/exporting_for_web.html#using-cookies-for-data-persistence)。

公开构建不预置共享 API Key。不要把个人凭据、本地存档、候选原图或审计目录复制进 `build/web`；CI 不读取个人 API secrets，也不上传整个仓库。

## 重建与发布

从仓库根目录运行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/dev/bootstrap.ps1 -WithWebExportTemplates
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/dev/export-web.ps1
```

入口为 `build/web/index.html`，相关 `.wasm`、`.pck`、脚本和导出图标需一起保留，不要自行重命名。可用本地 HTTP 服务验证文件加载，不能直接双击 `file://` 页面：

导出脚本会先对实际Web PCK运行隔离的原生引擎烟测，核对场景／物品／头像／着色器、真实新建／等待／读档以及禁入目录；断言失败或引擎错误会中止发布。它不运行WebAssembly，不替代实际浏览器的WebGL和IndexedDB持久性验收。原始音乐下载包等工程根目录额外文件只保留本地，不自动进入试玩包。

```powershell
python -m http.server 8060 --bind 127.0.0.1 --directory build/web
```

打开 `http://127.0.0.1:8060/`。本地 HTTP 不等同于线上 HTTPS/CORS 验收；正式 Pages 链接仍需实际浏览器试玩。

[发布 workflow](../.github/workflows/web-playtest.yml) 在推送 `codex/web-playtest` 时运行；保留手动入口，手动选择其他分支会跳过发布。只执行固定工具链安装、Web 导出与部署，不重复完整测试。新推送会取消旧发布运行，artifact 仅包含 `build/web`，保留一天。Actions 失败时查看失败步骤，不用旧网站仍可访问来推断新提交已上线。

Windows构建／包检查与上传完成后，独立部署任务通过 `needs: build` 消费产物。首轮CI45321775777曾在同一任务上传后立即查询到0个artifact而失败，稍后REST实际列出同名产物；分离后查询到1个并成功发布，原失败记录保留。该现象与 [官方上游报告](https://github.com/actions/deploy-pages/issues/451) 一致。最终有限尾段HTTP仍有3项重试断言未过，三轮完整失败不被CI部署成功覆盖。

仓库管理员需先将 Pages 的发布来源设为 **GitHub Actions**（API 中为 `build_type: workflow`）；若 `github-pages` 环境有分支保护规则，须允许 `codex/web-playtest`。workflow 不自行创建站点或申请额外管理权限；部署仅使用 `contents: read`、`pages: write`、`id-token: write`。官方配置依据见 [GitHub Pages 自定义 workflow](https://docs.github.com/en/pages/getting-started-with-github-pages/using-custom-workflows-with-github-pages)。

使用核查时官方稳定主版本：[checkout v7](https://github.com/actions/checkout/releases/tag/v7.0.1)、[configure-pages v6](https://github.com/actions/configure-pages/releases/tag/v6.0.0)、[upload-pages-artifact v5](https://github.com/actions/upload-pages-artifact/releases/tag/v5.0.0)、[deploy-pages v5](https://github.com/actions/deploy-pages/releases/tag/v5.0.1)。这里采用官方 action 的主版本标签，后续升级须重新核对发布说明与实际部署。
