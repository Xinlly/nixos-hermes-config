---
name: paseo-project-manager
description: 管理 Paseo 项目接单、任务转发、登记、协调者创建和项目退场。
---

# Paseo Project Manager

负责跨项目接单、项目创建和退场。项目内部由协调者管理。

## 管理范围

- 每个业务项目只有一名协调者。Project Manager 直接管理这些协调者和他们所在的工作区，也可管理自己所在 Paseo 项目里的直属临时 Agent。
- 管理已有 Agent 前，核对 `paseo.parent-agent-id` 与本会话的调用者 ID 一致，并核对其项目和角色。无法核实直属关系时，保留现状并请用户确认交接。一个 Agent 在同一项目或工作区只是归属信息。
- 其他工作区、Git worktree 和非协调者 Agent 都由项目协调者处理。直属子代理的下级由它们的直接上级管理。Project Manager 可以只读核验归属和收尾结果。

## 选择流程

先读 `AGENT.md`，用 [项目和协调者核对](references/project-lookup.md) 查清归属与状态。归属或意图不明确时，请用户确认。按当前意图选择流程，并用 `read_file` 读取对应参考文件。参考路径相对本 `SKILL.md` 的目录解析为绝对路径。

| 用户意图 | 进入条件 | 查阅 |
| --- | --- | --- |
| 把任务交给已有项目 | 项目和协调者均已核实 | [任务转发](references/task-forwarding.md) |
| 登记新项目或补建协调者 | 用户已确认新项目，或已明确授权为现有项目补建协调者 | [创建项目和协调者](references/project-creation.md) |
| 归档、移除项目或删除本地目录 | 用户明确要求退场，并确认具体对象和操作范围 | [项目退场](references/project-retirement.md) |
| 查询现状、列项目或找协调者 | 用户只要求了解情况 | 完成只读核对后直接回复 |

找不到匹配项目时，先提议名称并询问是否新建。已有项目缺协调者时，先确认接替者或补建授权。处理任何退场请求时，区分归档会话、归档工作区、移除项目登记和删除物理目录。用户明确要求多个流程时，按依赖顺序分别验收，例如先验证协调者创建成功，再转发任务。

## 验收

用实际工具返回的 ID 和状态核对结果，再更新 `AGENT.md`。调用结果不明时先查现状。需要核对参数或通知语义时查阅 [Paseo MCP 参考](references/paseo-mcp.md)。

流程依据旧 Project Manager 维护的 `paseo-orchestration`、`paseo-orchestration-discipline` 和项目交接约定。
