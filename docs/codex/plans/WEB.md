# WEB · 链接试玩

目标：把当前第二轮源码导出为实际可玩的浏览器版本，给人和具有浏览器操作能力的 Claude 通过 HTTPS 链接试玩。保留现有游戏规则、事务与 schema9；不打包本机存档、凭证、测试及美术中间产物，不新增付费服务。

采用 Godot 4.6.3 Compatibility 单线程 Web 导出，避免依赖跨源隔离头。优先复用现有 GitHub 仓库的 Pages 静态托管；若权限或服务限制阻挡，保留可部署产物并明确实际阻挡，不把本地地址说成公开链接。新增独立 codex/web-playtest 分支，不改 main／已审 round2-clean。

改动范围：export_presets.cfg、scripts/dev/bootstrap.ps1、网页导出／发布脚本、网页外壳及必要的浏览器兼容修复、README／docs/features.md／本计划与部署说明。运行副本与构建只留 ignored build/、.tools/，不再次提交大二进制。

验收：

1. 原完整 scripts/dev/run.ps1 -Test 全绿；实际固定版本 Web export 成功并审计输出。
2. 在真实浏览器打开构建，检查加载、中文、1280×720／1920×1080、点击导航、新建档、完成一个合法动作和刷新续玩；截图实看。
3. 公开 HTTPS 入口与 wasm／pck 返回成功，实际访问在线版本验证。测试环境不代表已在用户 Claude 账号内试玩。
4. 说明离线来客可玩；在线模型须支持 HTTPS/CORS 且由试玩者自行配置，本机 key 不上传；存档属于当前浏览器，不宣称云同步。
5. 更新功能与启动说明，登记外部工具来源；提交、普通 Git 推送并记录可验证链接或精确阻挡。

自主选择：用户此前明确无需中途提问。采用可撤回的静态发布与独立分支，不配置公共模型代理、不消费用户 API、不改用户存档。

## 验收收口：部分完成、实验试玩待发布

2026-11-24按用户最多三轮完整测试的上限收口，授权发布实验试玩；**完整回归未全绿，不运行第四轮**。游戏规则、provider、事务及存档生产代码与基线 `2b34ecb` 相同，本任务新增导出／发布工具及测试夹具修正。正式回执见 [WEB-validation.json](../results/WEB-validation.json)。

|完整轮次|真实退出|已报告范围|停止点与未完成范围|
|---|---:|---|---|
|1|1|93个summary，14345 checks／1 failure|DIRECT API 77／1；后续HTTP及Python／美术未完成。原包装器有限重现另列，不抹除本轮失败。|
|2|1|91个summary，14229 checks／1 failure|HTTP pending计时41／1；后续未完成。|
|3|1|90个已完成summary，14170 checks／0 reported failures|默认执行环境HTTP夹具超过30秒期限；该HTTP范围未完成，总数为null，Python／美术等尾段未跑到。未证明是网络阻断。|

原三份日志SHA分别为 `022fe006815747b5c73f82c94d6d4493fd369e90ca15214830273f90d19e1910`、`13022ad60f673c92bdbbe7bdd68d60cf09dd2da5920d1762534d15e203cd9a63`、`313acba3a493677d956f689c86103e49615347bc8b2f82d884e4db532d87ad76`；三轮分别封存，后续有限检查不改变这些退出结果。

计时实证与最小夹具修正：原50ms SceneTreeTimer实际仅耗1ms，改为真实单调时钟等待；2秒HTTP请求曾在3ms提前结束、remaining仍1997ms，同步新建／接待后的初始长帧改为先经过两帧再发请求。DIRECT API仍用650ms共享预算、前两阶段各130ms／审核800ms，保留原wall＜900ms及阶段断言。四个HTTP测试夹具保留原断言与阈值，生产provider未改。此前允许127本机服务的有限包装器513项＋wire256项通过属于独立范围，不能拼成完整测试全绿。

本次独立尾段尚在运行，初次发布回执complete=false：HTTP包装器只完成442项／3失败，停止于recovery43／3，mood／family未到达、HTTP全套总数仍null；PERSON64／64、People359／359与Python117／117分别通过，其他范围待实际终态。按授权与远端导出CI并行发布实验初版，尾段最终结果将在META补记，不追认任何full通过。

导出6已实际通过静态检查与Web PCK原生隔离烟测634／634、0引擎错误／警告，859个打包文件、禁止路径0；覆盖引用资源、真实新建／等待／读档及资源／钱包等值。PCK为147791660B、Wasm为37700666B。该检查不执行WebAssembly或WebGL，不等于浏览器保存验收。

原生GPU为1544／1544、30张capture；只选两张质量85 JPG入Git，root已实际打开 [1280×720](../../screenshots/round2/WEB/native-front-1280x720.jpg) 与 [1920×1080](../../screenshots/round2/WEB/native-front-1920x1080.jpg)。两帧通用五项检查合计8／10：纸面、文字、动态控件与布局四项均过；两帧旧林头像笔触均不符v3，未在本任务重画。30张capture不冒称30张人工已审，也不当网页截图。

电脑操作工具因不能可靠识别Windows浏览器URL而停止，未改用其他浏览器路径绕过。实际WebGL、IndexedDB刷新续玩及Claude会话操作均未验证，明确保持部分完成。公开HTTPS文件／CI结果在部署后记录，CLI文件成功也不代替浏览器实操。

体积初始暂存快照新增unique blob830062B，其中两JPG二进制622504B；后补文本单独登记，见 [WEB-size-inspection.json](../results/WEB-size-inspection.json)。本地音乐下载包、存档、候选原图、`.tools`及构建输出均不提交；Git普通上传，无LFS、无main／旧分支改写。
