# R3-AICASE：普通案件的完整定义、严格校验与即时回退

基线为已完成并正常推送的NAMES主提交818d604及记录8227d6d，schema13。标准full3已18716检查与391 Python测试零失败；本任务重新计最多三次完整测试，不重跑NAMES第四轮。现有五固定案、人物v3及旧档身份不改。用户无人值守授权下选最简单可逆方案；下述为本任务实施计划，不把tools原型当生产已通过。

## 方案

独立的案件协议与存档内不可变definition，不扩人物包、不往严格五案index里塞六模板。新`divination.emergent_cases`命名空间保存普通每日第0位案件客的预约；ready后保存完整definition、typed proof、当时本地公开context、hash和受限来源。升schema14，旧13只在内存加空命名空间，不补改已经计划的archive行，下一成功动作写盘。用原始NAMES schema13存档验证旧人物、案件、计划、处理回执及磁盘字节保持。

离线六题材为遗失物、邻里误会、宠物走失、旧照片、匿名礼物、搬家；每份均真实完整CASE格式并逐份校验。静态五固定案和G3原邀请不变。新普通第0位才预约，固定案、尾声、购物、家族与已存生成包不冒充普通案件客。

模型必须返回完整data/cases定义及独立typed proof，含3格、6证据且有误导、5真实牌、2–3建议和完整后果；不能仅返回若干ID由程序假称模型写了整案。采用受控事实/句型以证明正确答案、双向引用、可达证据、文本及后果一致。首版在线范围为温和物件摆放/核对；可组合出区别六fallback的新事实，不声称验证任意中文逻辑。长度、深度、原始JSON重复键/精确整数、危险内容、owner与固定角色隔离均拒绝非法结果。

请求只用程序确认的普通人物公开姓名/职业和已实际披露报告的白名单，传闻在发出前就核来源/时间。保存context不含请求专用人物字段、URL、key、seed、路径、原始回复或reasoning。固定人物设定和未披露世界事实不得进入模型。人物v3姓名/肤色锁合同保持。

后台传输单job即可，绝对单调deadline包含首帧和校验；epoch/save/预约/owner/token绑定，取消、换档、配置更换与迟到回调不能改已入档真相。callback只给私有候选；经`execute_action_async(admit_generated_case)`保存后才发布。点击请下一位时若无已验证候选，立即在同候选事务生成确定性fallback，不等网络；保存失败同action重试必须用第一次选择的同一完整定义。

唯一纯snapshot builder供SaveService、Session、事件、日程及公开投影使用。先严格构建候选catalog/definitions、保存，再在state_changed前发布同一已验证目录；失败不污染live目录。旧v1/v2人物/G3案例及已保存版本化案件均可重载。自由提问只允许已问到的动态话题，不因目录装载提前泄漏未问回答、工具线索、truth或proof；五类记录仍分开。

## 实作与验收

1. 先在当前生产new_game取得缺namespace/动态普通案的真实功能RED；不把预加载缺文件或解析错当RED。
2. 按已审工具清单移植六fallback规则/定义、full-definition GD-r1、严格配置/公开文案。原R0/R1草稿与失败证据保留，不整文件覆盖当前GameState。
3. 编译并实际验证纯leaf：Python/GD同fixture canonical/hash，21 raw数值向量、坏形状、两种novel truth、真实CaseSchema/G3引用，六fallback全部建议/错推理仍可结案。
4. 接schema迁移、pure store/catalog、日程与旧case桥接，再接GameState异步候选、即时回退及保存后发布。每次所有新增JSON有校验，版本资源保留以读旧ready定义。
5. 只用本地HTTP mock验完整生成报文与真实admission：有效完整新案、篡改/冲突/字段缺失、超时/取消/迟到、Web零请求、无网络零等待、同ID失败重试/成功重放/重载及signal回调即时读取。无真实付费模型调用；实际服务兼容留人工项。
6. 实际普通案完整问答/翻牌/证据/建议/次日反馈；原五案最佳/最差路线、邀请金样本和NAMES/原人物协议保持。原始schema13内存迁移、失败写盘、重试后落盘与原始SHA检查必做。
7. 双尺寸真实GPU验收并逐图检查，最多6 JPG；实际运行shop_ui，保留1280×720与1920×1080 PNG。复用CASE界面，不制造新美术或把名字状态烘焙进图。
8. 更新features/PROGRESS/审阅包，独审后执行规定标准全套，最多3轮。第3轮仍失败则明确部分完成继续TITLE，不跑第4轮。通过后只提交本任务文件并正常push codex/round3，main不动。

当前优选tools输入：fallback的gd-drafts；持久化integration-r1；模型规范full-definition-r1（24 Python/0，含1911坏形状）；实现full-definition-gd-r1（数值门修订，全部GD未跑）；http-drafts。静态独审0C/I/M不替代本任务实际GD、事务、界面或标准完整测试。
