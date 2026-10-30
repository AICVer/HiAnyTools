# 方案A更新版安装至iPhone16

日期：2026-10-30；负责人：主代理。用户明确授权将刚完成的更新版安装到已连接真机；更新安装，不卸载原App，不提交或推送Git。

已读取context、test21及既有真机安装流程、知识库协作规范。算法沿用test21通过的冻结源码（320项回归、核心行94.69%）；本轮只将构建号2→3区分更新版本，并使用用户已有Personal Team/开发证书。无新依赖、环境变量或证书创建。

设备：已发现USB连接iPhone16，UDID 00008140-000160EE3440801C；已有有效Apple Development签名身份。沿用本机临时DerivedData目录，避免桌面文件提供程序对.app附加FinderInfo影响签名。

完成条件：签名构建成功 → 本地codesign/描述文件/版本核查 → 更新安装 → 设备应用清单确认0.1.0(3) → 启动成功。安装/启动不替代真机画质与XDR功能验收。

## 安装与启动结果

- 本地签名构建BUILD SUCCEEDED，日志report-test22-signed-build.txt；没有启用ProvisioningUpdates/设备注册，没有创建证书或上传代码。
- codesign --verify --deep --strict通过；包版本0.1.0(3)，原bundle local.hdrimagelab，描述文件包含当前设备，调试权限正常，有效期至2026-11-06 14:48北京时间。
- test21的六个冻结源码/测试文件SHA256全部一致；本轮只更改构建号和记录，不重跑无变化的算法套件。
- devicectl更新安装成功，安装结果outcome=success；设备应用清单确认HDR Image Lab 0.1.0 / Bundle Version3。没有卸载原App。
- 首次启动返回CoreDeviceError10002，底层明确为Locked：手机未解锁，无法前台启动。不是签名或安装失败。已请求用户解锁并保持亮屏，等待继续启动验证。
- 结构化证据：output/iphone-clamp-verification.json、iphone-clamp-install.json、iphone-clamp-app-list.json、iphone-clamp-launch.json。
- 只读核对更新后导入缓存元数据，旧C6D89FC0测试JPEG文件仍存在、547352字节；未导出像素或图像，见report-test22-data-preserved.txt。

- 用户回复“已解锁”后重试成功：devicectl outcome=success、activatedWhenStarted=true，实际启动PID3117。再次查询应用清单仍为0.1.0(3)，进程清单确认PID3117来自本轮安装目录8DD4243D-A793-483F-B9EB-F759226083C2。
- 完成证据：report-test22-launch-unlocked.txt、report-test22-app-list-final.txt、report-test22-process-final.txt与对应output/iphone-clamp-*.json。首次锁屏失败日志保留。

状态：签名、更新安装、设备版本核对与实际启动均完成；算法真机交互/物理XDR未在本次安装任务中重新验收。见test22。
