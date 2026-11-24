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

## 验收收口：部分完成、实验试玩已部署

2026-11-24按用户最多三轮完整测试的上限收口，授权发布实验试玩；**完整回归未全绿，不运行第四轮**。游戏规则、provider、事务及存档生产代码与基线 `2b34ecb` 相同，本任务新增导出／发布工具及测试夹具修正。正式回执见 [WEB-validation.json](../results/WEB-validation.json)。

|完整轮次|真实退出|已报告范围|停止点与未完成范围|
|---|---:|---|---|
|1|1|93个summary，14345 checks／1 failure|DIRECT API 77／1；后续HTTP及Python／美术未完成。原包装器有限重现另列，不抹除本轮失败。|
|2|1|91个summary，14229 checks／1 failure|HTTP pending计时41／1；后续未完成。|
|3|1|90个已完成summary，14170 checks／0 reported failures|默认执行环境HTTP夹具超过30秒期限；该HTTP范围未完成，总数为null，Python／美术等尾段未跑到。未证明是网络阻断。|

原三份日志SHA分别为 `022fe006815747b5c73f82c94d6d4493fd369e90ca15214830273f90d19e1910`、`13022ad60f673c92bdbbe7bdd68d60cf09dd2da5920d1762534d15e203cd9a63`、`313acba3a493677d956f689c86103e49615347bc8b2f82d884e4db532d87ad76`；三轮分别封存，后续有限检查不改变这些退出结果。

计时实证与最小夹具修正：原50ms SceneTreeTimer实际仅耗1ms，改为真实单调时钟等待；2秒HTTP请求曾在3ms提前结束、remaining仍1997ms，同步新建／接待后的初始长帧改为先经过两帧再发请求。DIRECT API仍用650ms共享预算、前两阶段各130ms／审核800ms，保留原wall＜900ms及阶段断言。四个HTTP测试夹具保留原断言与阈值，生产provider未改。此前允许127本机服务的有限包装器513项＋wire256项通过属于独立范围，不能拼成完整测试全绿。

实验初版2b4ec41提交时独立尾段仍运行，回执complete=false；已按授权与远端导出CI并行。现在尾段已全部终止、complete=true／exit1：HTTP439／442，recovery43项中3失败，mood／family未到达，HTTP全套总数仍null；PERSON64／64、People359／359、Python117／117、美术254／254分别通过，formal364记录／367文件与alpha70通过，退役registry明确SKIP。14份原日志SHA均核对，415限定源码前后无变化。不把这些独立范围与14170相加冒充完整回归。

导出6已实际通过静态检查与Web PCK原生隔离烟测634／634、0引擎错误／警告，859个打包文件、禁止路径0；覆盖引用资源、真实新建／等待／读档及资源／钱包等值。PCK为147791660B、Wasm为37700666B。该检查不执行WebAssembly或WebGL，不等于浏览器保存验收。

原生GPU为1544／1544、30张capture；只选两张质量85 JPG入Git，root已实际打开 [1280×720](../../screenshots/round2/WEB/native-front-1280x720.jpg) 与 [1920×1080](../../screenshots/round2/WEB/native-front-1920x1080.jpg)。两帧通用五项检查合计8／10：纸面、文字、动态控件与布局四项均过；两帧旧林头像笔触均不符v3，未在本任务重画。30张capture不冒称30张人工已审，也不当网页截图。

电脑操作工具因不能可靠识别Windows浏览器URL而停止，未改用其他浏览器路径绕过。实际WebGL、IndexedDB刷新续玩及Claude会话操作均未验证，明确保持部分完成。公开HTTPS文件／CI结果在部署后记录，CLI文件成功也不代替浏览器实操。

体积初始暂存快照新增unique blob830062B，其中两JPG二进制622504B；后补文本单独登记，见 [WEB-size-inspection.json](../results/WEB-size-inspection.json)。本地音乐下载包、存档、候选原图、`.tools`及构建输出均不提交；Git普通上传，无LFS、无main／旧分支改写。

## 实际发布与剩余限制

初始功能提交 `2b4ec419fc56d285b5cafe3647a41ef42e33e379` 已普通push；首轮CI [45321775777](https://github.com/WuTong-ww/MagicStore/actions/runs/45321775777) 导出634／0及上传成功，但紧接的同job artifact查询返回0，部署失败。REST随后实际列出同名artifact14888061533；与 [上游#451](https://github.com/actions/deploy-pages/issues/451) 同型。仅workflow拆成Windows build与 `needs: build` 的独立deploy，未改检查、阈值或游戏代码；修复提交 `02d1d423aba4741c929acb1b2542a818ff939ef9` 普通push后，实际CI [45322600343](https://github.com/WuTong-ww/MagicStore/actions/runs/45322600343) 构建634／0、部署均success，查询实际找到1个artifact。

公开入口：[https://wutong-ww.github.io/MagicStore/](https://wutong-ww.github.io/MagicStore/)。匿名CLI实读build-info.commit等于02d1d42，HTML3845B／JS315759B全量SHA匹配；Wasm37700666B／CI PCK147776572B的HEAD长度与Range206前4字节magic通过。大文件SHA是CI公布值，未公网全量下载，不与本地导出6的PCK147791660B混同；见 [WEB-deployment.json](../results/WEB-deployment.json)。

最后META只补文档及证据，workflow路径过滤排除这批普通文档，不触发重复构建。初始feature、workflow修复及实际部署source分别登记；无force／无LFS，main=e27441b、round2-clean=2b34ecb、旧round2=18da84a保持。首次下载较大、旧林笔触、HTTP重试回归与浏览器实操缺口仍在；使用默认本地对白作为实验入口，不称任务100%完成。
