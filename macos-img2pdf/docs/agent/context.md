# 项目上下文

- 项目：本地批量图像转 PDF；目录没有 Git 仓库。
- 用户确认：本地图形窗口选择图片或文件夹，每张图片分别生成 PDF。
- 环境：本机 Miniforge `base`，现有 Pillow、PyMuPDF、Tkinter、pytest、pytest-cov；不安装新包。
- 入口：`启动图像转PDF.command`；核心 `image_to_pdf.py`；窗口 `image_to_pdf_gui.py`。
- 范围：当前层级文件、同名 PDF、重名跳过、透明区域白底、EXIF 方向修正、单帧普通 SDR 图片。
- 知识采用：[公共编码规范](/Users/wangshupeng/知识库/知识/工程实践/公共编码规范.md)、[K06 图像处理边界](/Users/wangshupeng/知识库/知识/色彩科学/ICC与HDR图像处理边界.md)。用于本地依赖复用、回读验证和明确格式边界。
- 已检查项目与知识索引、HueTools 目录，未定位名为 Hi[Func] 的工具；当前项目没有可复用转换代码，复用现有图像库。
- 开发过程：[任务记录](tasks/2026-10-12-image-to-pdf/progress.md)。

## 微信小程序（2026-10-12）

- 用户追加需求：编写图像转 PDF 微信小程序，沿用每张图片独立输出。
- 独立工程：`wechat-miniprogram/`；[说明](../../wechat-miniprogram/README.md)。不改变桌面版代码。
- 原生 JS/WXML/WXSS；选相册或拍照；最多 9 项；手机本地 Canvas 转换、白底、长边最多 2400 像素、JPEG 质量 0.92；本地保存 PDF 后预览或用户主动转发。
- Node 25.2.1 / Jest 30.4.2 为本机测试环境；小程序运行时无 npm 依赖。33 项 Jest 和 3 项独立 pytest 通过；微信平台行为未实测。
- 导入开发者工具的目录为 `wechat-miniprogram/`；当前配置使用游客 AppID 占位，真实授权/预览需换自己的 AppID 并配置隐私指引。
- 尚无本机微信开发者工具，未编译或真机验收，未上线。
- 记录：[小程序任务](tasks/2026-10-12-wechat-miniprogram/progress.md)。
