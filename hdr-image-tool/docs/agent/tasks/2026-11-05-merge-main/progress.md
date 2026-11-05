# 构建7合入主干

- 用户明确授权：将上述版本merge到主干分支，更新Git commit信息；允许本次提交/合并，不包含远程推送。
- 负责人：Codex，串行整合。源ui-workspace/root，目标main，二者初始HEAD均1e12a24。
- 范围：仅hdr-image-tool，包含四页工作台与构建7四项增量、测试、签名安装记录及配套文档；不纳入output、证书/签名产物或同级项目。
- 主干存在根.DS_Store、AGENTS.md/README.md删除、macos-img2pdf/.DS_Store、wechat-miniprogram及未跟踪目录改动。只记录快照，不stash/恢复/清理；在干净整合worktree完成no-ff合并，再安全快进main。
- 已核验：源生产代码与正式测试指纹等于test28最终快照，构建7安装/启动证据见test29。既有251项常规通过/2项缺外部参考跳过、6项UI通过是历史执行结果；本轮不为Git整合重复运行不变功能。
- 功能提交：74cf79999641b81c43c1f3d124a91d386177fff9，feat(hdr-image-tool): deliver HDR workbench 0.1.1(7)，32个文件均限hdr-image-tool。
- 合并提交：36ec99ff570a42d9856252d5cf4a87983131f877。在干净feature/merge-hdr-v7/root worktree以--no-ff合入ui-workspace/root；随后main --ff-only成功更新到此提交。
- 核验：合并树与功能提交树完全相同，目标只改变hdr-image-tool；生产/正式测试指纹等于test28最终快照。main快进后原有无关status逐字相同、受检文件SHA及wechat子模块状态相同。
- 冲突：无。没有改动产品行为，不重跑已通过且源码不变的功能测试。
- 当前：主干合并已完成，单独提交本次结果文档；该文档提交仍仅涉及hdr-image-tool，提交信息含Task: hdr-workbench-v7，不推送。
- 临时验证产物：开发阶段output仍保留在原ui-workspace/root；主干只纳入正式报告/源代码，Git整合摘要保存output/merge-main-20261105，不把签名、截图或临时构建入Git。
- 未验证：物理XDR/全面真机手势等test28/29限制保持，不随Git合并升级结论。
- 知识自检：knowledge-review.md；不建议新增入库。
