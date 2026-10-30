# 二维色度与三维散点越界排查

日期：2026-10-30；负责人：主代理。范围：本地诊断并汇报现有逻辑，没有修改 App 源码、提交 Git 或安装到手机。父仓库 main；项目目录原为未跟踪，保留其他未提交修改。

## 当前用户要求

- HDR 与 SDR 按各自的传递函数/输入语义解码；二维、三维均应使用正确的线性颜色计算。
- 参考包络上限默认 10000 nit，参考白保持 D65 / 203 nit。这是本轮新要求；当前 App 仍默认 203 nit 包络，尚未实施新默认值。
- 本轮措辞“三点”按上下文理解为“散点”；排查完成，不扩展为直接修复或部署任务。

## 已读取依据

- 项目 context、requirements、hdr-output-contract、参考包络任务及现有 test18 诊断线索；本轮重新编译探针、重新复现，不把旧记录当作本轮执行结果。
- `/Users/wangshupeng/知识库/规范/Agent协作与知识入库流程.md`；正式 K02 色域指标与边界映射、K06 ICC与HDR图像处理边界。K02 要求共享亮度尺度并区分边界近似与实际越界；K06 要求明确容器解码、分析数据与预览表观。
- diagnosing-bugs / color-science 技能。本轮仅诊断，因此修复与修复后的回归阶段不适用；保留失败用例作为后续修复入口。
- 本机 colour-science 0.4.7；只读参考 HiMagic/docs/gamut_volume.md。该工程的共同峰值归一化与当前 App 的 203 nit 白归一化不同，不能直接搬用其参数。

## 当前真实计算链

1. `Sources/ImageEngine.swift:126`：Core Image 根据源色彩描述解码，HDR 请求 expandToHDR=true / toneMapHDRtoSDR=false；GainMap 由系统展开。SDR 表观另外解码。
2. `ImageEngine.swift:207`：`outputImage` 对已有 HDR 返回原 HDR 图；对 SDR 应用 203…600 nit 高光增强，203 时恒等。
3. `Sources/PixelDistribution.swift:113`：分析始终取 outputImage，而不是当前 HDR/SDR/GainMap 预览选择；最长边64，RGBAf 渲染到扩展线性 BT.2020，恢复非预乘 RGB。工作 RGB=1 对应203 nit。
4. `PixelDistribution.swift:52`：线性 BT.2020 → XYZ（203 nit 归一化）→ xy/u′v′、Lab、CAM16-UCS。Lab 白 XYZ=(0.950456,1,1.089058)；CAM16 同一 D65 白，L_A=100、Y_b=20、Average、完全适应。Lab L*>100 / CAM16 J′>100 可以出现。
5. ICtCp：工作线性 RGB×203 → BT.2100 RGB→LMS → PQ 编码（固定10000 nit）→ ICtCp；只绘制 LMS 在合法PQ域内的点，端点容差1e-8 nit。没有把PQ编码RGB直接套在线性矩阵上。
6. `Sources/ReferenceGamut.swift:31`：参考原色线性RGB六面立方体 → 原色矩阵转BT.2020 → ×peak/203 → 共用 PixelColorMath。每面8×8格，暗端平方采样，386顶点/768三角形；UI默认峰值203（`PixelVisualizationView.swift:14`）。
7. 二维是标准原色 xy 三角形/u′v′变换，亮度缩放抵消；三维壳面按深度画完后再画全部散点（`:205`、`:237`），因此不能凭遮挡关系判断内外。坐标轴重排与旋转/缩放为共享变换，没有发现点/壳采用不同投影。

统一到线性 BT.2020 后复用数学函数本身合理；源 HDR/SDR 的解码语义必须先区分。当前没有在 PixelColorMath 中再做 EOTF，这是正确的，因为传入值已经线性化。

## 三个假设与实证

按 ①包络峰值不足、②非线性网格近似、③源原色真实越界排序探查。三项均有合成复现，不能据此认定用户未提供的具体图片属于哪一项。

### 1. 默认包络峰值与新要求不同

实际 PQ PNG 中203/1000 nit灰阶，回读 Lab L*≈99.9965/181.3745，ICtCp I≈0.580679/0.751826；203 nit参考壳白点 L*=100、I≈0.580689。1000 nit点高于203 nit壳是合理的亮度越界。新默认10000 nit会解决这类范围不足，但不会解决所有越界。

### 2. 合法RGB落在分面近似外，确定可复现

最小样本：线性BT.2020 RGB=(0.00001,0.6128143024535753,0.1972192905039931)，三个通道严格处于(0,1)。同一203 nit参考尺度，生产Swift返回 Lab=(71.3634914771,-124.3908405526,32.1397620431)。生产网格的有向立体角绕数≈7.07e-17（外部），内部应≈1。

原因：RGB立方体面经非线性变换是曲面；当前用变换后的顶点直连平面三角形，局部内缩。闭合拓扑、顶点坐标正确不保证几何包住所有内部颜色。

固定随机种子20261030，180个刻意靠近六面的严格内部样本（不是普通图片像素分布）：

| 峰值/nit | 每面格数 | Lab在显示壳外 | CAM16-UCS在显示壳外 | ICtCp在显示壳外 |
| --- | --- | --- | --- | --- |
| 203 | 8 | 40 | 163 | 62 |
| 203 | 16 | 37 | 166 | 49 |
| 10000 | 8 | 31 | 167 | 60 |
| 10000 | 16 | 30 | 167 | 34 |

以上计数只说明近边界样本的包含性缺口，未测屏幕偏差大小；加密不保证计数单调，不能推导普通照片越界率。后续应以源参考RGB约束判断实际越界，显示网格按曲面误差控制采样；不得用裁切图像点来掩盖问题。

### 3. 真实超出某个原色三角形是可能的

实际导入的Display P3红色 xy≈(0.6799945,0.3200040)。保持XYZ转BT.2020后，在Y=1尺度蓝通道≈-0.0052822，确在BT.2020三角形外；理想矩阵P3纯红的BT.2020蓝分量约-0.00121034。P3不被BT.2020几何上完全包含。超sRGB更正常。改变亮度上限不改变二维色度。

## 建议采用的明确契约

- PQ HDR：源PQ码值 → 源原色PQ EOTF，得到绝对线性RGB/nit → 源RGB2XYZ → XYZ_abs/203 → Lab/CAM16-UCS。HLG/GainMap按其实际源语义解码/重建，不能全部当PQ。
- SDR：源码值 → 源EOTF/ICC解码 → 源线性RGB → RGB2XYZ → 按SDR白203 nit定标后走同一Lab/CAM16-UCS路径。若目标是原始SDR分析，需与现有“增强结果分析”明确区分。
- ICtCp：两类输入均须先取得线性BT.2020 RGB绝对亮度/nit，再RGB→LMS→PQ→ICtCp。HDR若为P3原色也须转换到BT.2020。输入不能是未解码的任意RGB码值。[colour RGB_to_ICtCp文档](https://colour.readthedocs.io/en/latest/generated/colour.RGB_to_ICtCp.html)。
- 参考包络默认上限10000 nit；参考白203 nit；PQ常数10000 nit。三者职责不同。保留203白时，10000 nit中性点的Lab L*=409.2320、CAM16 J′=203.8200、ICtCp I=1；不能为了把L*限制到100而把203白换成10000白。
- 二维xy/u′v′不依赖统一亮度缩放；10000 nit只影响三维体积与PQ绝对量程，不会扩大二维原色三角形。
- `XYZ_abs/10000`是另一种白/尺度契约，不能与这里`XYZ_abs/203`混用。CAM16白与样本必须使用一致尺度，[colour CAM16-UCS说明](https://colour.readthedocs.io/en/develop/generated/colour.XYZ_to_CAM16UCS.html)。

## 验证及边界

- Miniforge base Python；实际Swift探针重新编译后，现有二维/三维坐标和包络模块36项通过，colour-science独立对照。
- 首次沙箱执行31通过、3失败、2错误：Core Image图形设备不可用导致合成/采样失败。允许本机图形设备访问后36通过；保留两份日志。
- 新增诊断断言明确失败：`conda run --no-capture-output -n base python -m pytest -q output/gamut-audit/test_mesh_containment.py`，1 failed；证明假越界存在，不冒充修复后回归通过。
- 相同最小断言独立重跑仍为1 failed、相同绕数；`report-test19-containment-repeat.txt`保留重复性证据。最终源文件SHA256与排查开始时一致。
- 审计和补充脚本成功；产物 `output/gamut-audit-19/results.json`、`checks.json`。所有图像为本地合成；未上传图像/代码、未新增依赖/环境变量。
- 未收到用户具体异常图，未做该图逐像素分类；未重新构建/安装App或验证手机UI，因为生产代码没有改动。无新增功能/生产代码，未重跑完整套件或重算覆盖率；既有覆盖率不当作本轮新证据。
- 没有修改源代码。SHA256：PixelDistribution.swift `83a3908514d447ae3d13e165e0daea733d5292624c24e9b187fe49dcef89a6dd`；ReferenceGamut.swift `7f95b4fc03ef793eb4a25e6748cbf4f40a2688abcfedf1e9dd06afa07ec6f659`；PixelVisualizationView.swift `1df06573f8a259b0b3cd7b56e1f76161a5cd781f0a874a01c1e62398e105c02b`；ImageEngine.swift `fc29e14a77ca32b239810563fa164e9dddfdf5a2873cde2fafde045eb7954a84`。

状态：排查与汇报完成；默认10000 nit、分析源策略及网格改进均未实施。总结日志见 `docs/tests/report-test19.txt`。

后续用户提供真实原图/截图，已在[实图排查](../2026-10-30-image3920-diagnosis/progress.md)中定位这张sRGB JPEG的主要离群原因：浮点解码负值、低质量采样和非物理XYZ有效性检查缺口；不再用本页的一般网格/P3解释替代这张图的实证。见test20。
