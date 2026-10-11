# Paseo MCP 注入诊断（mcp__paseo__* "not a deferrable tool"）

- 核查员：research·paseo-mcp-inject（只读）
- 时间：2026-09-26
- 执行环境：本机 NixOS（hermes 用户，HOME=/var/lib/hermes），Paseo daemon 0.8.0-beta.1
- 约束：只读取证，未改任何配置、未重启、未 cp/reload、未 commit

---

## 1. 结论（一句话）

**Paseo daemon 运行态 `~/.paseo/config.json` 确实缺 `daemon.mcp.injectIntoAgents=true`（动态注入通道关闭，开关默认 false），但这不是唯一根因——本机 Hermes 另有一条静态注册通道且已生效，实测报错是间歇性的（同一长会话内 create_agent 成功→失败→成功），直接机制是 Paseo MCP 连接 keepalive 超时进入 parked、工具被 deregister，revive 后重新注册；因此"只影响丢失后新会话"的单一假设不成立。**

---

## 2. 证据（file:line）

### 2.1 三处 config 中该字段状态

| 位置 | `mcp.injectIntoAgents` | 证据 |
|---|---|---|
| 运行态 `~/.paseo/config.json` | **缺失**（无 `mcp` 键，daemon 下仅 cors+relay） | `/var/lib/hermes/.paseo/config.json:21-30`（全文 32 行） |
| 声明式 `modules/paseo.nix` | **= true**（但为工作区未提交、未部署改动） | `modules/paseo.nix:43`；`git status` 显示该文件 ` M`，`git diff HEAD` 确认此行是新增 |
| Nix store 渲染件 `2wyp0wy…` | **= true** | `/nix/store/2wyp0wyhl0ra1qd5xlagm89fh66h575q-paseo-config.json`：`daemon.mcp.injectIntoAgents: true` |

**关键矛盾点：含 true 的 `2wyp0wy…` 并不被当前运行的 systemd unit 引用。**

- 当前 active unit：`systemctl cat paseo.service` →
  - `ExecStartPre=/nix/store/pxlnx6asq36hx8pnjpb3nnvx2kvqadvh-unit-script-paseo-pre-start/bin/paseo-pre-start`
  - `ExecStart=/nix/store/8aqadp0l6rdg1dcx5n865c73xaf8zkxm-paseo-0.8.0-beta.1/bin/paseo-server`
- 该 ExecStartPre 脚本内容（`/nix/store/pxlnx6…/bin/paseo-pre-start:4`）：
  ```
  install -m 0600 /nix/store/yhswhdgxiqwp5h6ri9v5sw9ir8kskafl-paseo-config.json /var/lib/hermes/.paseo/config.json
  ```
- 它渲染的是 `/nix/store/yhswhdgxiqwp5h6ri9v5sw9ir8kskafl-paseo-config.json`，内容与运行态一致（605 字节，**无 `mcp` 键**）。
- 即：`modules/paseo.nix:43` 的修复停留在工作区，`2wyp0wy…` 是工作区改动的一次 build 残留（无 referrer），**未进入当前 boot generation（gen97）闭包中的渲染源**。

> 注：取证中 yhswh 曾短暂返回 "No such file"，随后同一脚本复测可读、内容如上。文件名经 Node 逐字节比对与引用完全一致（50 字符）。该瞬时不可见原因 `[UNCERTAIN]`，不影响"当前运行态无该字段"的结论。

### 2.2 server dist：开关读取点与注入作用链

包真实路径前缀（下文记 `$D`）：
`/nix/store/8aqadp0l6rdg1dcx5n865c73xaf8zkxm-paseo-0.8.0-beta.1/lib/paseo/packages/server/dist`

**(a) 启动时读取，缺失默认 false**
- `$D/server/server/config.js:338`
  ```js
  mcpInjectIntoAgents: cli?.mcpInjectIntoAgents ?? persisted.daemon?.mcp?.injectIntoAgents ?? false,
  ```
- 同文件 `:337`：`mcpEnabled … ?? true`（MCP 总开关默认开）。

**(b) 构造初始 mutable daemon config**
- `$D/server/server/bootstrap.js:286-289`
  ```js
  mcp: {
      enabled: config.mcpEnabled ?? true,
      injectIntoAgents: config.mcpInjectIntoAgents ?? true,
  },
  ```
  （注意此处 `?? true` 只在传入值为 null/undefined 时兜底；而 (a) 已把"缺失"解析成布尔 `false`，故运行态缺失最终为 false。）

**(c) 开关 → AgentManager：spawn 时是否注入**
- `$D/server/server/bootstrap.js:1051-1052`
  ```js
  agentManager.setPaseoToolsEnabled(config.mcpInjectIntoAgents !== false);
  setAgentProviderToolsEnabled(config.mcpEnabled !== false && config.mcpInjectIntoAgents !== false);
  ```
- spawn/会话准备链路：`$D/server/server/agent/agent-manager.js:3517 prepareSessionConfig` → `:3522`
  ```js
  const launchConfig = this.applyDaemonAppendSystemPrompt(withRuntimePaseoMcpServer({
      config: storedConfig,
      agentId,
      mcpBaseUrl: this.paseoToolsEnabled && isPaseoToolPolicyEnabled(paseoToolPolicy) ? this.mcpBaseUrl : null,
      mcpAuthToken: this.mcpAuthToken,
  }));
  ```
- 真正把 paseo MCP server 拼进 agent `mcpServers` 的函数：
  `$D/server/server/agent/runtime-mcp-config.js:23-41`，其中
  - `:1` 服务器名 `const PASEO_MCP_SERVER_NAME = "paseo";`
  - `:2` 路径 `const PASEO_MCP_PATHNAME = "/mcp/agents";`
  - `:25` `if (!params.mcpBaseUrl …) return storedConfig;`（baseUrl 为 null → **不注入**）
  - `:33` `url: \`${params.mcpBaseUrl}?callerAgentId=${params.agentId}\``
  - `:34-36` 有 auth token 时加 `Authorization` 头
- baseUrl 由监听目标构造：`$D/server/server/bootstrap.js:173-179 createAgentMcpBaseUrl` → `http://<host>:<port>/mcp/agents`。
- 每个 agent 子进程注入 `PASEO_AGENT_ID`：`$D/server/server/agent/agent-manager.js:3561`（`:3557-3563`），供静态通道展开 callerAgentId。

**(d) 运行中热更（reload）支持**
- `$D/server/server/daemon-config-store.js:79` 与 `:101` 把 `daemon.mcp.injectIntoAgents` 列入 RELOADABLE_PATHS / persisted→mutable 映射。
- reload 实现：`$D/server/server/daemon-config-store.js:263-299`，变更经 `applyReplacement`（`:301-362`）触发字段回调。
- bootstrap 中的字段回调：`$D/server/server/bootstrap.js:1200-1207`
  ```js
  const inject = daemonConfigStore.get().mcp.injectIntoAgents !== false;
  ...
  agentManager.setMcpBaseUrl(mcpEnabled && inject ? mcpBaseUrl : null);
  agentManager.setPaseoToolsEnabled(mcpEnabled && inject);
  ```
  （`:1193-1197` 为 server 首次 listen 后的初始设置。）
- CLI 可强制覆盖：`$D/server/server/daemon-worker.js:83-87`（`--no-inject-mcp` → false 并 override）。

### 2.3 Hermes 侧："not a deferrable tool" 的产生处

前缀记 `$H`：
`/nix/store/c0rvf3mrl7av5n8djas0jcdysiy49ycq-hermes-agent-0.20.1/lib/python3.12/site-packages`

- 判定函数 `$H/tools/tool_search.py:204-227 is_deferrable_tool_name`：
  - `:218-223` registry 中查不到 entry → False；toolset 以 `mcp-` 开头 → True。
  - 即：**paseo 工具未在 registry 注册时，对它的 tool_call/tool_describe 一律按 "not deferrable" 拒绝。**
- 报错文案：
  - `$H/tools/tool_search.py:927-931`（tool_describe 路径）
  - `$H/tools/tool_search.py:1044-1048`（tool_call 路径 `resolve_underlying_call`）
- **工具被注销的直接代码（间歇性根因）**：`$H/tools/mcp_tool.py`
  - `:2383` 与 `:2401` `registry.deregister(tool_name)`（发生在工具列表刷新/park 后）
  - `:428-432` 注释明确："While parked (reconnect budget exhausted, tools deregistered) … no tool call can ever reach …"
  - parked 后按 `_PARKED_RETRY_INTERVAL=300`（`:432`）自愈探测。
- 环境变量插值：`$H/tools/mcp_tool.py:4985-5014 _interpolate_env_vars`，`:5008`
  `return _get_secret(name, m.group(0)) or m.group(0)`
  —— `PASEO_AGENT_ID` 缺失/取不到 secret 时，`${PASEO_AGENT_ID}` **原样保留**。

### 2.4 实测现象与日志

- 受影响会话实证：`~/.hermes/sessions/request_dump_cfafe11f-329f-4db6-8b1b-add74daa3ac1_*.json`
  （09:23、11:47 两份）。该会话为 Paseo 协调者长会话，内含
  `mcp__paseo__create_agent`（35 次）、`list_agents`、`kill_agent` 调用。
  逐轮配对 tool_call 结果：**同一工具多次成功 → 多次 `not a deferrable tool` → 之后又成功**。
- keepalive/park 日志（`~/.hermes/logs/errors.log`）：
  - 大量 `MCP server 'paseo' keepalive failed … TimeoutError`（如 `:10318/10353`）。
  - `:10368` `failed initial connection after 3 attempts, parking … 408 Request Timeout … callerAgentId=${PASEO_AGENT_ID}`。
  - `:10388/10586/10707/10876` `revived — session healthy again after parking`。
  - 按小时计数（00–08 点）：3,12,13,9,14,12,14,11,7；**09 点后无 paseo timeout/park 新记录**（最后一次 revive 08:59:27）。
- endpoint 本身正常（取证时刻）：
  - `ss`：`0.0.0.0:6767` LISTEN（Paseo Daemon pid=80174）。
  - `curl …/api/health` → `{"status":"ok"}`。
  - `tools/list` 对「未知 id / 字面 `${PASEO_AGENT_ID}` / 无 callerAgentId」三种 URL **均返回完整工具目录**——即 tools/list 不校验 callerAgentId（校验只在实际调用 create_agent 等需父级身份的工具时发生）。
- Paseo 进程：Supervisor pid=340（09:21 起）；其下 Daemon 子进程当日经历多代
  10:25(pid42455)、11:14(57260)、11:41(76604)、11:44(80174)，均见 daemon.log `Server listening`。
- 资源占用：service 内存 5.6G（peak 10.8G）、355 tasks。本机 loopback keepalive 却反复超时，疑似 daemon 事件循环/负载问题（见 §5）。

---

## 3. 因果链与影响范围

### 3.1 两条注入通道（必须区分）

1. **动态通道（Paseo daemon 控制）**：daemon spawn agent 时由 `withRuntimePaseoMcpServer` 注入，受 `daemon.mcp.injectIntoAgents` 控制（runtime-mcp-config.js:23-41；agent-manager.js:3522）。当前运行态该值缺失→false→**此通道关闭**。
2. **静态通道（Hermes config 控制）**：commit `cf1b4e8`（/etc/nixos 仓库，"register agent MCP endpoint in hermes mcp_servers"）在 Hermes 配置中静态注册：
   `~/.hermes/config.yaml:95-96`
   ```yaml
   paseo:
     url: http://127.0.0.1:6767/mcp/agents?callerAgentId=${PASEO_AGENT_ID}
   ```
   该通道在当前实际配置中**存在**（gen97 store `/nix/store/33bnsz7…-hermes-config.yaml:95-96` 同样有）。因此即便动态通道关闭，Paseo spawn 的 Hermes agent 仍能经静态通道获得 paseo 工具（只要进程 env 内有 `PASEO_AGENT_ID`，由 agent-manager.js:3561 注入）。

### 3.2 因果判定

- **"运行态缺 injectIntoAgents → 新会话不注入" 对动态通道成立，但不能单独解释本次报错**：静态通道仍然给会话提供了 paseo 工具，且实测同一会话先前成功调用过。
- **实测直接触发机制 = 连接 parked**：keepalive 超时 → 重连预算耗尽 → `registry.deregister`（mcp_tool.py:2383/2401）→ 该会话此刻对 paseo 的 tool_call 被判 `not deferrable`（tool_search.py:220→False）；300s 自愈或外部 revive → 重新注册 → 再次成功。这解释了间歇性与"同一会话内反复横跳"。
- 无 `PASEO_AGENT_ID` 的 Hermes 进程（非 Paseo spawn、纯手工启动的 hermes）走静态通道时占位符不展开，URL 保留 `${PASEO_AGENT_ID}`；实测 tools/list 仍可成功，但调用需父级身份的工具会在服务端报错（paseo-tools.js:366-368 `Parent agent … not found`），表现可能不同。

### 3.3 影响范围（如何区分）

- **不是"全部会话"也不是简单"仅新会话"**，按下表区分：

| 现象 | 判定 |
|---|---|
| 会话自始至终从未见过 paseo 工具 | 该会话静态/动态两通道都未注入（如非 Paseo-spawn 且无静态注册的受限 toolset 会话） |
| 同一会话间歇报 not deferrable、片刻后恢复 | parked/deregister → revive（本次 cfafe11f 即此型），与会话新旧无关 |
| 仅在 09-26 渲染丢失后新建、且无静态通道的 agent | 动态通道缺失导致不注入；但本机 Hermes 因有静态通道通常不暴露此问题 |
| 工具可见但调用报 `Parent agent … not found` | callerAgentId 无效/占位符未展开（非 "not deferrable"） |

现场快速区分：在报错时刻查 `~/.hermes/logs/errors.log` 该时段是否有 paseo `keepalive failed/parking`；有 = parked 型；无且工具从不出现 = 注入缺失型。

---

## 4. 最小修复步骤、是否需 reload/重启、由谁执行

核查员不执行任何写操作/重启。以下为**待管理者（xavier）批准后**由 ops/协调者执行的方案。

### 4.1 治本：让声明式真值进入部署（解决动态通道 + 防止再被覆盖）

1. 提交 `modules/paseo.nix:43`（`mcp.injectIntoAgents = true`）及同批 settings（该改动目前仅在工作区未提交）。
2. 走标准 NixOS 部署（`nixos-rebuild switch`，按仓库分支策略 develop→master）。部署后 ExecStartPre 将渲染含 true 的新 store config，重启服务也不再丢失。
3. 影响面：`services.paseo` 渲染的 config.json、daemon spawn 注入行为；不改变 Hermes 静态通道。属配置变更（CRITICAL 纪律），需人工确认 + 回滚 generation。

### 4.2 治标/即时恢复（无需重启 daemon）

- `daemon.mcp.injectIntoAgents` 在 RELOADABLE_PATHS 中（daemon-config-store.js:79），**支持热 reload，无需重启 daemon**：经 Paseo CLI/配置接口 patch 为 true 并触发 reload 即可，bootstrap 字段回调（bootstrap.js:1205-1207）会即时更新 AgentManager。
- 注意：直接手改 `~/.paseo/config.json` 不可靠——下次服务启动 ExecStartPre 会无条件覆盖（paseo-pre-start:4）。故手改只能临时，治本必须走 §4.1。
- parked 型故障：通常每 300s 自愈；如急需，可对该 MCP server 触发一次 reconnect（由 ops 执行）。已运行会话在 revive 后自动恢复工具，无需新建会话。

### 4.3 新会话验证方法

- 会话内：`mcp__paseo__list_agents` 可直接调用成功（或工具列表中可见 paseo 工具）。
- 连接态：errors.log 无该时段 paseo `parking/keepalive failed`。
- endpoint：`curl http://127.0.0.1:6767/api/health` 返回 ok；带真实 `callerAgentId` 的 tools/list 返回工具目录。
- 静态通道：`~/.hermes/config.yaml` mcp_servers 下存在 paseo 且运行进程 env 有 `PASEO_AGENT_ID`（占位符已展开）。

### 4.4 由谁执行

- 本核查员：仅产出本文档，**不 cp、不 reload、不重启、不部署**。
- §4.1/§4.2 的执行：待 xavier 批准后，由对应 ops/项目协调者按 nixos-hermes-safe-ops 流程实施；当前状态 = **待审批**。

---

## 5. 其他可能根因（已逐项排查）

- [endpoint/6767] **已排查，正常**：0.0.0.0:6767 LISTEN、health ok、tools/list 正常（§2.4）。
- [callerAgentId] **已排查**：tools/list 不校验；仅在调用 create_agent 等工具时校验父级，未注册 id 会报 `Parent agent … not found`（`$D/server/server/agent/tools/paseo-tools.js:362-370`），与本次 "not deferrable" 文案不同。
- [鉴权] **已排查**：`/mcp/agents` 属自认证路由（`$D/server/server/auth.js:88`，`:106-121`）；当前无 daemon password 时端点开放（日志 `authRequired:false`），非鉴权问题。
- [静态注册通道] **已排查且存在**：`~/.hermes/config.yaml:95-96` 与 gen97 store 均有 paseo。
- [daemon 负载/keepalive 超时] **高度可疑但根因 [UNCERTAIN]**：loopback keepalive 当日 00–08 点反复 TimeoutError/408，service 内存 peak 10.8G、355 tasks，daemon 子进程当日多代更替。为何 loopback 自连超时（事件循环阻塞 / 资源压力 / 某代 daemon bug）需进一步专项排查；这是间歇性报错的待查根因，不能用 injectIntoAgents 单一假设盖过。
- [声明式未部署] **已确认是配置层面根因**：modules/paseo.nix:43 未提交未部署，active unit 仍渲染无 mcp 的 yhswh（§2.1）。

---

## 附：关键路径速查

- 运行态：`/var/lib/hermes/.paseo/config.json:21-30`
- 声明式：`modules/paseo.nix:43`
- store（含 true，未被引用）：`/nix/store/2wyp0wyhl0ra1qd5xlagm89fh66h575q-paseo-config.json`
- store（active 渲染源，无 mcp）：`/nix/store/yhswhdgxiqwp5h6ri9v5sw9ir8kskafl-paseo-config.json`
- server：`config.js:338`；`bootstrap.js:288,1051-1052,1193-1207`；`runtime-mcp-config.js:23-41`；`agent-manager.js:3517-3530,3561`；`daemon-config-store.js:79,101,263-299`；`daemon-worker.js:83-87`
- hermes：`tool_search.py:204-227,927-931,1044-1048`；`mcp_tool.py:428-432,2383,2401,4985-5014`
