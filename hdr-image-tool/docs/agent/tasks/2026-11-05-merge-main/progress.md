# 构建7合入主干

- 用户明确授权：将上述版本merge到主干分支，更新Git commit信息；允许本次提交/合并，不包含远程推送。
- 负责人：Codex，串行整合。源ui-workspace/root，目标main，二者初始HEAD均1e12a24。
- 范围：仅hdr-image-tool，包含四页工作台与构建7四项增量、测试、签名安装记录及配套文档；不纳入output、证书/签名产物或同级项目。
- 主干存在根.DS_Store、AGENTS.md/README.md删除、macos-img2pdf/.DS_Store、wechat-miniprogram及未跟踪目录改动。只记录快照，不stash/恢复/清理；在干净整合worktree完成no-ff合并，再安全快进main。
- 已核验：源生产代码与正式测试指纹等于test28最终快照，构建7安装/启动证据见test29。既有251项常规通过/2项缺外部参考跳过、6项UI通过是历史执行结果；本轮不为Git整合重复运行不变功能。
- 当前：准备范围限定的功能提交，随后在干净整合分支合并/核验，再更新main与提交号记录。
- 冲突：待实际合并确认；不做超出需求的冲突重构。
- 未验证：物理XDR/全面真机手势等test28/29限制保持，不随Git合并升级结论。
- 知识自检：knowledge-review.md；不建议新增入库。
