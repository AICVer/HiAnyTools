# R7/R8 红蓝军对抗测试

日期：2026-10-30。**第四组软件门禁 PASS：最终核心复测19项全部通过，SDR主图P1已修复，源码时序审阅及典型模拟器交互通过。** 首轮1项未通过、18项通过，定位到原生HDR适配影响SDR primary解读；蓝军仅隔离SDR主图解码后，在原阈值下复测通过。iPhone 16真机XDR仍单列待验收。

## 核对口径

RGB/Y统计当前编码前HDR工作图，R/G/B为线性BT.2020，Y为nit；HSV统计源图8位sRGB SDR表观，统计与查看模式独立。默认采样长边512、每通道256桶；透明像素排除，灰色H记undefined，负值/越界单列计数。

## 独立红军用例

- 嵌入已知sRGB ICC的纯红/绿/蓝：colour-science独立转换线性BT.2020 RGB、Y nit与HSV主色角；误差按桶宽和CMM边界设置。
- 128灰：RGB必须在线性约0.216、V为编码约0.502，避免混淆Gamma域；H应全部undefined。
- 部分透明及全透明：对直通色计数，完全透明排除，不把预乘颜色当暗色，也不伪造透明图统计。
- HDR 1000nit：RGB/Y值域保持超白，SDR峰值滑块不改变既有HDR；SDR增强只改变HDR工作图统计，不改变源SDR HSV。
- 每个通道 `bins + underflow + overflow + undefined` 与对应有效像素总数守恒；透明/非法/有效总数与采样矩形相符。
- 512长边采样、1像素极小采样、EXIF方向与显示几何、非法采样参数。
- 4类真实GainMap分别实际执行HDR/SDR/GainMap三条预览路径，不仅检查辅助图旗标；无GainMap明确失败而不生成假图。
- 真实双GainMap的SDR导出，与Pillow独立读取主JPEG、LittleCMS相对色度转换比较，沿用平均ΔE00<1、P95<3的工程容差，核对SDR基图不是另一次无意的HDR色调映射。

测试：`/Users/wangshupeng/miniforge3/bin/conda run --no-capture-output -n base python -m pytest -q tests/red_team_r7_r8.py`。全部本机，只读用户原件。

## R8时序审阅初步事实

蓝军新增了MainActor导入generation、ActorSession对旧generation的拒绝、Photo异步Data返回后校验、defer只修改当前代busy、preview/statistics携带revision+mode+peak key并按key显示，能阻断旧图/旧直方图发布到当前视图。最终结论须对最终冻结源码复查，不用字符串匹配测试冒充并发UI自动化。

已向蓝军报告UI活性分支：`.task(id:previewKey)`如果因导出busy而提前返回，busy恢复本身不改变key，当前预览/统计可能不重启。蓝军确认该路径并移除外层busy跳过，依赖info/generation守卫和Actor串行；同时把分享URL失效移到真正改变导出结果的输入变化，避免迟到预览清掉新分享入口。该项按冻结源码复核关闭，不把它伪称为已穷举所有UI时序。

真实iPhone16物理XDR、性能/内存和完整主观画质仍不在软件门禁中伪造通过。

## 首轮冻结与实际结果

由主代理执行，红军独立读取 `output/red-team/round4-run.txt`：**1 failed, 18 passed in 10.13s**。旧日志、快照和脚本已分别保存在 `round4-first-run.txt`、`round4/snapshot-first.json`、`round4/red_team_r7_r8-first-frozen.py`。

| 文件 | SHA-256 |
| --- | --- |
| ImageEngine.swift | ae50e620dbb2d9afa92502574383b82a3abcd1e7d9324e3d420cc391c798b1cf |
| ExportOptions.swift | 6e3de64f0268c22f7a61a6fd8cbab4a35489aa7e88a8a742a1062f6fec0869d0 |
| HDRPNG.swift | f5edf8d51d20d60250de94b867dbbf4c04b69a0e65aff1b6f6217c5dcc589807 |
| Histogram.swift | dba27748cdb719753d63c0fe60557137bd3d007626e05d340dae93ac18fd59b6 |
| HDRImageLabApp.swift | ac51e8333d8c7d8402c24e06a27dba28791500765bcee17212ac71cc762a34b9 |
| Probe.swift | cd5569ce21a1fdedc98c353b7d4d5c589e2fe24579929096fe15b0f4ebcbb16d |
| red_team_r7_r8.py | 4df7166ce6e5584a9e85ef2035814249b03034abd621589087e2aa5ce17a7092 |

唯一失败：`GainMap-vs-HDR/gainMap.jpg` 的SDR导出对比Pillow主JPEG+LittleCMS sRGB参考，平均ΔE00=**1.243261**、P95=**3.462923**，均超过预设<1/<3。相同工程对普通P3 SDR的Gate1参考平均仅0.123891。

红军独立核查 `sdrOriginal.jpg` 和 `gainMap.jpg` 的ICC完全相同：620bytes、SHA-256 `73c48a9c10d529ee265e617f016db238a118ba4247491b16eac3e301f2f3352a`、描述 `image P3`；三条TRC均为sRGB型参数曲线。因此不能简单归为两个ICC不同，需查HDR展开后的内部表示/SDR色调映射策略。该事实已交蓝军定位；未擅改测试阈值。

## 对唯一失败的独立定位

1. 蓝军生成7个原生诊断变体：Data-backed CG默认/显式SDR/关闭luma、CIData expandfalse的toneMap false/true、CG与CI显式原ICC覆盖。红军对照全部得到相同mean=1.243261/P95=3.462923/max=52.957954。故简单retag ICC或切换toneMap参数没有修复证据，生产未盲改。
2. 将原620byte ICC与本机CG标准DisplayP3 536byte ICC逐tag比较：r/g/b XYZ矩阵和r/g/b TRC全部字节相同，wtpt/chad仅少量s15Fixed16最低位差。两个JPEG均4:4:4采样，不是采样比例不同的解释。
3. Adobe XMP明确 `BaseRenditionIsHDR=False`、容量0..3；复用HiIccTool现有ISO解析器，在辅助JPEG中解析到baseline headroom=0、alternate=3、use_base_colour_space=true。因此primary确为SDR，要求还原SDR基图有元数据依据。
4. 红军制作只读原件的诊断副本 `output/red-team/round4/primary-no-gainmap.jpg`：去除HDR XMP/MPF/ISO标记，保留ICC、EXIF和原始JPEG SOS之后扫描码流。Pillow核对解码RGB完全相同，源SHA保持，证据 `primary-copy-evidence.json`。
5. 蓝军用同一生产SDR出口转换该普通primary副本，红军独立比对恢复为 **mean=0.123513、P95=0.681387、max=4.164538**。严格sRGB线性单位立方体内mean=0.131894，外mean=0.053911。最差位置(504,708)，原P3[20,20,28]，参考sRGB[20,20,29]，native[17,21,26]。这排除了“一般色域外策略必然导致1.24”的推断，支持HDR适配影响SDR primary路径。

7变体与普通副本色差JSON分别在 `sdr-variants-reference.json`、`primary-copy-reference.json`。蓝军依据该结果实施了下节仅隔离SDR基图解码的最小修复，没有修改HDR重建或降低原色差阈值。

## SDR主图修复与核心复测

蓝军新增 `JPEGPrimary.swift`，在已确定JPEG GainMap的未展开主图为SDR（headroom≤1且非HDR色彩空间）时，仅对SDR基图解码隔离辅助标记；HDR重建仍使用原URL，HDR-primary仍由系统映射。未修改用户原件，未重编码JPEG扫描。

红军逐行复核新解析器：按长度跨过Exif/ICC段，不把其中缩略图伪FFDA/FFD9当边界；真实扫描内识别FF00、RST，扫描遇到真实标记再解析长度；支持渐进多SOS；在首主图EOI停止；截断和非法长度抛错。蓝军6项framing测试覆盖这些边界，全部通过。

同一19项红军脚本最终复测 `output/red-team/round4-retest.txt`：**19 passed in 10.18s**。平均ΔE00从1.243261恢复为 **0.123513**，P95从3.462923恢复为 **0.681387**；原<1/<3阈值未改。`round4/sdr-primary-reference.json`及新的 `snapshot.json` 已由红军独立读取，7个生产/Probe文件before/after一致。

最终与首轮相比的变动文件：

| 文件 | SHA-256 |
| --- | --- |
| ImageEngine.swift | d70df475a2c6d759b038720c27ebe4893ff8e75fdc83c0f0cee246a8850f5294 |
| JPEGPrimary.swift | a75b103a1461d8597bb662ef6068eb1433f92830ba7b9168fcb0a08010c33d3b |
| Probe.swift | e3bf7b3916f298c1e919b10cf9430188eadc299233db1c8f451868a9df0ae45f |

其余冻结文件和红军脚本沿用首轮表格。数学统计与源码时序条件已通过；模拟器交互证据与最终门禁见下节。

## R8已验证的源码守卫

在首轮最终冻结中，忙碌时跳过`.task`的分支已移除，预览更新也不再无条件清除HDR分享URL；改由峰值、导出参数、格式、切图等真实结果失效条件清除。红军复查确认该UI活性路径在代码上关闭。

MainActor导入generation、Actor旧load拒绝、Photo回传守卫、当前代defer和按requestKey展示均已复核，尚未发现确定性串图路径。此为源码时序审阅，不伪称已完成所有并发调度的自动化穷举；实际模式切换和直方图交互证据由蓝军另记。

## 最终整合证据复核

2026-10-30，红军读取最终原始日志并重新计算冻结哈希：上述6个生产文件及Probe共7项全部匹配，未出现测试后代码变化。`report-test12-all.txt`记录显式收集蓝军与红军脚本后 **232 passed in 78.21s**（蓝军127项、红军105项）；不能以默认pytest目录收集代替红军脚本的显式执行。

`report-test12-coverage.txt`记录平台无关Swift核心行覆盖率 **95.68%**、区域覆盖率 **84.75%**、函数覆盖率 **91.30%**；UI/MainActor不在该分母中，工具链没有提供分支覆盖率。`report-test12-device-build.txt`与`report-test12-simulator-build.txt`均有 **BUILD SUCCEEDED**。设备构建未签名，不能由此宣称已安装iPhone或已验证XDR物理效果。

核心与构建证据有效；结合下述模拟器交互证据，软件门禁通过。

## 最终模拟器交互证据

蓝军通过CUA实际操作iPhone 17 / iOS 27模拟器；红军独立读取以下AX记录和截图，而非自行操作模拟器。截图只支持软件交互与布局结论，不支持物理亮度结论。

- `output/tests/gate4-channels-ax.json`：逐个选择G/B/Y/S/V，均显示174,592个已分箱样本；RGB域为线性BT.2020、1=203nit，Y上界348.0nit，S/V域为源SDR sRGB编码RGB、上界1.0。统计域未随通道混淆。
- `gate4-sdr-export-ax.txt`与`gate4-mode-share-ax.txt`：960×640 SDR图按512×341采样，HDR/HSV有效样本均174,592；348nit增强后预览余量1.71×。PQ PNG生成后出现分享入口；切换SDR查看后该入口仍保留，符合查看模式不改导出结果的约定。
- `gate4-gainmap-hdr-ax.txt`、`gate4-gainmap-sdr-ax.txt`、`gate4-gainmap-map-ax.txt`及HDR/Map截图：64×64 GainMap JPEG的三视图实际切换；HDR截图显示灰主图、GainMap截图显示白色辅助图。计数为4,096且显示全像素统计，源HDR的增强滑块禁用。
- `gate4-back-to-sdr-ax.txt`与同名JPG：从GainMap查看状态重新导入960×640 SDR后，界面仅保留HDR/SDR两模式并选中HDR，显示色阶图、174,592样本；旧64×64统计和分享入口均未残留。
- `gate4-histogram-r-log.jpg`及同名`-ax.txt`、`gate4-histogram-h.jpg`及同名`-ax.txt`：经用户允许重新打开模拟器后，图表截图与完整AX已补齐，红军均独立复看。R通道红色图形、七通道选择器、线性BT.2020/参考白说明及512×341采样标签清晰可见，对数开关为1；H通道显示紫色峰线、0…360°和源SDR sRGB统计域，对数开关为0。H为12,696个分箱样本、161,896个无定义色相，合计174,592，与有效HSV样本一致。补录时峰值为408nit、预览余量2.01×，R横轴上界显示2.0倍参考白；这是后续界面状态，前述348nit导出证据保留原值，未混为同一次参数设置。此前图表截图保存失败的留存缺口已关闭。

这组证据检验了典型连续切换和导出后的状态保持；不等于所有异步调度已穷举，也不等于iPhone 16真机验收。

## 门禁结论

**PASS（软件范围）**。原有P1问题按原色差阈值关闭；核心统计、三条预览路径、JPEG主图隔离、冻结源码守卫、全部232项整合回归及双目标构建通过。模拟器已完成通道切换、增强后导出、分享状态保持、GainMap三视图与回切SDR的典型交互检查，没有遗留阻断缺陷。

未验证内容为真实iPhone 16的XDR亮度/显示映射、真机性能与内存、外部查看器完整兼容性，以及全部异步调度的穷举；这些不纳入本次用户已批准的软件门禁通过结论。未签名设备构建不能视为可直接安装的IPA。
