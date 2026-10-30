# R1/R2 红蓝军对抗测试

开始：2026-10-29；完成：2026-10-30。红军负责独立攻击用例与结果判读；蓝军负责生产实现。**软件门禁 Gate 1：PASS，可进入 R3/R4。** 最终 30 项独立红军用例全部通过，无未解决的阻断缺陷。该结论适用于下列冻结快照，不代表 iPhone 16 物理显示验收。

## 冻结快照

| 文件 | SHA-256 |
| --- | --- |
| Sources/ImageEngine.swift | 2f69a5015c9c8f3880470be9ea41930f9df8236b28190692fedc510acb0f0ab3 |
| Sources/ExportOptions.swift | 6e3de64f0268c22f7a61a6fd8cbab4a35489aa7e88a8a742a1062f6fec0869d0 |
| Sources/HDRImageLabApp.swift | 58290abfc81e4bf607dc2977a952fd6f2956a7772f084a001d2f17eb4927e6ef |
| tests/Probe.swift | 5beb75efef9ea89045ded07facbf9aaf11e496cd4005ba2faafaf42e6f7cf8c4 |
| tests/red_team_r1_r2.py | 661a6217fe4aff59e80230ca16a14e205dc66792de6b214e51805a2a7d3fcc15 |

最终 30 项执行前后生产四文件摘要一致，证据：`output/red-team/round1/snapshot.json`。源码变更后此轮审查不再直接适用，须确认影响范围并重新验证。

## 已执行攻击

命令：`/Users/wangshupeng/miniforge3/bin/conda run --no-capture-output -n base python -m pytest -q tests/red_team_r1_r2.py`，需本机 Core Image 图形服务权限。

首轮原始结果：`output/red-team/round1-first-run.txt`，**29 passed in 12.01s**。

最终原始结果：`output/red-team/round1-final-run.txt`，**30 passed in 12.76s**，由主代理在相同冻结快照下执行，红军独立读取原始结果、色差 JSON 和前后摘要确认。

| 攻击面 | 验证口径 | 结果 |
| --- | --- | --- |
| 真实 P3 SDR 到 JPEG/HEIC/PNG/BMP | 130×195、8 位 SDR；原始 SHA-256 保持 | 4 项通过 |
| DPI 四格式 | 301 dpi，误差 <0.03；PNG 更改 DPI 前后栅格完全一致 | 4 项通过 |
| EXIF 方向后宽/高缩放 | 定边 123 像素、方向应用一次、比例舍入误差 | 2 项通过 |
| 有损质量极值 | JPEG/HEIC 0.05 与 0.98 发生真实编码变化 | 2 项通过 |
| 可达目标字节 | JPEG/HEIC 实际文件 ≤ 上限，保持指定 160×120 | 2 项通过 |
| 不可达目标 | 四格式 1 字节上限明确失败，不缩小尺寸，不留下文件 | 4 项通过 |
| 非法与过大参数 | 质量越界、DPI 越界、零/负尺寸、宽高冲突、零目标、超 50MP 放大 | 9 项通过 |
| 真实透明 PNG | 缩放后仍含完全透明与完全不透明，源文件不变 | 1 项通过 |
| 真实 PQ PNG | SDR 转换与16位 PQ缩放/DPI，源文件不变 | 1 项通过 |

独立色彩对照补测：真实 P3 JPEG 经生产 Swift 引擎导出原尺寸 sRGB PNG，与 Pillow/ImageCms（LittleCMS，相对色度）独立转换后使用 colour-science 算 CIEDE2000。平均 **0.12389**、P95 **0.68139**、最大 **4.16454**；预先设定的工程容差为平均 <1、P95 <3，故通过。最大误差如实保留，不要求逐像素 ΔE<1。比较包含两个 JPEG 解码器及 CMM 的差异，不作为校准或通用人眼阈值。原始结果：`output/red-team/round1/lcms-reference.json`。

## 数据依据

用户指定根目录内的三张真实样图：

- `GainMap-vs-HDR/sdrOriginal.jpg`：650×975，ICC `image P3`，无 GainMap 标记。
- `hdr-sticker/example.png`：720×594 RGBA8、sRGB、透明。
- `hdr/b614d537-4817-46fc-9120-498f090161e2.png`：1500×1000 RGB16，cICP `9/16/0/1`、ICC `Rec. 2020 PQ`。

另有固定随机种子的噪声、方向和透明边界合成样本。真实文件路径、哈希、元数据见 `output/red-team/corpus-candidates.json`。未修改、搬移或上传用户数据。

## 执行边界与问题

- 暂无可复现生产阻断缺陷。
- 补充最终 30 项执行在红军子代理中两次被自动权限审批超时中止；这不是算法失败，也没有把超时当作通过。主代理随后完成同一脚本的有效执行，已解除该执行阻塞。
- 蓝军报告已在 iPhone 17/iOS 27.0 Device Hub 中从相册选入 960×640 SDR 色阶、设 DPI=300、点击「生成 SDR JPEG」，出现「保存或分享 SDR 文件」。这是实际模拟器导入与导出成功证据，不代表红军亲自完成全流程或真机物理测试。
- 蓝军独立功能回归 87 项与 iOS 模拟器构建通过；详见主代理本组报告，不用历史测试代替本组。
- 数字键盘缺少 Done 的便利性问题为 P2，不影响实际点击生成；可在 R8 完善键盘收起，不阻断本组。
- 本轮数据/编码验证在 macOS 共享生产引擎；iOS 设备构建、模拟器流程由蓝军报告分别记录。
- iPhone 16 原件、真机 XDR/亮度仍待硬件验收。用户已同意后续 R4 采用软件门禁，真机单列待验收。
