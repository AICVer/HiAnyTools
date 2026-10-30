# 2026-10-29 HDR 核心首轮

- 负责人：主代理；研究子代理仅维护平台研究报告。
- 目标：讨论需求后，交付本地 iOS HDR 核心首轮，范围以需求规格为准。
- 已完成：读取上级项目规则、已有项目上下文和知识库流程；检索 K06/K10/公共编码规范；官方平台资料研究；两轮用户问答确认平台、峰值、输出、验收设备与开发顺序。
- 工作区基线：根 main 分支已有 `.DS_Store` 和 `wechat-miniprogram` 修改；均不触碰。
- 环境：Xcode 27.0/SDK 27.0、base Python 3.12.12、pytest 9.0.2、colour 0.4.7 已存在；未安装依赖。沙箱内 CoreSimulator 服务连接失败，后续在获准的本机权限下完成启动，见下方图形权限记录。
- 首轮代码完成：原生 iOS 单图导入、HDR/SDR/GainMap 查看、选择性高光增强、PQ PNG/TIFF 写出与回读、分享保存入口；普通转换/压缩/直方图按确认顺序留到后续。
- 验证完成：28 项 pytest 驱动实际 Swift 引擎通过；colour-science 独立核对 PQ；1000 nit 原始 HDR 保持；生成 ISO GainMap 三视图与导出；引擎行覆盖率 94.92%、区域覆盖率 85.92%、函数覆盖率 83.33%。报告 `docs/tests/report-test1.txt`、`report-test2.txt`。
- 构建：Xcode 27.0 / SDK 27.0，iOS 18 最低版本，设备版和模拟器版无签名构建通过，见 test3/test4。高光 CIKernel 源码 API 有弃用警告，当前 SDK 可构建和运行；后续可换 Metal，不在本轮扩展。
- 图形权限：沙箱内 Core Image 渲染返回全零；经批准在本机图形服务权限下完成测试，无网络。CoreSimulator 也通过本机权限完成启动/安装/运行，iPhone 17 / iOS 27.0 模拟器应用 PID 77250；未冒充 iPhone 16 实测。
- 互通：本机 macOS 26.6.2「预览」实际打开 600 nit PQ PNG，检查器显示 RGB 16 / Rec. ITU-R BT.2100 PQ；只验证文件识别，不代表仪器亮度测量。
- UI 未完成：CUA 未找到可操作的 Simulator 应用窗口，未验证相册选择、滑块、导出与保存按钮点击。当前只有编译、原生引擎测试和模拟器进程启动证据。
- 改动范围：仅新增 `hdr-image-tool/` 下源码、Xcode 工程、测试和文档；没有安装包、添加环境变量、修改 .env、提交或推送 Git。
- 下一步：连接 iPhone 16，在 Xcode 配置用户开发团队后进行真实文件导入/XDR/存储验收；界面细节反馈后小步迭代。
- 重要决策：iOS 18+ 工程基线；默认 203 nit 意味无超参考白余量；原始 HDR 不使用 SDR 增强滑块。
- 未验证：手机 iOS、用户其他 Mac/macOS/显示器、真实手机 GainMap 及任意电视兼容；本机 macOS 26.6.2 预览识别已验证。

后续更新：已在[模拟测试交接](../2026-10-29-simulator-handoff/progress.md)定位 Xcode 27 Device Hub 实际入口，并确认应用界面可见；上方窗口未找到的记录是首轮当时的验证缺口。
