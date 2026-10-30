# iPhone16 安装测试版

日期：2026-10-30。用户明确要求将当前软件安装到已连接手机；沿用当前源代码与用户签名配置，不提交/推送。

## 初检

- 已发现USB连接的真实iPhone16，iOS26.6.1，已配对。
- devicectl明确返回Developer Mode Disabled，尚无DDI挂载；本机有兼容且可用的iOS DDI。
- 初检有效codesigning identity为0；随后在Xcode中观察到用户已选Personal Team，工程保存了DEVELOPMENT_TEAM。保留该用户配置，无需重新登录账号。
- 已请用户在手机开启开发者模式、重启并确认。此为设备端必要步骤，不能用模拟器构建替代。
- 指定手机构建暂未找到可用destination，原始日志report-test16-device-signing.txt；继续通用iOS签名准备，日志report-test16-signing-preparation.txt。

## 完成条件

签名构建成功 → codesign及描述文件核对 → devicectl安装 → 设备应用清单确认 → 启动进程确认。未安装/未启动不写成功；物理XDR与主观画质仍需真机另外验收。

## 安装进度

- 用户已开启开发者模式并重启，devicectl复查Enabled。
- Personal Team自动登记设备、生成开发证书与描述文件成功。
- 桌面目录的文件提供程序会给生成.app反复附加FinderInfo，导致CodeSign拒绝；仅移到独立本机临时构建目录后成功，不改源代码或关闭签名检查。
- 签名构建成功日志report-test16-signed-local-build.txt；路径记录output/iphone-build-location.txt。
- codesign --verify --deep --strict通过；描述文件包含当前iPhone、允许开发调试，有效期至2026-11-06 14:48（Asia/Shanghai）。摘要output/iphone-signature-verification.json。
- devicectl安装成功，设备应用清单确认HDR Image Lab 0.1.0 (1)，bundle local.hdrimagelab。report-test16-install.txt、report-test16-app-list.txt。
- 首次启动被iOS Security拒绝，返回签名/权限/开发者信任提示。本地签名与设备配置已通过，已请用户在手机VPN与设备管理完成开发者信任，再重试；未把安装成功写成启动成功。

## 完成

- 用户确认已信任开发者后，devicectl启动成功，PID1207，activatedWhenStarted=true。签名、安装、设备清单与启动四项均有证据，安装任务完成。
- 日志report-test16-launch-trusted.txt与output/iphone-launch-trusted.json；功能/XDR实测仍另行验收。
