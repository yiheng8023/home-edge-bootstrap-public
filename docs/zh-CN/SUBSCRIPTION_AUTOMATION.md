# 订阅自动化

> 中文版是英文 `docs/SUBSCRIPTION_AUTOMATION.md` 的阅读映射；英文文件是项目真源。

## 目的

更换代理服务商应当成为常规操作：替换订阅凭据，将订阅规范化为 Mihomo 可用配置，校验结果，写入缓存，并且只在明确允许时覆盖 live 配置。这个过程可以自动化，因为不同服务商最终描述的大多是同一类代理能力：Shadowsocks、VMess、VLESS、Trojan、Hysteria2、TUIC，或 Clash/Mihomo YAML。

不能静默自动化的是信任边界。订阅 URL 是凭据；接收它的转换服务能够看到该凭据。因此，本项目默认只直接下载，或使用 localhost/私有局域网内的转换器。公共转换器必须显式设置 `SUBSCRIPTION_ALLOW_REMOTE_CONVERTER=1` 才会使用。

## 支持流程

```text
服务商订阅 URL
-> 可选的本地/私有网络转换器
-> Mihomo/Clash YAML 校验
-> 缓存文件
-> 可选 live 配置路径
-> 自愈脚本验证已配置的可达性探测目标
```

当前实现中的订阅刷新由操作者显式调用。只有 self-heal 被定时调度；当前生命周期钩子和 cron 任务都不会定时刷新订阅。

路由器侧由 `/jffs/scripts/home-edge-update-sub.sh` 执行。主机侧提供两个常用安全入口：

- `scripts/store-subscription.ps1` / `.sh`：提示输入服务商 URL，并写入路由器；输出不会打印 URL。
- `scripts/refresh-subscription.ps1` / `.sh`：默认执行 DRY-RUN；只有显式 apply 时才更新缓存；可选覆盖已知 live 配置路径并执行已测试的重载命令。

## 配置

将服务商订阅 URL 放在：

```text
/jffs/home-edge-bootstrap/SUBSCRIPTION.local
```

重新部署项目时，会从上一版路由器安装目录保留 `SUBSCRIPTION.local`、`cache/`、`backups/` 和本地
policy override。更新项目脚本不应要求再次粘贴订阅 URL。

如果服务商已经返回 Mihomo/Clash YAML，使用直连模式：

Windows PowerShell：

```powershell
.\scripts\refresh-subscription.ps1 -Router $Router
.\scripts\refresh-subscription.ps1 -Router $Router -Apply
```

macOS/Linux shell：

```sh
sh scripts/refresh-subscription.sh "$router"
APPLY=1 sh scripts/refresh-subscription.sh "$router"
```

如果服务商返回 Mihomo 无法直接导入的原始/base64 订阅，使用转换模式：

Windows PowerShell：

```powershell
.\scripts\refresh-subscription.ps1 -Router $Router -ConverterBaseUrl "http://192.168.50.2:25500/sub" -ConverterTarget clash
```

macOS/Linux shell：

```sh
SUBSCRIPTION_CONVERTER_BASE_URL=http://192.168.50.2:25500/sub \
SUBSCRIPTION_CONVERTER_TARGET=clash \
sh scripts/refresh-subscription.sh "$router"
```

成功的 DRY-RUN 会输出 `subscription_dry_run=ok`。Apply 模式会输出 `subscription_cache=updated`，以及 `subscription_apply=cache_only` 或配置的 live 覆盖路径。这些输出不会包含订阅 URL。

`subscription_state=cache_ready` 只能证明项目持有已校验缓存，不能证明活跃运行时正在消费这些字节。强收官要求 `subscription_consumption_state=runtime_profile_matches_cache`，并具备成功重载证明、匹配的缓存摘要、运行时观测到的活跃配置路径与进程身份、不早于该进程启动且处于 `SUBSCRIPTION_RUNTIME_EVIDENCE_MAX_AGE_SEC`（默认 `300` 秒）内的证明，以及 fresh controller/路线证据。仅文件字节相等报告为 `profile_file_matches_cache`。受支持的仅缓存状态或 ShellCrash 手动导入仍是需要显式接受的边界。

运行时证明只接受项目自有的 `/tmp/home-edge-*` 或 `/jffs/home-edge-bootstrap/` 路径。所有已存在的路径组成部分和目标都必须无符号链接；拒绝发生在订阅获取、缓存或 live 配置变更之前。

如果你知道 live Mihomo/ShellCrash 配置路径，可以显式传入。希望继续用 ShellCrash 菜单导入，或不确定运行时 live 路径时，应保持为空：

Windows PowerShell：

```powershell
.\scripts\refresh-subscription.ps1 -Router $Router -Apply -ApplyPath "/path/to/live/config.yaml"
.\scripts\refresh-subscription.ps1 -Router $Router -Apply -ApplyPath "/path/to/live/config.yaml" -ReloadCommand "sh /path/to/reload.sh"
```

macOS/Linux shell：

```sh
APPLY=1 SUBSCRIPTION_APPLY_PATH=/path/to/live/config.yaml sh scripts/refresh-subscription.sh "$router"
APPLY=1 SUBSCRIPTION_APPLY_PATH=/path/to/live/config.yaml SUBSCRIPTION_RELOAD_CMD='sh /path/to/reload.sh' sh scripts/refresh-subscription.sh "$router"
```

可配置项：

| 变量 | 默认值 | 含义 |
|---|---:|---|
| `SUBSCRIPTION_CONVERTER_BASE_URL` | 空 | 转换器端点，例如自托管 subconverter 的 `/sub` |
| `SUBSCRIPTION_CONVERTER_TARGET` | `clash` | 转换目标格式 |
| `SUBSCRIPTION_CONVERTER_CONFIG_URL` | 空 | 可选转换规则/配置 URL |
| `SUBSCRIPTION_RUNTIME_EVIDENCE_MAX_AGE_SEC` | `300` | 与当前进程绑定的成功重载证明最大时效（秒） |
| `SUBSCRIPTION_ALLOW_REMOTE_CONVERTER` | `0` | 允许把订阅 URL 发给公共转换器前必须显式打开 |
| `SUBSCRIPTION_APPLY_PATH` | 空 | 备份后覆盖的 live 配置路径；为空则只写缓存 |
| `SUBSCRIPTION_RELOAD_CMD` | 空 | 覆盖 live 配置后的可选本地重载命令；重载失败时会尽力恢复上一份 live 配置 |
| `SUBSCRIPTION_DRY_RUN` | `1` | 只下载和校验，不改变缓存或 live 配置 |
| `SUBSCRIPTION_FETCH_PROXY` | 空 | 下载订阅时使用的可选代理 URL，例如本地 Mihomo mixed port |
| `SUBSCRIPTION_MIN_BYTES` | `64` | 拒绝明显异常的小响应 |

## 安全门槛

- 订阅文件必须存在，并且包含 URL。
- 公共转换器默认被阻止。
- 下载结果必须非空且达到最小体积。
- HTML/错误页会被拒绝。
- 原始/base64 服务商订阅会被拒绝，并提示需要转换器。
- 结果必须看起来像 Mihomo/Clash YAML 配置。
- 替换缓存或 live 文件前先备份。
- 覆盖 live 配置前先写入临时文件，再移动到目标路径。
- 如果配置了重载命令并在覆盖 live 后失败，存在备份时会恢复上一份 live 配置。
- 任一步失败时保留原有缓存和 live 配置。

## 调研结论

- Mihomo 支持 Clash 兼容配置和 proxy-provider 风格输入，这是本项目的目标运行格式。
- `subconverter` 是常见的订阅转换层，可把服务商原始订阅转换为 Clash 系配置。适合部署在本地或私有网络中。
- Sub-Store 可以管理多个订阅和转换规则，但它是更重的管理界面。除非未来确实需要多服务商聚合，本项目只需要转换器端点。

## 当前边界

在人提供可信订阅 URL，并在需要时提供可信转换器端点之后，换服务商流程可以自动化。账号购买、验证码/登录、付款，以及是否信任某个转换器，仍是人工边界。缓存刷新不代表已经重启运行时、导入/信任订阅、安装 Dashboard、修改防火墙/DNS、修改软路由或变更终端。


## 周期与按需节点更新

新增 `subscription-auto.sh` 统一处理周期、按需和手动刷新。站点明确开启
`SUBSCRIPTION_AUTO_ENABLED=1` 后，每五分钟检查：正常每 24 小时刷新一次；可用率连续
三次为零或低于健康参考值的一半，且上网探针通过、冷却和退避允许时，可提前刷新。
周期尊重供应方的 `profile-update-interval`。失败退避最长一天，未变化的节点不会重载。
控制和 mixed 代理端口从当前本地配置读取；订阅直连的传输故障可回退到本机现有代理，
仍校验 HTTPS 证书。HTTP 拒绝、无效内容或证书校验失败不会触发回退。
`SUBSCRIPTION_AUTO_PROXY_FALLBACK=0` 可关闭该行为。

此路径只接受直接 HTTPS 返回的 YAML/JSON 内联节点订阅。它保留本地策略组、规则、
DNS、控制器、监听配置与手动选择；子集组通过私有的 `subscription-groups.json` 定义匹配
规则。手动选择节点被删除时拒绝候选，不静默替换。原有原始/base64 转换流程仍可手动使用。

轻量解析桥由 `tools/yamlbridge` 在开发机编译，依赖固定版本和 go.sum，路由器不安装 Go。
通过当前内核配置校验和仅回环监听的隔离探针后，重新核对文件、来源、策略及选择，使用
不带 force 的 PUT /configs 获得同步重载确认。没有删除连接的调用。要求原生
`profile.store-selected` 未明确关闭，依赖内核保存选择，不重放旧选择 PUT；保存最新选择
并完成实际上网验证后才接受。失败或父进程卡住，由独立 120 秒监护恢复配置；若最新
选择不属于旧组成员则保留冲突。启动钩子先恢复未接受的持久配置，失败时暂缓项目启动，
其他用户钩子继续执行。恢复互斥放在 RAM，写锁绑定本次分配，防止跨重启遗留和误删后继锁。
`--check` 可验证和探测候选而不发布，也不修改持久刷新状态。

面板初始默认：按延迟从小到大、隐藏不可用代理、关闭自动断开旧连接。浏览器已经保存
的选项优先。本地 `/ui/` 入口自动选择页面所在路由器的控制器：首次只填写面板访问密钥，
验证并保存后，再次打开直接进入，不再 Add 或挑选 IP。控制器认证保持启用，服务器不把
访问密钥写入公开静态文件或 URL；密钥保存在该浏览器既有 Yacd 网站存储中。错误密钥可
重输，暂时断网只提供重试并保留已存密钥。显式的 `hostname`、`port`、`secret` 原生连接
链接保留原行为，显示偏好及其他后端记录保持。固定使用同一地址并允许保存网站数据；
仅移除空密钥、`addedAt: 0` 的内置 `127.0.0.1:9090` 占位记录，已配置的回环后端仍保留。
无痕会话、清理数据，以及不同 IP、域名或协议入口不能共用浏览器记住的连接。
这里只确认有界回退，不声称测试过断电持久性或现有 TCP 会话无缝迁移。
内核的手动选择与重载没有共同原子锁，恰好与重载重叠的点击仍有内核内部竞争窗口。
完整参数、构建和状态说明见英文真源新增章节。

启用前，host helper 会请求既有状态迁移器执行
`HOME_EDGE_STATE_RETIRE_SUBSCRIPTION_CACHE=1`：只有与已采纳稳定缓存字节完全相同的
旧 kit `cache/subscription.yaml`，才会移入私有
`backups/subscription/legacy-cache-*/subscription.yaml` 恢复留档。自动更新随后写稳定缓存，
不会因仍活跃的旧副本使下次部署失败。不同字节的副本仍严格拒绝，不放宽冲突门，也不丢失
原始数据。已有站点若带着启用前遗留的不同副本，需要一次有证据的本地核对，不能每次手动
替换缓存掩盖生命周期缺口。
