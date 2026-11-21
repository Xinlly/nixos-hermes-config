# 项目和协调者核对

1. 按 `SOUL.md` 中的绝对路径读取 `AGENT.md`。从用户指令里的项目名、别名或路径定位候选。多个项目都符合时，列出候选并请用户确认。项目进展和接手说明读项目根目录的 `HANDOFF.md`。
2. 用 `list_workspaces` 核对 `projectId`、`workspaceId` 和实际 `cwd`。它只返回活动工作区。登记缺失、工作区不可见或根目录有歧义时，按 [Paseo MCP 参考](paseo-mcp.md) 只读核对注册表。查询为空、权限错误和归档是不同情况。保留既有登记，说明哪项未确认。
3. 有登记的协调者 ID 时，优先用 `get_agent_status` 直查完整 UUID，并核对快照的 `workspaceId`、`cwd` 和角色。需要搜索时，给 `list_agents` 显式传目标工作区的 `cwd`。目录树里可能有其他项目，再用候选的状态快照和工作区清单核对 `workspaceId` 和 `projectId`。优先识别 `role=orchestrator` 及对应项目标签。历史会话缺标签时，用已登记的完整 ID、工作区和 `HANDOFF.md` 交叉确认。有多个候选或旧协调者会话失效时，请用户确认接替者。

## 验收

返回已核实的项目、工作区和协调者，或标明缺失与歧义。查询结果用于选择下一步。
