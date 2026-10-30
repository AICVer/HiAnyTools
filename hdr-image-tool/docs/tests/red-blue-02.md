# R3/R4 红蓝军对抗测试

日期：2026-10-30。**最终软件门禁 Gate 2：PASS，可进入 R5/R6。** 首轮 2 项失败、22 项通过；蓝军修复容器误标后，同一组未放宽断言的 24 项全部通过。两项 P1 均有复测关闭证据，不代表 iPhone 16 真实 XDR 已验收。

范围：真实 SDR、PQ PNG/AVIF/HEIC、Apple GainMap HEIC、ISO Adaptive HDR HEIC、双元数据 GainMap JPEG、Adobe Ultra HDR JPEG。独立文件结构确认的编码/标记及 SHA-256 见 `output/red-team/corpus-candidates.json`；最终再由 ImageIO 元数据、扩展线性像素和返回预览 CGImage 交叉核对。

## 软件门禁

- 真实文件 HDR/GainMap 分类与编码一致，读取不修改原文件。
- 已知具有超参考白信息的 HDR 样本，重建/解码的扩展线性 RGB 保持 >1 值。
- HDR 预览为 16 位浮点扩展线性表面，明确携带 >1 的 contentHeadroom，采样超白像素仍在；长边不超过 2048。
- SDR 预览使用独立 8 位表面，亮度不超 SDR 范围。
- 为 SDR 请求 HDR 预览并增强，不把原图元数据或原始 HDR 分类永久改写。
- 原始文件头与 UI/Probe 的容器类型一致；JPEG 的 SOI 不能因为 HDR 内部表示变化被误报为 HEIC。
- iOS 18+ availability 编译与 UIImageView 高动态范围显示由蓝军提供构建/模拟器证据；不得把无 headroom 的 CGImage 或普通 8 位截图当作真实 XDR 证明。

测试命令：`/Users/wangshupeng/miniforge3/bin/conda run --no-capture-output -n base python -m pytest -q tests/red_team_r3_r4.py`。渲染需本机图形服务；若子代理自动审批超时，可由主代理执行相同冻结用例，红军独立读取原始产物判定。

首轮由主代理执行，红军独立读取：`output/red-team/round2-run.txt`，**2 failed, 22 passed in 13.69s**。首轮生产四文件 before/after 一致，见 `output/red-team/round2/snapshot-first.json`。

首轮日志另存 `output/red-team/round2-first-run.txt`，旧快照另存 `output/red-team/round2/snapshot-first.json`。最终复测：`output/red-team/round2-retest.txt`，**24 passed in 10.63s**；红军独立读取该结果和新的 before/after，确认完全一致。

| 冻结文件 | SHA-256 |
| --- | --- |
| ImageEngine.swift | 69dd15da01358303c20a5d5ada589899ab0dac49bd667df50b6585d553643026 |
| ExportOptions.swift | 6e3de64f0268c22f7a61a6fd8cbab4a35489aa7e88a8a742a1062f6fec0869d0 |
| HDRImageLabApp.swift | 5445e7726b78733df1e1e55d441892347feabb96840b8cfc94a32a9a094bc2bf |
| Probe.swift | 72e2f7fb58ab1acd6b77734c91f5dadb299d503b562ca8ea7447cd4ded15efd8 |

最终有效快照（两项未变文件沿用上表）：

| 文件 | SHA-256 |
| --- | --- |
| ImageEngine.swift | 6ebfac86836e17446fb075d4d11184e35c848009853ccbbd6117fdacf65c9dcf |
| Probe.swift | 29fc605b2c4484abe1f2d3f67785a718292836be268179f36a2add72e6a440fa |
| tests/red_team_r3_r4.py | 1e93add18921bc53062f10183c190a41f56258bda187deffe93d7d5ef19dd595 |

## 冻结前发现与修复目标

- P1，已在最终冻结关闭：ImageIO/CIImage 展开 HDR 后，原 JPEG 的 URL source 类型可能变成 `public.heic`。红军独立读到 `gainMap.jpg` 和 Ultra HDR 01 的文件头均为 `ffd8ffe1`，Pillow 也按 JPEG 读取；小复现显示 before=`public.jpeg`、after=`public.heic`、CreateWithData=`public.jpeg`。首次蓝军把捕获提前到辅助图操作之前，但仍在 CopyProperties 之后，复测仍误标。最终生产代码使用独立 incremental source 读取原文件前 65536 字节识别容器；Probe 原始类型提前到 properties 之前捕获。最终两个文件的 type/rawContainerType 均恢复 `public.jpeg`，与原始 magic 一致，不依赖文件扩展名，且 HDR/GainMap 分类仍正确。
- P1，已在本冻结验证修复：PQ-RGBW.avif 默认 contentHeadroom=4.926，而实际采样 maxRGB=50.123。蓝军改为 CIAreaMaximum 获取实际内容余量并显式标记浮点 CGImage。红军实测预览 headroom=**50.123363**、maxRGB=**50.09375**、16位 extendedLinear ITUR2020，通过 `max(0.01, 0.1%)` 半精度量化容差断言。该项不是把数值截为 SDR 来伪装通过。

## 真机边界

用户已明确同意：通过代码、数值、模拟器软件门槛后继续后两组；iPhone 16 的实际 XDR/物理亮度单列待验收。软件 PASS 不宣称设备达到内容参数标示 nit。

## 蓝军提供的实际模拟器证据

在 iPhone 17/iOS 27.0、第二组冻结构建中，经 PhotosPicker 导入用户真实 PQ PNG（`hdr/b614d537-4817-46fc-9120-498f090161e2.png`）：界面显示 1500×1000、文件格式 PNG / PQ HDR、内容余量 **10.41×**、屏幕余量 **1.00×** 及系统映射提示，SDR 增强滑块禁用。内容余量为全图 GPU 最大值，故高于 Probe 的64px近似采样最大值，二者不是互相矛盾。

系统相册导入 AVIF 时 `simctl addmedia` 返回 File type unsupported，未将其误报为应用解码失败；AVIF 在独立引擎文件读取/预览测试中通过，但没有宣称 iOS 相册选择器支持该导入路径。
