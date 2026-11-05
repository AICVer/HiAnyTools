# RGBY 显示增量（第2批）

仅在第1批完成后执行。用户要求默认RGBY同时显示、四个独立开关、HSV保持原样。
布局已由用户明确确认“同图叠加RGBY，四个独立开关”，与先行推荐方案一致。

只修改Sources/HDRImageLabApp.swift，不改Histogram.swift或任何解码/统计/导出算法，不删除既有函数或类型，不重写整个文件。保持第1批所有改动。

- 默认RGBY四条曲线全开，使用R红/G绿/B蓝/Y原有primary色，提供四个独立按钮开关，可全关；全关显示“未选择通道”。
- 用一个“RGBY / H / S / V”分段控件替换旧七通道选择，H/S/V维持原单通道曲线、原始分箱、颜色、范围、无定义色相与范围外提示、对数纵轴选项。
- 保留既有HistogramChannel枚举和统计结构，不增加虚拟RGBY统计通道。可以保留channel绑定并增加showRGBY布尔与visibleRGBY集合两个绑定，让显示模式/开关由ContentView持有，经AnalyzeTab传至HistogramPanel，确保切图表/功能页不重置。
- RGBY按原始256分箱位置叠加，共用计数纵轴（线性或log1p）；最大值从全部四通道原始bins求共同最大值，不按各通道独立峰值归一化，不随隐藏某通道改变比较基准。
- 横轴明确标注RGB分量“倍参考白”与Y的nit，按现有范围分别给出上下双标尺；1倍参考白对应203nit是数值尺度关系，不能把单个RGB分量当作像素实际Y。不得改分箱或为了叠加重新量化样本。
- 每个开关accessibilityIdentifier分别为histogram-channel-R/G/B/Y，accessibilityValue明确显示“显示”或“隐藏”；叠加图accessibilityIdentifier为histogram-rgby，并标注当前可见通道，便于真实UI验收。
- 仍显示原有统计域/采样/透明排除/无效计数；RGBY下分别标出有范围外计数的通道，不把HSV统计域混入线性HDR。

另请先修正第1批全屏代码的三处审阅问题，保持原函数/类型：
1. updateUIView不能每次重置zoomScale；仅CGImage身份或mode变化时重置，普通SwiftUI刷新应保留缩放。Coordinator保存上次图像/模式。
2. 首次updateUIView可能遇到零bounds。用小型UIScrollView子类在layoutSubviews通知Coordinator，viewport尺寸首次有效或变化时按宽高比布局；缓存已布局尺寸，避免centerContent设置inset再次触发布局的递归/每次拖动重置缩放。新图可强制重排，保留layoutImage函数。
3. UIScrollView.contentSize本身已经反映缩放，不要在centerContent中再乘zoomScale，否则中等倍数图像无法正确居中；关闭自动safeArea内容inset调整，使全屏图像中心正确。

保留全屏双击关闭与右上角关闭行为，不要让捏合触发关闭。
请实际用edit_file保存增量，结束只报告修改摘要、文件SHA256和不能在云端执行Xcode的未验证项。不要部署或提交Git，不再重复确认已经确定的需求。
