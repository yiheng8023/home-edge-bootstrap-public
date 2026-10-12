# Service routing and login recovery

[简体中文](zh-CN/SERVICE_ROUTING.md) · [Home](../README.md)

A stored login credential does not prove that its authentication or refresh request can reach the service. If changing a proxy restores access, investigate routing and service responses before clearing credentials. A generic latency test or a provider `[AI]` node label is only a signal; neither guarantees login, streaming or future availability.

Inspect the current policy group and its selected route in the dashboard. Preserve a working manual choice. Check login, chat, static assets and file domains together: different service groups can select different exits. `HEAL_ROLE_ROUTE_GROUP_MATCH_REGEX` and `HEAL_ROLE_ROUTE_TARGET_REGEX` choose existing group candidates; they do not rewrite group membership or enable a dedicated service-health monitor.

For the implemented Merlin/ShellCrash reference adapter, the following is a **router SSH terminal** command, after the project helper has been deployed. Replace the group placeholder with the exact existing group confirmed in your dashboard:

```sh
HOME_EDGE_SERVICE_PROFILE=openai \
HOME_EDGE_SERVICE_GROUP='YOUR_EXISTING_SERVICE_GROUP' \
sh /jffs/scripts/home-edge-configure-service-rules.sh
```

This plans a bounded dependency profile. Exact OpenAI/ChatGPT keyword rules participate in group discovery; conflicting dependency and keyword groups require an explicit group. The profile includes service domains such as `openai.com`, `chatgpt.com`, `oaistatic.com`, `oaiusercontent.com`, and exact shared dependency hosts, including `frontend-apps-multi-region.workos.com`.

Setting `HOME_EDGE_SERVICE_RULES_ACTION=apply` writes the persistent ShellCrash overlay and recovery state. It reports `runtime_reload_state=pending`: the running core has not thereby adopted the overlay. An ordinary Mihomo `PUT /configs {}` rereads its bound config and does not run ShellCrash's overlay synthesis. Arrange a separately validated synthesis or rule-only hot application; check the generated configuration, saved/current selections and recovery before reloading. A ShellCrash restart may interrupt traffic and later restore saved choices.

Verify the current controller `/rules`, new connection chains, and the persistent profile independently. Existing connections may keep their original route. Preserve the working node, runtime/core and unrelated configuration; do not replay an old selection snapshot over a later user choice. `status` checks persistent markers and explicitly reports `not_checked` for runtime activation. A routing correction alone does not prove the original OAuth failure's complete cause.
