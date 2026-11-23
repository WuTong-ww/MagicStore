# 家族库填写指南（G2）

本轮只提供框架与三人原创占位`data/people/families/family_placeholder.json`。正式库和占位均默认关闭，触发率为0；作品内容、改写角色及原文屏蔽词由策划另行提供，不把测试占位自动投入玩家客流。

## 文件登记与启用

每家族一份UTF-8 JSON，放`data/people/families/<safe_key>.json`；在`data/people/family_library.json`的`template_paths`显式登记`res://`路径。只接受该目录单层文件名，不能路径穿越或按目录扫描顺序抽样。建议复制占位完整结构后填写，未知字段／引用或缺文件会拒绝整个库，不会加载半个家族。

`template_id`和成员／边／目标`key`是永久技术键，只用小写字母、数字、下划线并以字母开头。上线存档后保持不变；显示姓名可以改稿，但既有存档保存人物快照，不应凭当前模板重写已经认识的人。不同模板可复用`first`等成员key，实际ID同时含存档域与模板域；数组重排不改人物／关系身份。

启用需要库`enabled=true`、模板`enabled=true`及政策`trigger_percent>0`同时成立。手册中的family_trigger_percent对应`policy.trigger_percent`。只有满足入场条件且仍有活跃容量的模板会参与；不要只把测试概率改到100就当作正式数值。

## 模板和成员

| 字段 | 填写与边界 |
| --- | --- |
| version/template_id/enabled/placeholder | 当前格式version=1；只有原创测试占位设placeholder=true。正式作品模板不得借此跳过来源字段。 |
| source_work/reference_note | 原作品名与策划备注，仅本地来源信息；占位source_work为空。不要放进玩家可见背景、口头禅、问题或对白。 |
| rarity/background | rarity为rare或epic；background是改写后的简体背景。稀有度保存为分类，不凭名称隐含额外概率。 |
| members | 任意成员数，key唯一；本轮占位3人。不要自行添加作品内容到占位。 |
| relationships/member_goals/entry_conditions | 分别定义完整图、初始问题与入场门槛，见下文。 |

成员必须填写`key、reference_character、name、role、birthday、mbti、personality、personality_text、generation、background、preferences、speech_style、catchphrase、information_boundaries、appearance、easter_egg_items`。

- `reference_character`只记原角色供策划审核，原创占位为空；`name`是改写后简体姓名。模型拿到改写后的必要公开身份，不能看到原名或原作台词。
- `birthday`用有效`YYYY-MM-DD`，沿用现有人物日期范围1902–2050；`mbti`取现有16种技术枚举，`personality`取templates.json性格ID，`personality_text`填写改写后的自然性格。
- `speech_style`描述口吻，`catchphrase`可为空，`information_boundaries`是至少一条**改写后的公开边界**。写“只谈自己知道的近况”，不要写“不能透露原作某角色叫某名字”，后者自身已泄露来源。
- `appearance`是完整A4 version2十层部件／三组颜色／年龄键，参考占位与appearance_parts.json。新固定值必须满足新选择互斥，例如帽子与高马尾；不能新增旧preset或让模型填部件ID。旧档已有合法外观不因新选择规则而重抽。
- `preferences`至少一条自然偏好；`easter_egg_items`可空，非空必须指向已有catalog物品ID。登记彩蛋物件不等于自动发奖，发放仍须有真实G3效果来源。

## 关系、问题与揭示

边格式是`{key,from_key,to_key,kind,closeness,tension}`：两端指已声明的不同成员，closeness为0–100整数，tension为0–100有限数值。边key唯一，不依赖成员数组前两项；三人可以完整声明三条边。G3的npc_relationship效果修改实际实例边，重复effect/action不重复结算；tension本轮只保存初值，未实现张力结算。

每个成员必须恰有一个初始问题：`{key,owner_key,subject_key,relationship_key,kind:"reconnect",question,source:{kind:"authored_initial"}}`。owner和subject均须为所指边的端点；question为简体自然问句，不能泄露未披露事实。程序将本地key映射为该存档实例ID，模型不能猜rel_id或自由修改关系。

完整图一次实例化并存入同一保存事务，成员按政策分批出场。到门不等于相识，真正开始接待才记introduced；档案只显示已见成员和已揭示关系。关系变化不等于已向玩家披露。没有明确动作／结果来源的目标保持open，不以一次交谈冒充完成的任务追踪。

新成员开场保留自己的问题，再按`policy.copy.family_opening_relation`说明自己与问题对象的关系，只揭示该问题指向的一条边。该记录是绑定已保存接待动作与开场对白的**顾客陈述**，不把其他边一并公开，也不标为已核实的世界事实。模板中的subject_name与relationship_kind占位符必须保留；不要在句式里添加作品来源。

## 入场条件与客流预算

`entry_conditions`填写`min_day、min_reputation、required_spells、trust_requirements:[{npc_id,min_trust}]`。术式必须已存在；信任前置只读已知人物，不会为了满足条件创建人或关系。评估输入只有日期、口碑、已学术式和必要的已知信任，不传整个世界包。

前置人物若是另一家族成员，不要预写含本局存档域的实际npc_id；使用稳定引用`family:<template_id>:<member_key>`放在该条件的npc_id字段，例如`family:family_placeholder:first`。运行时只为已经相识的对应成员提供该信任键，未相识或信任不足均不能满足；普通固定人物仍可用原npc_id。此别名只用于本地条件判断，不显示或发给对话模型。

政策分开配置触发率、最大活跃家族数、每家族每日／同时段新成员上限、slot分钟、首个时刻和特殊回访率。当前活跃定义为仍有未相识成员或首次接待待办；所有成员已相识后释放新家族槽，回访仍沿用同一npc_id及普通预约／冷却机制。

默认特殊**实际到店**占比上限12%，首次、回访、预约、介绍采用同一口径。只在物理到达时计数，未来普通计划不充当分母；1特殊+7普通是12.5%，不能当作12%内。预约预算R与实际S/T分开，新承诺前按保守余量预留；不能先确认预约、到点再静默取消。旧已确认预约的ID、时间和同意来源优先保留，无法恢复的历史统计以明确legacy基线／例外说明，不编造过去。

同一arrival_id可能被现有预约机制复用，物理计数按`[arrival_id,at]`这一episode去重：同一动作重试不累加，下一次真实到门可以再计。修改模板或读取存档都不能增加触发／到店计数。迁移后的统计窗口与旧累计数分开，报表不得暗称覆盖完整旧历史。

## 对白保护与验证

来源字段、完整图、编辑备注、原作角色名和屏蔽原文都不进入生成／分类／审核模型的HTTP请求；本地策略可用它们拒绝不合格输出，但不向模型发送词表。改写后的公开人设只能在已认识且允许谈论的范围内投影。不得把删词后的候选当作原已审核内容继续结算。

正式启用前至少验证：三人分批、三条边变化、条件与容量、实际特殊比例含回访、旧demo迁移、失败保存／重试／重开、双端禁词与真实HTTP请求不泄漏。测试占位与合成禁词不代表对任意模型输出的绝对保证。所有状态变更经GameState.execute_action_async，成功写盘后才更新界面；最终执行记录与未完成项见codex/plans/G2.md。
