# R5/R6 红蓝军对抗测试

日期：2026-10-30。**最终软件门禁 Gate 3：PASS，可进入 R7/R8。** 首轮2项未通过、30项通过；独立codec证明原峰值参考忽略了PQ 10000nit上限。依据标准修正参考域后，保持原0.5%容差，最终32项全部通过。此处不把测试真值更正伪称为生产算法修复，也不宣称外部查看器/真机物理效果已验收。

## 独立验证范围

- 7 类真实输入（PQ PNG/AVIF/HEIC、Apple GainMap HEIC、Adaptive HDR HEIC、双元数据与 Adobe GainMap JPEG）分别导出 PQ PNG/TIFF，共14项。
- 输出按原始 magic/metadata 检查容器、16位、HDR、无原 GainMap 辅助图；PNG cICP 必须为 `9/16/0/1`；源文件 SHA-256 保持。
- ≤1500像素宽的小样本按原尺寸转换，对原/输出64px采样的 peak、meanY 设0.5%量化与变换容差；peak参考须在PQ合法0..10000nit范围。大图缩至512宽控制测试内存/磁盘，只核对几何、超白与近似 meanY（10%），不把合理重采样导致的局部峰值变化当作缺陷。
- SDR 白在203/400/600 nit的16位PNG真实码值，使用 colour-science 的 ST 2084 独立对照；编码容差5e-5，反解亮度容差0.4 nit。
- 灰阶暗部恒等、跨0.5线性亮区起点的单调性、峰值上限、非灰色RGB比例、半透明/全透明、非法峰值。
- 原始1000nit HDR在203nit滑块参数下导出仍保持>990nit，不误套用SDR增强上限。
- PNG cLLI：所有chunk CRC、两个uint32大端/0.0001nit量纲、从实际16位码值独立反解MaxCLL与mean(maxRGB)；红绿非灰样本区别mean(Y)/mean(RGB)的错误做法；纯黑不误用203nit参考白作峰值；最终目标字节上限包含新chunk。

工程容差来自最终16位量化、float误差及采样插值边界，不代表真实显示器的校准或通用主观画质阈值。

## 执行约定

命令：`/Users/wangshupeng/miniforge3/bin/conda run --no-capture-output -n base python -m pytest -q tests/red_team_r5_r6.py`。主代理可在本机图形权限下代运行冻结脚本；红军独立读取输出、源/结果摘要、冻结前后哈希做判定。

R5/R6 通过后才能进入 R7/R8；真机XDR仍按用户确认单列待验收。

PNG cLLI 属标准光级元数据；TIFF 没有同等通用的 cLLI 字段，本组不伪造通用viewer兼容承诺，仍验证16位/PQ/ICC与像素数据，外部查看器默认映射的限制单列说明。

## 首轮结果与独立定位

主代理运行、红军独立读取 `output/red-team/round3-run.txt`：**2 failed, 30 passed in 15.58s**。首次日志与快照另存 `round3-first-run.txt`、`round3/snapshot-first.json`，测试源码 SHA-256 `865b07b4f2b28db384a2c9bb52ecfb7993f4537bb8a2ac9ac00b4f6bd09774e0`。

两个失败的共同数值：原生工作域采样 maxRGB=50.123363，而输出=49.261086，相对变化1.72%，超过预设0.5%。但乘203参考白后，前者约10175nit，后者约10000nit，后者恰为 ST 2084 码值1的物理编码上限。

红军随后独立核查该 AVIF，而不是降低容差：

- ffprobe：`gbrp10le`、full range、BT.2020、ST 2084。
- ffmpeg 以原始 `gbrp10le` 输出 RGBW 4块数据，所有分量只取0或1023，最大码值1023，未包含超范围码。
- Pillow 解得四块标准红/绿/蓝/白，与 codec 结果一致。
- colour-science ST2084 对 `1023/1023` 反解为10000nit；原生工作域中超出该值的RGB分量来自解码/变换链，不是原文件能够以PQ合法码值存储的更高峰值。

独立证据：`output/red-team/round3/avif-independent-stream.json`、`avif-independent-codes.json`。已有输出PNG的原始16位码值核对在 `png-independent-codes.json`，最大码值为1.0，处于合法范围。

蓝军明确同意将参考峰值改为 `min(max(0, sourceMax), 10000/203)`，保留原0.5%精度阈值；meanY 首轮没有失败，维持原断言。旧32项脚本保存于 `round3/red_team_r5_r6-first-frozen.py`，当前脚本只修正此参考真值，不降低精度。生产代码既有的上限行为已通过界面/Probe明确表达为解码工作域超出PQ范围，不伪称原文件包含非法码值，随后完成下列冻结复测。

## 最终复测与冻结

主代理执行、红军独立读取 `output/red-team/round3-retest.txt`：**32 passed in 14.02s**。`output/red-team/round3/snapshot.json` 的生产/Probe五文件执行前后摘要一致。

| 文件 | SHA-256 |
| --- | --- |
| Sources/ImageEngine.swift | b42f9752b4b2872f5993a71795bdb3bab0d965ca9baa9c1260e4ed2a0902c5de |
| Sources/ExportOptions.swift | 6e3de64f0268c22f7a61a6fd8cbab4a35489aa7e88a8a742a1062f6fec0869d0 |
| Sources/HDRPNG.swift | f5edf8d51d20d60250de94b867dbbf4c04b69a0e65aff1b6f6217c5dcc589807 |
| Sources/HDRImageLabApp.swift | 2df1a323b0689db9e2cca102b954d8f8dc9736ae24ae2f5f0393b8ba55a90c49 |
| tests/Probe.swift | dd9fa7b69ff25c7e2485187388a35973ef07eab553577e5b88b1ce3088353afc |
| tests/red_team_r5_r6.py | 3dfb47b8108c0c3e513245812cb83f114b5fc07eed51ceeb614701a6ae6f047d |

峰值边界复核：PQ AVIF源工作域maxRGB=50.123363，输出=49.261086，恰等于10000/203；输出解码峰值10000.00036nit，浮点误差边界内。meanY从24.680634到24.579441，变化约0.410%，仍满足原0.5%容差。

真实双GainMap JPEG→PQ PNG：采样maxRGB从7.395436到7.404648，meanY从0.696374到0.695190，均在0.5%内；原始GainMap已烘焙成单层PQ，类型/位深/cICP正确。

6项cLLI专项全部通过，含3个峰值的独立CRC/量纲/量化后亮度验证、红绿图明确区分mean(maxRGB)与meanY、纯黑不误填参考白、最终字节上限包含新chunk。新增元数据不会静默绕过R2体积上限。

蓝军104项全量回归通过（`docs/tests/report-test10-blue-all.txt`），iOS模拟器构建通过（`report-test10-build.txt`）；红军已直接读取原始通过日志。

## 保留的边界

- PNG cLLI符合标准并有独立字节级验证，不等同所有查看器一定采用该信息；本次 native CIImage 回读仍可能报告默认4.926余量，而实际像素高于此值，本App依实际像素峰值处理。外部 macOS「预览」的具体色调映射效果仍需实测。
- TIFF无统一cLLI字段，按已公开的16位/PQ/ICC和像素保真边界交付，不承诺所有第三方viewer行为相同。
- R4实际iPhone 16/XDR与用户主观画质验收仍待设备，不因本门禁通过自动关闭。
