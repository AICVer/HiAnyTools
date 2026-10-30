# R1–R8 顺序实施与红蓝军门禁

日期：2026-10-29。用户本轮明确要求按 R1→R8 顺序，每完成两项进行一轮红蓝军对抗测试，通过才进入下一对。

## 角色与数据

- 蓝军：主代理，实施、功能测试、修复与构建。
- 红军：独立测试子代理，只写独立攻击测试与报告；针对冻结文件哈希复现问题，蓝军修复后重新冻结并复测。
- 测试源：用户指定本地 Gainmap 目录，524 张图像；源文件只读，SHA256 记录，输出只写本项目 output；代码和图像不上传。
- 工作区原有 .DS_Store/微信子项目修改保留，不提交、推送 Git，不修改 .env 或安装依赖。
- 已读取 context、规格、知识库协作流程与 K06/K10/公共编码规范；采用格式/像素/显示与证据分级的区分。

## 门禁

| 组 | 范围 | 状态 | 进入下一组条件 |
| --- | --- | --- | --- |
| 1 | R1 普通格式 + R2 导出参数 | PASS | 红军30项、蓝军87项、实际模拟器导入/DPI/JPEG、构建通过，报告 red-blue-01.md |
| 2 | R3 HDR 可视化 + R4 EDR 显示 | PASS | 红军首次2失败后修复，同断言24项复测通过；蓝军94项/构建通过，red-blue-02.md |
| 3 | R5 HDR 转换 + R6 SDR→HDR | PASS | 红军32项、蓝军104项、构建通过，red-blue-03.md |
| 4 | R7 直方图 + R8 三视图 | PASS | 红军19项、最终全量232项及七通道/三视图/切图界面验证通过，red-blue-04.md |

## 本轮决策

- R2 已确认：保持指定像素尺寸，只搜索编码质量；达不到文件上限则明确报错，不自动缩小。
- R2 实现参数：质量上限 0…1，DPI 1…2400（只改密度），宽/高择一按比例，目标体积按实际编码后字节检查；JPEG/HEIC 搜索质量，无损格式只校验体积。HDR PNG/TIFF 共用尺寸/DPI/体积参数。
- R7 已确认：HDR RGB/线性 BT.2020 与 Y/nit，HSV/SDR sRGB 表观，标记统计域与采样。
- R4 已确认：代码/数值/模拟器门禁通过后继续 R5–R8，真机 XDR 单列待验收，不阻塞后续软件实现。

## 当前证据

- R2 共用写出链路接入后，既有 58 项 HDR/R1 回归通过，report-test8-baseline.txt。
- 新增 ExportOptions、质量搜索/体积校验、SDR 与 PQ 导出参数、UI 控件；蓝军 R2 29 项、全量 87 项通过，iOS 模拟器构建通过。
- 红军首轮 29 项已过；补独立 P3/LittleCMS+colour-science 对照后最终30项在冻结快照通过（12.76s）。子代理后续 escalation 审批两次超时，由主代理原样代跑、红军独立判读，不降低门槛。
- 模拟器实际操作：iPhone17/iOS27，PhotosPicker 选择960×640 SDR色阶，DPI填300，点击生成SDR JPEG，出现保存/分享入口；模拟器软件链路已验证，物理亮度不在此证据内。
- 红军独立文件结构筛选已发现 P3 SDR、透明 sRGB PNG、PQ PNG/AVIF、Apple/ISO/Adobe GainMap；manifest 位于 output/red-team/corpus-candidates.json。
- 第一组独立跨CMM P3核对平均ΔE00=0.12389、P95=0.68139，满足mean<1/P95<3；冻结哈希与正式PASS结论见 ../../../tests/red-blue-01.md。
- 第二组发现两项P1：CGImage无内容余量标记导致可能不参加系统tone-map；ImageIO展开GainMap/读属性后把JPEG内部表示误报HEIC。最终分别用GPU最大值归约+CGImage显式headroom、独立增量文件头识别修复。红军原24项不降断言复测通过，真实JPEG标签恢复且PQ超白仍在；源码快照与失败/修复链见red-blue-02.md。
- 第二组补充真实iOS界面：通过PhotosPicker导入1500×1000真实PQ PNG，显示PNG/PQ HDR、内容余量10.41×、屏幕1.00×、系统映射提示，增强滑块禁用。simctl相册不接受AVIF；AVIF仍走文件引擎测试，未把相册系统限制误说成App解码失败。
- 第三组新增HDRPNG标准cLLI写入（系统zlib CRC，无新增包）、最终量化像素maxRGB最大/平均光级、字节上限包含元数据；HDR非法峰值统一拒绝，Alpha回读保持。参考W3C PNG3与MovieLabs/CTA算法。
- 第三组首次32项中PQ AVIF两项失败：native工作域峰值10175nit不能原样保留到PQ10000nit编码。独立ffmpeg gbrp10le证明原始RGBW只有0/1023；红军保持0.5%容差，仅把参考投影到PQ合法域，保留首次失败与修正证据。UI增加系统解码分量越界提示。复测32项已过，蓝军104项/构建通过，等待红军正式结论。
- 第三组正式PASS已由红军独立判定，允许进入第四组；外部viewer是否采用标准cLLI仍单列边界，不承诺其物理显示映射。
- 第四组新增 Histogram.swift：RGB/Y为编码前HDR工作图（线性BT2020、1=203nit），HSV为源SDR sRGB8表观，默认最长边512，256 bins；透明排除、灰色H undefined、负/超范围计入独立计数。蓝军17新增/全量121项通过。
- R8新增图片importGeneration/Actor latestGeneration拒旧、Photo异步取数后校验、busy只由本代清除、preview/statistics requestKey条件展示、取消/CPU循环检查。红军时序审阅发现busy跳过新preview导致永久空白的活性风险，已移除该跳过，并把分享URL失效移到真实参数变化，不因模式切换清除有效文件。
- 第四组首轮19项：18通过、1失败。真实双GainMap JPEG的SDR表观与独立Pillow+LittleCMS主图参考meanΔE00=1.24326/P95=3.46292，超过固定mean<1/P95<3；保持门禁未放行。
- 首轮定位记录：原GainMap与普通sdrOriginal的ICC字节完全相同；CG Data-source默认/显式SDR/关luma与CIData tone开关五变体输出均相同且未改善；诊断代码/输出位于output/sdr-diagnosis.swift、output/sdr-variants/。显式源ICC两个变体已生成，红军独立核对中；还需确认primary是否确为SDR以及Native适配路径是否改了原基图。
- 首轮诊断阶段未改生产或降低红军阈值，原图只读；后续修复与最终结论如下。
- 后续状态、阻断问题、修复与门禁结论随每组报告记录；没有将未运行测试或真机显示描述为通过。

## 最终交付（2026-10-30）

- 第四组主图缺陷已修复：新增 JPEGPrimary 按真实 JPEG 分段隔离 SDR 主图辅助标记，保留 ICC/EXIF/扫描码流，HDR 重建仍读取原文件。原 mean<1/P95<3 门槛下恢复为 0.123513/0.681387；红军19项复测通过，新增6项解析边界测试。
- 最终显式蓝红军回归232项通过（127+105）；核心行覆盖率95.68%、区域84.75%、函数91.30%，UI不计入且无分支指标。设备无签名与模拟器构建通过，日志见 ../../../tests/report-test12.txt。
- 最后实际模拟器验收：七通道/对数切换、HDR RGB/Y与SDR HSV标签、H无定义色相、峰值更新与PQ生成/分享保持；64×64 GainMap三模式切换，再回960×640 SDR仅两模式，统计从4096恢复174592，旧分享入口清空。
- Device Hub窗口中途失联，用户明确允许重开后补齐R/H图表截图与AX，存于 output/tests/gate4-*。红军独立复核并关闭第四组软件门禁。
- R1–R8四组软件门禁全部通过。当前原生iOS测试版可在本机模拟器试用；真机Team签名/安装、iPhone16物理XDR、性能/内存及其他显示路径仍待验收。源码未在最终回归后改动；本次仅补证据、需求/上下文/报告/变更日志，无Git提交推送。
