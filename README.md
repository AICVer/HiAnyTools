# 批量图像转 PDF

本机图形工具：选择图片或文件夹，每张图片生成一个同名 PDF。

微信小程序版本已新增到 `wechat-miniprogram/`，请按[小程序导入说明](wechat-miniprogram/README.md)使用微信开发者工具打开。下面的操作说明仍针对桌面版。

## 使用

1. 在 Finder 中双击 `启动图像转PDF.command`。
2. 点击「添加图片…」多选图片，或「添加文件夹…」读取该文件夹当前层级。
3. 在「保存到」选择 PDF 输出目录，默认是本项目的 `output/pdf/`。
4. 点击「开始转换」，等待窗口显示成功、跳过和失败数量。

同名 PDF 已存在时跳过，不覆盖；不同文件夹或不同扩展名的同名图片也共享同一输出名称，后处理的图片会跳过。需要分别保留时，选择不同输出目录或先重命名图片。

## 首版范围

- 支持 JPG/JPEG、PNG、BMP、WebP、单页 TIFF；不读取子文件夹。
- 保留原图像素尺寸和比例，不裁切；自动按 EXIF 方向旋转，透明区域铺白底。
- 普通 RGB/灰度 JPEG 直接嵌入原始压缩数据；需要旋转或转换的图片以 PNG 数据嵌入，避免再次有损压缩。
- 纸面尺寸按 150 DPI 换算，不强制 A4，不使用源文件 DPI；不改变像素分辨率。
- 单张失败继续下一张；输出完整写入后才生成最终 PDF。转换期间请等待完成再关闭窗口。
- 不支持 HEIC、GIF、多帧 WebP、多页 TIFF、高位深/HDR；不含 OCR、合并、压缩率调节或专业 ICC 印刷色彩管理。
- 首版面向本机 macOS；输出目录需支持硬链接，默认本机 APFS 目录可用。外接 FAT/exFAT 盘可先输出到本机再复制。

## 本机环境

使用已存在的 Miniforge `base`：Python 3.12.12、Pillow 10.4.0、PyMuPDF 1.27.2.3、Tk 8.6 和 rich。没有安装新依赖，也不访问网络。启动脚本使用本机 Miniforge 绝对路径，迁移电脑后需要调整该路径。

也可在项目目录执行：

```sh
/Users/wangshupeng/miniforge3/bin/conda run --no-capture-output -n base python image_to_pdf.py gui
/Users/wangshupeng/miniforge3/bin/conda run --no-capture-output -n base python image_to_pdf.py --log-level DEBUG gui
```

## 验证

在能访问桌面会话的本机终端运行：

```sh
/Users/wangshupeng/miniforge3/bin/conda run --no-capture-output -n base python -m pytest -q --cov=image_to_pdf --cov=image_to_pdf_gui --cov-branch --cov-fail-under=80 --cov-report=term-missing
```

- 29 项 pytest 全部通过，语句与分支综合覆盖率 99.29%，见 `docs/tests/report-test5.txt`。
- 5 张项目 JPG 转换成功；逐份核对单页、尺寸、嵌入 JPEG 字节一致、重复运行跳过，见 `docs/tests/report-test6.txt`。
- Poppler 渲染后的五页拼图已目视检查，无新增裁切、旋转错误或空白页；原始图片及原有 PDF 的 SHA-256 保持不变。
- 测试中使用真实 Tk 控件和后台线程；系统文件选择框在自动测试中模拟返回路径。未完成 Finder 人工双击与系统选择框点选的全程自动化验收：桌面 UI 检查工具超时，但同一启动脚本已实际运行。
- PyMuPDF/SWIG 的 5 条弃用警告不影响测试结果。

核心代码：`image_to_pdf.py`；界面：`image_to_pdf_gui.py`；测试：`tests/`；进度：`docs/agent/tasks/2026-10-12-image-to-pdf/progress.md`。
