# 微信小程序：图像转 PDF

- 日期：2026-10-12；负责人：Codex。
- 用户目标：编写图像转 PDF 微信小程序。
- 范围：沿用本会话已确认的每张图片独立生成 PDF；新增本地原生小程序工程，不修改桌面版功能，不上传代码或素材，不发布上线。
- 启动检查：读取项目 context、知识库协作流程和已确认知识索引；沿用公共编码规范与 K06 图像处理边界。本目录仍无 Git 仓库。
- 实现：原生 WXML/WXSS/JS，Canvas 解码和缩小到长边 2400 像素、白底、JPEG 0.92、JavaScript 封装 PDF、微信本地文件系统持久化、预览及用户主动转发。
- 用户体验：最多 9 项、隐私授权、批次进度、单项失败隔离和重试、清空确认、恢复本地结果。
- 依赖：运行时无第三方包；为满足 Jest 测试要求新增工程局部开发依赖。离线安装因缺少间接依赖未成功，随后从 npm 仓库下载，仅用于本机测试；未使用 Coze、未修改 .env、未安装 Python 包。
- API 依据：官方文档抓取受限，改为只读获取微信官方 api-typings 的 lib.wx.api.d.ts 核对，下载副本仅在 output/wechat。
- 分层验证：report-test7 环境；report-test8 编码器与转换模块 17 项通过；report-test9 全套 32 项通过；补充退出中止与记录失败回归后，report-test10 最终 33 项通过，语句/函数/行 100%，分支 94.62%。
- 独立验证：report-test11，base Python pytest 共 3 项通过；Node 真实编码 → PyMuPDF 解析及渲染，对横竖方图检查页数、尺寸、原 JPEG 数据及像素。样本另经 Poppler 渲染目视检查。
- 最终接口审查：微信隐私监听是覆盖式注册，没有 offNeedPrivacyAuthorization；已改为退出时覆盖旧回调并补充断言。report-test12 再次 33 项通过，覆盖率保持语句/函数/行 100%、分支 94.62%。工程配置与页面四件套引用检查通过。
- 修改范围：wechat-miniprogram 新目录、tests/test_wechat_pdf.py、README 导航、context、changelog、任务与测试报告。
- 未验证：未检测到微信开发者工具且没有实际 AppID；无法完成小程序编译、WXML/WXSS 视觉检查、iOS/Android 真机权限/选图/Canvas/预览/转发验收。Jest 的微信 API 模拟不等同于真机验证。
- 当前状态：源码与本地验证完成；打包可导入工程，附导入与真机验收说明。未发布小程序、未提交或推送 Git。
