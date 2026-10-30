# 全屏、GainMap 合成、色域导出与像素分布

日期：2026-10-30。负责人：主开发代理。仅本机开发，原图只读，无 Git 提交或推送。

## 已确认范围

- 双击当前图像全屏，同样双击或关闭按钮退出，沿用 HDR/SDR/GainMap 显示链路。
- SDR+灰度：当前原图或另图的 SDR 线性 Y，黑0不增强、白1最大 G，倍率 G^Y；默认600/203，首版滑动范围1…16倍。另图先应用方向、等比居中裁切。透明灰度来源以透明度加权至黑，基础图保留透明。可恢复源图；重复应用不累计合成。
- HDR：PQ PNG/TIFF及ISO GainMap JPEG/HEIC，P3或BT.2020原色。PQ使用相应PQ曲线；GainMap基图P3使用sRGB曲线，BT.2020使用系统标准BT.2020编码。
- SDR：sRGB/P3/Adobe RGB；等XYZ为源→XYZ→目标并裁切越界，RGB直通保留源SDR编码值并重新解释为目标空间。两策略都输出正确ICC，不能先统一转sRGB再直通。
- 像素可视化：当前HDR工作图，默认最长边64采样。CIE1931 xy、CIE1976 u′v′；sRGB/P3/2020三角形独立开关。Lab/CAM16-UCS/ICtCp三维点云，自动旋转、拖动、缩放。
- 用户确认“自动宣传”指自动旋转；固定D65/203nit参考。CAM16采用HiGamut观察条件LA100、Yb20、平均环绕、完全适应；ICtCp按BT.2100 PQ绝对亮度，未沿用HiGamut的JND显示倍率。

## 实现与验证进度

- 已实现引擎合成与两类HDR/三类SDR空间；首轮GainMap四种组合全部通过ISO辅助图及实际HDR回读。
- PNG的AdobeRGB回读有时没有系统色彩空间名称；改为检查实际ICC色度转换，不用字符串等价冒充色度等价。
- ImageIO BMP忽略色彩描述；经标准V5 ICC实验，本机ImageIO拒绝该文件，故生产BMP仅开放sRGB，宽色域使用PNG/JPEG/HEIC。V5实验实现保存在output/BMPProfile-investigation.swift，未丢弃函数或接入生产。
- 已实现六项界面，首次模拟器构建成功；最后代码变动后需重新构建及实际交互。
- 像素坐标已用colour-science独立核对，当前15项坐标/采样测试通过；测试日志保留失败与修复过程于report-test13-*。
- 软件回归、核心覆盖率、最终构建及文档已完成，结果见下方最终状态。模拟器交互因锁屏待验收；真机XDR与性能仍单列待验收。

## 参考与边界

- 已读取项目context、知识库协作流程、正式K06与color-science技能。未写知识库或修改其他Hi项目。
- 只读参考HiGamut：`packages/backend/app/services/color_science.py`、`packages/frontend/src/components/GamutViewer/sceneCoordinates.ts`和`index.tsx`，采用亮度朝上/统一缩放/轨道旋转策略；未引入Python或Three.js运行时到iOS。
- 数学坐标不从SDR显示颜色倒推；点云颜色取SDR表观仅辅助辨识。黑色无定义色度、透明和模型无效点明确计数。
- [Apple HDR 双表观写出](https://developer.apple.com/documentation/coreimage/ciimagerepresentationoption/hdrimage)、[RGB GainMap](https://developer.apple.com/documentation/coreimage/ciimagerepresentationoption/hdrgainmapasrgb)、[BMP V5](https://learn.microsoft.com/en-us/windows/win32/api/wingdi/ns-wingdi-bitmapv5header)、[colour CAM16-UCS](https://github.com/colour-science/colour/blob/develop/colour/models/cam16_ucs.py)、[colour ICtCp](https://colour.readthedocs.io/en/develop/_modules/colour/models/rgb/ictcp.html)。

- 合并回归首轮278项通过；随后复核修正P3目标分量光级与GainMap目标空间headroom，新增5项边界测试。无HDR余量时系统不写ISO辅助图，生产明确提示提高增益或改存SDR/PQ，不伪造HDR文件。最终回归已通过，见下。
- 最终界面验收时CUA报告Mac锁定，已异步请用户解锁；未绕过锁屏，继续完成构建与文档。

## 最终软件状态

- 283项完整回归通过（232基线+51新增），96.91s；核心行94.08%、区域82.66%、函数89.80%，UI和光谱静态表除外。
- 最终iOS设备/模拟器构建均成功；设备产物无签名。源码SHA存output/tests/extension-source-sha256.txt。
- 文档与使用清单同步更新；[test13报告](../../../tests/report-test13.txt)为本版本权威结果。随后已补齐主要界面交互，结果见test14；双指缩放因工具无多点触控支持单列手动待测。
- 最终模拟器版已安装并启动（iPhone17，PID61808）；后续已完成主要交互并更新版本。文档本地链接、空白及git diff --check通过；未自动提交或推送。

## 界面收尾

- 用户解锁后完成全屏、当前/另图灰度合成、恢复、P3 GainMap JPEG/HEIC、Adobe RGB两策略、BMP限制、xy/u′v′和独立三角形、三坐标系/自动旋转/拖动/重置。界面导出文件独立回读符合ICC与ISO辅助图。
- 修正合成图元数据文案和三角形开关断行，仅改两处UI文件；核心SHA保持。设备与模拟器重编译成功、最终版本重新安装启动PID77835。
- [test14](../../../tests/report-test14.txt)记录实际步骤、截图/AX及未覆盖范围；所有证据在output/tests/extension-ui。收尾最后截图时再次锁屏，不重复请求解锁补非必要截图。双指缩放和真机XDR仍待手动验收，未宣称通过。
