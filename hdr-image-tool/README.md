# HDR Image Lab

本机开发的原生 iOS HDR 图像工具，最低系统 iOS 18。需求与开发顺序已经两轮讨论确认，见 [需求规格](docs/requirements.md)。

最新源码与签名测试包为 **0.1.1（构建7）**：状态详情分别显示SDR/HDR/GainMap色彩描述；全屏支持捏合缩放；调整页模式控件间距与查看页一致；直方图默认RGBY叠加、四个独立开关，H/S/V保持单通道。251项常规及6项真实模拟器UI用例通过，见[test28](docs/tests/report-test28.txt)。构建7已覆盖安装到用户iPhone16并成功启动，见[test29](docs/tests/report-test29.txt)。

本次界面迭代已完成“四页工作台”：查看、调整、分析、导出；共用导入入口，调整页保留紧凑预览，分析图三选一，导出参数折叠。由 Coze DeepSeek-v4-Pro 出稿，本机集成验收，位于 `ui-workspace/root` 独立 worktree，未合并main；已更新至用户iPhone16并启动，见 [test27](docs/tests/report-test27.txt)。双目标构建、238项常规回归和两项模拟器UI用例通过，范围与限制见 [test25](docs/tests/report-test25.txt)。

当前本地迭代：**0.1.1（构建7）**，四项新功能已签名覆盖安装到iPhone16并启动；原21份导入缓存元数据保留。见[本轮安装记录](docs/tests/report-test29.txt)，历史构建6安装见[test27](docs/tests/report-test27.txt)。当前开发描述文件有效至2026-11-06 14:48（北京时间），到期需重新签名安装。历史0.1.1(5)归档见[test24](docs/tests/report-test24.txt)。

## 当前功能

图标采用光谱轨道与HDR高光星芒设计，见[图标源文件](artwork/AppIcon.svg)。早期0.1.0（构建2）的[图标与安装验证](docs/tests/report-test17.txt)保留，当前版本以本轮test24为准。

- 相册或文件导入单张静态图片；处理在设备本地完成。
- HDR、SDR、GainMap 三视图；无可读取 GainMap 时不生成假增益图。
- SDR 高光选择性增强：默认峰值 203 nit，滑动至最高 600 nit；较暗区域不变，亮区逐渐增强。已有 HDR 保留原动态范围。
- 导出 16 位 BT.2020/PQ PNG 或 TIFF；回读检查尺寸、位深、色彩空间后提供系统保存/分享入口，PNG 显式写入 cLLI 光级。
- HDR 预览使用系统高动态范围显示，显示当前 EDR 余量；预览长边最多 2048 像素。
- 普通格式单图转换：JPEG/HEIC/PNG/BMP，源图 SDR 表观、8 位 sRGB。PNG 保留透明，其余白底；选择项按系统实际编码器能力提供。
- 导出参数：JPEG/HEIC 质量上限 0～100%，DPI 1～2400，按宽或高等比缩放，文件大小上限（KiB）。尺寸保持不变的质量搜索无法达标会报错；无损格式只检查上限，不暗中缩小图像。
- R/G/B/Y/H/S/V 直方图：默认最长边 512 的采样估计，支持通道切换和对数计数；RGB 为线性 BT.2020、Y 为 nit，HSV 为源 SDR sRGB 表观，明确标记灰色无定义色相、透明和范围外计数。
- 切图/切模式/调峰值采用图片代次、取消和结果键守卫，过期图像/统计/分享结果不会显示为新图结果；无 GainMap 时隐藏不可用视图。
- 双击预览进入全屏，双击或右上角关闭按钮退出；沿用当前HDR/SDR/GainMap显示模式。
- SDR+灰度GainMap：选当前源图或另一张相册/文件图像，调最大增益后点击「应用合成」；另图等比居中裁切，可「恢复源图」。默认2.96×，黑不增强、白为最大增益，基图始终为原始SDR表观。
- HDR输出新增ISO GainMap JPEG/HEIC；PQ与GainMap均可选Display P3或BT.2020原色。GainMap结果需超过SDR参考白，否则明确提示改存SDR/PQ或提高增益。
- SDR PNG/JPEG/HEIC可选sRGB/P3/Adobe RGB，以及等XYZ转换或保留源编码值的RGB直通；BMP受系统限制只开放sRGB。
- 打开「显示像素色域分布」可查看CIE1931 xy/CIE1976 u′v′及独立色域三角形，或CAM16-UCS/ICtCp/Lab三维采样点云。支持自动旋转、拖动、双指缩放；统计域和固定观察条件在图下标明。
- 分析副本在源线性RGB域将解码负值置零，显示修正采样数，二维与三维共用结果；保留正向HDR高光和合法P3→BT.2020负分量，不改变预览、直方图与导出。[修复验证](docs/tests/report-test21.txt)。
- 三维图新增「三维参考外包络」：sRGB、Display P3、BT.2020分别显示/隐藏，半透明外壳与网格边线随点云一起旋转。参考峰值默认10000nit，可选203/600/1000/10000nit，参考白仍203nit；三个三维开关与二维三角形互不联动。
- SDR图像可在「SDR · 3D LUT增强」中导入并应用`.cube`，或直接使用提供的17³示例。首版约定为sRGB编码码值输入→线性BT.2020输出；支持2～65阶与DOMAIN，HDR源图禁用。每次从原图应用，可恢复/重新应用；预览、分析和SDR导出使用结果，新增BT.2020 SDR导出目标。
- LUT应用后，像素分布可独立显示原图/LUT散点与各自凸包：二维为边线，三维为半透明外壳，青色原图、粉色增强图。两组采样位置、参考白与峰值一致；凸包仅描述最多4096个采样点，会填平凹陷，不是全分辨率精确色域或设备边界。工作数据保留正向扩展值，分析负值沿用方案A；SDR预览/导出受目标范围限制。[功能与验证](docs/tests/report-test23.txt)。

当前处理最多5000万像素的静态主图，可另选一张灰度来源，暂不支持批量或动态图片。普通格式输出源SDR表观，不应用HDR增益；HDR输出可用PQ或GainMap。DPI只改元数据；尺寸参数只作用于导出，预览、直方图、像素分布针对当前工作图。详见[输出与像素统计契约](docs/hdr-output-contract.md)。

## 在 iPhone 上运行

详细步骤见[iPhone16安装与签名指引](docs/iphone-testing.md)。2026-10-30已通过用户Personal Team签名并安装到iPhone16/iOS26.6.1；用户完成开发者信任后已成功启动，结果见[test16](docs/tests/report-test16.txt)。当前描述文件有效至11月6日14:48北京时间。此前无签名构建仍不能作为安装包使用。

1. 用本机 Xcode 打开 `HDRImageLab.xcodeproj`。
2. 选择 `HDRImageLab` scheme，在 Signing & Capabilities 选择自己的开发团队；当前 bundle ID 为 `local.hdrimagelab`，如签名冲突可改为自己的唯一标识。
3. 连接 iPhone 16，确认系统 ≥ iOS 18，选择设备并运行。
4. 导入原始 HEIC/GainMap 文件，切换三视图；普通 SDR 图片可调输出峰值。
5. 生成 PQ PNG/TIFF，再通过「保存或分享已生成文件」存储到文件。即使当前查看 SDR/GainMap，导出仍为 HDR 结果。

相册读取请求当前表示，但不保证所有来源都交付拍摄原件；验证 GainMap 时优先同时使用「导入文件」比较原文件。PQ 输出为单表观图像，不附带原始 GainMap。默认不复制原图 GPS 等拍摄元数据。

## 在 macOS 上模拟测试

本机 Xcode 27.0 的模拟设备窗口由 **Device Hub** 提供，应用位于 `/Applications/Xcode.app/Contents/Applications/DeviceHub.app`，不在旧版 `Developer/Applications/Simulator.app` 路径。

本轮在 iPhone 17 / iOS 27.0 模拟器测试新版；Device Hub 另有 iPhone 18 Pro，侧栏须选择与已安装版本对应的设备。

两台模拟设备的相册均已加入三张本地生成的测试图，原文件位于 `output/manual-test-images/`：

1. `01-SDR-chart.png`：色阶和色块。点击「从相册选择」，选该图，将峰值从 203 调到 600，检查预览变化与响应，再分别生成 PQ PNG/TIFF。
2. `02-ISO-GainMap.jpg`：灰色测试图，带生成的 ISO GainMap；检查 HDR/SDR/GainMap 三视图。
3. `03-PQ-1000nit.png`：两格亮度测试图；检查识别为 HDR、SDR 增强滑块禁用、导出保留原有 HDR 动态范围。

生成后点击「保存或分享已生成文件」测试系统保存入口。测试图是人工生成的数值样本，不代表真实相机画质；模拟器当前显示余量为 1.00×，不用于判断真实 iPhone XDR 峰值亮度。

如需直接在 Mac「预览」检查生成文件，运行以下命令取得当前应用数据目录，进入其 `tmp/HDRExports/` 子目录（点击「生成」后才创建）。无需先完成模拟器的分享操作。应用重新安装后目录 UUID 可能变化，以命令结果为准：

```sh
xcrun simctl get_app_container 8FC2AEA1-6399-4FA4-9A41-B4A81F74B221 local.hdrimagelab data
```

上面是 iPhone 18 Pro ID；本轮测试用 iPhone 17 ID 为 `ADA3A538-F53C-4F1C-B79B-9D734FAFAB49`。把命令中的 ID 换成正在测试的设备。

向 iPhone 17 模拟器相册加入自己的 Mac 本地图片，可在终端运行（将最后一个路径换成实际图片）：

```sh
xcrun simctl addmedia ADA3A538-F53C-4F1C-B79B-9D734FAFAB49 "/绝对路径/图片.heic"
```

重新编译并在 Xcode 中运行：打开工程，选择 `HDRImageLab` 和一个 iPhone 模拟设备，按 `⌘R`；模拟器运行无需开发者签名。选择 Device Hub 侧栏中对应设备查看应用。

系统模拟器相册的 addmedia 不接受本轮 AVIF 样图；AVIF 的文件读取已由实际引擎测试覆盖，不能把相册限制当成所有文件解码能力限制。真实 PQ PNG 已通过相册进入 App 并显示正确 HDR/格式信息。

## 本地验证

三维参考包络的[测试与交付报告](docs/tests/report-test15.txt)：199项常规测试与105项原有红军回归通过；独立colour-science核对全部边界顶点、闭合拓扑及四档峰值。参考包络为理想原色范围，非手机实测色域。

当前扩展版本的[最终软件报告](docs/tests/report-test13.txt)：283项通过，共享核心行覆盖率94.08%，设备/模拟器构建成功。[新版主要界面验收](docs/tests/report-test14.txt)已完成：全屏、合成、导出、二维/三维切换和旋转通过，并修正两处显示问题。双指缩放仍待手动验证。上一版四组门禁记录保留，不代替新界面交互证据。

复用现有 Miniforge base、pytest、colour-science、NumPy、Pillow 和 Xcode，无新增依赖。测试直接编译并调用 `Sources/ImageEngine.swift`，不会用 Python 实现替代生产引擎。

在项目目录的本机终端运行（Core Image 需要图形服务权限，受限沙箱内可能返回全零像素）：

```sh
/Users/wangshupeng/miniforge3/bin/conda run --no-capture-output -n base python -m pytest -q tests/test_hdr_engine.py
xcodebuild -project HDRImageLab.xcodeproj -scheme HDRImageLab -configuration Debug -destination 'generic/platform=iOS' -derivedDataPath output/DerivedData CODE_SIGNING_ALLOWED=NO build
```

测试资料与覆盖率在 `output/tests/`，实际报告在 `docs/tests/`。覆盖率仅统计平台共享的生产 Swift 核心；SwiftUI、私有异步 UI 模型与真实设备显示另行审阅/操作验证，不计入核心覆盖率。

上一版R1–R8按顺序执行四组红蓝军门禁，四组软件门禁均通过。最终汇总：[232项回归、覆盖率与交互证据](docs/tests/report-test12.txt)。报告：[R1/R2](docs/tests/red-blue-01.md)、[R3/R4](docs/tests/red-blue-02.md)、[R5/R6](docs/tests/red-blue-03.md)、[R7/R8](docs/tests/red-blue-04.md)。所有失败、修复、参考真值纠正、源码/用例 SHA256 与复测均保留。完整最终回归结果见 `docs/tests/report-test12-all.txt`。高光 Core Image 源码 kernel API 有弃用警告，当前 SDK 和本地测试正常，后续可迁移 Metal。

蓝军测试与四组独立红军可在本机终端执行：

```sh
/Users/wangshupeng/miniforge3/bin/conda run --no-capture-output -n base python -m pytest -q tests
/Users/wangshupeng/miniforge3/bin/conda run --no-capture-output -n base python -m pytest -q tests/red_team_r1_r2.py tests/red_team_r3_r4.py tests/red_team_r5_r6.py tests/red_team_r7_r8.py
```

## 色彩与显示约定

内部使用扩展线性 BT.2020，1.0 对应 203 nit 参考白；导出为 ST 2084 PQ。文件目标 nit 与屏幕物理亮度分开；实际屏幕可用余量由系统管理，截图或模拟器不证明 XDR 物理亮度。

默认 203 nit 是 SDR 恒等映射，不具有高于参考白的额外 HDR 余量。高光增强采用确定性亮度曲线，不恢复原图已剪切细节；没有对肤色或物体进行语义识别。

本机 macOS 26.6.2「预览」已识别生成 PQ PNG 为 RGB 16 / Rec. ITU-R BT.2100 PQ；这不证明它一定采用 cLLI 或给出指定物理亮度。真实 Apple/ISO/Adobe GainMap、PQ PNG/AVIF/HEIC 和 SDR 样图已在共享引擎核对。iPhone 16 真机、其他 macOS 版本及电视路径另行验收。

JPEG GainMap 的原始 SDR 基图在部分 Native HDR 适配路径中有额外色差；本项目只对识别为 SDR 基图的 JPEG 隔离 HDR 辅助标记、保留原 ICC/EXIF/扫描码流解码 SDR。HDR 视图和转换继续读取完整原文件，HDR-primary 使用系统映射；原图不被改写。

主要模块：`ImageEngine.swift`（图像/色彩/编码）、`ExportOptions.swift`（参数）、`HDRPNG.swift`（光级）、`Histogram.swift`（统计）、`JPEGPrimary.swift`（SDR基图隔离）、`HDRImageLabApp.swift`（界面/异步状态）。

开发记录：[R1–R8 进度](docs/agent/tasks/2026-10-29-r1-r8/progress.md)；平台来源：[研究报告](docs/research/platform-feasibility.md)。
