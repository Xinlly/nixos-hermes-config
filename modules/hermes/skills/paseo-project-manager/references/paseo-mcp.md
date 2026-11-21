# Paseo MCP 参考

适用于当前 NixOS 配置钉住的 Paseo 版本 `da8c1b5c94e7`。实际调用以当前会话暴露的工具 schema 和服务返回为准。

## 查询工具

| 工具 | 参数与使用方法 |
| --- | --- |
| `list_workspaces` | 参数为 `{}`。返回活动工作区及其 `workspaceId`、`projectId` 和 `cwd`。 |
| `list_agents` | 跨项目查询显式传 `cwd`。默认按调用者目录筛选，匹配该目录及子目录。`limit` 默认 50、最大 200。`statuses` 可选。`includeArchived` 默认为 `false`。`sinceHours` 默认 48、最大 720，当前实现只用它过滤归档记录。 |
| `get_agent_status` | 传 `{"agentId": "完整 UUID"}`。可以跨目录直查。核对返回的状态、`snapshot.workspaceId`、`snapshot.cwd`、`snapshot.labels`、`snapshot.activeTurn` 和待审批项。 |
| `list_providers` / `list_models` | 前者参数为 `{}`，用于核对 provider 和可用模式。后者传 `{"provider": "实际 provider ID"}`，用于核对 model ID。创建时的 `provider` 字段使用对应的 `provider/model` 组合。 |

`projectId` 通常形如 `prj_…`，`workspaceId` 形如 `wks_…`，会话 `agentId` 使用完整 UUID。调用 MCP 时用实际返回值。会话标题和 `shortId` 只用于展示或辅助定位。历史注册可能用 `paseo.role`、`paseo.project`，也可能用 `role`、`project`。

## 必要时只读核对注册表

- `/var/lib/hermes/.paseo/projects/projects.json` 保存项目的 `projectId`、`rootPath`、`displayName`、`customName` 和 `archivedAt`。查不到活动工作区时，可用它确认该根目录是否已登记或归档。
- `/var/lib/hermes/.paseo/projects/workspaces.json` 保存工作区的 `workspaceId`、`projectId`、`cwd` 和 `archivedAt`。用它区分工作区已归档和查询当前未返回。
- 文件里是登记状态，协调者活跃状态和审批以 `get_agent_status` 为准。遇到文件不可访问时，报告读取错误。通过 MCP 执行创建和派单。

## 创建和转发参数

- `create_workspace` 用 `isolation: local`、`path` 和 `title` 准备协调者的工作区。已有项目还要传 `projectId`。初次登记由该工具按根目录查找或创建项目。此版本没有独立的 `create_project` MCP 工具。
- `create_agent` 一次传入 `title`、`provider`、`workspaceId`、`labels` 和 `initialPrompt`。可显式传 `background: true`、`notifyOnFinish: true`。会话模式按 provider 的实际能力选填 `settings.modeId`。根据返回的 `agentId` 核对创建结果。
- `send_agent_prompt` 传 `agentId`、`prompt`、`background: true` 和 `notifyOnFinish: true`。

## 调用者身份和通知

- 使用配置好的、带 `callerAgentId` 的 Paseo MCP 连接。该 ID 识别当前调用会话。`workspaceId` 决定子代理在哪个工作区运行，`paseo.parent-agent-id` 记录创建者。指定另一工作区时，创建的子代理仍归属于调用者。给已有 Agent 派单不会改变其父子关系。
- 创建或后台派单的完成通知直接发给该次调用者，订阅在该轮终态结束。项目内部的子代理结果由协调者明确回报 Project Manager。工具缺失或连接失败时，说明哪一步无法执行，并保留已确认的登记。
