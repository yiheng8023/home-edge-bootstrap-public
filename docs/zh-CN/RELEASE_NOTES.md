# 发布说明

[English](../RELEASE_NOTES.md) · [首页](../../README.zh-CN.md)

## v0.1.1（2026-07-31）

本维护版本纳入 RT-AX86U Pro 真实恢复中发现的问题；它不授予已验证适配器成熟阶段，也不
在已声明能力边界之外认证硬件。

- 对启动阶段递归启动服务、更新内核、更新脚本或更新规则数据的 ShellCrash 自动任务先备份
  再规范化，同时保留无关自定义任务和无害任务。
- 安装保守启动辅助脚本：尊重人工停用和先前启动错误标记，从受保护状态恢复缺失的压缩
  Mihomo 内核，并避免重复启动。
- 把 ShellCrash 启动与自愈注册恢复作为彼此独立、边界明确的生命周期动作。
- 加固 Merlin/BusyBox 回退、订阅校验、controller 密钥文件、DNS/规则数据准备、部署 staging
  和生命周期证据。
- 规范化 ShellCrash `command.env` 时只按受限数据解析，不再 source 文件，避免意外语句以
  路由器 root 身份执行。
- 把 Windows 用户级持久代理变量识别为实际客户端拓扑控制面，而不是仅凭进程或监听名称判断。
- 增加可选、原子、可回滚且不自动重载运行时的服务依赖配置，避免把服务专用路线写入通用
  故障恢复策略。每个配置只备份自身受管块，使交错 apply/rollback 可组合；状态提交失败时
  会恢复原规则文件。
- 增加来自现场证据的 `asus-global-account` 配置，只对观测到失败的 `nomos.asus.com`
  令牌端点设置直连例外，不扩大到全部 ASUS 流量。
- 补充任意上游网关、双重 NAT 与独立 IPv6 验收边界。
- 让稳定订阅凭据原子写入，并在后续运行时部署失败时回滚已 staging 的控制面。
- POSIX 远端脚本模板改用带引号 heredoc，避免模板内 `awk` 引号逃逸并递归调用部署。来源
  证明不再为每个 staging 文件创建一个 Git Bash shell，失败路径 fixture 使用最小且可校验
  的运行时载荷，回滚清理也会覆盖服务规则辅助脚本。运行时阶段失败时，要么重放已恢复的
  旧控制面，要么清除首次安装写入的活动脚本与钩子后再报告回滚结果。

RT-AX86U Pro 真实恢复演练验证了混合模式内核、controller 认证、Dashboard 可达性，以及
显式代理、透明探测，以及独立上游网关后的下游华硕拓扑。修复启动钩子后已观察到路由器断电/
重启恢复。这是有边界的现场证据；破坏性回滚分支由确定性离线夹具验证，不会为了复现而故意
中断正在使用的网络。

### 应该下载哪些文件

不需要下载全部九个文件。按操作电脑选择一个发布包，并同时下载 `SHA256SUMS`：

| 使用场景 | 下载文件 | 同时需要 |
|---|---|---|
| Windows 离线包，包含运行时 | [`home-edge-bootstrap-v0.1.1-offline.zip`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.1/home-edge-bootstrap-v0.1.1-offline.zip) | [`SHA256SUMS`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.1/SHA256SUMS) |
| macOS/Linux 离线包，包含运行时 | [`home-edge-bootstrap-v0.1.1-offline.tar.gz`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.1/home-edge-bootstrap-v0.1.1-offline.tar.gz) | [`SHA256SUMS`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.1/SHA256SUMS) |
| Windows 仅脚本/文档，运行时已存在 | [`home-edge-bootstrap-v0.1.1-source.zip`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.1/home-edge-bootstrap-v0.1.1-source.zip) | [`SHA256SUMS`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.1/SHA256SUMS) |
| macOS/Linux 仅脚本/文档，运行时已存在 | [`home-edge-bootstrap-v0.1.1-source.tar.gz`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.1/home-edge-bootstrap-v0.1.1-source.tar.gz) | [`SHA256SUMS`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.1/SHA256SUMS) |

一种用途选择一种归档格式即可。manifest、SBOM 和完整源码归档用于审计与保障源码可获得性，
不是额外安装部件：

| 资源 | 用途 | 普通安装是否需要 |
|---|---|---|
| [`RELEASE-MANIFEST.json`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.1/RELEASE-MANIFEST.json) | 记录公开提交、组件锁、大小与摘要 | 否 |
| [`SBOM.spdx.json`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.1/SBOM.spdx.json) | 发布专用软件清单与许可证元数据 | 否 |
| [`mihomo-v1.19.28-source-complete.tar.gz`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.1/mihomo-v1.19.28-source-complete.tar.gz) | Mihomo 完整对应源码 | 否 |
| [`shellcrash-1.9.4-source-complete.tar.gz`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.1/shellcrash-1.9.4-source-complete.tar.gz) | ShellCrash 完整对应源码 | 否 |
| GitHub **Source code (zip)** / **Source code (tar.gz)** | GitHub 自动快照，不是契约内发布包 | 否 |

精确非空 GitHub 资源标签如下：

| 文件名 | GitHub 标签 |
|---|---|
| `home-edge-bootstrap-v0.1.1-offline.zip` | `Windows offline package - runtime included` |
| `home-edge-bootstrap-v0.1.1-offline.tar.gz` | `macOS/Linux offline package - runtime included` |
| `home-edge-bootstrap-v0.1.1-source.zip` | `Windows source-only package - runtime not included` |
| `home-edge-bootstrap-v0.1.1-source.tar.gz` | `macOS/Linux source-only package - runtime not included` |
| `SHA256SUMS` | `Checksums - download with one selected package` |
| `RELEASE-MANIFEST.json` | `Release manifest - provenance and audit` |
| `SBOM.spdx.json` | `SPDX SBOM - audit` |
| `mihomo-v1.19.28-source-complete.tar.gz` | `Mihomo complete source - not required for installation` |
| `shellcrash-1.9.4-source-complete.tar.gz` | `ShellCrash complete source - not required for installation` |

## v0.1.0

Home Edge Bootstrap 框架及其当前已实现参考适配器的首个公开发布；该适配器面向运行官方
Asuswrt-Merlin 的华硕网关。

参考适配器角色只说明它是首个已实现架构路径，不代表取得“已验证”适配器成熟阶段，也不会
认证更宽兼容范围。

### 应该下载哪些文件

> **v0.1.0 已知限制：**资源仍可通过校验和验证，但自动化全新运行时安装路径尚未在 JFFS
> 空间有限或缺少辅助命令的官方 Asuswrt-Merlin 目标上完成验证。不要把 v0.1.0 当作这类
> 目标上已经验证的全新安装路径。可审阅源码/文档、配合已有可用运行时使用，或等待通过真实
> 环境验收合同的后续版本。

不需要把 GitHub 列出的所有文件全部下载。按操作电脑选择一个归档，并同时下载
`SHA256SUMS`；下表说明各资源的预期角色，但仍受上述限制约束：

| 使用场景 | 下载文件 | 同时需要 |
|---|---|---|
| Windows 离线包 | [`home-edge-bootstrap-v0.1.0-offline.zip`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.0/home-edge-bootstrap-v0.1.0-offline.zip) | [`SHA256SUMS`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.0/SHA256SUMS) |
| macOS/Linux 离线包 | [`home-edge-bootstrap-v0.1.0-offline.tar.gz`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.0/home-edge-bootstrap-v0.1.0-offline.tar.gz) | [`SHA256SUMS`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.0/SHA256SUMS) |
| Windows 仅需脚本/文档，运行时已存在 | [`home-edge-bootstrap-v0.1.0-source.zip`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.0/home-edge-bootstrap-v0.1.0-source.zip) | [`SHA256SUMS`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.0/SHA256SUMS) |
| macOS/Linux 仅需脚本/文档，运行时已存在 | [`home-edge-bootstrap-v0.1.0-source.tar.gz`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.0/home-edge-bootstrap-v0.1.0-source.tar.gz) | [`SHA256SUMS`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.0/SHA256SUMS) |

一种用途选择一种归档格式即可；ZIP 与 `tar.gz` 不必都下载。需要运行时载荷时，源码包不能
替代离线包。

其余资源用于验证、审计和源码可获得性：

| 资源 | 用途 | 普通安装是否需要 |
|---|---|---|
| [`RELEASE-MANIFEST.json`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.0/RELEASE-MANIFEST.json) | 记录公开提交、组件锁、制品大小与摘要 | 否；可选的来源记录 |
| [`SBOM.spdx.json`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.0/SBOM.spdx.json) | 发布专用软件清单与许可证元数据 | 否；可选的审计输入 |
| [`mihomo-v1.19.28-source-complete.tar.gz`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.0/mihomo-v1.19.28-source-complete.tar.gz) | 所分发 Mihomo 载荷的完整对应源码 | 否；用于源码审阅与许可证合规 |
| [`shellcrash-1.9.4-source-complete.tar.gz`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.0/shellcrash-1.9.4-source-complete.tar.gz) | 所分发 ShellCrash 载荷的完整对应源码 | 否；用于源码审阅与许可证合规 |
| GitHub **Source code (zip)** / **Source code (tar.gz)** | GitHub 自动生成的源码快照 | 否；不是契约内源码包或离线包 |

每个离线包内部也包含完整对应源码。单独发布这些源码归档，是为了无需下载体积更大的离线包
也能直接取得源码。

GitHub 资源标签采用以下精确映射：

| 文件名 | GitHub 标签 |
|---|---|
| `home-edge-bootstrap-v0.1.0-offline.zip` | `Windows offline package - known v0.1.0 limitation` |
| `home-edge-bootstrap-v0.1.0-offline.tar.gz` | `macOS/Linux offline package - known v0.1.0 limitation` |
| `home-edge-bootstrap-v0.1.0-source.zip` | `Windows source-only package - runtime not included` |
| `home-edge-bootstrap-v0.1.0-source.tar.gz` | `macOS/Linux source-only package - runtime not included` |
| `SHA256SUMS` | `Checksums - download with one selected package` |
| `RELEASE-MANIFEST.json` | `Release manifest - provenance and audit` |
| `SBOM.spdx.json` | `SPDX SBOM - audit` |
| `mihomo-v1.19.28-source-complete.tar.gz` | `Mihomo complete source - not required for installation` |
| `shellcrash-1.9.4-source-complete.tar.gz` | `ShellCrash complete source - not required for installation` |

发布者先从 Release API 取得资源 ID，复核 ID 与文件名映射，再只更新 `label` 字段：

```sh
gh api "repos/OWNER/REPOSITORY/releases/tags/v0.1.0" --jq '.assets[] | [.id,.name,.label] | @tsv'
gh api --method PATCH "repos/OWNER/REPOSITORY/releases/assets/ASSET_ID" \
  -f label='Windows offline package - known v0.1.0 limitation'
```

文件名仍是契约身份。

Windows PowerShell 只校验已下载的离线 ZIP：

```powershell
$File = "home-edge-bootstrap-v0.1.0-offline.zip"
$Expected = ((Get-Content .\SHA256SUMS | Where-Object { $_ -match "  $([regex]::Escape($File))$" }) -split '\s+')[0]
if ((Get-FileHash ".\$File" -Algorithm SHA256).Hash.ToLowerInvariant() -ne $Expected) {
  throw "SHA256 mismatch: $File"
}
```

macOS/Linux 只校验已下载的离线 `tar.gz`：

```sh
file=home-edge-bootstrap-v0.1.0-offline.tar.gz
line=$(awk -v f="$file" 'NF == 2 && length($1) == 64 && $2 == f { n++; hit=$0 }
  END { if (n == 1) print hit; else exit 1 }' SHA256SUMS) || exit 1
if command -v sha256sum >/dev/null 2>&1; then
  printf '%s\n' "$line" | sha256sum -c -
else
  printf '%s\n' "$line" | shasum -a 256 -c -
fi
```

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

解压前，先用 `SHA256SUMS` 核对所选归档；解压后，在运行向导前核对归档内的
`CONTENT-SHA256SUMS`。

### 已知限制

- 兼容性以能力为基础，政策矩阵尚未发布现场证据。
- 当前参考适配器尚未正式取得“已验证”成熟阶段。
- fixture 不会认证硬件、固件、提供方或真实网络。
- 每个离线发布物都必须补全并审查运行时载荷的来源、软件包与校验和记录。
- 第三方组件继续适用其各自许可证；参见[第三方声明](../../THIRD_PARTY_NOTICES.md)和 [`config/sbom.json`](../../config/sbom.json) 中的 SPDX 文档。

### GitHub Release 正文

不要直接把本文或英文发布说明原样粘贴为 GitHub Release 正文：GitHub 会从 tag 根目录而
不是本文所在的 `docs/zh-CN/` 目录解释相对链接。应先生成能感知 tag 的正文：

```sh
python scripts/render-release-body.py \
  --repository OWNER/REPOSITORY \
  --version v0.1.0 \
  --source docs/RELEASE_NOTES.md \
  --output /path/outside/the/checkout/GITHUB-RELEASE.md
```

生成器从 `--source-ref` 读取正文源（默认值是 `--version`），同时用 `--version` 指定的目标
tag 校验链接。若要用后续已审阅提交勘误现有 Release 正文，必须显式传入
`--source-ref COMMIT_SHA`；新版本则应让两者都指向新 tag。
