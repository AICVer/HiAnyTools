# 项目上下文

- 构建7已发布到用户指定的[HiAnyTools](https://github.com/AICVer/HiAnyTools)：annotated tag `hdr-image-tool/v0.1.1-build.7`固定指向e80782a，远程main及标签解引用SHA已核对一致。用户明确选择完整仓库/完整历史，包含历史其他工具、PDF与output产物；原origin=image2pdf保留，新增hianytools远程。发布结果文档随后单独提交并推送main，不移动版本标签。19份冻结源码/测试指纹全匹配；本轮没有重跑既有功能测试。见[test31](../tests/report-test31.txt)、[进度](tasks/2026-11-05-publish-build7/progress.md)。历史各阶段“未推送”记录只描述当时状态。

- 主干已整合：[进度](tasks/2026-11-05-merge-main/progress.md)、[test30](../tests/report-test30.txt)。用户授权提交并merge，功能提交74cf799、no-ff合并36ec99f，main已安全快进。合并无冲突，产品/正式测试指纹与test28一致，原有主干无关修改/删除/子模块状态保留；结果文档单独提交，最新hash以main日志为准。范围仅hdr-image-tool，不推送、不改写历史或删除worktree。历史调试输出仍在原ui-workspace/root的output，正式报告已纳入主干。

- 构建7真机安装完成：[test29](../tests/report-test29.txt)。用户重新连接并解锁后，现有0.1.1(7)签名/源码指纹复核通过，已覆盖更新iPhone16并激活启动PID47369，设备版本与本次安装目录进程核验一致；旧21份导入缓存相对路径/大小均保留。源码/正式测试不变，不重跑test28；本轮只证实安装启动，不替代真机手势/XDR实测。现有开发签名有效至2026-11-06 14:48北京时间。无提交/合并/推送。

- 最新四项增量完成：[test28](../tests/report-test28.txt)、[进度](tasks/2026-11-05-ui-followup/progress.md)。0.1.1(7)支持分层色彩描述/缺失标注、原生全屏捏合、调整顶部20pt、RGBY默认叠加与四开关（用户已确认，HSV原样）。Coze DeepSeek-v4-Pro实际完成主要UI及接线，后续中断/空响应后由本机补齐绘图与集成修正；最终主UI/色彩模块已按原始附件回同步，SHA一致。251项常规通过/2项外部参考缺失跳过，6项真实模拟器UI用例全部通过；核心95.44%、新增色彩模块95.65%、主UI83.82%。签名包已构建校验通过，后续已安装构建7并启动，见test29；历史构建6见test27。真实XDR/新功能真机手势仍待验，未提交/合并/推送。

- 最新真机安装：[test27](../tests/report-test27.txt)、[进度](tasks/2026-11-05-iphone-install/progress.md)。用户要求将当前四页界面安装到已连接手机，已于2026-11-05用现有签名覆盖更新iPhone16/iOS26.6.1为0.1.1(6)，设备版本复核通过，启动并激活成功PID45544且运行路径与本次安装目录一致；原16份导入缓存相对路径/大小均保留。14份生产Swift与test25冻结快照相同，本次仅递增构建号及文档，未重跑无变化算法；真机画质/XDR和手势仍另列待验。开发描述文件至2026-11-06 14:48北京时间，到期需重新签名安装。源代码仍在ui-workspace/root worktree，未提交/合并/推送。

- 第二轮直接补验完成：[test26](../tests/report-test26.txt)。再次解锁后，三维拖动旋转与跨页视角保持、HDR PQ PNG/SDR JPEG实际生成和分享入口隔离通过；生成文件均960×640，分别为16位BT.2100 PQ及8位sRGB。后续连续截图观察到自动旋转持续更新。双指缩放仍受当前CUA多指操作能力限制而未验证，真实iPhone/XDR仍待验；不是产品故障结论。仅更新证据与文档，源码/测试指纹不变。

- 2026-11-05直接界面补验：[test26](../tests/report-test26.txt)。用户解锁后，通过系统相册实际选择960×640 SDR测试图并完成回调；双击全屏及关闭返回通过；调整页203→600nit与预览刷新通过。切入分析页前Mac再次锁屏，三维手动拖动/双指缩放及剩余导出屏幕操作未完成，已请求再次解锁。仅更新验证记录，未改源码或重跑test25回归；相册实际选图缺口已补齐，真实iPhone/XDR仍待验。

- 最新四页工作台：[进度](tasks/2026-11-04-ui-workspace/progress.md)、[test25](../tests/report-test25.txt)。用户确认方案B、DeepSeek-v4-Pro、main/1e12a24基线及源码发给Coze；分支ui-workspace/root，独立worktree内交付，未提交/合并/推送。有效Coze项目7704274349251133475，流式生成两份Swift稿，SHA256核对后本机集成；补齐共用导入入口、分析视图身份保持及调整页模式切换。最终双目标构建通过；238项常规通过/2项因外部HiEnhance LUT缺失跳过；两项真实模拟器UI用例通过（空状态导航、加载后状态/图层/导出）。核心行95.43%，两份UI文件80.42%/89.68%。系统相册服务未返回测试图，加载后用例通过仅模拟器入口复用真实文件加载路径；相册实际选图回调、真机/XDR及直接手动缩放仍未验收。最终截图已导出并视觉核对。未更新真机，既有版本记录见下文。

- 最新真机迭代：[0.1.1发布/本地Git归档](tasks/2026-10-30-release-0.1.1/progress.md)，[test24](../tests/report-test24.txt)。按用户明确要求递增为0.1.1(5)，现有证书签名、覆盖安装及设备版本核对通过，用户解锁后实际启动成功PID4310，旧导入缓存元数据保留；算法源码与test23冻结快照一致。用户本轮授权本地commit，范围仅hdr-image-tool；output/签名/临时图像和同级其他项目改动不纳入，提交结果以Git日志为准，不推送。
- 最新功能：[SDR 3D LUT与像素凸包](tasks/2026-10-30-lut-distribution/progress.md)，[test23](../tests/report-test23.txt)，构建4。指定17³ LUT的契约已核对为sRGB码值→线性BT.2020；支持导入/内置示例、原图恢复、预览/分析/SDR导出及BT.2020目标；前后散点与采样凸包四开关，二维边线/三维外壳。345项回归通过，核心行95.65%、新CubeLUT/PixelHull行100%，双目标构建、iOS数值与主要模拟器交互通过。模拟器已更新，真机仍为构建3，未安装此功能版；外部Files选择另一份LUT的完整回调及全空间UI组合未全部遍历。
- 真机部署完成：[方案A构建3安装](tasks/2026-10-30-clamp-iphone-install/progress.md)，[test22](../tests/report-test22.txt)。已签名构建并覆盖安装到iPhone16，设备清单确认0.1.0(3)，test21冻结源码一致、旧导入缓存保留；用户解锁后实际启动成功PID3117，应用与进程清单复核通过。真机画质/UI/XDR尚未在本轮安装任务重新验收。
- 当前实现：[源线性RGB截断方案A](tasks/2026-10-30-source-rgb-clamp/progress.md)，[test21](../tests/report-test21.txt)。用户已确认开发；仅分析副本截断源负值并显示修正采样数，保护P3合法负BT.2020分量与正向HDR高光。真实IMG_3920在iOS默认低质量采样配置下修正80/1792点，负XYZ/无定义xy为0；320项回归通过，核心行94.69%，设备/模拟器构建及iOS模拟器数值验证通过。参考包络默认10000nit、白203nit已落实。模拟器已安装并启动；Mac锁屏阻止UI实测。后续test22已将修复更新至真机构建3，启动状态以部署记录为准。
- 前置实图排查：[IMG_3920/IMG_4456](tasks/2026-10-30-image3920-diagnosis/progress.md)，[test20](../tests/report-test20.txt)。原图是sRGB SDR，真机导入缓存SHA相同；本机复现截图三个离群位置及xy无定义1。用户解锁后，已在iPhone16/iOS26.6.1通过LLDB按App相同Core Image参数复算，1792点中负RGB14/负XYZ11/无定义xy1，三个xy与本机差为0；只取汇总和三个坐标，已脱离PID1382。此为修复前证据，未直接读取UI缓存分布，当轮未修改/重装App。高质量/8位SDR入口改善仍以本机对照为据，真机高质量汇总未完成；当轮诊断1失败/5通过。
- 前置通用排查：[二维/三维散点越界](tasks/2026-10-30-gamut-diagnosis/progress.md)，[test19](../tests/report-test19.txt)。36项既有模块测试通过，合法BT.2020颜色在分面壳外的失败断言已复现；当轮App代码未改。用户要求包络默认10000nit、白203nit，已在test21落实；二维色度不随统一亮度缩放变化。
- 需求与已确认决策：[需求规格](../requirements.md)。继续开发先读该文档；待确认项不作为已确认功能。
- 当前任务：[SDR LUT/像素凸包](tasks/2026-10-30-lut-distribution/progress.md)；此前：[源RGB负值截断](tasks/2026-10-30-source-rgb-clamp/progress.md)、[三维参考外包络](tasks/2026-10-30-reference-envelopes/progress.md)、[全屏、合成、色域与像素可视化](tasks/2026-10-30-compose-gamut/progress.md)；已通过基线：[R1–R8 顺序与红蓝军门禁](tasks/2026-10-29-r1-r8/progress.md)；历史：[iPhone 安装/R1](tasks/2026-10-29-iphone-and-r1/progress.md)、[模拟测试交接](tasks/2026-10-29-simulator-handoff/progress.md)、[HDR 首轮](tasks/2026-10-29-hdr-core/progress.md)。
- 本项目独立于同级旧图像转 PDF 工程，仅本机处理；默认不自动提交或推送Git。本轮用户已明确授权本地提交，按指定范围执行，不推送。
- iOS 原生首轮已获用户确认；手机 iPhone 16，iOS 未知，PQ PNG 目标查看器为 macOS 预览。
- Swift 使用本机 Xcode；Python 测试必须通过 Miniforge base。新增依赖和环境变量仍按上级项目指令事先确认。
- 首轮实现入口：`Sources/HDRImageLabApp.swift`；共享引擎：`Sources/ImageEngine.swift`；Xcode 工程：`HDRImageLab.xcodeproj`。运行和验证命令见 [README](../../README.md)。
- 已通过的上一版基线：R1–R8，包含普通转换/导出参数、HDR/EDR 预览、PQ PNG/TIFF、高光增强、七通道直方图和 GainMap 三视图。最终显式蓝红军回归 232 项通过，核心行覆盖率 95.68%（UI 不计入），设备无签名及模拟器构建通过。最终证据见 [test12](../tests/report-test12.txt)，按四组门禁报告判断状态。
- 上一版 iPhone 17 / iOS 27 模拟器已安装；2026-10-30 实际验证七通道、统计域/采样、峰值更新/PQ生成、模式切换保留分享和 GainMap→SDR 切图。真实 iPhone XDR 与所有并发时序不由该证据替代。
- 真机已签名安装：[test16](../tests/report-test16.txt)、[安装进度](tasks/2026-10-30-iphone-install/progress.md)。iPhone16/iOS26.6.1已开启开发者模式，用户Personal Team签名验证通过，设备已更新为图标版0.1.0 (2)，启动成功（PID1382），见[test17](../tests/report-test17.txt)。签名、安装与启动已完成；XDR物理效果仍未实测。当前描述文件至2026-11-06 14:48北京时间。
- 已读取 `/Users/wangshupeng/知识库/规范/Agent协作与知识入库流程.md`；使用正式知识 K06/K10/公共编码规范，详情见需求规格。研究结论未自动入正式知识库。

- 当前扩展实现E1–E6：全屏、灰度合成、GainMap/P3导出、SDR多空间映射及二维/三维像素分布。最终状态以test13报告和当前任务进度为准；test12/四组门禁属于上一版，不作为扩展界面已实测的证据。
- 扩展版最终软件验证：[test13](../tests/report-test13.txt)，283项通过，核心行94.08%，设备与模拟器构建成功；主要界面交互已补齐，见[test14](../tests/report-test14.txt)。仅两处UI文件更新，核心SHA不变；无需无变化重跑全套测试。双指缩放、真机XDR仍待手动/设备验收。

- 三维外包络已实现：[test15](../tests/report-test15.txt)，304项回归通过，核心行94.51%，设备/模拟器构建成功；203nit三外壳截图及1000nit仅BT.2020状态已记录。部分UI组合受控制工具超时影响未遍历，不与已验证数值范围混淆。

- App图标：参考HiMagic的本地矢量设计，源artwork/AppIcon.svg，资源Sources/Assets.xcassets/AppIcon.appiconset；构建号2。原Swift源码未变，设备更新安装与启动通过。
