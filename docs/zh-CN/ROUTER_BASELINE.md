# 路由器基线与状态机

> 中文版是英文 `docs/ROUTER_BASELINE.md` 的阅读映射；英文文件是项目真源。

路由器基线不是“把所有推荐设置一次性强行写进去”。它应当是一套基于状态判断的循环：

```text
只读审计
-> 判断当前状态
-> 找出最小必要人工操作
-> 重新只读审计
-> 只对允许自动化的部分生成计划或执行
-> 验证
-> 循环，直到路线可用且可观测
```

## 状态模型

| 状态区域 | 取值 | 含义 |
|---|---|---|
| `device_state` | `unreachable`, `lan_reachable`, `web_initialized`, `ssh_reachable` | 本地电脑能访问路由器到哪一步 |
| `firmware_state` | `official_merlin`, `merlin_compatible_modified`, `stock_asuswrt`, `unsupported`, `unknown` | 审计能判断出的固件族 |
| `admin_state` | `web_only`, `ssh_reachable`, `jffs_scripts_ready` | 路由器侧自动化是否可以安全运行 |
| `baseline_state` | `risky`, `needs_review`, `reviewed`, `reviewed_with_monitoring` | 路由器安全与兼容性设置是否需要处理 |
| `core_baseline_state` | `match`, `drift`, `unrecorded`, `invalid`, `unavailable` | 观察到的内核及证据是否与站点已采纳记录一致；独立于安全风险状态 |
| `proxy_state` | `absent`, `policy_deployed`, `api_reachable`, `self_heal_installed`, `verified` | 代理链路推进到了哪一步 |
| `subscription_state` | `missing`, `credential_stored`, `cache_ready`, `runtime_imported` | 更换服务商是否能由本项目驱动；`runtime_imported` 表示当前运行时可能健康，但订阅凭据和缓存不在项目管理下 |
| `automation_state` | `audit_only`, `dry_run_ready`, `apply_ready`, `live_managed` | 项目下一步允许做到什么程度 |

任何人工操作之后，旧状态都视为过期。如果用户在路由器 Web UI 中改了设置，下一步必须先重新审计。

## 推荐基线

推荐默认项：

- 选择或刷写路由器前，先按准确型号和硬件修订版核对
  [Asuswrt-Merlin 官方支持型号页](https://www.asuswrt-merlin.net/about)，再到
  [官方下载页](https://www.asuswrt-merlin.net/download)确认当前确有对应构建；型号专属的
  ASUS 手册、原厂固件和恢复工具以[华硕官方下载中心](https://www.asus.com/global/support/download-center/)
  为准。华硕仍提供该型号资料，并不等于 Asuswrt-Merlin 当前仍支持。刷写步骤应遵循
  [梅林官方安装指南](https://github.com/RMerl/asuswrt-merlin.ng/wiki/Installation)，不使用本仓库
  另写的刷机教程；项目官网不可达时，使用下载页所链接的官方
  [SourceForge 发布区](https://sourceforge.net/projects/asuswrt-merlin/files/)。第三方支持网站可能只面向
  某个国家或地区；不假定其他国家或地区存在对应站点，也不要把它当作官方来源；
- 当前 ASUS 手动更新页在选定固件文件后，可能无需再次点击“应用”便立即上传并重启。应把
  “选定文件”视为写入边界：先导出路由器设置与 JFFS 备份，核对准确型号和官方摘要，保留
  局域网管理路径，并在选定文件前预期一次临时断网；
- SSH 可用后保持 JFFS custom scripts/configs 开启；
- 管理后台仅面向 LAN，不向 WAN 暴露；
- 关闭 WPS；
- 除非确有旧客户端依赖，否则关闭 PPTP server；
- 除临时诊断外，保持 WAN ping response 关闭；
- 需要 VPN server 时优先使用 WireGuard，而不是 PPTP；
- 对简单代理和防泄漏场景，IPv6 可以保持关闭；启用前应先确认防火墙、DNS 与代理策略。

需要审阅而不是盲改的项目：

- UPnP 在游戏、通讯软件、下载器或家庭成员设备需要时可以保留。它应作为兼容性设置被监控，并定期查看活动映射；
- QoS 如果改善家庭流量体验，可以保留；如果吞吐或硬件加速异常，再重新测试；
- Wi-Fi 信道、带宽和自动/固定策略取决于型号、无线代际、地区、周边网络和客户端设备，不应写死为统一方案；
- WPA3 过渡模式是可选项，只有重要客户端兼容良好时才建议开启；
- AiProtection、DNSSEC、DNS-over-TLS 和 IPv6 都是带有兼容性与隐私权衡的策略项，不应静默开启。

只应人工处理或显式确认的项目：

- 固件刷写、降级；
- 首次管理员密码和账号设置；
- WAN 模式、PPPoE、VLAN/IPTV、静态 IP、运营商专属设置；
- Wi-Fi SSID、密码、地区法规和发射功率；
- VPN peer 密钥、端口转发、DDNS、远程访问暴露面；
- 服务商订阅 URL 和订阅转换器信任边界。

## 只读审计

引导式循环建议使用：

Windows PowerShell：

```powershell
.\scripts\guide-router.ps1 -Router <user>@<router-lan-ip> -NoPause
```

macOS/Linux shell：

```sh
sh scripts/guide-router.sh <user>@<router-lan-ip>
```

向导会运行审计、总结状态，输出 `next_action_code`，并给出下一条安全命令。其他工具需要读取状态机时可使用 JSON 输出：

```powershell
.\scripts\guide-router.ps1 -Router <user>@<router-lan-ip> -Json
```

```sh
sh scripts/guide-router.sh --json <user>@<router-lan-ip>
```

Windows PowerShell：

```powershell
.\scripts\audit-router-baseline.ps1 -Router <user>@<router-lan-ip> -NoPause
```

macOS/Linux shell：

```sh
sh scripts/audit-router-baseline.sh <user>@<router-lan-ip>
```

审计脚本只读运行。它不会输出 Wi-Fi 密码、SSH authorized keys、服务商订阅 URL 或 VPN 私钥。它会报告：

- 路由器与固件状态；
- SSH 和 JFFS 就绪状态；
- WPS、PPTP、UPnP、WAN ping、IPv6、WireGuard、QoS 状态；
- 相关监听端口；
- 活动 UPnP 映射；
- 代理部署、Mihomo API、cron 和最近自愈状态；
- 活动二进制版本及其与站点已采纳内核、证据记录的一致性；
- 下一步安全操作。

## 站点已采纳内核记录

经授权的本机换核需要独立采纳记录。审计不会拿 ShellCrash `core_v` 与仓库发行 manifest
比较；站点采纳新版不会改写 v0.1.4 的历史发行基线 `v1.19.28`。`core_baseline_state`
不会改变 `baseline_state`、风险计数，也不会自动替换或降级内核。

两种 host wrapper 都将本地可信的 `scripts/audit-core-baseline.sh` 前置到既有 SSH payload，
无需新增部署 router helper。`mihomo_version` 来自活动 `/proc/PID/exe -v`，不再把
`authenticated` 当成版本；控制器认证状态单独保留。审计计算活动二进制、原生
`/jffs/ShellCrash/CrashCore.gz`、受保护的
`/jffs/home-edge-bootstrap-state/runtime/mihomo-linux-arm64.gz` 及原始 receipt 的 SHA-256，
并比较真实版本、ShellCrash `core_v` 与站点预期版本。观察前后核对 PID 启动时间；
证据不完整时保留未知。

站点负责人应核验原始换核 receipt 和验收证据后，再创建私有记录：

```text
/jffs/home-edge-bootstrap-state/runtime-core-baseline.env
```

schema version 1 只允许下面六个不带引号的字段；摘要占位符必须换成真实值：

```text
schema_version=1
core_version=v1.19.32
core_raw_sha256=<64位小写十六进制>
core_gzip_sha256=<64位小写十六进制>
receipt_path=/jffs/.home-core-update-YYYYMMDD/result.env
receipt_sha256=<64位小写十六进制>
```

`core_raw_sha256` 绑定未压缩二进制；`core_gzip_sha256` 绑定原生和受保护路径应具有的同一份
gzip 原始字节；`receipt_sha256` 绑定原始 receipt 字节，不统一换行或改写原件。receipt
必须各有唯一一项：`version=<采纳版本>`、`selectors_unchanged=yes`、`route_verified=yes`。
同目录独立 `status` 文件必须只有一行 `verified`。没有独立文件时，也兼容历史 receipt
内唯一的 `status=verified` 字段；两种状态源冲突则拒绝。站点记录仍保持六字段 schema。
其他字段仍是由整文件摘要绑定的数据。这记录历史验收，不重新证明
当前链路、上游来源真实性或断电耐久性。

解析器不 source 两类文件。记录重复或未知字段、不安全路径、不支持的 schema、记录和
receipt、status 路径中的符号链接都会被拒绝；记录允许空行和注释，摘要格式严格校验。本地目录
存在下载的 gzip 不等于本地已有 `result.env`；本审计只读取记录指向的路由器原始 receipt。

| 状态 | 含义 |
|---|---|
| `match` | 活动版本/raw 摘要、规范化的 `core_v`、两份 gzip 摘要及 verified receipt 均与记录一致 |
| `drift` | 已观察到的版本、元数据、文件摘要或 receipt 摘要与采纳记录不符 |
| `unrecorded` | 未建立站点记录；不推断发行 manifest 漂移或降级需求 |
| `invalid` | 记录、路径、schema、验收状态或 receipt 验收字段无效 |
| `unavailable` | 缺少活动进程、元数据、摘要能力、gzip 或 receipt 等必要观察 |

输出包含 `core_baseline_reason`、`core_baseline_expected_version`、`core_baseline_status_source`、`shellcrash_core_version`
和已观察到的 raw/native/protected/receipt SHA-256；不输出 receipt 原文、节点或密钥。
版本比较会规范化可选 `v` 前缀，也接受原生 `core_v` 的外层引号。不一致意味着需要核对
证据，不是覆盖内核或修改原始 receipt 的授权。
摘要工具用 `which` 发现，兼容没有 `command` builtin 的 BusyBox shell。

离线 fixture 用 `HOME_EDGE_CORE_AUDIT_ROOT` 映射路由器路径，
`HOME_EDGE_CORE_PROC_ROOT` 指向模拟进程树；其他可信测试路径参数为
`HOME_EDGE_CORE_BASELINE_FILE`、`HOME_EDGE_CORE_NATIVE_GZIP`、
`HOME_EDGE_CORE_PROTECTED_GZIP`、`HOME_EDGE_CORE_SHELLCRASH_CONFIG`。生产默认路径如上。

```sh
sh scripts/test-core-baseline-fixtures.sh
```

## 自动化边界

只有当前状态证明下一步安全、可逆时，自动化才应继续。

SSH/JFFS 就绪后可以自动化：

- 部署仓库管理的脚本和策略文件；
- 安装或更新 self-heal cron；
- 运行 DRY-RUN 自愈；
- 验证 Mihomo API 和已配置的可达性探测目标；
- 当订阅 URL 已在路由器本地存在时，缓存并校验订阅；
- 备份后应用明确列入 allowlist 的低风险设置。

没有显式确认时，不应自动化：

- 固件刷写；
- WAN 和运营商设置；
- Wi-Fi 名称与凭据；
- 路由器管理员凭据；
- VPN 密钥与 peer 暴露；
- 在家庭兼容性未知时关闭 UPnP；
- 替换已有 ShellCrash 运行时。

## 目标最终状态

```text
router_initialized=yes
ssh_ready=yes
jffs_ready=yes
baseline_reviewed=yes
provider_subscription_present=yes
mihomo_api_reachable=yes
main_selector_verified=yes
self_heal_installed=yes
self_heal_live_after_dry_run=yes
rollback_available=yes
```

只要发生人工介入，就从只读审计重新开始。
