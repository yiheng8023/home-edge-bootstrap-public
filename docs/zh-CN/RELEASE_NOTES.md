# 发布说明

[English](../RELEASE_NOTES.md) · [首页](../../README.zh-CN.md)

## v0.1.0

Home Edge Bootstrap 框架及其当前已实现参考适配器的首个公开发布；该适配器面向运行官方
Asuswrt-Merlin 的华硕网关。

参考适配器角色只说明它是首个已实现架构路径，不代表取得“已验证”适配器成熟阶段，也不会
认证更宽兼容范围。

### 包含的能力

- 面向 Windows PowerShell，以及 macOS、Linux POSIX 主机的编号式 TUI 入口。
- 能力优先的路由器引导、dry-run 计划、精确应用确认、带备份的部署、回滚、自愈设置、健康检查与脱敏支持包导出。
- 面向受支持主机 CI 环境的合成离线 fixture 与本地验证。
- 能力驱动型框架边界、当前 Merlin 参考适配器，以及独立软路由或端点回退边界。
- 面向未来社区演进、彼此独立的适配器成熟度与目标支持分类。

### 发布物类型

- 源码归档或源码检出：包含脚本、文档、政策与 fixture。它可以配置已有运行时，但本身不代表可全新离线安装运行时。
- 离线恢复归档：在源码表面基础上增加经过审查的运行时载荷、校验材料、第三方许可证、
  完整对应源码和发布专用 SBOM。使用前验证发布校验和。

### 验证

Windows 运行 `powershell -NoProfile -ExecutionPolicy Bypass -File scripts\verify-local.ps1`；macOS/Linux 运行 `sh scripts/verify-local.sh`。主机 CI 覆盖相应的 PowerShell 与 POSIX 路径，但不会认证路由器硬件或固件。

### 已知限制

- 兼容性以能力为基础，政策矩阵尚未发布现场证据。
- 当前参考适配器尚未正式取得“已验证”成熟阶段。
- fixture 不会认证硬件、固件、提供方或真实网络。
- 每个离线发布物都必须补全并审查运行时载荷的来源、软件包与校验和记录。
- 第三方组件继续适用其各自许可证；参见[第三方声明](../../THIRD_PARTY_NOTICES.md)和 [`config/sbom.json`](../../config/sbom.json) 中的 SPDX 文档。
