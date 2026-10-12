# 服务分流与登录恢复

[English](../SERVICE_ROUTING.md) · [首页](../../README.zh-CN.md)

登录凭据仍在，并不能证明认证或刷新请求能到达服务。如果换代理出口后恢复，应先检查分流与服务响应，再考虑清理凭据。普通延迟测试、服务商 `[AI]` 节点标签只能提供线索，不能保证登录、流式连接或未来可用性。

先在面板确认当前策略组及所选路线，保留已能工作的手动选择。应一起核对登录、会话、静态资源和文件域名；不同服务组可能选到不同出口。`HEAL_ROLE_ROUTE_GROUP_MATCH_REGEX` 和 `HEAL_ROLE_ROUTE_TARGET_REGEX` 选择的是组内已有候选，不会重写组成员，也不会启用专门的服务健康监视器。

对于已经实现的 Merlin/ShellCrash 参考适配器，下面是在部署项目 helper 后，进入**路由器 SSH 终端**执行的命令。将占位符换成面板中已确认存在的精确策略组名：

```sh
HOME_EDGE_SERVICE_PROFILE=openai \
HOME_EDGE_SERVICE_GROUP='填入已有服务策略组的精确名称' \
sh /jffs/scripts/home-edge-configure-service-rules.sh
```

这是受限依赖规则包的计划。精确 OpenAI/ChatGPT 关键词规则参与策略组推断；关键词和依赖域名指向不同组时，必须显式给出组。规则覆盖 `openai.com`、`chatgpt.com`、`oaistatic.com`、`oaiusercontent.com` 等服务域名及精确的共享依赖主机，包括 `frontend-apps-multi-region.workos.com`。

设置 `HOME_EDGE_SERVICE_RULES_ACTION=apply` 仅写入持久 ShellCrash 规则覆盖文件及恢复记录，并报告 `runtime_reload_state=pending`，这不表示运行内核已采用这些规则。普通 Mihomo `PUT /configs {}` 只重读绑定的配置，不执行 ShellCrash 的规则合成。须另行安排经过校验的合成或仅规则热应用；重载前核对候选配置、已保存与当前选择及恢复路径。ShellCrash 重启可能中断流量，并在之后恢复保存的选择。

分别验证当前 controller 的 `/rules`、新连接链和持久规则；旧连接可能仍沿用原路线。保留能工作的节点、运行时／内核及无关配置，不用旧选择快照覆盖用户后续选择。`status` 只检查持久标记，并将运行生效报告为 `not_checked`。局部分流修正也不能单独证明原 OAuth 异常的完整原因。
