# macOS 模拟测试交接

- 日期：2026-10-29；负责人：主代理。
- 用户要求：可模拟则重新编译启动，由用户手工测试；不可模拟才转向后续功能。
- 结论：可模拟，已交付可见设备窗口；本轮仅启动与文档，不扩展后续功能。
- 启动上下文：读取项目 context/首轮进度/README、知识库协作流程、K10 正式知识及索引。沿用区分功能模拟、格式验证与真机物理显示的口径。
- 基线：根仓库 main，原有 `.DS_Store`、`wechat-miniprogram` 修改及未跟踪的新项目保留。
- 当前源码用 Xcode 27.0 / SDK iOS 27.0 对 iPhone 17 模拟器重编译，BUILD SUCCEEDED；日志 `docs/tests/report-test6-build.txt`。
- 重新安装并启动：iPhone 17，ADA3A538-F53C-4F1C-B79B-9D734FAFAB49，iOS 27.0；应用 PID 63872。
- 窗口定位：旧版 Simulator.app 路径不存在；实际为 `/Applications/Xcode.app/Contents/Applications/DeviceHub.app`。已通过 CUA 打开，见 iPhone 18 Pro/iOS 27.0 的应用界面与已加载图像、600 nit 滑块、导出按钮。当前 EDR 余量 1.00×。
- 用户在操作 iPhone 18 Pro；读取最新窗口后保留该设备与已加载图像状态，不重置或重新安装该设备应用。
- 测试数据：`output/manual-test-images/` 中 SDR 色阶、生成的 ISO GainMap JPEG、1000 nit PQ PNG；simctl addmedia 已加入 iPhone 17 和 iPhone 18 Pro 相册，全部人工生成，无用户图像上传。
- 改动：README 模拟器测试步骤、changelog、本任务记录、test6 报告；业务源码与工程配置未改。
- 验证：当前版本构建、安装/启动、测试图导入、可见交互窗口。没有重复执行引擎测试，因本轮未改源码；历史 28 项测试不当作本轮新执行。
- 未验证：用户手工点击全流程、实际 iPhone 16 XDR、iOS 18 设备运行。模拟器 1.00× 余量不能代表真机高光亮度。
- 后续：等待用户试用反馈；不自动提交或推送。
