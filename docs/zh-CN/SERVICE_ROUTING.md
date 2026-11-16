# 服务分流与登录恢复

[English](../SERVICE_ROUTING.md) · [首页](../../README.zh-CN.md)

登录凭据仍在，并不能证明认证或刷新请求能到达服务。如果换代理出口后恢复，应先检查分流与服务响应，再考虑清理凭据。普通延迟测试、服务商 `[AI]` 节点标签只能提供线索，不能保证登录、流式连接或未来可用性。

先在面板确认当前策略组及所选路线，保留已能工作的手动选择。应一起核对登录、会话、静态资源和文件域名；不同服务组可能选到不同出口。原有 `HEAL_ROLE_ROUTE_GROUP_MATCH_REGEX` 和 `HEAL_ROLE_ROUTE_TARGET_REGEX` 选择的是组内已有候选，不会重写组成员，也不是下述独立语义服务健康流程的启用开关。

## 通过既有标准代理观察

当前宿主原生 `yamlbridge` 另有产品中立的协议观察适配器。它使用显式 loopback／私网 IP 上的既有 HTTP/S 代理，无需 controller、具名节点、内核可执行文件、运行配置或路由器安装。保存请求，例如：

```json
{"adapter":"http-proxy-observe","profile":"gemini","proxy_url":"http://127.0.0.1:7890","timeout_sec":15}
```

使用针对该宿主 OS 构建的当前二进制运行 `yamlbridge service-probe request.json report-new.json`（PowerShell：`.\yamlbridge.exe service-probe request.json report-new.json`）。报告必须是新文件。可选服务为 `gemini`、`openai`、`anthropic`；端点必须是带明确端口的本机／私网 IP 字面量，不含 URL 凭据、查询参数或自定义路径。这里支持 HTTP/S 代理传输，不增加 SOCKS 或客户端控制能力。

结果标记 `route_binding=proxy_endpoint_only`、`egress_bound=false`、`verification_scope=frontend_only`、`account_verified=false`。即使观察到明确地区拒绝，也不能据此授权具名节点故障切换：代理实际出口尚未证明，适配器没有选择／恢复 API。控制能力缺失时只观察，证据未知则保持 unknown，不要求更换运行时或客户端产品。

该观察器与运行时驱动调用同一纯 `internal/healthpolicy` 决策包。观察器提供固定 observe 模式和仅观察能力，`policy_action`／`policy_reason` 报告其决策，`egress_unbound` 保留具名路线证据缺口。共用策略不授予控制能力。见[架构边界](ARCHITECTURE.md#产品中立的服务健康决策与具体适配器)。

## 当前 Merlin/Mihomo 分流适配器

对于已经实现的 Merlin/ShellCrash 参考适配器，下面是在部署项目 helper 后，进入**路由器 SSH 终端**执行的命令。将占位符换成面板中已确认存在的精确策略组名：

```sh
HOME_EDGE_SERVICE_PROFILE=openai \
HOME_EDGE_SERVICE_GROUP='填入已有服务策略组的精确名称' \
sh /jffs/scripts/home-edge-configure-service-rules.sh
```

这是受限依赖规则包的计划。精确 OpenAI/ChatGPT 关键词规则参与策略组推断；关键词和依赖域名指向不同组时，必须显式给出组。规则覆盖 `openai.com`、`chatgpt.com`、`oaistatic.com`、`oaiusercontent.com` 等服务域名及精确的共享依赖主机，包括 `frontend-apps-multi-region.workos.com`。

设置 `HOME_EDGE_SERVICE_RULES_ACTION=apply` 仅写入持久 ShellCrash 规则覆盖文件及恢复记录，并报告 `runtime_reload_state=pending`，这不表示运行内核已采用这些规则。普通 Mihomo `PUT /configs {}` 只重读绑定的配置，不执行 ShellCrash 的规则合成。须另行安排经过校验的合成或仅规则热应用；重载前核对候选配置、已保存与当前选择及恢复路径。ShellCrash 重启可能中断流量，并在之后恢复保存的选择。

分别验证当前 controller 的 `/rules`、新连接链和持久规则；旧连接可能仍沿用原路线。保留能工作的节点、运行时／内核及无关配置，不用旧选择快照覆盖用户后续选择。`status` 只检查持久标记，并将运行生效报告为 `not_checked`。局部分流修正也不能单独证明原 OAuth 异常的完整原因。

## 当前源码的语义服务健康流程

当前源码为 Merlin/ShellCrash 适配器增加可选的按服务配置与健康流程。这里说明已实现的源码行为，不表示现有发布包或路由器已经包含、部署或运行这些 helper。前述 `configure-service-rules` 仍是只管理受限覆盖规则的工具；下述新配置流程另行验证并应用其受管运行配置、覆盖文件和登记，保留恢复回执。

下表列出可选配置。默认 `SERVICE_HEALTH_PROFILES=gemini` 仅选择 Google/Gemini，保留其他服务的现有规则与选择。增加其他配置必须显式选择，并分别确认其当前初始化路线，不能假定各服务使用同一出口。

| 服务配置 | 用户外层选择器 | 私有自动选择器 |
|---|---|---|
| Gemini／指定 Google 端点 | `Edge-gemini` | `Edge-gemini-Auto` |
| OpenAI／ChatGPT | `Edge-openai` | `Edge-openai-Auto` |
| Anthropic／Claude | `Edge-anthropic` | `Edge-anthropic-Auto` |

各服务独立管理，Gemini 失败不授权修改 OpenAI、Anthropic 或其他选择器。Gemini 配置使用精确服务端点，不接管全部 Google 流量；其中共享的 `accounts.google.com` 规则也影响 Google 登录。其前端探测不验证 Gemini API、AI Studio 或 Antigravity。配置期间核对并保留原有选择器值。初始化路线发现有歧义时停止，不把一个公共出口自动赋给所有服务；有意共用初始化组须由操作者另行明确选择。

安装扩展解析工具不需要启用订阅自动化，可在任意工作目录使用主机入口。设备须已部署当前项目 helper；缺少时停止并提示先部署／刷新对应层。主机需要 SSH/SCP，以及用于模块验证、测试和按路由器 arm64/amd64 架构构建静态 Linux 工具的 Go；不会自动安装 Go 或盲目下载预编译工具：

```sh
sh /path/to/project/scripts/enable-service-health.sh USER@ROUTER
APPLY=1 sh /path/to/project/scripts/enable-service-health.sh USER@ROUTER
```

```powershell
& 'C:\path\to\project\scripts\enable-service-health.ps1' -Router USER@ROUTER
& 'C:\path\to\project\scripts\enable-service-health.ps1' -Router USER@ROUTER -Apply
```

第一条是 PLAN：只使用私有暂存并做设备原生验证，不安装受保护工具或配置。显式 APPLY 才安装已核验的压缩解析工具及原始 SHA256，保留一代自有工具备份，再仅配置 Google/Gemini 自动模式。SSH 默认严格沿用已有主机信任，并接受 `SSH_OPTS`（PowerShell 还支持 `-SshOptions`）。操作者也可用原始二进制及预期摘要代替 Go 构建：`SERVICE_HEALTH_PREBUILT`、`SERVICE_HEALTH_PREBUILT_SHA256`，或 PowerShell 的 `-PrebuiltBinary`、`-ExpectedSha256`；仍须通过设备原生哈希和能力检查。远端结局未知时保留私有暂存供核对；配置失败时保留其恢复回执和工具备份，不报告完成。

**仅在这些源码 helper 和已编译解析桥已经部署后**，进入**路由器 SSH 终端**执行：

```sh
sh /jffs/scripts/home-edge-configure-service-health.sh --plan
```

默认值是 `SERVICE_HEALTH_GOOGLE_MODE=manual`、`SERVICE_HEALTH_OPENAI_MODE=manual`、`SERVICE_HEALTH_ANTHROPIC_MODE=manual` 和 `SERVICE_HEALTH_MODE=observe`。计划只验证候选，不应用。确认计划后，按默认手动／观察模式应用：

```sh
SERVICE_HEALTH_CONFIRM=APPLY \
sh /jffs/scripts/home-edge-configure-service-health.sh --apply
```

启用 Google/Gemini 自动修复必须**同时**选择该服务的自动分支和健康引擎的实写模式。预览与应用须使用相同的显式设置：

仅有这两个模式还不够：下述受支持的已加载定义绑定也必须持续有效，否则驱动只观察，不自动选择。

```sh
SERVICE_HEALTH_GOOGLE_MODE=auto SERVICE_HEALTH_MODE=auto \
sh /jffs/scripts/home-edge-configure-service-health.sh --plan

SERVICE_HEALTH_GOOGLE_MODE=auto SERVICE_HEALTH_MODE=auto \
SERVICE_HEALTH_CONFIRM=APPLY \
sh /jffs/scripts/home-edge-configure-service-health.sh --apply
```

此例未选择 OpenAI、Anthropic，因此保留它们的现有分流；选择对应配置及模式均须另行显式启用。在任一外层 `Edge-*` 选择器中直接选择具体节点，即使引擎处于 auto，也保持该服务人工控制。选择对应 `Edge-*-Auto` 分支后，才允许已登记的自动化在该私有组内处理。准备期间用户选择、成员或配置改变时取消动作，不用旧快照覆盖后续选择。分别核对配置回执与实际加载规则；计划、源码更新或文件写入成功都不是部署或服务验收。

```sh
sh /jffs/scripts/home-edge-service-health.sh --check
sh /jffs/scripts/home-edge-service-health.sh --run
sh /jffs/scripts/home-edge-service-health.sh --status
```

`--check` 只观察并生成报告，不切换生产选择器。`--run` 遵守已登记的 observe/auto 模式和各服务手动保持，不自行授权实写。`--status` 显示上次报告，不重新探测。周期检查复用既有自愈 cron 生命周期，默认间隔 600 秒，不新增守护进程。默认要求连续三次合格失败、冷却 1,800 秒，并共享每小时两次写入预算（包含预留的回滚写入）；每项服务单次最多探测三个其他具体候选。这不保证每小时能成功修复两次。

`SERVICE_HEALTH_PROFILES` 选择一个或多个业务。已有 `Edge-*` 路由时优先沿用；否则可分别设置 `SERVICE_HEALTH_GEMINI_SEED_GROUP`、`SERVICE_HEALTH_OPENAI_SEED_GROUP` 或 `SERVICE_HEALTH_ANTHROPIC_SEED_GROUP` 解决发现歧义。`SERVICE_HEALTH_SEED_GROUP` 是有意指定共用初始组，避免据此误把其他厂商迁到同一出口。

后续只维护工具时，使用 `TOOLS_ONLY=1 APPLY=1 sh scripts/enable-service-health.sh USER@ROUTER`，或 PowerShell 的 `-ToolsOnly -Apply`；这只更新已验证工具，不重新配置／重载业务路由，也不修改手动选择。移除 APPLY 即预览同一范围。

## 探测证据与兼容边界

`mihomo-isolated` 是旧式 core／config／node 探测请求的默认适配器。每个候选使用现有 Linux 内核启动独立短时实例，采用私有目录和带认证的 loopback 监听器，固定绑定具体出站。这是 Mihomo 能力，不是通用代理控制契约。探测不轮换生产选择器、不刷新订阅、不共享生产缓存或 controller、不启动 TUN/DNS 监听器，也不改防火墙。只复制受支持的内联节点或已有 provider 缓存节点及可解析的 dialer 依赖；未知依赖保守停止。前述 `http-proxy-observe` 不启动内核，也不提供具名出口或自动控制证据。

结果归因于候选之前，适配器必须验证路由器自身出站的绕行条件。当前参考检查要求运行配置已有非零 routing mark、无 nftables 可执行程序，且 IPv4 的 `nat`／`mangle` OUTPUT 链为空并接受。源配置启用 IPv6 时，还检查对应 IPv6 OUTPUT 链，再提供双栈已核验前提。后端保留源 IPv6 选择；mark／IPv6 证据缺失或不一致时返回 unknown，不关闭用户 IPv6，也不尝试新防火墙标记。其他拦截拓扑需要经过验证的适配器。

自动控制还要求 `loaded_binding_file` 引用的私有回执。当前绑定**仅支持 Mihomo v1.19.34 inline 代理实例**：受控 `service-bind-reload` 路径执行真实、获授权的重载，并核对源文件／core 身份、规范化 `GET /configs`、重载后变化的 inline 实例 ID 及后续连续性。实例 ID 不是参数指纹。绑定缺失或源文件／core／配置／实例漂移时，报告 `loaded_definition_unverified` 或 `loaded_definition_changed`，降为 observe-only／unknown。重启或外部 reload 后须明确执行受控 rebind，不根据名称、相同文件字节或旧回执重建权限；不能伪造绑定文件绕过门槛。`proxy-providers` 不具备该自动绑定资格；`rule-providers` 可在静态目标及所有权检查通过时使用。通用代理观察器没有自动控制，因此不要求该回执。离线载荷可能固定为较旧 core；新 helper 不会升级它，也不表示自动控制门槛通过。

探测通过有限时长、校验 TLS 的 GET 检查响应正文，因此 HTTP 200 的明确 Gemini 国家限制页仍可判为 `region_denied`。尚未收到任何 HTTP 响应的请求失败可判为 `transport_failed`；取消、正文过大或不完整、鉴权、浏览器挑战、HTTP 429、泛化策略错误及无法识别的页面均保持 unknown，不据此发起切换。unknown 会打断连续失败序列。合格的重复失败仍须先找到独立正向验证的候选，才允许切换；切换后核验及所有权检查约束回滚／恢复，未确认的写入保留 pending 状态。

报告标记 `verification_scope=frontend_only`。`frontend_available` 仅表示响应中识别到有限的入口结构，不证明 JavaScript 已执行、CSS／浏览器实际渲染、账户资格、登录成功、模型生成或流式会话。入口／拒绝标记与 template、hidden、aria-hidden 或行内可见性结构共存时，保守返回 unknown；helper 不实现浏览器或完整 CSS 可见性模型。`account_verified` 始终为 false。网站变化可能使保守分类器返回 unknown，须在实际客户端另行验证登录后的使用。FlClash 等本地客户端不会被修改；其代理／TUN／DNS 路线可能在流量到达路由器前优先生效，所以路由器探测不能证明该客户端的实际路线。

FlClash 只是这种优先关系的示例，不是必需产品。协议夹具、纯策略夹具及受限原生观测分别证明不同事实；任何一项都不证明已经实现另一套路由器 kit，也不代表所有 OS／客户端／运行时组合通过实际客户端验收。只有观测接口、没有安全控制适配器时，保持只观察。

默认 Gemini 匿名探测（`/app?hl=en`）**尚不能证明能够检出已登录账户的地区限制**。登录后失败的路线与可用路线，匿名访问时可能都返回 HTTP 200 登录页，因此两者都保持 unknown；改用根页面也不是已经验证的解决办法。若响应正文实际出现可见的 `Gemini 目前不支持你所在的地区。敬请期待！`，分类器会识别为地区拒绝，但夹具通过不证明匿名端点会展示该内容。隐藏 JavaScript 能力标志或仅查询位置的 RPC 都不作为前端或账户成功证据。覆盖依赖登录状态的故障，需要另行明确配置并授权的认证探针，同时限定凭据、范围和维护责任；这里尚未实现该认证探针，helper 也不捕获浏览器 cookie。

## 自动管理与手动选择

订阅刷新与线路自愈的权限分开。刷新验证节点变更、保留已选节点，并在准备期间选择发生变化时取消；它不替你判断哪个节点适合某项业务。低延迟和 `[AI]` 标签都不能保证应用可用。

自愈保留可达的当前路线。允许实写后，可在探测失败或显式地区约束不满足时，为明确受管的主选择器做故障切换。用 **准确且可写的选择器名称**设置 `HEAL_GROUP` 来限定权限；指定组不存在或不可写时停止。自动主组发现排除含中文“手动”或英文单词 `Manual` 的名字；显式指定这样的组，即表示有意授权自动管理它。嵌套切换默认关闭，角色策略另有启用与匹配控制；这些显式功能仍可能授权主组之外的变更。每次切换及补偿回滚前重新核对当前选择和候选成员，发现计划变化就取消。控制器没有已确认的原子比较交换 API，所以这不能消除读取到写入间的短竞态及同值 ABA。

当前 Merlin 参考适配器的现场覆盖设置位于 `/jffs/home-edge-bootstrap-state/policy.local`。如果其他组要保持人工控制，应保留嵌套切换关闭并关闭角色修改。本地源码、登记桌面入口、设备项目文件、活跃 helper 和实际加载规则是不同状态：只更新有差异的一层，并逐层验证。README 或 Git 提交变化本身不要求重装路由器；仅项目刷新保留运行时／内核载荷，但可能改变受管集成与配置，应用前应预览并保留恢复材料。
