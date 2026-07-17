# 快速开始

[English](QUICKSTART.md) · [首页](README.zh-CN.md)

这是 Home Edge Bootstrap 最短的可执行路径。当前已实现的参考适配器面向运行官方
Asuswrt-Merlin、ShellCrash/ShellClash 与 Mihomo 兼容运行时的华硕网关；这不等于取得
“已验证”成熟阶段。

查看帮助和运行操作员预检通常只需数秒到几分钟。固件安装、运行时准备、部署和恢复会随
设备、网络和离线转移需求变化，不承诺固定完成时间。完整本地验证对首次只读探测是可选的，
可能需要数分钟，也可能明显更久。

## 1. 克隆并在本地检查

```powershell
git clone https://github.com/yiheng8023/home-edge-bootstrap-public.git
cd home-edge-bootstrap-public
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\tui.ps1 -Help
```

```sh
git clone https://github.com/yiheng8023/home-edge-bootstrap-public.git
cd home-edge-bootstrap-public
sh scripts/tui.sh --help
```

预期帮助以 `usage:` 行开头。帮助路径只在本地运行，不会连接路由器。

在 macOS 与 Linux 上，本地验证需要 Python 3。可使用 `python3`；仅当 `python` 指向 Python 3 时才可使用 `python`。不支持 Python 2。

先运行短路径操作员预检：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\doctor.ps1
```

```sh
sh scripts/doctor.sh
```

仅检查宿主机且健康时，预期终态是 `doctor_state=local_ready_router_not_checked`；提供路由器
目标后，应按实际报告的 doctor 状态和下一步行动继续，不能把宿主机就绪当成路由器已验证。
缺少必需工具时先修复，再碰路由器。可选的深度离线 fixture checkout 检查使用
`scripts\verify-local.ps1` 或 `sh scripts/verify-local.sh`。成功时最后输出
`local_verification_state=ready`；失败会指出应先检查的门禁。fixture 不会对具体路由器、
固件构建、服务商或网络形成现场认证。

## 2. 准备路由器与恢复边界

声明目标前：

- 阅读[兼容性](docs/zh-CN/COMPATIBILITY.md)和[路由器基线](docs/zh-CN/ROUTER_BASELINE.md)。
- 保留独立软路由或端点回退，以及厂商恢复路径。
- 完成路由器首次登录，开启局域网 SSH 和 JFFS custom scripts/configs，并在预期局域网内管理。
- 订阅 URL 属于凭据，不得放入命令历史、issue 或支持归档。
- 运行时不存在时，使用单独校验过的离线发布物，不能让未验证代理路径成为自身安装前提。

先按准确型号和硬件修订版核对
[Asuswrt-Merlin 官方支持型号页](https://www.asuswrt-merlin.net/about)，再到
[官方下载页](https://www.asuswrt-merlin.net/download)确认当前构建；型号专属手册、原厂固件和
恢复工具以[华硕官方下载中心](https://www.asus.com/global/support/download-center/)为准。
华硕仍提供资料不代表梅林当前仍支持。刷写遵循
[梅林官方安装指南](https://github.com/RMerl/asuswrt-merlin.ng/wiki/Installation)；本项目不会下载或刷写固件。

代理可用前无法访问官网时，使用官方
[SourceForge 发布区](https://sourceforge.net/projects/asuswrt-merlin/files/)，或官方下载页当前列出的
其他官方入口。第三方社区或支持网站可能只面向某个国家或地区，也可能分发改版固件；不要
假定它是官方来源或在其他地区存在。可信来源均不可达时，在另一条可信网络取得并校验压缩包后
离线带回，否则停止。

## 3. 设置实际目标并核验 SSH 身份

请用路由器实际配置的 SSH 账户和局域网 IP 替换整个目标。下例既不是本项目创建的账户，也
不是发现路由器 IP 的办法：

```powershell
$Router = "<router-admin-user>@192.168.50.1"
```

```sh
router="<router-admin-user>@192.168.50.1"
```

变量只在当前终端有效；新开 PowerShell、Terminal 或 SSH 窗口后，必须重新设置 `$Router` 或
`router`。

首次探测前，通过独立可信渠道取得路由器 SSH 主机密钥指纹，例如本地控制台、固件提供的
指纹显示或可信操作员记录。不同界面并不一致，无法取得可信指纹时应停止。
`ssh-keyscan -t ed25519 192.168.50.1` 可以采集网络对端展示的密钥用于比对，但它本身不能证明身份。
指纹不一致时停止；不要为了继续而删除已保存密钥或关闭主机密钥检查。

## 4. 启动可接续、先只读的会话

编号式 `tui` 是菜单和导览入口；`run-bootstrap` 是可接续执行循环。两者都可启动流程，但绝不
能针对同一路由器同时运行两个可写会话。

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\run-bootstrap.ps1 -Router $Router -NoPause
```

```sh
sh scripts/run-bootstrap.sh --no-pause "$router"
```

循环会在 `logs/bootstrap/<router-id>/` 下保存 `state.env`、日志和专用 `known_hosts` 记录。
收官前保留这个目标会话。预期暂停或终态标记：

- `bootstrap_state=waiting_prerequisite`：修复所列宿主机/路由器前置条件，再运行同一命令。
- `bootstrap_state=waiting_manual`：同时阅读 `next_action_code` 和 `next_action_command`，完成
  所列人工动作，再运行同一 bootstrap 命令。
- `bootstrap_state=pass`：最终安装门禁通过。
- `bootstrap_state=accepted_boundary`：仍有已审阅人工例外；证据弱于完整通过。

需要操作者行动时，循环会输出两个下一步字段；它先执行只读能力探测，并在可写动作前准备
`--dry-run` 行为。

## 5. 审查每次写入并保留回滚

检查准确目标、受管路径、能力不匹配、已接受边界、备份和回滚命令。部署写入要求精确令牌
`APPLY`，开启真实自愈要求 `ENABLE`，提示式回滚要求 `ROLLBACK`。EOF、中断、无效输入或其他
回答都会取消动作。

当前项目 kit 位于 `/jffs/home-edge-bootstrap`；存在旧 kit 时保留到
`/jffs/home-edge-bootstrap.prev`，并报告 `rollback_available=0|1` 和准确回滚命令。运行时配置
备份是另一类制品，默认位于 `/jffs/home-edge-bootstrap-state/backups/runtime`。apply 健康失败时不要开启自愈。

### 项目退出是独立生命周期操作

先运行计划，审查精确删除/保留集合后才应用：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\decommission-merlin.ps1 -Router $Router -NoPause
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\decommission-merlin.ps1 -Router $Router -Apply -Confirmation DECOMMISSION -NoPause
```

```sh
sh scripts/decommission-merlin.sh "$router"
sh scripts/decommission-merlin.sh "$router" --apply --confirm DECOMMISSION
```

项目退出只删除项目辅助脚本、精确项目注册、经过校验的 kit 变体和默认可再生缓存。它保留
`/jffs/home-edge-bootstrap-state`、操作者订阅与策略文件、恢复备份、Asuswrt-Merlin 固件以及
外部 ShellCrash/Mihomo 运行时。回滚恢复上一版项目 kit；项目退出移除项目控制面；运行时卸载
遵循运行时维护者流程；固件恢复遵循[华硕官方下载中心](https://www.asus.com/global/support/download-center/)
和[梅林官方指南](https://github.com/RMerl/asuswrt-merlin.ng/wiki/Installation)。本项目不替代通用刷机教程。

## 6. 运行最终门禁

在使用该路由器的客户端上运行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\check-client-topology.ps1 -Router $Router
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\check-installation-closeout.ps1 -Router $Router -RunClientCheck
```

```sh
sh scripts/check-client-topology.sh "$router"
sh scripts/check-installation-closeout.sh "$router" --run-client-check
```

纯路由器主路径通过会报告 `client_topology_mode=router_primary` 和
`installation_closeout_state=pass`。本地代理/TUN 可能产生 `client_runtime_present`；只有明确采用
兜底或混合模式时才接受。

## 7. 仅在需要时导出支持证据

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\export-support-bundle.ps1 -Router $Router
```

```sh
sh scripts/export-support-bundle.sh "$router"
```

成功时报告 `support_bundle_state=ready` 和 `support_bundle_archive=<path>`。默认归档根目录在
Windows 上是 `C:\tmp\home-edge-support-bundles`，在 macOS/Linux 上是
`/tmp/home-edge-support-bundles`。支持包会脱敏，但附加前仍须逐个检查文件。

## 术语表

- **目标（target）**：正在检查或修改的路由器账户与地址。
- **能力（capability）**：某步骤需要且已观测到的能力，例如 SSH、JFFS 或运行时端点。
- **受管路径（managed path）**：框架被允许创建、替换、备份或删除的路径。
- **目标会话（target session）**：`logs/bootstrap/<router-id>/` 下可接续的状态与证据。
- **支持分类**：某目标的声明证据级别，不代表每台设备都经过认证。
- **已接受边界**：经明确审阅的人工例外，不是强通过。

## 快速故障排查

| 现象 | 第一处理动作 |
|---|---|
| 缺少 Python 3 或其他本地工具 | 安装所列工具，再运行 `doctor` |
| SSH 不可达或认证失败 | 核对实际局域网 IP、已配置 SSH 账户、局域网 SSH 设置和可达性 |
| 主机指纹不可得或不一致 | 停止并通过独立可信渠道核验；不要绕过检查 |
| 缺少 JFFS | 开启 custom scripts/configs；固件要求时重启，再运行同一会话 |
| apply 后运行时不健康 | 不要开启自愈；使用已报告回滚并检查会话日志 |
| 自愈注册不完整 | 先检查状态，再仅修复项目自有生命周期条目 |

详细诊断、架构、适配器成熟度、无代理恢复和贡献说明见
[完整 README](README.zh-CN.md)。
