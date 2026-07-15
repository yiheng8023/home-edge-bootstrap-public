# 离线载荷契约

> 中文版是英文 `docs/BUNDLE_CONTRACT.md` 的阅读映射；英文文件是项目真源。

`bundle/` 默认被 Git 忽略，因为里面可能包含体积较大、与架构绑定的二进制文件。即便如此，契约本身应保持稳定，以便未来路由器在没有可用代理的情况下恢复。

## 预期文件

| 文件 | 用途 | 说明 |
|---|---|---|
| `bundle/mihomo-linux-arm64` | aarch64 Linux 路由器；需核验目标 Merlin 型号架构 | Mihomo 内核二进制 |
| `bundle/ShellCrash.tar.gz` | 全新安装 ShellCrash | ShellCrash 离线快照 |
| `bundle/SHA256SUMS` | 离线校验 | 使用前校验 SHA256 摘要 |
| `bundle/MANIFEST.json` | 来源记录 | 记录 release、资产、URL、大小和摘要 |

## 准备与校验

先检查当前仓库是否已经具备已校验 bundle。该检查不会访问网络。

Windows PowerShell：

```powershell
.\scripts\check-no-wall-readiness.ps1
```

macOS/Linux shell：

```sh
sh scripts/check-no-wall-readiness.sh
```

只在可信且可达的网络环境中准备离线包，或在已有另一条代理链路后准备。该步骤会下载发布资产，不是第一条代理链路建立前的必需步骤。

Windows PowerShell：

```powershell
.\scripts\prepare-bundle.ps1
```

macOS/Linux shell：

```sh
sh scripts/prepare-bundle.sh
```

在无网络环境中校验：

```sh
sh scripts/verify-bundle.sh
```

如果需要 clone 后即可离线恢复，应显式纳入载荷：

```sh
git add -f bundle/mihomo-linux-arm64 bundle/ShellCrash.tar.gz
git add bundle/MANIFEST.json bundle/SHA256SUMS
```

## 规则

- 不在 `bundle/` 放订阅 URL、服务商节点列表、密码或 API secret。
- 只有当确实需要 clone 后即可离线恢复时，才用 `git add -f bundle/<file>` 显式加入二进制。
- 架构相关载荷必须用清晰文件名标明，不让 `bootstrap.sh` 猜。
- 如果载荷缺失，适配器只能退化为“配置已有 ShellCrash”，不能声称已支持完整离线全新安装。
- 在代理链路验证通过前，不得要求 GitHub 或其他互联网下载源必须可达。
- 运行时安装是显式动作：设置 `BOOTSTRAP_INSTALL_RUNTIME=1`。已有 ShellCrash 目录不会被替换，除非同时设置 `BOOTSTRAP_REPLACE_RUNTIME=1`。

## 当前状态

默认情况下，当前仓库支持配置和监督已安装的 ShellCrash/Mihomo 运行时。当预期载荷齐备且设置 `BOOTSTRAP_INSTALL_RUNTIME=1` 时，Merlin 适配器可以从 `ShellCrash.tar.gz` 安装 ShellCrash，将 bundled Mihomo 内核写为 `CrashCore.gz`，并继续执行策略和自愈安装。订阅导入仍然是人工凭据步骤。
