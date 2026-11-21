# A1R 正式文件审计冻结说明

`approved-files.json`、`approved-files.txt` 与逐项预算输出已经冻结。白名单59 PNG未改变；59/59真实PNG、29/29 runtime为1920×1080。按记录HEAD树排除重复后为54个blob、118,461,784 bytes（112.97 MiB）；本地对象库已有style_reference同字节blob的另一个口径是53个、115,956,472 bytes，两者没有混用。预算包含59文件逐项SHA、尺寸和字节归属。

审计第一次观察到两正式根含59批准PNG及1099个加工文件；root随后执行了安全归档。实际索引是 `assets/_incoming/a1r_v3_processing_evidence/relocation-index.jsonl`，1099行、总计1,048,783,624 bytes。本次将索引逐行与原始excluded-processing-files-plan.jsonl核对：原路径、实际新路径、记录SHA和大小均对应；1099个原文件已不在正式根，1099个归档文件存在且大小与索引一致。实际移动与全SHA验证由root执行，本审计未移动任何资产。

`archive-plan.json` 已恢复原1099项历史计划，并明确标记root已执行及实际索引；其中files保留原计划记录的历史status，顶层实际完成状态另列。当前两正式根为 **59批准PNG + 59个Godot .import 设置文件**。这些.import是正式资源设置，保留；`archive-post-import-snapshot.json` 已标记retained_engine_import_settings，不是拒图或待归档列表。

S03/S07 preserve_base 四个原生 B_all 与 C：编码字节不一致（RGB与RGBA），解码RGBA像素完全一致；四对runtime则字节与像素均一致。没有改图或把像素相同误称为字节相同。

冻结的早先预算说明若包含“59侧车归档提案”这一并发快照描述，以本说明及已恢复的archive-plan/post-import-snapshot为准；不执行该侧车归档。
