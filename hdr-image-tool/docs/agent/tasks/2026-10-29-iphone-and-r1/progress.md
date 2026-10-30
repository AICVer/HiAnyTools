# iPhone 安装准备与 R1 普通格式转换

- 负责人：主代理；日期：2026-10-29。
- 用户要求：生成可装 iPhone 16 的 APP；不可行则继续 R1–R8 后续功能。
- 环境结论：`security find-identity -v -p codesigning` 为 0 valid identities；devicectl/xctrace 未发现物理 iPhone，仅有模拟设备。工程未配置 DEVELOPMENT_TEAM。当前无法完成可安装签名包，不把已有无签名构建当作安装包。
- 安装方案：本地 Xcode + Apple Account/Personal Team + USB 真机；用户完成账号登录、信任、开发者模式与团队选择。已补官方来源的安装步骤。
- 已授权后备工作：按小步迭代落实 R1，新增 JPEG/HEIC/PNG/BMP 单张普通格式导出；R2、R7 后续迭代。
- 范围：源图 SDR 表观 → 8 位 sRGB，保留原尺寸和已应用方向；PNG 保留 Alpha，JPEG/HEIC/BMP 白底；JPEG/HEIC 暂用 0.92 固定质量。HDR 来源按现有系统 SDR 表观转换，界面明确显示 SDR，不宣称保留 HDR；HDR 保留仍用 PQ 导出。
- 复用：现有 ImageEngine/CIContext/ImageIO；HiIccTool 为 Python 桌面后端，不直接移植，不新增依赖。
- 改动范围：ImageEngine、SwiftUI 导出控件、Swift probe、pytest 与相关文档；不修改签名配置/账户/.env，不提交推送。
- 知识依据：已读上下文、协作流程及 confirmed K06/公共编码规范；按读写能力、真实像素转换与回读分别验收。
- 验证完成：Swift 类型检查；R1 新增 30 项 pytest、全量 58 项 pytest 均通过。生产 ImageEngine 行覆盖率 94.51%、区域覆盖率 83.84%、函数覆盖率 88.00%；SwiftUI/设备显示不计入覆盖率。
- 构建：iPhone 设备无签名构建和 iOS 模拟器构建均通过。设备构建产物为 `output/DerivedData/Build/Products/Debug-iphoneos/HDRImageLab.app`，明确未签名，不可当作可安装 IPA。
- 模拟器：iPhone 17 / iOS 27.0 已安装并启动 R1 新版，PID 74511。Device Hub 已打开；当前窗口为 iPhone 18 Pro 且在切换/加载中，CUA 多次报告用户窗口状态变化，未完成新控件点击流程；用户可选择侧栏 iPhone 17 测新版。
- 报告：`docs/tests/report-test7*.txt`；覆盖灰阶、16 种格式组合、Alpha、方向、原文件不变、HDR→SDR 及既有 HDR/GainMap/PQ 回归。类型和位深均检查实际写出文件回读。
- 注意：本机 macOS ImageIO 支持四种输出格式；iOS 界面按系统实际编码器过滤，真实手机支持与画质待验收。
- 未验证：有效 Apple 开发签名、真实 iPhone 16/iOS 版本/XDR；新增 iOS 控件的用户操作待模拟器或真机。
