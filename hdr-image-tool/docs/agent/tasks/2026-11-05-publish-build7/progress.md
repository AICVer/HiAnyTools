# 构建7版本标签及远程发布

- 负责人：Codex。用户明确授权打版本tag并推送HiAnyTools；发现历史PDF/output后，用户明确选择“推送整个现有仓库及完整历史，包含已提交的其他工具、PDF和output产物”。
- 基线：main/e80782a070fd1157023bdb5e9c3d6257fc440463；版本0.1.1、构建7。文档在既有干净整合worktree维护，不触碰main的无关修改/删除/子模块内容。
- 远程预检：HiAnyTools无分支或标签。保留origin=https://github.com/AICVer/image2pdf.git；新增hianytools=https://github.com/AICVer/HiAnyTools.git。
- 已创建annotated tag：hdr-image-tool/v0.1.1-build.7；tag对象7a55f1337de125c2eb6d2ae3d4d52841daa3c5d3，解引用为e80782a070fd1157023bdb5e9c3d6257fc440463。
- 已执行git push --atomic，只指定main和本次标签，未强推、未推其他分支/标签；首次推送成功。git ls-remote确认远程main、tag对象及解引用SHA与本地完全一致。
- 本轮验证：版本配置0.1.1/7；19份冻结源码/测试SHA256全部匹配。没有产品变化，不重复运行test28的251通过/2跳过及6项UI测试；test29真机安装启动与未验物理XDR/全面手势的边界保持。
- 发布结果文档单独提交后安全快进main并正常推送；远程最终main/hash及工作区保留核验写入本机output/publish-build7-20261105/summary.json，不移动本次版本标签。
- 主干未提交文件保持；本轮不创建GitHub Release、不上传签名安装包或本地未跟踪调试数据。完整历史中原已提交产物按用户确认保留。
- 知识自检：见knowledge-review.md；不建议新增公共知识，不修改知识库或私有memory。
