# Paseo 原生能力核实报告（callerAgentId / 工具权限边界）

> 日期：2026-11-21 · 钉住 commit：`getpaseo/paseo@da8c1b5`（flake.nix 同款）
> 源码位置：`References/paseo/`（浅克隆 + 检出钉住 commit）

## 结论摘要

CodeX 最后卡住的问题是：**「原生配置能否限制 Project Manager 只操作直属协调者？」**

**答案：不能。** Paseo 原生提供的是「按 callerAgentId 注入受限工具目录」的能力，但
**它只做身份绑定 + 创建/路由层面的约束，不强制 archive/kill/send_prompt 等破坏性工具
的直属关系校验**。要真正实现「只能操作直属协调者」，必须在 Hermes 侧补一层校验，
或用 SOUL.md/Skill 的流程约束 + 工具白名单兜底。

## 关键事实（源码证据）

### 1. 身份注入：每个 spawn 的 agent 进程拿到自己的 PASEO_AGENT_ID
`packages/server/src/server/agent/agent-manager.ts:buildLaunchContext()`（约 5017-5034 行）：
```ts
const context: AgentLaunchContext = {
  agentId,
  env: { ...env, PASEO_AGENT_ID: agentId, PASEO_AGENT_CWD: cwd },
};
```
→ 每个 ACP 子进程的 `PASEO_AGENT_ID` 就是它自己的 agentId（**不是**父的）。

### 2. 原生受限工具目录：paseoToolCatalogFactory + callerAgentId
同文件 5026-5033 行：
```ts
if (this.paseoToolsEnabled && isPaseoToolPolicyEnabled(paseoToolPolicy)
    && client.capabilities.supportsNativePaseoTools && this.paseoToolCatalogFactory) {
  context.paseoTools = await this.paseoToolCatalogFactory({ callerAgentId: agentId, paseoToolPolicy });
}
```
→ 这是 Paseo 原生的「按会话 callerAgentId 注入工具」机制，**但仅在
`supportsNativePaseoTools=true` 的 provider 上生效**（ACP 通用 provider 大概率是 false，
见 `plugin-provider.ts:1497 supportsNativePaseoTools: false`）。

### 3. 工具策略只支持「开关 + 禁用名单」，不支持「直属关系」
`packages/protocol/src/provider-config.ts:31`：
```ts
ProviderPaseoToolsPolicySchema = z.object({
  enabled: z.boolean().optional(),
  disabledTools: z.array(z.string()).optional(),
});
```
→ 只有 `disabledTools`（禁用名单），**没有** `allowedTargets`/`directChildrenOnly` 之类的
直属关系字段。

### 4. callerAgentId 的实际作用：创建/路由约束，非破坏性操作校验
`paseo-tools.ts` 里，callerAgentId 决定：
- `create_agent`：走 `agent-scoped` 分支 → `resolveChildAgentCwd`（cwd 从 caller 派生）、
  `agentToAgentCreateAgentArgsSchema`（输入受限）、默认创建「你的 subagent」。
- `send_agent_prompt`：agent-scoped 默认 `background=true` + `notifyOnFinish=true`，
  且 `setupFinishNotification` 把 callerAgentId 设为完成通知的父。
- `create_agent` 打 label `paseo.parent-agent-id = callerAgentId`（`create-agent/intent.ts`）。

**但 `archive_agent` / `kill_agent` / `send_agent_prompt` / `update_agent` 的 handler 和
底层 command（`lifecycle-command.ts:archiveAgentCommand`）都不校验目标 agent 的
`paseo.parent-agent-id` 是否等于 callerAgentId**——它们直接拿任意 agentId 执行。

### 5. parent 关系只用于「归档级联」和「子代理清单」，不用于「授权拒绝」
`agent-manager.ts:1717 cascadeArchiveChildren(parentAgentId)` 用 label 找到并级联归档子代理；
`listProviderSubagents` 用 parentAgentId 列子代理。这些是「父子关系维护」，不是
「越权拒绝」。真正的「拒绝非直属操作」在 Paseo 源码里**不存在**。

## 对 CodeX 原方案的影响

| CodeX 设想 | 核实结果 | 建议 |
|---|---|---|
| 「写 ACP 包装器注入会话级 MCP」 | 多了一层。Paseo 已原生给每个 ACP 进程注入 `PASEO_AGENT_ID`，且已有 `paseoToolCatalogFactory` 按 callerAgentId 生成工具 | 优先用原生 `PASEO_AGENT_ID` 环境变量，不写包装器 |
| 「原生配置限制只操作直属协调者」 | **不成立**。原生的 `disabledTools` 只能禁用工具，不能做目标级直属校验 | 必须在 Hermes 侧（受限文件工具 + Skill 流程）补直属校验 |
| 「用 PASEO_AGENT_ID 展开 MCP URL」 | 可行但受 `supportsNativePaseoTools` 限制 | 见下 |
| 「移除全局 ${PASEO_AGENT_ID} MCP URL」 | 需确认 Hermes 的 `mcp_servers` 是否能读到 Paseo 注入的进程 env | 待验证 |

## 二、Hermes 侧两个技术前置问题（已核实）

> 源码：`References/hermes-agent/`（v0.23.3 canary，与 flake.nix 钉住版本一致）

### 问题 A：Hermes ACP 进程能否读到 Paseo 注入的 `PASEO_AGENT_ID`？

**答案：能，且不会被覆盖或误删。**

链路与证据：
1. Paseo 在 spawn 每个 agent 时，把 `PASEO_AGENT_ID` / `PASEO_AGENT_CWD` 写入子进程环境
   （`agent-manager.ts:buildLaunchContext`）。Hermes ACP 进程是 Paseo 的子进程，启动时这两个变量已在 `os.environ` 里。
2. ACP 入口 `acp_adapter/entry.py:_load_env()` 调 `load_hermes_dotenv()`。该函数加载 `.env`
   时只写**文件里存在的 key**（dotenv 语义），不会清空或覆盖文件里没有的 `PASEO_AGENT_ID`。
3. `_clear_known_keys_missing_from_dotenv`（`env_loader.py:113`）只清除
   `_PROFILE_MANAGED_ENV_KEYS = {HERMES_ACP_AUTH_METHOD, HERMES_ACP_AUTO_APPROVE} ∪ profile_env_names()`
   这个**固定窄名单**——`profile_env_names()` 来自 `LEFT_CORE` 静态表（Hermes 自身的功能迁移
   环境变量），**不含 `PASEO_AGENT_ID`**。故不会被误删。

→ 结论：ACP 进程里 `os.environ["PASEO_AGENT_ID"]` 可用，值是「该 agent 自己的 id」。

### 问题 B：`mcp_servers.paseo.url` 里的 `${PASEO_AGENT_ID}` 展开发生在哪层？

**答案：在「加载 config 的那个进程」里，即 ACP 进程自己，展开时读该进程的 `os.environ`。**

链路与证据：
1. `hermes_cli/config.py:1874 load_config()` 对整份 config 递归调用 `_expand_env_vars`
   （第 2048/2081/2179 行），**包括 `mcp_servers.*.url` 字符串值**。
2. 展开用 `_ENV_REF_RE = r"\${([^}]+)}"`（config.py:1385）匹配，`_env_ref_lookup(name)` 取值：
   - 无 secret scope 时 → `os.environ.get(name)`（默认 profile 的 legacy 行为）。
   - multiplex secret scope 内 → `agent.secret_scope.get_secret(name)`（读该 profile 的 `.env`）。
3. 所以：**ACP 进程自己加载 config 时，`${PASEO_AGENT_ID}` 从进程 `os.environ` 解析到正确值**。
   前提是 ACP 进程确实自己加载 config（而非由 gateway 进程代加载后注入）。

⚠️ **仍需现场验证的一处**：`profile-paseo-project-manager.nix:17` 直接复制了
`agent.nix:248` 的 `url = "...callerAgentId=\${PASEO_AGENT_ID}"`，但该 profile 的
`settings.mcp_servers.paseo` 是「局部覆盖」，需确认 ACP 模式下 profile 的 config 展开
发生在 **profile 进程内**（此时 `PASEO_AGENT_ID` 来自 Paseo 注入，可用），而非被
multiplex gateway 代理展开（此时可能读不到、或读到错值）。

## 三、最终结论（对 CodeX 原方案）

1. **不写 ACP 包装器**：Paseo 已原生注入 `PASEO_AGENT_ID`，Hermes 的 `${VAR}` 展开已原生支持
   读进程环境变量。CodeX「写 ACP 包装器」是多余的一层。
2. **`multiplex_profiles` 无需声明**：v0.23.3 默认开启且 `false` 已退役，会被强制改写为 true。
3. **飞书凭证只需保留在 default**：`gateway.profile_routes` 真实存在，将来需要飞书消息进 manager
   时再在 default 加路由。
4. **直属关系校验必须在 Hermes 侧补**（Paseo 原生不做）：
   - SOUL.md / Skill 里写死「只允许操作 `paseo.parent-agent-id == 自己` 的对象」；
   - 文件写入靠 `HERMES_WRITE_SAFE_ROOT`（注意它读 `os.getenv`，进程级，需在 spawn 环境里注入，
     不能只写进 profile 的 `.env`）；
   - 破坏性工具（archive/kill/send_prompt）的目标校验，要么靠流程约束，要么写受限工具包装器。

## 四、下一步（待用户确认后实施）

1. 现场验证 `profile-paseo-project-manager` 的 ACP config 展开发生在 profile 进程内
   （确认 `PASEO_AGENT_ID` 能正确注入 MCP URL）。
2. 按 CodeX 两阶段方案实施：先恢复多 Profile Gateway（default 持飞书、两个 manager 只接 Paseo），
   再给新 PM 补「直属关系」校验兜底（SOUL.md/Skill 约束 + 可选受限工具包装器）。
3. 验收：testpro 一正一反（直属协调者能管、下级/其他 workspace/托管 worktree 拒绝）。
