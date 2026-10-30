# 在 iPhone 16 上安装测试版

本项目可通过本机Xcode安装到自己的iPhone16，最低iOS18，无需上架。2026-10-30已在用户iPhone16（iOS26.6.1）完成Personal Team签名和安装，现已更新为图标版0.1.0 (2)，启动成功（PID1382），图标更新证据见[test17](tests/report-test17.txt)，首次安装过程见[安装进度](agent/tasks/2026-10-30-iphone-install/progress.md)。

## 首次配置

1. 用 USB 连接 iPhone 16 与 Mac，解锁手机并在手机上确认「信任此电脑」。
2. Xcode → Settings → Apple Accounts，登录自己的 Apple Account。账号登录与验证由用户本人完成；不把账号或密码写进项目。
3. 打开 `HDRImageLab.xcodeproj`，选择项目 → HDRImageLab target → Signing & Capabilities。
4. 保持 Automatically manage signing，Team 选择自己的 Personal Team 或已有开发团队。本机已保存用户选择的Personal Team；换电脑或账号时选择自己的团队。
5. 如果 Bundle Identifier 冲突，将 `local.hdrimagelab` 改成自己的唯一标识，再等待 Xcode 完成签名资源配置。
6. 在 Xcode 运行目标中选择真实 iPhone 16。按系统提示，在手机「设置 → 隐私与安全性 → 开发者模式」中启用开发者模式，完成重启与确认。
7. 按 `⌘R`。Xcode 编译、签名并安装；若手机提示未信任开发者，按手机系统指引处理信任，然后重新运行。

普通 Apple Account 可用 Personal Team 在个人设备上测试；Apple 说明免费个人配置的描述文件在签发 7 天后过期，届时需重新通过 Xcode 安装。详见 [Apple 开发者账号说明](https://developer.apple.com/help/account/basics/about-your-developer-account/)。

## 关于 APP 与 IPA

工程已支持 iPhone 构建，但 `CODE_SIGNING_ALLOWED=NO` 构建产物只证明代码可编译，不能当作可安装测试包。需要针对开发团队及目标手机完成有效签名与描述文件配置；单纯压缩 `.app` 或把文件发到手机不能替代此流程。

本轮推荐直接从 Xcode 安装，签名完成后手机上会出现「HDR Image Lab」图标。当前不上传构建到分发服务。

## 真机测试重点

- 相册和文件导入原始 iPhone HEIC，检查是否读取到 GainMap，以及 HDR/SDR/GainMap 三视图。
- SDR 源图从 203 调到 600 nit；观察亮区变化、预览响应和显示余量。
- 原始 HDR 图不应用 SDR 增强滑块上限。
- PQ PNG/TIFF 导出后回到 Mac「预览」检查色彩识别和显示。
- 普通 JPEG/HEIC/PNG/BMP 转换为源图 SDR 表观，PNG 保留透明，其他格式铺白底；与 PQ 导出分别测试。

## 官方依据

- [在模拟或真实设备运行应用](https://developer.apple.com/documentation/Xcode/running-your-app-on-simulated-or-physical-devices)
- [签名与团队流程](https://help.apple.com/xcode/mac/current/en.lproj/dev60b6fbbc7.html)
- [开启 Developer Mode](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device)

状态：2026-10-30已签名安装；原首次配置步骤供后续重装参考。当前描述文件至2026-11-06 14:48（北京时间），到期须重新签名安装。构建产物应使用独立本机临时目录，避免桌面文件提供程序附加FinderInfo导致codesign失败；本轮路径记录在output/iphone-build-location.txt。
