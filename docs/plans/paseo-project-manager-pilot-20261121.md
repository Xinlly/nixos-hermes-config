# Hermes Profile 与 Paseo 编排试点

2026-11-21。当前持久化基线为 `master` 的 `e69f36b`。WSL 运行 Hermes `v0.23.3`、Paseo `da8c1b5`。这里把 Door 理解为用户提交任务的 Project Manager 入口。

## 职责

- Hermes Profile 提供角色身份、SOUL、技能、模型、会话和记忆配置。Project Manager 用 `paseo-project-manager`，原 `manager` 保留原会话。Paseo Provider 负责启动对应 Profile。
- Paseo 管业务项目、协调者、其他 Agent、工作区、Git worktree 和会话恢复。Project Manager 判断任务归属，转交给直属协调者。协调者按任务规模调用计划者、工作者、审核者，负责项目内收尾。
- Hermes Kanban 支持持久任务、依赖、重试和按 Profile 启动工作者。它可以独立承担以 Hermes 为中心的任务流。本试点让 Paseo 持有开发分派和会话状态，项目登记册只保存项目路由和退场进度。[Hermes Kanban 固定版本文档](https://github.com/NousResearch/hermes-agent/blob/v0.23.3/website/docs/user-guide/features/kanban.md)

手机、网页和 Windows 客户端应接入同一 WSL Paseo daemon，看到同一个 Agent、历史和待确认事项。编排状态由 daemon 与项目记录维护。三端接续是后续验收条件。[Paseo 连接架构](https://github.com/getpaseo/paseo/blob/main/public-docs/security.md)

## 多 Agent 协作方式

| 方案 | 适合借鉴的机制 | 在 Paseo 内的用法 |
| --- | --- | --- |
| LangGraph | 协调者动态拆分，相互独立的任务并行，评估结果决定完成或返工。 | 由协调者决定拆分，按验收条件收齐结果，对指定提交发起评审。 |
| Microsoft Agent Framework Magentic | 经理根据进展改计划，停滞计数触发重规划。 | 新证据推翻方案时找计划者复核，返工达到设定上限则报告阻塞。 |
| CrewAI | 分层管理，经理做分配、监督和结果验证。 | 项目协调者持有项目内执行决策，Project Manager 持有项目路由。 |
| Claude Code Agent Teams | 组长、共享任务列表、独立上下文和横向沟通。 | 各工作者各有会话和交付接口；有接口依赖再交换信息，协调者登记依赖变化。 |
| Hermes Kanban | 持久任务、依赖和 Profile 执行分派。 | 借鉴任务状态和依赖；执行仍由 Paseo 创建、恢复及跟踪。 |

来源：[LangGraph](https://docs.langchain.com/oss/python/langgraph/workflows-agents) · [Magentic](https://learn.microsoft.com/en-us/agent-framework/workflows/orchestrations/magentic) · [CrewAI](https://docs.crewai.com/en/learn/hierarchical-process) · [Claude Code Agent Teams](https://code.claude.com/docs/en/agent-teams) · [Paseo 编排](https://github.com/getpaseo/paseo/blob/main/public-docs/orchestration.md)

- 常驻 Project Manager 和每项目一名协调者。计划者、工作者、审核者按任务启动。范围明确的变更由协调者直接给 Worker 派单；需求不清、涉及多模块或要拆依赖时再启动 Planner。涉及需要独立把关的改动，Reviewer 只读审查 Worker 提交，回报阻塞与证据。
- 项目内由协调者统一派工和集成。Planner 交付计划、依赖与可验证的完成条件。Worker 交付 worktree、提交 SHA 和测试结果。Reviewer 针对同一个 SHA 给出 `通过`、`需修改` 或 `阻塞`。Worker 改了 SHA 后按新差异复审。协调者串行合入，会改同一片代码的工作串行执行。
- 用同一任务 ID 串联用户请求、Paseo Agent、工作区、提交和审核结论。最小记录含任务范围、完成条件、依赖、当前负责人和状态。区分 prompt 已提交、Agent 已结束和交付已验收。协调者负责在失败、重启或改派时从已有状态恢复，项目级进度汇总到入口。
- 试验对比单 Worker 和 Planner 加多 Worker 两种路径，用同一个小型本地任务分别覆盖短任务、并行模块、阻塞返工及独立评审。记录完成时间、返工次数、集成冲突和用户介入次数。跨端验收时在 Windows 发起、在网页查看同一会话，最后在手机续聊，再从 Windows 核对同一条历史和任务状态。

## 接入路线

当前 Paseo 能通过 `session/new` 和 `session/load` 注入会话 MCP。它的 Provider 策略限制工具目录。对象级规则需要在服务端执行。`callerAgentId` 用于关联调用，Paseo 当前的 MCP Bearer 以 daemon 为单位生成。受限工具需要将调用者绑定到工具执行前由可信进程签发的身份，任何模型提供的 ID、路径、标签和确认字段都只是请求参数。[固定版本会话 MCP](https://github.com/getpaseo/paseo/blob/da8c1b5c94e752b01d451645e5fa52aba2c1b2f0/packages/server/src/server/agent/runtime-mcp-config.ts#L29-L57) · [固定版本工具策略](https://github.com/getpaseo/paseo/blob/da8c1b5c94e752b01d451645e5fa52aba2c1b2f0/public-docs/mcp.md)

首选用 Paseo 插件按会话给 `project-manager` 注入专用 MCP。Paseo v0.14.0 添加了这项能力，当前固定版本的 `agent.session_open` 只能改环境变量。先在隔离环境验证插件 API 与 ACP 的能力，再决定是否升级线上 Paseo。若必须维持当前版本，可以用 Project Manager 专用的 ACP 启动适配器传入受限 MCP 描述符，或对固定版本做小范围回移。两种做法都保留服务端校验。[固定版本插件接口](https://github.com/getpaseo/paseo/blob/da8c1b5c94e752b01d451645e5fa52aba2c1b2f0/public-docs/plugins/v0.8/reference.md#L476-L527) · [Paseo v0.14.0](https://github.com/getpaseo/paseo/releases/tag/v0.14.0) · [Hermes ACP](https://github.com/NousResearch/hermes-agent/blob/v0.23.3/website/docs/user-guide/features/acp.md)

隔离验证候选版本为 Paseo `v0.16.2`。该版的 `agent.open.before` 可以按 Provider 和由 daemon 提供的 Agent ID 注入只在会话打开时使用的 MCP 描述符。测试配置应允许 ACP 接收 MCP，同时关闭这个 Provider 的通用 Paseo 工具目录。插件工具和通用工具共用目录开关，因此优先试专用 MCP 注入。`agent.turn.after` 等通知属于实时、尽力投递，编排器收到通知后应以任务记录、Agent 状态和提交证据推进，并在恢复时校对遗漏的结果。[v0.16.2 Hook 文档](https://github.com/getpaseo/paseo/blob/v0.16.2/public-docs/plugins/hooks.md) · [v0.16.2 AgentManager](https://github.com/getpaseo/paseo/blob/v0.16.2/packages/server/src/server/agent/agent-manager.ts)

## 执行端验收

1. 从 Paseo 读取实际对象。转发、查询状态和归档都验证直属关系、角色、项目 ID 和主工作区 ID。管理本项目直属临时 Agent 走对应规则。跨项目、隔代、错误工作区和误归档会触发级联的对象都拒绝。核验和写操作共用执行端保护，避免中途变化造成越界。
2. 项目创建绑定已确认名称和路径，限定工作区内的普通主目录。文件能力仅开放登记册、已登记项目的必要只读材料和新项目的首份交接文件，拒绝路径越界及符号链接绕过。工具拒绝时记录原因。
3. 协调者完成 Git 收尾并回报「已收尾，可以归档」。入口依据该回报和 Paseo 实时记录归档直属协调者及其主工作区。验证归档范围和级联后，再推进项目退场。普通目录删除单独绑定用户确认的确切路径。
4. 用 `testpro` 验证直接和隔代两类 Agent、其他项目、主工作区和托管 worktree，验证会话恢复、Gateway 重启及 Paseo 重启后身份分配。原型先使用测试元数据，接入真实 Paseo 数据后重跑权限用例。

## Agent Autoloop 的协作参考

Agent Autoloop 提供一个协作参考。管理方掌握路由规则，执行者依约返回结果或阻塞，上游根据结构化回执决定交给谁继续。试点借鉴可追溯的委派、暂停和续接方式，所有协作在 Paseo 内实现。

项目新建、归档和目录删除的批准应绑定具体动作与目标。人工答复后由执行端重新核对当前状态。若以后接受外部事件，则用可信配置映射到项目，按事件 ID 去重，并设置每项目并发上限和自动重试上限。Autoloop 的 `askFirst` 属于提示词约定，其通用 CLI 适配器也不会限制被启动程序的权限。现有 Project Manager 的直属关系校验仍由专用执行端负责。[Autoloop 通信协议](https://github.com/KKKKhazix/agent-autoloop/blob/main/docs/protocol.md) · [Autoloop 安全说明](https://github.com/KKKKhazix/agent-autoloop/blob/main/SECURITY.md)

## 试验结果

- 在 `testpro` 创建的新 Project Manager 会话通过 Ark 回复 `PROJECT-MANAGER-ACP-OK`。同一工作区内的临时调研 Agent 调用了 Paseo 原生注入的 `list_workspaces`，返回预期的 `wks_9547e642c6039c25`。
- 通过真实 Hermes Gateway 给试点 Profile 注入临时会话 MCP。执行端以测试元数据判定直属协调者允许、隔代 Worker 拒绝、其他项目协调者拒绝。关闭 ACP 进程后，另一个 ACP 进程以相同会话 ID 和 MCP 描述符恢复，对直属对象的再次调用成功。
- 下一轮验收需要接入 Paseo 的实时上下级关系和真实工作区数据，并验证转发、建项、归档和重启。测试工具只检查目标，没有执行归档、项目写入或目录删除。

### TESTPRO-TEAM-01

固定版本 Paseo 的协调者 `cfd06ff6-082e-4d80-b9d7-383525525b1e` 创建了托管工作区 `wks_7a7adbe760df6d55`，分支 `pilot/team-01`。Worker `f1ec93c5-fc5b-4ead-a015-52fee77d264c` 和 Reviewer `1647aee1-1085-43f4-bba3-ac09e8029c6c` 都有该协调者的直属标签。

协调者的任务书把目标误算为 17 字节。Worker 实测是 16 字节，在提交前报告冲突。协调者接到澄清后向原 Worker 续发指令，收到提交 `b9b649a8e6e933011a02859990141a4ea22f9f4e`。Reviewer 按提交 SHA 独立检查内容和工作树。提交仅新增 `team-01.txt`，试点 worktree 干净，`testpro` 主工作区仍为 `develop@40f514ae`。保留测试会话和 worktree 供回查。

编排中出现了重复完成通知，最终只有一位 Reviewer。通知只用于唤醒协调者，推进状态仍要核对任务、Agent 与被审查的 SHA。后续验收需要覆盖重启后重复通知和重试，验证发起下一阶段的去重逻辑。

### v0.16.2 隔离插件探针

在 `127.0.0.1:16767` 启动单独的 Paseo `v0.16.2` daemon，使用独立 `PASEO_HOME`。只为 `project-manager` 用 `agent.open.before` 注入只读 `pilot.who_am_i`，关闭该 Provider 的内置 Paseo 工具目录。真实 Hermes ACP 通过该工具返回 `81d483a5-aefc-4910-8a83-bdf811bac7dc`，与隔离 daemon 的 Agent ID 一致。重启隔离 daemon 后，对同一 Agent 发消息，再次从同一个 Hermes 会话得到匹配的工具回执。隔离 daemon 在测试后停止。探针仅验证会话身份与工具接入，真实 Paseo 项目权限规则待实现。
