# HDR 图像工具：平台可行性研究

日期：2026-10-29。状态：需求研究依据；本报告的证据等级是公开资料核实，后续实施与实测见[任务记录](../agent/tasks/2026-10-29-hdr-core/progress.md)。仅查询公开资料，未上传代码或图像，未使用云开发。

## 结论与建议

**用户已确认原生 iOS 路线。** Apple 已有公开的 HDR 静态图像读写、显示、GainMap 处理链路；iOS 18+ 可简化 Adaptive HDR 支持，已作为首轮工程基线。用户另确认 SDR→HDR 采用选择性高光增强，HDR 输出峰值默认 203 nit、最高 600 nit；PQ 输出需要 PNG/TIFF。目标为 iPhone 16 与 macOS「预览」；手机 iOS 版本和电视路径尚未提供。微信比较仅保留为平台选择研究记录。

## 官方依据

| 主题 | 已取得的依据 | 对项目的含义 |
| --- | --- | --- |
| HDR 读取、显示 | Apple 官方示例要求 iOS 17+，示例采用 `CIImageOption.expandToHDR`、`UIImageView.preferredImageDynamicRange = .high`，并演示保存 10-bit HEIC。[Apple 示例](https://developer.apple.com/documentation/uikit/supporting-hdr-images-in-your-app) | 系统提供基础链路；示例可用不等于本项目所有输入格式都已经验证。 |
| GainMap 与 PQ 导出 | WWDC23 说明 `expandToHDR` 合成 GainMap HDR；建议用 `writeHEIF10Representation` 和 HDR 色彩空间写 HEIF。[WWDC23](https://developer.apple.com/videos/play/wwdc2023/10181/) | GainMap→PQ 应先依据原元数据重建 HDR，再编码输出，不能只改扩展名或色彩标签。 |
| Adaptive HDR | WWDC24 说明 iOS 18 转向 Adaptive HDR，支持 SDR/HDR 双表观、读取 GainMap、以 SDR+HDR 或 SDR+GainMap 写入；HDR 单表观可保存为 PQ 10-bit HEIF。[WWDC24](https://developer.apple.com/videos/play/wwdc2024/10177/) | iOS 18+ 是合理候选。需要区分旧 Apple GainMap、新 Adaptive HDR 和外部 GainMap 方言。 |
| 标准状态 | ISO 21496-1:2025 已于 2025-07 发布，规定动态范围转换用 GainMap 与元数据。[ISO 标准页](https://www.iso.org/standard/86775.html) | 不应沿用 2024 演讲中“尚为草案”的当前时态，也不能把所有历史 GainMap 都等同于该正式标准。 |
| Adobe/Ultra HDR | Ultra HDR v1 使用 Adobe `hdr-gain-map/1.0` XMP；Google 文档解释其与 ISO 元数据可共存，并建议双格式以提高跨平台兼容。[Google 官方格式说明](https://developer.android.com/media/platform/hdr-image-format) | “支持 GainMap”必须列出具体来源和元数据种类。首版不宜承诺兼容所有 Google/Adobe/Apple 文件。 |
| 显示亮度限制 | `currentEDRHeadroom` 是屏幕当前最亮白相对于 SDR 白的比值，可随配置和 EDR 内容变化；最大余量另由 `potentialEDRHeadroom` 提供。[当前余量](https://developer.apple.com/documentation/uikit/uiscreen/currentedrheadroom)、[最大余量](https://developer.apple.com/documentation/uikit/uiscreen/potentialedrheadroom) | 应显示实际可用 HDR 余量，并为余量不足提供映射；内容设为 600 nit 不等于屏幕保证物理输出 600 nit。 |
| PQ 与工作空间 | Apple 提供 `CGColorSpace.itur_2100_PQ`；扩展线性 Display P3 则供线性处理。[PQ 空间](https://developer.apple.com/documentation/coregraphics/cgcolorspace/itur_2100_pq)、[扩展线性 P3](https://developer.apple.com/documentation/coregraphics/cgcolorspace/extendedlineardisplayp3) | PQ 是传递函数，HEIF/HEIC 是容器/编码选择；输出规格还需固定色域、位深、亮度映射与元数据。 |

## 微信小程序：证据缺口

尝试访问官方 [wx.canvasToTempFilePath](https://developers.weixin.qq.com/miniprogram/dev/api/canvas/wx.canvasToTempFilePath.html) 和 [wx.compressImage](https://developers.weixin.qq.com/miniprogram/dev/api/media/image/wx.compressImage.html)，本轮网页抓取失败。搜索可见镜像对 Canvas 导出给出 JPG/PNG，但镜像不能作为本次官方核实结果，因此这里不把它升级为已确认平台限制。

本轮未核实小程序具有可选 10-bit/浮点画布、PQ/ICC HDR 输出、GainMap 辅助图原样获取、EDR headroom 控制的官方接口。若用户选择小程序，应先做本地真机能力探针，确认导入是否转换 HEIC、是否丢 GainMap，及显示/导出是否仍有 HDR 信息；在此之前，HDR/XDR 全链路列为研究项。读取/预览某种文件成功不能证明具有该格式的编码导出能力。

## 已确认的 203 与 600 nit 语义

ITU-R BT.2408-9（2026）将 203 cd/m² 用作标称 HDR Reference White，并讨论 100 与 203 cd/m² SDR 工作流。它不是所有 SDR 图片自带的普适物理峰值；对常见相对编码 SDR 图片，这是转换时指定的参考映射条件。[ITU-R BT.2408-9](https://www.itu.int/dms_pub/itu-r/opb/rep/R-REP-BT.2408-9-2026-PDF-E.pdf)

用户已明确这是 **HDR 输出目标峰值**：默认 203 nit、最高 600 nit，并选择高光增强，而非全图等比例提亮。若选用 203 nit 作为固定参考白，则默认峰值等于参考白，没有高于参考白的 HDR 余量；升至 600 nit 时，峰值/参考白约 2.96，约 1.56 stops。这是参数含义的结果，应在预览及说明中体现，不再把峰值语义列为待确认问题。

高光阈值、过渡曲线与肤色/中间调保护仍需通过样图调试。上述数值是内容编码/映射参数，不是设备亮度滑块。增强不能保证恢复输入中已经剪切或量化丢失的高光细节。

## PQ PNG/TIFF：已确认输出范围与兼容性边界

Apple 在 WWDC23 明确给出 HDR PNG 与 TIFF 写入路线：向 `CIContext.writePNGRepresentation` 或 `writeTIFFRepresentation` 传入 HDR 色彩空间，并请求 `.RGBA16`。这支持把 **16-bit BT.2020/PQ PNG、TIFF** 列为技术验证目标；HEIF 只作参考输出，不替代用户要求。[Apple 官方说明](https://developer.apple.com/videos/play/wwdc2023/10181/)、[CIContext API 列表](https://developer.apple.com/documentation/coreimage/cicontext)

PNG 第三版已经是 W3C Recommendation，明确支持 `cICP` 表述原色、传递函数、矩阵和量程；BT.2100 PQ 全范围 RGB 示例为十六进制 `09 10 00 01`，即十进制 `9,16,0,1`。规范规定读取器理解 cICP 时，它优先于 iCCP。文件应具有一致的 BT.2020/PQ 像素与色彩标识，不能标为 SDR sRGB。[PNG 第三版 §11.3.2.6](https://www.w3.org/TR/png-3/#11cICP)

**Apple API 能写 HDR PNG，不证明指定 iOS 版本会自动输出目标 cICP chunk。** 必须检查实际文件结构、16-bit 深度、PQ/色域标识及参考白/峰值表达。如系统仅写 ICC，应评估是否需要补入一致的 cICP；在实测前不能宣称已具备规范完整的跨平台 PQ PNG 输出。

TIFF 可嵌入 ICC Profile（tag 34675）；ICC 规范同时指出 Baseline TIFF 读取器不必读取这个 tag。因此 16-bit TIFF 加 PQ 色彩描述仅说明文件可携带数据，不保证目标软件会识别其 HDR 含义或采用 EDR 输出。[ICC.1:2010 附录 B.3](https://www.color.org/specification/ICC1v43_2010-12.pdf)

**电脑/电视兼容性须逐条验证，不以“文件可打开”或 Apple 自家照片显示正常作为通过。** 电视 USB 图片浏览、电脑查看器、HDMI 输出链路是不同路径；本轮没有取得用户具体目标设备的支持证据，不承诺任意电视能以 HDR 显示 PNG/TIFF。验收清单应记录设备型号、固件/OS、查看器版本、导入方式、HDR 模式及实际效果。PNG/TIFF 保留高位深时文件通常较大，不能承诺可用有损“质量”滑块控制到任意目标大小。

## 开发前的最小验证门槛

- 固定目标 iOS 版本和一台支持 HDR 的 iPhone；在实际 Xcode SDK 编译确认所用 API availability。本文没有运行 SDK 编译或真机程序。
- 准备有明确来源的旧 Apple GainMap、新 ISO/Adaptive HDR、PQ HEIF 样本；仅本地处理。
- 验证原始文件导入、HDR/SDR/GainMap 三视图，以及 **16-bit BT.2020/PQ PNG 与 TIFF 导出再导入**；检查方向、ICC/色彩描述、PNG cICP、位深和亮度范围。另以 PQ HEIF 作参考。GainMap 保留测试与已烘焙成单表观 PQ 的导出测试分开；后者不默认保留原始 GainMap。区分原始 SDR 基图与 HDR 的自动色调映射 SDR 预览。
- 用 203、最高 600 nit 及至少一个中间峰值验证高光增强；检查峰值上限、中间调/肤色变化和渐变连续性，不把默认 203 nit 宣传为具有超过 203 nit 的高光。
- 已指定 macOS「预览」为首轮电脑读取目标；未来若纳入电视，须另定播放路径并验证。查看器文件识别与实际显示 HDR 亮度分别记录。
- 真机比较应用与系统照片显示；检查可用 EDR 余量变化后的降级。截图、模拟器和 SDR 屏幕不作为实际 XDR 效果的充分证据。
- 外部 Adobe/Ultra HDR 方言、BMP 的实际编码支持、所有机型/系统和分享到微信后的元数据保留，均未验证，按需求优先级逐项验证。

## 研究限制

本报告自身为公开一手资料核实，不作为格式实样测试、SDK 编译、文件读写或真机亮度测量报告。ISO 引用仅使用公开摘要/预览，不声称已审阅付费规范全文。后续本地测试和构建已有独立报告；真机亮度仍未测量。
