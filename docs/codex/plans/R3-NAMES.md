# R3-NAMES：程序先确定新人物的地域、姓名和肤色

LIN已以7b09759及META d89e89f完整验收并正常推送。正式NAMES先在真实new_game上取得4检查/3功能缺失的RED，无解析错误；随后按combined/handoff的唯一上下文hunk应用24个owned文件（11既有/13新增），830个非owned源保持。生产已进入schema13核心验收，不再覆盖whole combined镜像。LIN最终UI及新增旧咨询兼容测试保留。实施边界见`.tools/r3-names/implementation-preflight.md`。

`data/people/name_pools.json`保存权重、地域、名字池、格式、肤色范围和有限冲突处理；每个外国地区至少30名和30姓，使用同一命名传统，混合人物用中文姓+音译名。初值local/foreign/mixed=78/20/2，foreign的五地区等权，均为可逆配置。肤色使用已有色板明确ID，允许地区内多样性，不关联职业、性格或事件好坏。地域名为cultural_origin；既有profile.origin仍是生成来源。

纯BirthIdentity选择器使用独立稳定seed。普通生成人物先完整运行原legacy sampler和G4 overlay，再对真正新生主角和关联人加新身份；保持原RNG最终状态和姓名外既有结果。已存在的profile不重抽。新记录有版本、地域、名字池、姓名、肤色，名字与外貌须吻合。旧人物不补造身份，固定剧情人物不参与随机池。各允许名姓组合均须通过已有姓名长度/字符规则，坏配置失败关闭。

在线生成在排队前决定主角和关联人身份，保存于本地job，只将新人物的公开身份约束交模型写故事；不传save_id、seed、路径、旧档私密字段或世界真相。新wire v3明确两人birth_identity及从白名单重算的身份hash；直连、网关、admission均比对本地预选值。换名/换肤色/换地域/交换两人/降级/伪造hash均拒绝，回退也使用原预选身份。外貌描述映射后再锁程序肤色。

v1/v2按明确字段表分派，canonical/hash、离线bundle再现、旧profile本地身份hash保持；不能简单改VERSION常量使旧字段校验失效。新身份记录属于存档结构变化，提升届时schema（预计12→13），迁移只在内存添加未来新生策略门，不改旧名字、外貌、人物来源、已排日程、已处理动作或旧bundle；下一成功动作才写盘。默认顺序模式不重开后台实时生成。

先RED再GREEN覆盖各池≥30、坏配置、全组合长度、固定seed/排重、RNG oracle；新双语言v3金样本和旧两版精确hash；各入口身份篡改拒绝/同身份回退；实际普通主/友、旧档、保存失败/重试/重放/重载。双尺寸实看程序生成外来客与档案，最多六JPG，旧shop_ui实际GPU、标准全测最多三轮。更新features/PROGRESS/审阅包并普通push codex/round3，main不动。

本任务不改职业/生日/关系/固定剧情事实，不让地域控制人物善恶；不通过削弱旧断言或跳过原生成器来保留RNG。

正式接线验证发现两处必要的旧协议入口：GeneratedCases只接受version1，导致合法v3真实入档被拒；DialoguePolicy仍只接受旧8字段/version2，导致正常本地对话设置为空。只追加这两个严格协议gate接线，委托完整GeneratedPerson校验，原G3安装、隐私投影、情绪及家族guard保持；两处都保留真实RED/GREEN，不以宽松membership替代校验。新公开BIRTH错误用独立data/ui/names.json与校验叶转换中文，内部拒绝码不因空文案变成功。

性能先实测后优化：同一批26普通/28总人物的真实保存原为5.23–6.05秒；只加绑定完整resolved内容及真实默认依赖的有界valid-config缓存，嵌套篡改重新拒绝，不改姓名结果或RNG。工作副本复测0.55–0.85秒；人物完整字典保持，仅正常设置/动作回执/版本推进，文件并非完全同大小，不给不实精确倍率。

UI首次素材准备仍按正常权重及真实动作采样，不改seed、人物或存档payload。取得的三组原始保存文件将作为固定回归fixtures（逐字节/SHA、SavedService加载校验）供标准全套复制，避免每次完整测试以随机是否抽中mixed决定成败；producer与实际动作证据保留。所有新fixture JSON有校验，技术ID不显示，六JPG仍来自真实加载和保存失败/重试/重载后的可见档案。

标准前两轮保留真实失败：full1旧followup写死schema12，单项25/1→仅当前schema预期→25/0；full2所有NAMES专项已过，后因合成v3旧档残留出生新字段停止。第三轮前只作确证兼容修复：event/shop的历史投影剥离未来出生字段，traffic先验证新marker再从比较副本移除；旧event_workflows须用完整合法v1人物夹具；旧生成整合mock按真实当前五字段上下文与本地锁定pair给v3回复，保留排序、取消、迟到、保存失败、重试、重放、重载与私密材料检查，并新增首故障真实同身份fallback证据。产品门不放宽，原始旧档不改。第三次标准全套为最后一次；未全绿则准确标部分完成后继续AICASE，不跑第四轮。
