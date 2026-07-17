# Home Edge Bootstrap

[English](README.md) | 简体中文

最短路径：[快速开始](QUICKSTART.zh-CN.md)。

Home Edge Bootstrap 是面向家庭与中小组织网络边缘的能力驱动型启动、恢复与韧性框架。
它将未准备好的边缘网关渐进式引导为可观测、可恢复、可自愈的代理路径，同时把必须由人
判断的事项保留为明确边界。

当前已实现的参考适配器面向运行官方 Asuswrt-Merlin 的华硕路由器，并使用
ShellCrash/ShellClash 与 Mihomo 兼容运行时。这是首个已实现适配器，不是永久架构边界，
也不代表该适配器已经取得“已验证”成熟阶段。Windows、macOS 与 Linux 是当前声明能力
边界内的操作宿主机系列。

框架复用成熟代理运行时及其既有管理界面，不重复实现代理核心或仪表盘。未来可通过独立
适配器接入其他设备、固件和运行时系列，但必须先明确并验证相应能力、安全、恢复、证据和
维护契约。

## 从这里开始

选择或刷写路由器前，先按准确型号和硬件修订版核对
[Asuswrt-Merlin 官方支持型号页](https://www.asuswrt-merlin.net/about)，再到
[官方下载页](https://www.asuswrt-merlin.net/download)确认当前确有对应构建；型号专属的
手册、原厂固件和恢复工具以[华硕官方下载中心](https://www.asus.com/global/support/download-center/)
为准。华硕仍提供该型号资料，并不等于 Asuswrt-Merlin 当前仍支持。修改设置前先阅读
[路由器基线](docs/zh-CN/ROUTER_BASELINE.md)。

刷写步骤遵循[梅林官方安装指南](https://github.com/RMerl/asuswrt-merlin.ng/wiki/Installation)；本项目
不会下载或刷写路由器固件。项目官网不可达时，使用官方
[SourceForge 发布区](https://sourceforge.net/projects/asuswrt-merlin/files/)，或梅林官方下载页当前
列出的其他官方下载入口。第三方社区或支持网站可能只面向某个国家或地区，也可能分发改版固件；
不假定其他国家或地区存在对应站点，也不要把它当作官方来源。

克隆仓库并打开编号式引导界面：

```powershell
git clone https://github.com/yiheng8023/home-edge-bootstrap-public.git
cd home-edge-bootstrap-public
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\tui.ps1
```

```sh
git clone https://github.com/yiheng8023/home-edge-bootstrap-public.git
cd home-edge-bootstrap-public
sh scripts/tui.sh
```

可使用 `router-user@router.lan` 这样的通用目标。帮助路径只在本地运行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\tui.ps1 -Help
```

```sh
sh scripts/tui.sh --help
```

在 macOS 与 Linux 上，本地验证需要 Python 3。可使用 `python3`；仅当 `python` 指向 Python 3 时才可使用 `python`。不支持 Python 2。

## 完成标准

只有目标自身的证据同时满足以下条件，才可将该目标视为可用：

- 已具备必需的宿主机、SSH、固件、持久化存储、shell 与运行时能力。
- 路由器基线不存在尚未处理、也未由操作者明确接受的行动项。
- 任何写入前，dry-run 计划都已明确目标、受管路径、备份和回滚路径。
- 运行时已消费通过校验的订阅或配置，且没有暴露订阅凭据。
- 健康检查能够发现并查询运行时，而不是依赖固定 controller 端口。
- 在理解路线选择与回退行为之前，自愈保持 dry-run。
- 客户端侧检查确认了预期拓扑，没有把终端代理静默当成路由器路径证据。
- 声明目标及已接受边界的最终安装门禁通过。

合成 fixture 证明的是脚本行为，不会认证具体路由器、固件构建、服务商或网络。应用变更前
请阅读[兼容性](docs/zh-CN/COMPATIBILITY.md)。

## 引导式 TUI

零新增依赖的 TUI 是常规交互入口。它是编号式向导，不是仪表盘：路由器固件、ShellCrash、
软路由和终端代理继续使用各自管理界面。向导调用已有诊断、启动、离线恢复、回滚和支持包
导出脚本，不复制这些脚本的状态机。

引导按以下顺序渐进执行：

1. 不连接路由器，先检查本机前置条件与文档。
2. 声明目标，再通过 SSH 执行只读能力探测。
3. 审查 `--dry-run` 部署计划，包括备份与回滚信息。
4. 只有计划可接受时，才输入精确令牌 `APPLY`。
5. 先验证运行时和客户端拓扑；只有确实准备开启真实自愈时，才输入精确令牌 `ENABLE`。
6. 只有确实准备执行提示中的回滚时，才输入精确令牌 `ROLLBACK`。
7. 生成脱敏支持包后，逐个检查文件，再决定是否共享。

EOF、中断、无效输入或任何不符合要求的确认内容都会取消可写动作。

## 架构与产品边界

框架将通用控制契约与适配器实现分离：

- 通用层定义任务入口、能力检查、plan/apply 分离、备份、回滚、恢复、秘密处理、证据和
  收官行为。
- 适配器把这些契约映射到具体设备、固件、文件系统、服务管理器与运行时组合。
- 成熟第三方运行时继续负责流量处理和自身运维界面。
- 回退路径保持运维独立；回退成功不能证明路由器路径工作正常。

| 领域 | 当前公开范围 | 边界 |
| --- | --- | --- |
| 已实现参考适配器 | 运行官方 Asuswrt-Merlin 的华硕网关 | 仅为首个实现；不是永久产品边界，也不是“已验证”成熟度声明 |
| 代理运行时 | ShellCrash/ShellClash 与 Mihomo 兼容运行时 | 项目负责协调并验证路径，不替代运行时或其仪表盘 |
| 操作宿主机 | Windows、macOS 或 Linux | 不同宿主机的命令与可用能力不同 |
| 离线恢复 | 源码 checkout；存在时另用经过独立校验的离线发布物 | 源码 checkout 不代表已经包含运行时载荷 |
| 回退路径 | 独立软路由或端点回退 | 用于保留恢复访问能力，但不会认证路由器路径 |
| 自动化 | 对安全、边界明确且可验证的动作自动化 | 刷固件、购买服务、凭据、信任判断与最终接受仍由人负责 |

详见[架构](docs/zh-CN/ARCHITECTURE.md)、[无代理前置约束](docs/zh-CN/NO_WALL_BOOTSTRAP.md)
与[威胁模型](docs/zh-CN/THREAT_MODEL.md)。

## 适配器与支持模型

适配器成熟度和目标支持分类是两个独立维度：

- 适配器成熟度描述实现责任与证据：外部集成、实验性适配器、社区维护适配器或已验证适配器。
- 目标支持分类描述适配器对某一目标的判断：`supported`、`supported_needs_manual`、
  `accepted_modified`、`unknown` 或 `unsupported`。

当前 Merlin 实现是已实现参考适配器；这一角色不等于取得“已验证”成熟阶段。公开兼容性
矩阵当前只包含政策声明与合成 fixture 证据，现场证据集合有意保持为空，因此其中列出的目标
路径保持为 `unknown`，直到目标专用证据能够建立其他分类。

未来适配器在具备明确维护者，以及边界清晰的能力、安全、恢复、证据、维护、迁移和项目退出契约，
并具备合成 fixture、回滚行为、不含敏感信息的诊断、
双语操作说明和与支持声明相匹配的证据路径之前，应保持为外部实现。接纳与成熟度调整由维护者
通过审查决定；受欢迎程度或与现有代理方案相似不能替代证据。

## 稳定状态与安全项目退出

可替换项目代码位于 `/jffs/home-edge-bootstrap`；保留的操作者与恢复状态位于
`/jffs/home-edge-bootstrap-state`。部署、回滚和项目退出都会保留稳定状态。项目退出默认先生成
计划，只删除经审查的项目辅助脚本、精确注册、经过校验的 kit 变体和默认可再生缓存；它不会
删除订阅、本地策略、恢复备份、Asuswrt-Merlin 固件或外部 ShellCrash/Mihomo 运行时。准确命令见
[快速开始](QUICKSTART.zh-CN.md)。运行时卸载和固件恢复仍是彼此独立的维护者/厂商操作。

## 源码 checkout 与离线恢复

本仓库是项目源码 checkout，包含脚本、文档与合成离线 fixture。它可以配置既有受支持
运行时，但不代表全新安装所需的运行时载荷已经包含在源码中。

单独发布的离线发布物可以包含受校验和约束的运行时载荷、第三方许可证、完整对应源码、
SPDX SBOM 与发布清单。解压前必须校验发布物摘要。制品可用性不会扩大已声明的设备、固件、
架构或支持边界。

这一区分用于保护无代理前置路径：在 `proxy_state=verified` 之前，必需步骤不能依赖代理已经
可用。应使用本地 checkout、局域网管理、局域网 SSH、目标上已有文件，或此前已校验的离线
发布物。互联网下载只能作为可选准备来源，不能成为必需恢复步骤。

## 安全与人工边界

- 自行核验 SSH 主机密钥；不要关闭主机密钥检查。
- 测试网关变更时，保留独立管理或恢复路径。
- 输入 `APPLY` 前，审查 dry-run 目标、路径、备份与回滚命令。
- 只有理解 dry-run 和回退行为后，才开启真实自愈；该写入需要精确令牌 `ENABLE`。
- 订阅 URL 属于凭据。绝不能提交到仓库、粘贴到 issue 或放入支持归档。
- 分享脱敏支持包前，逐个检查其中的文件。
- 不要把 fixture 成功、品牌知名度或单个目标成功扩展为更宽泛的兼容性声明。

对于账号、支付、注册及其他身份敏感操作，普通连通性或最低延迟出口不能证明出口身份稳定、
适用。自动选路与自愈可能在多次尝试之间改变出口。本项目可以暴露并约束这一连续性边界，
但不承诺平台接受、地区资格或交易成功。

## 渐进式操作路径

1. 阅读[快速开始](QUICKSTART.zh-CN.md)与[兼容性](docs/zh-CN/COMPATIBILITY.md)。
2. 运行 TUI 帮助和本地验证；这些路径不会连接路由器。
3. 确认宿主机工具，并准备独立回退或管理路径。
4. 声明目标，执行只读能力与基线检查。
5. 审查部署 dry-run 与明确的回滚路径。
6. 只有输入 `APPLY` 后才应用，并保留报告的备份。
7. 通过文档定义且不暴露敏感信息的路径提供订阅。
8. 验证运行时、路由器与客户端拓扑。
9. 自愈 dry-run 证据可接受后，再开启真实自愈。
10. 运行最终安装门禁，并保留恢复所需的非秘密证据。

任何阶段不能建立所需证据时，都应停在该边界，不得把证据缺失改写成接受结论。

## 本地验证

本地验证不会连接路由器或网络：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\verify-local.ps1
```

```sh
sh scripts/verify-local.sh
```

这些命令验证公开 checkout 与合成 fixture，不会替代目标能力检查、现场观察或
[发布就绪边界](docs/zh-CN/RELEASE_READINESS.md)中的发布专用门禁。

## 支持、安全与贡献

- 使用与设计问题：[支持说明](SUPPORT.zh-CN.md)
- 兼容性证据与未来适配器提案：
  [结构化 Issue 表单](https://github.com/yiheng8023/home-edge-bootstrap-public/issues/new/choose)
- 机密漏洞报告：[安全政策](SECURITY.zh-CN.md)
- 聚焦且可复现的变更：[贡献指南](CONTRIBUTING.zh-CN.md)
- 维护者权责与证据规则：[治理](GOVERNANCE.zh-CN.md)
- 第三方许可：[第三方声明](THIRD_PARTY_NOTICES.md)
- 可复用项目图文与无障碍文本：[媒体包](media/MEDIA_KIT.md)

社区支持按力所能及原则提供。赞助不会形成服务级承诺、保证、响应优先级、发布承诺或功能权利。

## 自愿赞助

如果 Home Edge Bootstrap 对你有帮助，并且你愿意支持项目的持续维护、文档、测试与社区工作，
诚挚感谢任意金额的自愿赞助。赞助完全自愿，不购买支持优先级、功能、发布决策或技术影响力。

- 人民币赞助可以扫描下方微信支付或支付宝收款码。
- 跨境赞助或其他受支持币种可以使用
  [PayPal 付款链接](https://www.paypal.com/ncp/payment/LNTF8KXGJXMZY)。实际可用币种、付款方式、
  换汇与手续费以 PayPal 结算页为准，并可能因国家或地区而异。

付款前请核对结算页面显示的收款方。感谢你对项目的支持。

<table>
  <tr>
    <td align="center"><strong>微信支付（人民币）</strong><br><img src="docs/assets/sponsoring/wechat-pay.png" alt="微信支付自愿赞助收款码" width="280"></td>
    <td align="center"><strong>支付宝（人民币）</strong><br><img src="docs/assets/sponsoring/alipay.png" alt="支付宝自愿赞助收款码" width="280"></td>
  </tr>
</table>

完整的自愿赞助与治理边界见[赞助说明](SPONSORING.zh-CN.md)。

## 仓库结构

```text
adapters/    设备与固件适配器；当前实现面向 Asuswrt-Merlin
bundle/      离线运行时契约与发布时填充的载荷位置
config/      可移植策略、兼容性、锁与 SBOM 数据
docs/        架构、恢复、兼容性、威胁与发布说明
media/       可复现公开图文、源文案、清单与无障碍文本
scripts/     引导操作、部署、恢复、验证与 fixture 入口
```

项目原创内容采用 Apache-2.0。打包或引用的第三方组件继续适用各自许可证与对应源码义务；
参见[第三方声明](THIRD_PARTY_NOTICES.md)。
