# R3-LIN：林照晚固定A4组合

前置STORY已以6d4e95c完成提交并推送，正式应用前已核基线SHA，按12文件/19个唯一上下文hunk合入生产。当前实装完成，进入实际GPU与标准完整测试验收；不再以隔离草稿覆盖生产。

从现有A4部件选固定组合：hair_front_02、hair_back_10长后发、eyes_01柔和杏眼、outfit_02工作围裙，hair_02深棕、outfit_01鼠尾草、skin_02暖杏；其余沿用合法adult/body/face/brows/mouth，accessory=none。完整ID写data/story/npcs.json的Lin档案并经既有校验，组合不依save_id抽取，不生成新图。

新档在new_game的fresh candidate明确写入固定parts，保存失败不预显，同ID重试/重放不换脸。现有结构已支持A4 v2，保持schema12且不新增持久标记。公共档案按明确已有字段保持来源；本任务聚焦外观，不改原invitation事实/事件/反馈/推荐和人物关系、信任、出生资料。

旧档里的两个合法Lin旧preset保留读取和原存档字段；在统一公开/显示适配处映射为固定A4，不再把旧手绘路径交给沙发、气泡、档案或legacy前台。已有合法parts保持，不重抽。旧PNG与preset登记保留以读旧档。去掉shop_front直接加载旧Lin图片的入口，复用现有Portrait组件；避免只替沙发而漏掉前台或档案。

日程维持每个新档第1天第1位npc_lin、原invitation与fixed_invitation定义hash。所有持久变化在已有execute_action_async新档事务中；公共显示适配只读，不写旧档。

验证先RED后GREEN：至少两个独立新档的第一位、案件、固定组合、五态A4路径一致；写入失败/同ID重试/重放/重载、旧preset与旧parts源字节及身份/关系/事件保留；咨询坐姿/沙发遮罩、气泡、档案、legacy前台均不使用旧Lin PNG。回归原邀请金样本与推荐。双尺寸1280×720、1920×1080合成实看，最多6JPG；shop_ui实际GPU和标准全测最多3轮，更新features/PROGRESS/审阅包后普通push，main不动。
