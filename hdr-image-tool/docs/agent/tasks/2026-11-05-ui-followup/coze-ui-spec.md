# 本轮 SwiftUI 增量（第1批）

继续修改已有原生SwiftUI，不创建Expo/Web替代应用，不部署、不提交Git、不新增依赖。
模型DeepSeek-v4-Pro。用户已明确授权本项目开发及必要代码发送给Coze，不再索取相同授权。

唯一可改文件：Sources/HDRImageLabApp.swift。ImageColorInfo.swift附件只供读取API，不改它；其他源代码不动，不删除已有函数或类型，不顺带重构整个文件。优先edit_file小段修改。

1. 图片状态详情添加“SDR 色域”“HDR 色域”“GainMap 色域”三行，读取info.colorInfo三个字段。新增ImageInfo的最后一个默认字段var colorInfo = ImageColorInfo.unavailable；ImageSession三个ImageInfo构造末尾分别传loaded.colorInfo()、result.colorInfo(generatedHDR: maximumGain != nil)、result.colorInfo()。LoadedImage.colorInfo与ImageColorInfo由本机独立模块提供，见附件，禁止另写颜色科学逻辑。明确这些描述为解码表观/合成域，不是面板实测色域或导出目标。
2. 双击预览进入全屏后，使用原生UIScrollView+UIImageView实现应用内双指缩放（1～8倍）和放大后的拖动，保持相同CGImage及HDRPreferredDynamicRange/toneMap设置，禁止SDR截图替代。新图/模式变化时重置缩放，关闭后重开从1倍开始。保留右上角关闭及全屏双击退出，主预览双击进入不变，避免与双指捏合冲突。可新增小型UIViewRepresentable与Coordinator。缩放容器accessibilityIdentifier设为full-screen-preview，accessibilityValue包含两位小数缩放倍率（如缩放 1.00×），代理scrollViewDidZoom更新，便于真实XCTest捏合验收。不要用仅视窗缩放冒充图像缩放。
3. 调整页导入行与HDR/SDR/GainMap分段控件之间，采用与查看页相同的20pt顶部内容间距；保留固定紧凑预览和下方工具滚动，避免重复添加导入按钮。
4. HistogramPanel本批不要改。用户正选择RGBY同图叠加或四图布局，HSV也保持原样，待下一批指令。

不要改ImageModel/解码/增强/导出算法。交付时实际保存修改，并只给修改摘要、最终文件SHA256、未验证项。这里不能编译Swift，构建和测试由本机Xcode负责，不虚报验证。请现在执行第1批。
