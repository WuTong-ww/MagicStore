# RWS 原版牌面

78 张牌的唯一运行时索引是 `data/oracle/card_art.json`，ID 原样取自 `data/oracle/decks.json`。B 线不改抽牌逻辑或牌面显示界面；C 线按约定读取索引。

来源为 [mixvlad/TarotCards 的固定修订](https://github.com/mixvlad/TarotCards/tree/840b84d012c6b74dc1634fa2d00d1b21f5b28093/tarot/rider-waite)，仅使用 `full-png` 下的 78 张牌，不含两个封套。上游当前元数据写明是 [Steve P. 修复的 1909 Pam-A 扫描](https://steve-p.org/cards/RWSa.html)，不是 Wikimedia 来源；没有使用 U.S. Games 现代重印或 lysator 镜像。作者 Pamela Colman Smith（1878–1951），1909 年 Rider & Company 发行的原始画作；上游将该牌组标为公有领域。上游代码的 MIT 许可证不替代画作的公有领域说明。

每张原图的 Git blob、SHA256、原生尺寸、裁切框和输出 SHA256 记录在 `provenance.json`。原图与下载回执保留在仓库外，不提交。

处理脚本为 `tools/art/rws_cards.py`：只裁掉图案外的多余近白纸边并留 3px 安全边，完整保留原图、黑框、原版标题；饱和度乘 0.9，RGB 乘 1.004/1/0.987 轻微暖色；等比容纳到 360×617，不拉伸也不裁图案。617 是 `360×12/7` 的最近整数。为避免扫描网点缩小后的摩尔纹，固定使用双线性缩小与 0.7 输出像素的抗锯齿滤波，所有图片相同参数。WebP 质量固定 80、编码 method 6，没有为个别图片降质量。

复现：安装 Python、Pillow、NumPy，将上述固定修订的源目录与下载 SHA 回执传给脚本的 `--source` 和 `--receipt`。测试运行 `python tests/art/test_rws_cards.py`，检查实际解码、78 个 ID、360×617、每张 ≤60,000 字节、总计 ≤4,000,000 字节和逐张摘要。
