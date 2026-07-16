# 贡献指南

[English](CONTRIBUTING.md)

感谢你帮助改进 Home Edge Bootstrap。贡献应保持聚焦、可审查，并能够在不访问任何真实网络或
账号的情况下安全复现。

## 提交变更前

1. 搜索已有 issue 与 pull request。
2. 说明用户可见问题和满足需求的最小方案。
3. fixture 必须使用合成数据。不得提交订阅 URL、节点列表、凭据、公网 IP、原始日志或未经
   人工检查的支持包。
4. 改变行为前先新增或更新测试，再运行相关 PowerShell 与 POSIX 验证入口。
5. 行为或用户指引变化时，在同一个 pull request 中同时更新英文文档与对应中文文档；该要求
   同时适用于仓库根目录文档和 `docs/` 下的文档对。

## 适配器提案

请先使用仓库的结构化适配器提案表单发起讨论，使维护责任、边界和验证证据保持可审查。

新增适配器或显著扩大适配器范围时，必须说明：

1. 设备、固件、运行时与文件系统/服务管理器边界；
2. 明确维护责任人；
3. 必需能力与目标支持分类；
4. fail-closed 探测、合成 fixture、备份、回滚与恢复行为；
5. 不含敏感信息的诊断与支持证据；
6. 许可与第三方源码义务；
7. 双语操作说明。

上述条件尚未满足时，应让实现保持外部状态。参考实现角色、与既有适配器相似或单个目标成功，
都不能建立“已验证”适配器成熟度或更宽兼容性。

## 测试

运行变更范围内的聚焦测试。请求最终审查前，按顺序运行两套本地验证入口：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\verify-local.ps1
sh scripts/verify-local.sh
```

如果当前环境无法运行其中一个入口，应明确说明限制并列出已执行检查。不得用真实配置或诊断
数据替代不含敏感信息的合成 fixture。

## Developer Certificate of Origin

每个提交都必须带有 Developer Certificate of Origin 签署。可使用 `git commit --signoff`，
或用你有权使用的真实姓名和电子邮件地址添加以下 trailer：

```text
Signed-off-by: Your Name <your.email@example.com>
```

姓名与电子邮件会成为公开、持久的提交元数据。如果托管平台接受相应签署，可以使用已验证的
GitHub noreply 地址；否则应使用你愿意公开的地址。

签署表示你确认有权根据项目 Apache-2.0 许可证与 Developer Certificate of Origin 1.1
提交该贡献。

## Pull request

pull request 应保持聚焦，说明验证证据和面向用户的文档变化，并回应审查。当拆分有助于审查
安全、许可或行为时，维护者可以要求拆分变更。

术语应遵循[兼容性](docs/zh-CN/COMPATIBILITY.md)与[治理](GOVERNANCE.zh-CN.md)。代码、文档、
仓库元数据、发布说明与推广不得声明超出提交证据的成熟度或支持范围。
