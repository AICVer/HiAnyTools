# 0.1.1真机发布与本地Git提交

日期：2026-10-30；负责人：主代理。用户明确要求编译、真机安装、版本向前迭代一次，并更新Git commit。本次用户授权覆盖项目默认“不自动提交”规则；仅提交hdr-image-tool，不推送，不纳入同级其他项目修改。

版本从0.1.0(4)递增为0.1.1(5)，bundle/Personal Team不变；算法源码保持test23已验证快照（345项回归、核心行95.65%）。读取context、LUT进度、既有安装test22、知识库协作规范与正式K10，区分构建/安装/启动和功能实测。

Git现状：父仓库main，hdr-image-tool整体未跟踪，暂无已暂存改动；另有根目录.DS_Store及wechat-miniprogram改动，均不纳入提交。新增本项目.gitignore排除output（约2.1GB的构建、签名、夹具与调试产物）、剖面文件和Xcode用户状态；源码资源中的AppIcon和指定LUT属于构建所需内容。

执行顺序：版本/文档更新 → 已有证书签名构建 → 版本/签名/描述文件校验 → 覆盖安装并核对设备清单 → 启动验证 → 审查暂存范围并创建一条本地提交。所有构建与图像处理本机完成，不安装依赖、不修改.env。

## 编译、安装与启动

- 本机现有证书签名构建BUILD SUCCEEDED，没有启用ProvisioningUpdates/设备注册，不创建证书或上传代码。签名codesign --verify --deep --strict通过。
- 实际包Info.plist版本0.1.1(5)、bundle local.hdrimagelab；描述文件包含当前iPhone，有效期至2026-11-06 14:48北京时间；内置17³LUT与源码资源逐字节一致。
- devicectl覆盖安装outcome=success，设备清单确认0.1.1/Bundle Version5。未卸载旧App；旧C6D89FC0测试JPEG缓存仍存在（元数据547352字节），不导出图像/像素。
- 首次启动因Locked被拒。用户回复“已解锁”后立即重试成功，activatedWhenStarted=true，PID4310；进程路径属于本次0A924B94安装目录，运行清单核对通过。
- Swift源码与测试探针逐项SHA保持test23快照，因此引用345项既有回归和核心行95.65%，不为版本元数据重复执行全部算法测试。此轮构建/签名/安装/启动为新执行证据，画质/XDR不在本次安装任务重测。
- 本轮修改只有版本/构建号、项目Git排除配置和相应文档；源码功能为此前完成且已验证的LUT/凸包版本。

## Git归档范围

- 初检暂存区为空，hdr-image-tool整体未跟踪。首次纳入其源码、AppIcon/LUT构建资源、共享Xcode工程、pytest、README/需求/输出契约/任务与测试报告。
- .gitignore排除output（约2.1GB构建、签名、临时图片）、profraw/profdata、Xcode用户状态及缓存；逐路径核对无描述文件、私钥归档、.env或output文件进入提交范围。
- 根目录.DS_Store和wechat-miniprogram原有改动保留，不提交。采用现有Git身份，在当前main创建新本地commit；不amend历史、不推送。
- 本次提交ID通过`git log -1 -- hdr-image-tool`查询，提交结果归档output/release-0.1.1-commit.json；避免在提交正文内自引用自身hash。只提交本项目路径。

状态：本轮编译、安装、版本与运行验证完成；以上验证/版本/源码基线一同作本地Git归档。最终commit以Git日志为据。详见[test24](../../../tests/report-test24.txt)。
