# 无代理前置引导契约

> 中文版是英文 `docs/NO_WALL_BOOTSTRAP.md` 的阅读映射；英文文件是项目真源。

本项目的目的就是建立代理链路。因此，在代理链路可用之前，所有必需步骤都必须不依赖这条尚未建立的代理链路。

## 契约

在 `proxy_state=verified` 之前，必需操作只能依赖：

- 本地已经存在的仓库；
- 本地系统工具，例如 Git、SSH、tar、PowerShell，以及 POSIX 系统上的 gzip；
- 局域网内的路由器 Web GUI；
- 局域网内的路由器 SSH；
- 路由器上已经存在的文件；
- `bundle/` 中已经存在的文件；
- 用户提供的服务商订阅 URL，前提是该服务商端点可直连访问。

在 `proxy_state=verified` 之前，必需操作不得把以下来源的可达性作为前提：

- GitHub、SourceForge、Asuswrt-Merlin 官网，或其他在当前网络下可能较慢、被阻断或阶段性不可达的互联网下载；
- 公共订阅转换器；
- 需要联网拉取内容的包管理器或安装器；
- 需要依赖尚未可用代理链路的 DNS、geosite、geoip、内核、dashboard 或规则下载。

## 推论

- `prepare-bundle` 不是代理建立前的必需步骤。它会从 GitHub 下载发布资产；GitHub 在中国大陆通常并非完全不可访问，但可能较慢，也可能在敏感时期阶段性不可达。因此，无代理主流程不能依赖它一定可用。
- 全新无代理运行时安装要求 `bundle/` 中已有经过校验的文件。
- 如果 `bundle/` 缺失，本工具仍可配置和监管已有 ShellCrash/Mihomo 运行时，但不得声称可以完成全新离线安装。
- 公共远端转换器默认保持阻止。代理可用前，应优先使用服务商直出 YAML、ShellCrash 菜单导入，或可信本地/私有转换器；只有用户明确接受暴露订阅 URL 后，才允许公共转换器。

## 本地就绪检查

Windows PowerShell：

```powershell
.\scripts\check-no-wall-readiness.ps1
```

macOS/Linux shell：

```sh
sh scripts/check-no-wall-readiness.sh
```

该检查不会访问网络。它会检查本地工具，并在 `bundle/` 存在时校验离线运行时载荷。

## 实际流程

1. 使用路由器 Web GUI 和局域网 SSH 完成初始设置。
2. 运行 `check-no-wall-readiness`。
3. 运行 `guide-router`。
4. 如果 ShellCrash/Mihomo 已存在，则部署策略和脚本，并导入服务商配置。
5. 如果运行时缺失，只有在 `bundle/` 已校验时才使用 `-InstallRuntime`。
6. 只有路线验证通过后，在线准备任务才可以作为便利项，而不是阻塞项。
