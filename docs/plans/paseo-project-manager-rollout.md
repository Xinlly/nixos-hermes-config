# Project Manager 配置与验收

先完成并验收 `project-manager` Provider，再调整下一个角色。验收入口是用户日常使用的 Project Manager 会话 `30a3de67-cc8b-41fc-98f2-14d232b6c188`。使用现有 `testpro`（`prj_415e1d5752d3aacf`）及其主工作区 `wks_9547e642c6039c25`。测试保留主目录、仓库提交、现有 worktree 和历史会话。

## 日常接单

| 步骤 | Project Manager 的动作 | 工具及来源 | 通过标准 |
| --- | --- | --- | --- |
| 1. 查项目 | 识别用户说的项目，核对活动工作区的 `projectId`、`workspaceId` 和 `cwd`。需要辨别归档项目时，才只读核对 Paseo 注册表。 | 原生 Paseo `list_workspaces`；Hermes `read_file` | 用户只说 `testpro`，入口会话实际调用 Paseo 并给出正确项目和主工作区。登记册缺失也能完成查询。 |
| 2. 找协调者 | 在主工作区查找协调者，核对完整 ID、所属工作区、直属关系和当前轮次。需要本地别名时读 `AGENT.md`。 | 原生 Paseo `list_agents`、`get_agent_status`；Hermes `read_file` | 唯一直属且空闲才可派单。有多个候选时给出歧义，忙碌时保留任务，陌生或隔代 Agent 不接收派单。 |
| 3. 转发 | 把用户的目标、授权范围、禁止项和交付条件原样带给协调者。 | 原生 Paseo `send_agent_prompt` | 协调者的活动记录里有来自原 Project Manager 的消息，包含原要求。提交回执只记为已派发。 |
| 4. 收回报 | 收到协调者的明确结论后，核对任务标识、实际结果及证据，按需要更新登记册并向用户答复。 | 原生 Paseo `get_agent_status`、`get_agent_activity`；Hermes `read_file`、`patch` | 原会话收到真实协调者结果，汇总具体交付、失败或阻塞。等待子任务的回复不被记为完成；重复通知不重复派工。 |

## 项目缺失或缺协调者

| 步骤 | Project Manager 的动作 | 工具及来源 | 通过标准 |
| --- | --- | --- | --- |
| 5. 确认对象 | 无匹配项目时，提议名称和 Workspace 内路径，等待用户真正授权新建。已有项目使用它现有的主工作区。 | 原生 Paseo `list_workspaces`；Hermes `read_file` | 未获授权时零写入；明确属于 `testpro` 的验收任务直接使用现有路径。 |
| 6. 准备工作区 | 新项目经授权后用 Hermes 写首份 `HANDOFF.md`，再调用 `create_workspace`。已有项目补建工作区时显式传 `projectId`；已有主工作区直接复用。 | Hermes `write_file`；原生 Paseo `create_workspace` | 工作区实际 `cwd` 和项目归属一致，已有项目没有重复登记。 |
| 7. 启动协调者 | 查可用 Provider 和模式，指定 `provider/model`、`settings.modeId`、主 `workspaceId` 及初始任务。核对首次真实答复。 | 原生 Paseo `inspect_provider`、`list_models`、`create_agent`、`get_agent_status` | 协调者在正确主工作区运行，确为入口会话的直属子 Agent，能回答并接收任务。项目已有协调者时先做交接。 |

`testpro` 当前的 `orchestrator·testpro`（`cfd06ff6`）使用旧 `hermes` Provider，未登记为新入口的直属子 Agent。实测前核对其在途任务和子 Agent。迁移使用同一个项目和主工作区，保留旧会话历史，确保不会有两名活跃协调者或误归档已有 worktree。

## 独立的项目退场流程

- [ ] 用户明确要求退场时，先通知直属协调者收尾。协调者核验自己的分支和项目内工作区，并回报「已收尾，可以归档」。Project Manager 核对回报和 Paseo 对象，不重新查 Git 提交推送。
- [ ] 使用原生 `archive_agent` 和 `archive_workspace` 归档直属协调者及普通主工作区。整项目登记的归档与物理目录清理只在退场时处理。保留已有清理记录与恢复依据。
- [ ] 未获具体删除授权时，可验收状态为「已归档 / 待确认清理」，主目录保留。日常查询、派单、交付验收不需要用户确认物理路径。

## 本轮执行顺序

- [ ] 使 Project Manager 的日常入口只依赖表中的原生工具；从原会话验证项目查询及实际工具名。
- [ ] 在现有 `testpro` 核对并完成必要的协调者交接，然后由原 Project Manager 发一条安全的只读任务。核对收件会话、任务原意、一次完成回传及入口的最终答复。
- [ ] 用同一入口查询不存在的项目，确认只有提议而无写入；用一个已验证的非直属目标做无副作用的拒绝测试。完成以上各项后再调整协调者和 Planner 的配置。
