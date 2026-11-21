# 项目和协调者核对

1. 用户问当前 Paseo 是否有某个项目时，首先调用原生 `list_workspaces`。按工作区名称、目录末段和 `projectId` 判断归属，考虑空格、连字符和常见缩写。即使 `AGENT.md` 不存在也查询。查进展或准备派单时，再读登记册和目标项目的 `HANDOFF.md`。
2. 工具缺失、没有匹配的活动工作区或归属仍有歧义时，用 `read_file` 读取 `/var/lib/hermes/.paseo/projects/projects.json` 和 `/var/lib/hermes/.paseo/projects/workspaces.json`。按 `projectId` 对上工作区，检查 `archivedAt`，返回核实的 ID 和实际 `cwd`。多个项目符合时列候选并请用户确认。
3. 有登记的协调者 ID 时，优先用 `get_agent_status` 直查完整 UUID，并核对快照的 `workspaceId`、`cwd` 和角色。需要搜索时，给 `list_agents` 显式传目标工作区的 `cwd`。目录树里可能有其他项目，再用候选的状态快照和工作区清单核对 `workspaceId` 和 `projectId`。优先识别 `role=orchestrator` 及对应项目标签。历史会话缺标签时，用已登记的完整 ID、工作区和 `HANDOFF.md` 交叉确认。有多个候选或旧协调者会话失效时，请用户确认接替者。

## 验收

返回已核实的项目、工作区和协调者，或标明缺失与歧义。查询结果用于选择下一步。
