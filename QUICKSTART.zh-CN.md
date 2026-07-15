# 快速开始

[English](QUICKSTART.md) · [首页](README.zh-CN.md)

本路径按渐进顺序介绍框架。当前已实现参考适配器面向运行官方 Asuswrt-Merlin、
ShellCrash/ShellClash 与 Mihomo 兼容运行时的华硕网关；这不代表该适配器已经取得
“已验证”成熟阶段。

## 1. 克隆源码 checkout

```powershell
git clone https://github.com/yiheng8023/home-edge-bootstrap-public.git
cd home-edge-bootstrap-public
```

源码 checkout 包含脚本、文档与合成 fixture，但不一定包含全新离线安装所需的运行时载荷。

## 2. 仅在本地检查向导

Windows PowerShell：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\tui.ps1 -Help
```

macOS 或 Linux：

在 macOS 与 Linux 上，本地验证需要 Python 3。可使用 `python3`；仅当 `python` 指向 Python 3 时才可使用 `python`。不支持 Python 2。

```sh
sh scripts/tui.sh --help
```

帮助路径只在本地运行，不会连接路由器。

## 3. 验证 checkout

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\verify-local.ps1
```

```sh
sh scripts/verify-local.sh
```

本地验证离线运行并使用合成 fixture，不会对具体路由器、固件构建、服务商或网络形成
现场认证。

## 4. 准备安全边界

声明目标前：

- 阅读[兼容性](docs/zh-CN/COMPATIBILITY.md)。
- 阅读[路由器基线](docs/zh-CN/ROUTER_BASELINE.md)。
- 保留单独管理的恢复或回退路径。
- 确认能够自行核验 SSH 主机密钥。
- 不要把订阅 URL 放入命令历史、issue 或支持归档。
- 如果运行时不存在，应使用经过单独校验的离线发布物，不能让尚未验证的代理路径成为
  自身安装的前置条件。

先按准确型号和硬件修订版核对
[Asuswrt-Merlin 官方支持型号页](https://www.asuswrt-merlin.net/about)，再到
[官方下载页](https://www.asuswrt-merlin.net/download)确认当前确有对应构建；型号专属的
手册、原厂固件和恢复工具以[华硕官方下载中心](https://www.asus.com/global/support/download-center/)
为准。华硕仍提供该型号资料，并不等于 Asuswrt-Merlin 当前仍支持。

刷写步骤遵循[梅林官方安装指南](https://github.com/RMerl/asuswrt-merlin.ng/wiki/Installation)；本项目
不会下载或刷写路由器固件。项目官网不可达时，使用官方
[SourceForge 发布区](https://sourceforge.net/projects/asuswrt-merlin/files/)，或梅林官方下载页当前
列出的其他官方下载入口。第三方社区或支持网站可能只面向某个国家或地区，也可能分发改版固件；
不假定其他国家或地区存在对应站点，也不要把它当作官方来源。

## 5. 启动目标引导会话

使用 `router-user@router.lan` 这样的通用 SSH 目标：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\tui.ps1 -Router router-user@router.lan
```

```sh
sh scripts/tui.sh --router router-user@router.lan
```

提供目标后，向导可以通过 SSH 执行只读能力探测。请自行核验 SSH 主机密钥，不要关闭
主机密钥检查。

## 6. 写入前审查

部署前，向导会先准备 dry-run。应检查准确目标、受管路径、备份、回滚命令、能力不匹配项
与已接受边界。只有输入精确令牌 `APPLY` 才会写入；EOF、中断、无效输入或其他回答都会
取消动作。

## 7. 开启自愈前验证

应用后：

1. 确认运行时配置与健康端点。
2. 确认预期路由器/客户端拓扑。
3. 保留报告的备份与回滚路径。
4. 只有理解自愈 dry-run 行为后，才开启真实自愈；该写入需要精确令牌 `ENABLE`。

如果应用后的状态不健康，应使用报告的回滚路径。出现回滚提示时，必须输入精确令牌
`ROLLBACK` 才会继续。

## 8. 验收或请求支持

针对声明目标运行最终安装门禁。需要共享诊断时，生成脱敏支持包并逐个检查其中的文件。
订阅 URL 属于凭据，绝不能出现在 issue 或支持归档中。

架构、适配器成熟度、无代理恢复与贡献说明见[完整 README](README.zh-CN.md)。
