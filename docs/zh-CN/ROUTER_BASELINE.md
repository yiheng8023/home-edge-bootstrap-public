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
- 下一步安全操作。

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
