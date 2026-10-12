# 发布说明

[English](../RELEASE_NOTES.md) · [首页](../../README.zh-CN.md)

## v0.1.9（2026-10-13）

v0.1.9 修正自愈的写入权限：配置的 HEAL_GROUP 必须精确匹配可写 Selector，自动主组发现排除手动名称。显式指定手动组会授权其自动管理；嵌套与角色切换保留各自的主动启用控制。PUT 前重新核验图与选择值；回滚也受介入变化守卫约束。controller 没有原子 compare-and-swap（CAS），这些检查缩小已观测竞态窗口，但不能消除全部并发变化风险。

项目采用证据包含当前 service-helper 来源。Merlin 检测在原 command 不可用时回退到可用的命令定位器，不把缺命令误判为未安装。PowerShell 5/7 与 POSIX 部署采用短 SSH argv、UTF-8/LF stdin 和分行 base64 传输，归档失败在独立作用域检查；覆盖 16K fixture 传输。来源记录明确非 Git／缺 Git 情况，不借用父级仓库，并确定性选择首个可用 Git。 Windows 短路径与长路径暂存目录生成相同的相对校验路径。Windows 克隆失败不会启动已有目标目录。

参考现场另行验收了执行源码的仅项目刷新，保留运行时／core、策略组选择与 profiles，并在后续自然 cron 中观测到选择未变。这是受限现场证据，不代表全部新归档、原生 GUI、服务商、账号或网络结果已验收。本次版本／文档提交与此前现场来源收据不同；文档字节需要单独协调采用状态。

后续发现源码缺口，因此 v0.1.8 标签、草稿资产及原发布说明保留且保持未发布。v0.1.9 须完成自身精确源码 CI、具体归档及发布核验。Mihomo v1.19.32、ShellCrash 1.9.4、GPL／源码锁、公开九资产角色及广泛声明 blocked 边界不变。

获取路径任选其一：发行包校验解压、Git 克隆、复用完整本地目录／桌面入口，或离线转移一个完整包。Windows 打开 start.cmd，macOS 打开 start.command，Linux 通过 sh 打开 start.sh，随后选择 1 按实际状态继续。不提供 npm、pnpm 或 npx 安装入口。

公仓 source 包／克隆不含离线运行时；已有运行时时可选 source 包，目标缺运行时时选择 offline 包。

Windows 下载完整 ZIP、全部解压后双击 start.cmd；macOS/Linux 选择 tar.gz。只选适合系统的一个包并下载 SHA256SUMS 校验；源码审计材料不是额外安装部件。

| Download | Purpose / GitHub label |
|---|---|
| [`home-edge-bootstrap-v0.1.9-offline.zip`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.9/home-edge-bootstrap-v0.1.9-offline.zip) | Windows offline package - runtime included |
| [`home-edge-bootstrap-v0.1.9-offline.tar.gz`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.9/home-edge-bootstrap-v0.1.9-offline.tar.gz) | macOS/Linux offline package - runtime included |
| [`home-edge-bootstrap-v0.1.9-source.zip`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.9/home-edge-bootstrap-v0.1.9-source.zip) | Windows source-only package - runtime not included |
| [`home-edge-bootstrap-v0.1.9-source.tar.gz`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.9/home-edge-bootstrap-v0.1.9-source.tar.gz) | macOS/Linux source-only package - runtime not included |
| [`SHA256SUMS`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.9/SHA256SUMS) | Checksums - download with one selected package |
| [`RELEASE-MANIFEST.json`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.9/RELEASE-MANIFEST.json) | Release manifest - provenance and audit |
| [`SBOM.spdx.json`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.9/SBOM.spdx.json) | SPDX SBOM - audit |
| [`mihomo-v1.19.32-source-complete.tar.gz`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.9/mihomo-v1.19.32-source-complete.tar.gz) | Mihomo complete source - not required for installation |
| [`shellcrash-1.9.4-source-complete.tar.gz`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.9/shellcrash-1.9.4-source-complete.tar.gz) | ShellCrash complete source - not required for installation |

| Filename | GitHub label |
|---|---|
| `home-edge-bootstrap-v0.1.9-offline.zip` | `Windows offline package - runtime included` |
| `home-edge-bootstrap-v0.1.9-offline.tar.gz` | `macOS/Linux offline package - runtime included` |
| `home-edge-bootstrap-v0.1.9-source.zip` | `Windows source-only package - runtime not included` |
| `home-edge-bootstrap-v0.1.9-source.tar.gz` | `macOS/Linux source-only package - runtime not included` |
| `SHA256SUMS` | `Checksums - download with one selected package` |
| `RELEASE-MANIFEST.json` | `Release manifest - provenance and audit` |
| `SBOM.spdx.json` | `SPDX SBOM - audit` |
| `mihomo-v1.19.32-source-complete.tar.gz` | `Mihomo complete source - not required for installation` |
| `shellcrash-1.9.4-source-complete.tar.gz` | `ShellCrash complete source - not required for installation` |

选择对应系统的一种包和 `SHA256SUMS`；只校验你下载的文件。manifest、SBOM（公开发行）和完整对应源码是审计／源码可用性资料，不是额外安装部件。GitHub 自动生成的 Source code 不是契约发行包。

只有已有运行时且只需要脚本／文档时才选 source 包；全新离线运行时准备选择 offline 包。

先将选中的发行包与 `SHA256SUMS` 放在同一文件夹。下面的校验命令在该文件夹的终端执行：Windows 可在资源管理器中打开该文件夹，在地址栏输入 `powershell` 并回车；macOS/Linux 可打开终端，输入 `cd `（保留空格），拖入下载文件夹后按回车。校验成功后再解压；无需回到项目目录。

Windows PowerShell 只校验已下载的离线 ZIP：

```powershell
$File = "home-edge-bootstrap-v0.1.9-offline.zip"
$Expected = ((Get-Content .\SHA256SUMS | Where-Object { $_ -match "  $([regex]::Escape($File))$" }) -split '\s+')[0]
if ((Get-FileHash ".\$File" -Algorithm SHA256).Hash.ToLowerInvariant() -ne $Expected) {
  throw "SHA256 mismatch: $File"
}
```

macOS/Linux 只校验已下载的离线 `tar.gz`：

```sh
file=home-edge-bootstrap-v0.1.9-offline.tar.gz
line=$(awk -v f="$file" 'NF == 2 && length($1) == 64 && $2 == f { n++; hit=$0 }
  END { if (n == 1) print hit; else exit 1 }' SHA256SUMS) || exit 1
if command -v sha256sum >/dev/null 2>&1; then
  printf '%s\n' "$line" | sha256sum -c -
else
  printf '%s\n' "$line" | shasum -a 256 -c -
fi
```


## v0.1.8（2026-10-12）

### 获取与启动方式（发行页指引修订）

获取方式任选其一：发行包下载并校验解压、Git 克隆、复用完整本地目录／桌面入口，或离线转移完整包。Windows 打开 `start.cmd`；macOS 打开 `start.command`；Linux 通过 `sh` 打开 `start.sh`；随后选择 **1** 按实际状态开始／接续。不存在 npm、pnpm 或 npx 安装入口。

公仓 source 包和克隆不含离线运行时；只需脚本且运行时已有时可用，目标缺少运行时时选择 offline 包。

本段是发行页的文档修订；下载包仍精确绑定 manifest 中的原 v0.1.8 提交，不包含后续 README 改写。完整最新路径见[中文 README](https://github.com/yiheng8023/home-edge-bootstrap-public/blob/main/README.zh-CN.md)。已有资产、标签及校验值保持不变。

修复 OpenAI 服务策略组推断：精确 `DOMAIN-KEYWORD,openai/chatgpt` 规则与依赖域名规则一起参与判断；存在策略组冲突时要求显式 `HOME_EDGE_SERVICE_GROUP`，不再静默选择媒体组。依照当前官方网络建议补充精确 `frontend-apps-multi-region.workos.com` 依赖。

安装观测仅将普通、可读、空的历史 `home-edge-policy.local.bak.<14 位数字>` 备份排除出活动文件所有权检查，并保留原文件。非空未知备份、其他名称及链接继续受保护；被动备份不能证明安装所有权或授予替换权。

中英文运行手册区分普通延迟探测、服务商 `[AI]` 标签与实际服务可用性，也区分持久 ShellCrash 规则覆盖文件与当前运行规则。保留用户选择；没有新增自动 AI 节点切换，也不保证服务以后始终可用。

向导按 1 到 9 排序并将退出收尾，合并重复帮助入口；无论当前语言是什么，Language / 语言及 English / 中文都可辨认。Windows 安装探测也在原生命令管道追加的 CRLF 之前保留观测器退出码并退出，避免尾部 CR 被误当成 SSH 探测失败。

受影响回归覆盖关键词／依赖组冲突、显式服务绑定、无关与运行配置保留、回滚及历史空备份边界。参考现场的仅规则热更新另行核验了运行规则、策略组选择及内核进程；这不代表全部发行包、路由器、OAuth 故障或网络条件已验收。运行时固定版本、许可、源码锁及广泛发布 `blocked` 边界不变。旧发布章节、标签和资产保持原样。

Windows 下载完整 ZIP、全部解压后双击 start.cmd；macOS/Linux 选择 tar.gz。只选适合系统的一个包并下载 SHA256SUMS 校验；源码审计材料不是额外安装部件。

| Download | Purpose / GitHub label |
|---|---|
| [`home-edge-bootstrap-v0.1.8-offline.zip`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.8/home-edge-bootstrap-v0.1.8-offline.zip) | Windows offline package - runtime included |
| [`home-edge-bootstrap-v0.1.8-offline.tar.gz`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.8/home-edge-bootstrap-v0.1.8-offline.tar.gz) | macOS/Linux offline package - runtime included |
| [`home-edge-bootstrap-v0.1.8-source.zip`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.8/home-edge-bootstrap-v0.1.8-source.zip) | Windows source-only package - runtime not included |
| [`home-edge-bootstrap-v0.1.8-source.tar.gz`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.8/home-edge-bootstrap-v0.1.8-source.tar.gz) | macOS/Linux source-only package - runtime not included |
| [`SHA256SUMS`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.8/SHA256SUMS) | Checksums - download with one selected package |
| [`RELEASE-MANIFEST.json`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.8/RELEASE-MANIFEST.json) | Release manifest - provenance and audit |
| [`SBOM.spdx.json`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.8/SBOM.spdx.json) | SPDX SBOM - audit |
| [`mihomo-v1.19.32-source-complete.tar.gz`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.8/mihomo-v1.19.32-source-complete.tar.gz) | Mihomo complete source - not required for installation |
| [`shellcrash-1.9.4-source-complete.tar.gz`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.8/shellcrash-1.9.4-source-complete.tar.gz) | ShellCrash complete source - not required for installation |

| Filename | GitHub label |
|---|---|
| `home-edge-bootstrap-v0.1.8-offline.zip` | `Windows offline package - runtime included` |
| `home-edge-bootstrap-v0.1.8-offline.tar.gz` | `macOS/Linux offline package - runtime included` |
| `home-edge-bootstrap-v0.1.8-source.zip` | `Windows source-only package - runtime not included` |
| `home-edge-bootstrap-v0.1.8-source.tar.gz` | `macOS/Linux source-only package - runtime not included` |
| `SHA256SUMS` | `Checksums - download with one selected package` |
| `RELEASE-MANIFEST.json` | `Release manifest - provenance and audit` |
| `SBOM.spdx.json` | `SPDX SBOM - audit` |
| `mihomo-v1.19.32-source-complete.tar.gz` | `Mihomo complete source - not required for installation` |
| `shellcrash-1.9.4-source-complete.tar.gz` | `ShellCrash complete source - not required for installation` |

选择对应系统的一种包和 `SHA256SUMS`；只校验你下载的文件。manifest、SBOM（公开发行）和完整对应源码是审计／源码可用性资料，不是额外安装部件。GitHub 自动生成的 Source code 不是契约发行包。

只有已有运行时且只需要脚本／文档时才选 source 包；全新离线运行时准备选择 offline 包。

先将选中的发行包与 `SHA256SUMS` 放在同一文件夹。下面的校验命令在该文件夹的终端执行：Windows 可在资源管理器中打开该文件夹，在地址栏输入 `powershell` 并回车；macOS/Linux 可打开终端，输入 `cd `（保留空格），拖入下载文件夹后按回车。校验成功后再解压；无需回到项目目录。

Windows PowerShell 只校验已下载的离线 ZIP：

```powershell
$File = "home-edge-bootstrap-v0.1.8-offline.zip"
$Expected = ((Get-Content .\SHA256SUMS | Where-Object { $_ -match "  $([regex]::Escape($File))$" }) -split '\s+')[0]
if ((Get-FileHash ".\$File" -Algorithm SHA256).Hash.ToLowerInvariant() -ne $Expected) {
  throw "SHA256 mismatch: $File"
}
```

macOS/Linux 只校验已下载的离线 `tar.gz`：

```sh
file=home-edge-bootstrap-v0.1.8-offline.tar.gz
line=$(awk -v f="$file" 'NF == 2 && length($1) == 64 && $2 == f { n++; hit=$0 }
  END { if (n == 1) print hit; else exit 1 }' SHA256SUMS) || exit 1
if command -v sha256sum >/dev/null 2>&1; then
  printf '%s\n' "$line" | sha256sum -c -
else
  printf '%s\n' "$line" | shasum -a 256 -c -
fi
```


## v0.1.7（2026-10-12）

新增完整本机双语帮助（`H` / `?` / `help` / `6`）及会话内语言切换（`L` / `language` / `9`），保留路由器目标与所选会话，不联网、不写全局设置。

已有或部分项目安装默认重新只读诊断并复用保存的会话。安装证据绑定所选路由器和路径，只有正面确认不存在才允许首次安装；所有权未知、外来内容、链接及探测格式异常会停止部署。`installed` 只表示项目自有内容存在，不是完整生命周期／网络健康验收；单独安装 ShellCrash/Mihomo 不证明本项目已安装。

主动选择 `R` 刷新项目时，先审阅仅项目计划及 `<项目路径>.prev` 备份，再精确输入 `REPLACE`，随后输入 `APPLY`；旧备份可能被替换。实际写者持锁后重新检查所有权。运行时／core 载荷保留，但项目受管集成／配置可能变化。单独替换运行时也保留已有 core，除非另行显式选择 core 替换。此操作不是完整运行时回滚。

登记目标、缓存启动文件与桌面指向均匹配时复用；其它自有目标／缓存更新或修复需要 `REPLACE` 后再 `APPLY`。无所有权内容不能覆盖。菜单／动作切换及重要工作前后进行当前结构、目录实例与工具的事件触发检查；已知退化时保留本机帮助／语言／退出并给出恢复指引。没有后台守护，不声称发现全部未知故障。

Mihomo v1.19.32、ShellCrash 1.9.4、源码锁与供应链审查保持不变。yamlbridge 仍仅源码交付，沿用 v0.1.5 的准备和显式启用前提。通用、宿主和设备证据分别成立；Merlin 是唯一已实现的真实设备参考。不新增真实设备、随包 core 执行或原生 GUI 现场验收，广泛声明仍为 `blocked`。全部历史发布章节、标签与资产保持不变，发布不会更新已有安装。

Windows 下载下面的 ZIP，全部解压后双击 `start.cmd`。需要固定入口时再双击 `create-desktop-shortcut.cmd`。保留解压目录；只下载脚本或在压缩包内打开不是完整安装。macOS/Linux 选择 tar.gz；若 macOS 未保留执行权限，可通过 `sh` 加完整路径打开 `start.sh`。安装时不需要下载完整源码审计资产。

| Download | Purpose / GitHub label |
|---|---|
| [`home-edge-bootstrap-v0.1.7-offline.zip`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.7/home-edge-bootstrap-v0.1.7-offline.zip) | Windows offline package - runtime included |
| [`home-edge-bootstrap-v0.1.7-offline.tar.gz`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.7/home-edge-bootstrap-v0.1.7-offline.tar.gz) | macOS/Linux offline package - runtime included |
| [`home-edge-bootstrap-v0.1.7-source.zip`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.7/home-edge-bootstrap-v0.1.7-source.zip) | Windows source-only package - runtime not included |
| [`home-edge-bootstrap-v0.1.7-source.tar.gz`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.7/home-edge-bootstrap-v0.1.7-source.tar.gz) | macOS/Linux source-only package - runtime not included |
| [`SHA256SUMS`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.7/SHA256SUMS) | Checksums - download with one selected package |
| [`RELEASE-MANIFEST.json`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.7/RELEASE-MANIFEST.json) | Release manifest - provenance and audit |
| [`SBOM.spdx.json`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.7/SBOM.spdx.json) | SPDX SBOM - audit |
| [`mihomo-v1.19.32-source-complete.tar.gz`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.7/mihomo-v1.19.32-source-complete.tar.gz) | Mihomo complete source - not required for installation |
| [`shellcrash-1.9.4-source-complete.tar.gz`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.7/shellcrash-1.9.4-source-complete.tar.gz) | ShellCrash complete source - not required for installation |

| Filename | GitHub label |
|---|---|
| `home-edge-bootstrap-v0.1.7-offline.zip` | `Windows offline package - runtime included` |
| `home-edge-bootstrap-v0.1.7-offline.tar.gz` | `macOS/Linux offline package - runtime included` |
| `home-edge-bootstrap-v0.1.7-source.zip` | `Windows source-only package - runtime not included` |
| `home-edge-bootstrap-v0.1.7-source.tar.gz` | `macOS/Linux source-only package - runtime not included` |
| `SHA256SUMS` | `Checksums - download with one selected package` |
| `RELEASE-MANIFEST.json` | `Release manifest - provenance and audit` |
| `SBOM.spdx.json` | `SPDX SBOM - audit` |
| `mihomo-v1.19.32-source-complete.tar.gz` | `Mihomo complete source - not required for installation` |
| `shellcrash-1.9.4-source-complete.tar.gz` | `ShellCrash complete source - not required for installation` |

选择对应系统的一种包和 `SHA256SUMS`；只校验你下载的文件。manifest、SBOM（公开发行）和完整对应源码是审计／源码可用性资料，不是额外安装部件。GitHub 自动生成的 Source code 不是契约发行包。

只有已有运行时且只需要脚本／文档时才选 source 包；全新离线运行时准备选择 offline 包。

Windows PowerShell 只校验已下载的离线 ZIP：

```powershell
$File = "home-edge-bootstrap-v0.1.7-offline.zip"
$Expected = ((Get-Content .\SHA256SUMS | Where-Object { $_ -match "  $([regex]::Escape($File))$" }) -split '\s+')[0]
if ((Get-FileHash ".\$File" -Algorithm SHA256).Hash.ToLowerInvariant() -ne $Expected) {
  throw "SHA256 mismatch: $File"
}
```

macOS/Linux 只校验已下载的离线 `tar.gz`：

```sh
file=home-edge-bootstrap-v0.1.7-offline.tar.gz
line=$(awk -v f="$file" 'NF == 2 && length($1) == 64 && $2 == f { n++; hit=$0 }
  END { if (n == 1) print hit; else exit 1 }' SHA256SUMS) || exit 1
if command -v sha256sum >/dev/null 2>&1; then
  printf '%s\n' "$line" | sha256sum -c -
else
  printf '%s\n' "$line" | shasum -a 256 -c -
fi
```

## v0.1.6（2026-10-12）

新增 Windows、macOS、Linux 平等支持的目录内入口、独立登记入口与可选桌面集成。macOS 使用 `start.command`，Linux 使用自身定位的 `start.sh`。所有入口都自动定位所在包，保留原有向导、错误退出码及确认门禁。README 和快速开始不再假设已经 clone、知道目录或先执行 `cd`。

Mihomo v1.19.32、ShellCrash 1.9.4、源码锁与既有安全证据不变。本次没有新现场验收或运行时升级，旧标签与资产保持不变，广泛发布声明仍 blocked。启动不联网、不自动更新、不修改路由器、不申请管理员权限；Windows execution-policy bypass 只作用于启动的子进程。本机登记与桌面集成由用户选择，核对路径类型和目录实例，保护无关文件；移动或替换副本后重新选择。缺少可选设备能力不再阻断核心菜单。设备候选探测移入适配器，通用 dispatch 对未知或多个候选要求选择。yamlbridge 仍以源码交付，沿用 v0.1.5 的启用前提。

Windows 下载下面的 ZIP，全部解压后双击 `start.cmd`。需要固定入口时再双击 `create-desktop-shortcut.cmd`。保留解压目录；只下载脚本或在压缩包内打开不是完整安装。macOS/Linux 选择 tar.gz；若 macOS 未保留执行权限，可通过 `sh` 加完整路径打开 `start.sh`。安装时不需要下载完整源码审计资产。

| Download | Purpose / GitHub label |
|---|---|
| [`home-edge-bootstrap-v0.1.6-offline.zip`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.6/home-edge-bootstrap-v0.1.6-offline.zip) | Windows offline package - runtime included |
| [`home-edge-bootstrap-v0.1.6-offline.tar.gz`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.6/home-edge-bootstrap-v0.1.6-offline.tar.gz) | macOS/Linux offline package - runtime included |
| [`home-edge-bootstrap-v0.1.6-source.zip`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.6/home-edge-bootstrap-v0.1.6-source.zip) | Windows source-only package - runtime not included |
| [`home-edge-bootstrap-v0.1.6-source.tar.gz`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.6/home-edge-bootstrap-v0.1.6-source.tar.gz) | macOS/Linux source-only package - runtime not included |
| [`SHA256SUMS`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.6/SHA256SUMS) | Checksums - download with one selected package |
| [`RELEASE-MANIFEST.json`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.6/RELEASE-MANIFEST.json) | Release manifest - provenance and audit |
| [`SBOM.spdx.json`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.6/SBOM.spdx.json) | SPDX SBOM - audit |
| [`mihomo-v1.19.32-source-complete.tar.gz`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.6/mihomo-v1.19.32-source-complete.tar.gz) | Mihomo complete source - not required for installation |
| [`shellcrash-1.9.4-source-complete.tar.gz`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.6/shellcrash-1.9.4-source-complete.tar.gz) | ShellCrash complete source - not required for installation |

| Filename | GitHub label |
|---|---|
| `home-edge-bootstrap-v0.1.6-offline.zip` | `Windows offline package - runtime included` |
| `home-edge-bootstrap-v0.1.6-offline.tar.gz` | `macOS/Linux offline package - runtime included` |
| `home-edge-bootstrap-v0.1.6-source.zip` | `Windows source-only package - runtime not included` |
| `home-edge-bootstrap-v0.1.6-source.tar.gz` | `macOS/Linux source-only package - runtime not included` |
| `SHA256SUMS` | `Checksums - download with one selected package` |
| `RELEASE-MANIFEST.json` | `Release manifest - provenance and audit` |
| `SBOM.spdx.json` | `SPDX SBOM - audit` |
| `mihomo-v1.19.32-source-complete.tar.gz` | `Mihomo complete source - not required for installation` |
| `shellcrash-1.9.4-source-complete.tar.gz` | `ShellCrash complete source - not required for installation` |

## v0.1.5（2026-10-05）

本次有限发行将当前项目功能装入新的版本化归档，并把固定 Mihomo 载荷更新至 v1.19.32。
全部历史标签及下载资产保持不变。

- 新增显式启用的受保护节点订阅更新，统一周期、需求与手动触发；保留本地配置所有权、
  手动选择，进行候选检查并提供有边界的回滚和启动恢复。
- 将稳定凭据、缓存和恢复状态与可替换脚本分离；只在字节一致和所有权检查通过后退役
  已被接管的旧缓存。
- 本地面板使用页面自身的 controller origin，记住已验证的浏览器连接并保留显示选择；
  修正宿主 SSH 命令规范化及测试临时路径。
- Mihomo 固定为 v1.19.32，提交 `88dcbf7f1614a67c3b36b848ee3592dfa92ada36`；ShellCrash 保持 1.9.4。
  下载的 Linux ARM64 二进制独立记录 Go1.26.8 和 `with_gvisor`，不是从源码准备工具链推断。
  同步刷新完整对应源码、库存和证据。
- 对精确 v32 完整源码重新运行 CVE-2025-56499 的十用例、移除保护负对照及显式绕过对照；
  v28 的 proof 和日志作为历史证据保留。

**运行时变化与安全边界：** 原 v1.19.28 二进制记录 Go1.26.5，位于
[GO-2026-6090 / CVE-2026-56862](https://pkg.go.dev/vuln/GO-2026-6090) 的 Go1.26 受影响范围
（`go1.26.0-0` 至 `<go1.26.6`）。v32 二进制的 Go1.26.8 位于该已报告范围之外；这只是
版本范围处置，不是广泛漏洞清白证明。上游 v1.19.30 说明列出 TLS 修复。v1.19.32 将默认
TUN/IP 栈改为 `mips`/mipstack，并包含 TCP、UDP、ICMP 行为变化，采用前需审阅本地 TUN 设置。
本次不增加随包 ARM64 二进制执行、真实路由器升级、目标回滚演练或广泛固件/服务商兼容证据。
GitHub asset digest 已匹配，但没有维护者签名或独立可复现构建证明。广泛发布就绪声明继续
保持 blocked；本次发行只验证已声明的源码、宿主行为和归档范围。

**订阅前提：** 包内包含 yamlbridge 源码及构建 helper，不包含预编译 yamlbridge 可执行文件。
可选更新器需要宿主 Go 编译器、POSIX shell、gzip/OpenSSL，以及通过可信网络或预备模块缓存
可取得的固定 YAML 模块。先构建并核验 Linux ARM64 gzip 和未压缩二进制 SHA256，再在已部署
helpers、HTTPS 订阅、私有 controller key、内联节点配置及本地组过滤齐备后显式启用。
路由器不需要安装 Go。该可选准备独立于两载荷离线运行时包；源码/宿主夹具不证明站点验收。
发布不会自动更新或重启既有安装。

请选择一个包并同时下载 `SHA256SUMS`。manifest、SBOM、完整源码用于审计和源码可获得性；
GitHub 自动 Source code 归档不能替代契约软件包。

| 下载 | 用途 / GitHub 标签 |
|---|---|
| [`home-edge-bootstrap-v0.1.5-offline.zip`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.5/home-edge-bootstrap-v0.1.5-offline.zip) | Windows offline package - runtime included |
| [`home-edge-bootstrap-v0.1.5-offline.tar.gz`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.5/home-edge-bootstrap-v0.1.5-offline.tar.gz) | macOS/Linux offline package - runtime included |
| [`home-edge-bootstrap-v0.1.5-source.zip`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.5/home-edge-bootstrap-v0.1.5-source.zip) | Windows source-only package - runtime not included |
| [`home-edge-bootstrap-v0.1.5-source.tar.gz`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.5/home-edge-bootstrap-v0.1.5-source.tar.gz) | macOS/Linux source-only package - runtime not included |
| [`SHA256SUMS`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.5/SHA256SUMS) | Checksums - download with one selected package |
| [`RELEASE-MANIFEST.json`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.5/RELEASE-MANIFEST.json) | Release manifest - provenance and audit |
| [`SBOM.spdx.json`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.5/SBOM.spdx.json) | SPDX SBOM - audit |
| [`mihomo-v1.19.32-source-complete.tar.gz`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.5/mihomo-v1.19.32-source-complete.tar.gz) | Mihomo complete source - not required for installation |
| [`shellcrash-1.9.4-source-complete.tar.gz`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.5/shellcrash-1.9.4-source-complete.tar.gz) | ShellCrash complete source - not required for installation |

| 文件名 | GitHub 标签 |
|---|---|
| `home-edge-bootstrap-v0.1.5-offline.zip` | `Windows offline package - runtime included` |
| `home-edge-bootstrap-v0.1.5-offline.tar.gz` | `macOS/Linux offline package - runtime included` |
| `home-edge-bootstrap-v0.1.5-source.zip` | `Windows source-only package - runtime not included` |
| `home-edge-bootstrap-v0.1.5-source.tar.gz` | `macOS/Linux source-only package - runtime not included` |
| `SHA256SUMS` | `Checksums - download with one selected package` |
| `RELEASE-MANIFEST.json` | `Release manifest - provenance and audit` |
| `SBOM.spdx.json` | `SPDX SBOM - audit` |
| `mihomo-v1.19.32-source-complete.tar.gz` | `Mihomo complete source - not required for installation` |
| `shellcrash-1.9.4-source-complete.tar.gz` | `ShellCrash complete source - not required for installation` |


## v0.1.4（2026-09-06）

本补丁版本在订阅传输安全和宿主验证方面取代 v0.1.3。旧归档保持不变，不包含这些修复。

- 直接服务商订阅在下载前拒绝非 HTTPS 地址；普通与代理获取分支均将初始请求和重定向
  限定为 HTTPS，避免凭据明文传输。
- 保留独立的本地/私网 HTTP 转换器策略；这不允许使用 HTTP 服务商订阅。服务商必须提供
  HTTPS 订阅端点。
- PowerShell 子检查失败时，Windows 验证立即失败；增加验证链不同位置失败的回归覆盖。
- Windows 路由选择在最长前缀匹配后比较路由 metric 与接口 metric 之和，避免误判本机代理/TUN。
- 第三方合规测试使用已选定的 Python 解释器，兼容仅提供 Python 3 的宿主。

Mihomo v1.19.28、ShellCrash 1.9.4 载荷及源码锁保持不变。不声明新增真实路由器验收或扩大
兼容性。发布不会自动更新既有安装。

**安全证据勘误（2026-09-06）：** 此前“[CVE-2025-56499](https://github.com/advisories/GHSA-7m6g-3fpv-8gmx)
对锁定源码仍无法判断”的表述现已更正。上游 [PR #2177](https://github.com/MetaCubeX/mihomo/pull/2177)
已纳入 [v1.19.12](https://github.com/MetaCubeX/mihomo/releases/tag/v1.19.12)，且本项目锁定的
v1.19.28 源码保留该修复。既有隔离源码回归证据支持默认路径策略下已修复：路径检查开启、
未扩展允许目录、采用非 CMFA 构建；随包启动脚本静态复核未发现覆盖路径策略的设置。
这是源码层处置，不是新增随包二进制执行测试或真实路由器安全验收，也不解除独立的上游真实性
要求。已发布标签和下载归档保持不变，因此仍保留原文字；本次带日期的勘误只更新文档与发布页说明。

请选择一个软件包并同时下载 `SHA256SUMS`。如选择仅源码包，其中不含运行时载荷。
manifest、SBOM 和完整对应源码用于审计，不是额外安装步骤。

| 下载 | 用途 / GitHub 标签 |
|---|---|
| [`home-edge-bootstrap-v0.1.4-offline.zip`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.4/home-edge-bootstrap-v0.1.4-offline.zip) | Windows offline package - runtime included |
| [`home-edge-bootstrap-v0.1.4-offline.tar.gz`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.4/home-edge-bootstrap-v0.1.4-offline.tar.gz) | macOS/Linux offline package - runtime included |
| [`home-edge-bootstrap-v0.1.4-source.zip`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.4/home-edge-bootstrap-v0.1.4-source.zip) | Windows source-only package - runtime not included |
| [`home-edge-bootstrap-v0.1.4-source.tar.gz`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.4/home-edge-bootstrap-v0.1.4-source.tar.gz) | macOS/Linux source-only package - runtime not included |
| [`SHA256SUMS`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.4/SHA256SUMS) | Checksums - download with one selected package |
| [`RELEASE-MANIFEST.json`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.4/RELEASE-MANIFEST.json) | Release manifest - provenance and audit |
| [`SBOM.spdx.json`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.4/SBOM.spdx.json) | SPDX SBOM - audit |
| [`mihomo-v1.19.28-source-complete.tar.gz`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.4/mihomo-v1.19.28-source-complete.tar.gz) | Mihomo complete source - not required for installation |
| [`shellcrash-1.9.4-source-complete.tar.gz`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.4/shellcrash-1.9.4-source-complete.tar.gz) | ShellCrash complete source - not required for installation |

| 文件名 | GitHub 标签 |
|---|---|
| `home-edge-bootstrap-v0.1.4-offline.zip` | `Windows offline package - runtime included` |
| `home-edge-bootstrap-v0.1.4-offline.tar.gz` | `macOS/Linux offline package - runtime included` |
| `home-edge-bootstrap-v0.1.4-source.zip` | `Windows source-only package - runtime not included` |
| `home-edge-bootstrap-v0.1.4-source.tar.gz` | `macOS/Linux source-only package - runtime not included` |
| `SHA256SUMS` | `Checksums - download with one selected package` |
| `RELEASE-MANIFEST.json` | `Release manifest - provenance and audit` |
| `SBOM.spdx.json` | `SPDX SBOM - audit` |
| `mihomo-v1.19.28-source-complete.tar.gz` | `Mihomo complete source - not required for installation` |
| `shellcrash-1.9.4-source-complete.tar.gz` | `ShellCrash complete source - not required for installation` |

## v0.1.3（2026-08-01）

该勘误版本在发布文档完整性方面取代 v0.1.2。运行时载荷、组件锁、部署行为与已声明
兼容性边界均未改变；不新增硬件、服务商、网络或真实路由器认证声明。

- GitHub Release 正文只渲染精确目标版本章节，当前发布页不会再把历史下载矩阵显示成
  当前下载指导。
- fixture 版本从发布说明推导，要求中英文当前章节一致，拒绝历史下载 tag，并要求覆盖
  当前版本完整资源合同。
- 打包源码文档采用版本中立的构建指引；Windows fixture 清理改为确定性处理；源码准备阶段
  显式优先使用 POSIX `find`，避免 Git Bash 误选不兼容的 Windows 命令。

v0.1.2 资源保持不可变且仍可校验。请使用发布展示和验证合同已修正的 v0.1.3，并选择
一个软件包与 `SHA256SUMS`：

| 需要 | 下载 | 必须同时下载 |
|---|---|---|
| Windows 离线包，包含运行时 | [`home-edge-bootstrap-v0.1.3-offline.zip`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.3/home-edge-bootstrap-v0.1.3-offline.zip) | [`SHA256SUMS`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.3/SHA256SUMS) |
| macOS/Linux 离线包，包含运行时 | [`home-edge-bootstrap-v0.1.3-offline.tar.gz`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.3/home-edge-bootstrap-v0.1.3-offline.tar.gz) | [`SHA256SUMS`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.3/SHA256SUMS) |
| Windows 仅脚本/文档，已有运行时 | [`home-edge-bootstrap-v0.1.3-source.zip`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.3/home-edge-bootstrap-v0.1.3-source.zip) | [`SHA256SUMS`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.3/SHA256SUMS) |
| macOS/Linux 仅脚本/文档，已有运行时 | [`home-edge-bootstrap-v0.1.3-source.tar.gz`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.3/home-edge-bootstrap-v0.1.3-source.tar.gz) | [`SHA256SUMS`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.3/SHA256SUMS) |

其余资源用于审计与对应源码可获得性：

| 资源 | 用途 | 正常安装是否需要 |
|---|---|---|
| [`RELEASE-MANIFEST.json`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.3/RELEASE-MANIFEST.json) | 记录公开提交、组件锁、大小与摘要 | 否 |
| [`SBOM.spdx.json`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.3/SBOM.spdx.json) | 发布专用的软件清单与许可证元数据 | 否 |
| [`mihomo-v1.19.28-source-complete.tar.gz`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.3/mihomo-v1.19.28-source-complete.tar.gz) | 分发 Mihomo 载荷的完整对应源码 | 否 |
| [`shellcrash-1.9.4-source-complete.tar.gz`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.3/shellcrash-1.9.4-source-complete.tar.gz) | 分发 ShellCrash 载荷的完整对应源码 | 否 |

| 文件名 | GitHub 标签 |
|---|---|
| `home-edge-bootstrap-v0.1.3-offline.zip` | `Windows offline package - runtime included` |
| `home-edge-bootstrap-v0.1.3-offline.tar.gz` | `macOS/Linux offline package - runtime included` |
| `home-edge-bootstrap-v0.1.3-source.zip` | `Windows source-only package - runtime not included` |
| `home-edge-bootstrap-v0.1.3-source.tar.gz` | `macOS/Linux source-only package - runtime not included` |
| `SHA256SUMS` | `Checksums - download with one selected package` |
| `RELEASE-MANIFEST.json` | `Release manifest - provenance and audit` |
| `SBOM.spdx.json` | `SPDX SBOM - audit` |
| `mihomo-v1.19.28-source-complete.tar.gz` | `Mihomo complete source - not required for installation` |
| `shellcrash-1.9.4-source-complete.tar.gz` | `ShellCrash complete source - not required for installation` |

## v0.1.2（2026-07-31）

本补丁版本在跨平台宿主验证与生命周期迁移层面取代 v0.1.1，并纳入最终 RT-AX86U Pro
现场发现，但不声明新增硬件、服务商或网络认证。

- PowerShell 部署路径与 POSIX 路径一致支持临时 `DEPLOY_BUNDLE_DIR` 覆盖；运行时计划测试
  使用小型合成 bundle，不再假设源码 checkout 含有生产运行时。
- macOS 缺少 GNU `sha256sum` 时，通过临时兼容命令使用系统原生 `shasum -a 256`，不安装
  软件包，也不修改宿主环境。
- GitHub checkout action 更新至当前基于 Node 24 的主版本；PowerShell 验证实时输出，并为
  宿主矩阵失败写入受限的末尾日志注解。
- 发布候选版本从所推送 tag 或手动触发时的显式输入取得，不再错误构建标为 v0.1.0 的制品。
- 在投影、部署、验证、秘密扫描与 fixture 临时目录中统一规范化 macOS `TMPDIR` 末尾的
  路径分隔符；ShellCrash 数据 fixture 使用兼容 GNU/BSD 的文件模式检查。
- 将一个结构完整的旧 ShellCrash `services-start` 块迁移为唯一规范生命周期块；标记缺失、
  重复、逆序或交叠时在改写无关钩子内容前阻断，decommission 同样识别该旧表面。
- 在真实 RT-AX86U Pro 手动从官方固件 `3006.102.8_0` 更新至 `3006.102.8_2` 后验证该迁移：
  CrashCore 保持可用，controller 认证与 Yacd 响应健康，旧块归零且只保留一条启动命令。
  这是受限现场证据，不构成对其他型号、服务商或网络的认证。

v0.1.1 资源保持不可变。v0.1.2 的九个文件不需要全部下载；选择一个包，并同时下载
`SHA256SUMS`：

| 使用场景 | 下载文件 | 同时需要 |
|---|---|---|
| Windows 离线包，包含运行时 | [`home-edge-bootstrap-v0.1.2-offline.zip`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.2/home-edge-bootstrap-v0.1.2-offline.zip) | [`SHA256SUMS`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.2/SHA256SUMS) |
| macOS/Linux 离线包，包含运行时 | [`home-edge-bootstrap-v0.1.2-offline.tar.gz`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.2/home-edge-bootstrap-v0.1.2-offline.tar.gz) | [`SHA256SUMS`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.2/SHA256SUMS) |
| Windows 仅脚本/文档，运行时已存在 | [`home-edge-bootstrap-v0.1.2-source.zip`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.2/home-edge-bootstrap-v0.1.2-source.zip) | [`SHA256SUMS`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.2/SHA256SUMS) |
| macOS/Linux 仅脚本/文档，运行时已存在 | [`home-edge-bootstrap-v0.1.2-source.tar.gz`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.2/home-edge-bootstrap-v0.1.2-source.tar.gz) | [`SHA256SUMS`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.2/SHA256SUMS) |

manifest、SBOM 与完整源码归档不是额外安装部件：

| 资源 | 用途 | 普通安装是否需要 |
|---|---|---|
| [`RELEASE-MANIFEST.json`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.2/RELEASE-MANIFEST.json) | 记录公开提交、组件锁、大小与摘要 | 否 |
| [`SBOM.spdx.json`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.2/SBOM.spdx.json) | 发布专用软件清单与许可证元数据 | 否 |
| [`mihomo-v1.19.28-source-complete.tar.gz`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.2/mihomo-v1.19.28-source-complete.tar.gz) | Mihomo 完整对应源码 | 否 |
| [`shellcrash-1.9.4-source-complete.tar.gz`](https://github.com/yiheng8023/home-edge-bootstrap-public/releases/download/v0.1.2/shellcrash-1.9.4-source-complete.tar.gz) | ShellCrash 完整对应源码 | 否 |

| 文件名 | GitHub 标签 |
|---|---|
| `home-edge-bootstrap-v0.1.2-offline.zip` | `Windows offline package - runtime included` |
| `home-edge-bootstrap-v0.1.2-offline.tar.gz` | `macOS/Linux offline package - runtime included` |
| `home-edge-bootstrap-v0.1.2-source.zip` | `Windows source-only package - runtime not included` |
| `home-edge-bootstrap-v0.1.2-source.tar.gz` | `macOS/Linux source-only package - runtime not included` |
| `SHA256SUMS` | `Checksums - download with one selected package` |
| `RELEASE-MANIFEST.json` | `Release manifest - provenance and audit` |
| `SBOM.spdx.json` | `SPDX SBOM - audit` |
| `mihomo-v1.19.28-source-complete.tar.gz` | `Mihomo complete source - not required for installation` |
| `shellcrash-1.9.4-source-complete.tar.gz` | `ShellCrash complete source - not required for installation` |

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
  证明不再为每个 staging 文件创建一个 Git Bash shell，会规范化平台差异产生的 SHA-256
  输出并兼容既有星号分隔记录；失败路径 fixture 使用最小且可校验的运行时载荷，回滚清理
  也会覆盖服务规则辅助脚本。运行时阶段失败时，要么重放已恢复的旧控制面，要么清除首次
  安装写入的活动脚本与钩子后再报告回滚结果。

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
