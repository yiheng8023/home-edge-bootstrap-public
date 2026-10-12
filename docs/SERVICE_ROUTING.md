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

## Automatic management and manual choices

Subscription refresh and route self-heal have separate authority. Refresh validates node changes, preserves the selected nodes, and cancels when those choices change during preparation; it does not decide which node is best for an application. A latency result or an `[AI]` label is not an application-availability guarantee.

Self-heal keeps a healthy current route. When enabled for writes, it may fail over the explicitly managed main selector after a failed probe or an unmet explicit region constraint. Set `HEAL_GROUP` to the **exact writable selector name** to define that boundary; a missing or non-writable named group stops the run. Automatic main-group discovery excludes names containing Chinese `手动` or the English word `Manual`; explicitly naming such a group deliberately authorizes its automation. Nested switching remains off by default, and role policies have their own enable/matching controls. Those opt-ins can still authorize changes outside the automatically discovered main group. Before every switch or compensating rollback, the helper checks the current selection and membership again; a changed plan is cancelled. The controller has no established compare-and-set API, so this check does not eliminate the short read-to-write or same-value ABA race.

For the current Merlin reference adapter, site overrides live in `/jffs/home-edge-bootstrap-state/policy.local`. Keep nested switching disabled and role mutation disabled if the other groups are to remain under manual control. Local source, the registered desktop entry, deployed kit files, active helpers and loaded runtime rules are separate states: update only the differing layer and verify it. A new README or Git commit alone does not require router reinstallation; project-only refresh preserves runtime/core assets but may change managed integration/configuration. Preview that refresh and keep recovery material before applying it.
