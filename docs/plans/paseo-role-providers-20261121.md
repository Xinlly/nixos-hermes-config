# Paseo 角色与提供者规划

2026-11-21。用于讨论角色拆分，部署基线为 WSL `nixos` 的现有 Paseo 和 Hermes。第一阶段优先把项目管理者收敛为任务归属入口。凭据和工作目录暂时继续共用，Paseo 版本暂缓更新。

## 当前运行情况

- Paseo 有 7 个活动工作区，对应 7 个项目。6 个业务项目是 `nixos`、`EPL-AddIns`、`EPL-Scripts`、`tree-hole-sites`、`PVE` 和考勤。第 7 个项目 `hermes` 是管理入口所在的工作区。
- MCP 返回 9 条未归档会话记录。6 条是业务项目的协调者会话，2 条是旧 `Project Manager` 和试点 `Project Manager.new`，还有 1 条历史遗留的已结束研究会话。
- NixOS 已声明 `hermes` 和 `hermes-manager` 两个 provider。旧管理者与各项目协调者仍使用 `hermes`。试点管理者使用 `hermes-manager`，由 Paseo 以 `hermes --profile manager acp` 启动。Paseo 的已保存 agent profile 列表为空。
- `manager` 已有独立 Hermes Home，但现有 `SOUL.md` 与默认 profile 内容一致。它从共享 Nix 设置继承 MCP、技能和其他能力。两个管理会话的活动记录都显示过技术调研。
- `EPL-Scripts` 的协调者目前靠会话名称和工作区识别，缺少统一的 `role`、`project` 标签。项目归属优先用 Paseo 的 `projectId`、`workspaceId`，再用标签和名称辅助。父路径 `/var/lib/hermes` 涵盖子项目，不能靠路径前缀判断归属。

## 角色分工

| 角色 | 职责 | 生命周期和交付 |
| --- | --- | --- |
| 项目管理者 | 接收任务入口，判断属于哪个已有项目、是否有歧义或是否需要新设项目。 | 跨项目常驻。转发给对应协调者，或拟定新项目名称并询问用户。 |
| 协调者 | 管理单个项目的工作区和工作线，安排计划、实现与审核，处理结果汇总、验收和集成。 | 每个业务项目一位，常驻 primary 工作区。 |
| 计划者 | 澄清技术需求，做方案、任务拆解和可验证的技术验收标准。 | 随工作线运行，交付方案和工作任务。 |
| 工作者 | 按工作任务在指定工作区实现，并提交自测证据。 | 随实现任务运行，把变更和测试结果交给审核或协调流程。 |
| 审核者 | 独立检查实际方案、差异与测试证据，给出审核结论。 | 按审核任务启动，通常是只读会话。 |

旧角色规范还定义了按需启动的 `researcher`，可作为临时调研角色。先讨论五个核心 provider。这里将“协调计划者、工作者、审核者”理解为项目协调者的责任。现有长工作线通常由计划者实际派生 worker 和 reviewer，短任务可以由协调者直接派工。是否统一实际派工层级，留待确认。

## 第一阶段 项目管理者试点

1. 以 `project-manager` provider 和 `paseo-project-manager` Hermes profile 作为试点入口，单独编写项目管理者角色说明。处理结果限定为已有项目、需要澄清、建议新设项目三类。唯一匹配时转发用户原指令。没有匹配时先拟定名称，再询问用户是否新建。
2. 为该入口只保留 Paseo MCP。第一版只考虑 `list_workspaces`、`list_agents`、`get_agent_status`。验收时从真实 Paseo ACP 会话观察模型获得的工具列表，确认 MCP URL 展开了 `PASEO_AGENT_ID`，且 Paseo 只通过 Hermes 配置提供这四个工具。查询其他工作区的协调者时显式传 `cwd`。
3. 当前 Paseo MCP 的 `list_workspaces` 可覆盖现有项目，但没有独立的完整项目查询工具。若以后存在无活动工作区的项目，应从项目注册表补齐查询。无 `projectId` 的 `create_workspace` 可能连同工作区一起登记项目，识别阶段只使用查询接口。
4. 用四类输入验证路由。明确指向现有项目、多个项目都可能匹配、确实需要新项目、任务误落入 `hermes` 父目录。检查协调者命中是否唯一，并确认实际会话仅有预期的 MCP 工具。

## 后续待定

- 在真实会话中验证唯一匹配的任务能转发给对应协调者，以及没有匹配时会给出拟定名称并询问。
- 五种角色是否都需要独立 Paseo provider。可以先用 provider 区分默认能力与权限，在确实需要独立记忆、会话或身份文件时再配对应 Hermes profile。
- 旧 `Project Manager` 会话与试点会话的迁移时点，以及各项目协调者的角色标签如何补齐。

## 参考

- 管理者交接见 WSL `/var/lib/hermes/workspace/work/paseo-dr-20261112/HANDOFF.md` 和同目录的 `templates/PROJECT_CONVERGENCE_SOP.md`。项目级动态交接的约定位置为项目根目录 `./HANDOFF.md`。
- 既有角色规范见 WSL `/var/lib/hermes/.hermes/skills/devops/` 下的 `paseo-role-system`、`paseo-orchestrator`、`paseo-orchestration-discipline`。
- 部署入口和 profile 生成逻辑见 [Paseo Nix 模块](../../modules/paseo.nix) 与 [新项目管理者模块](../../modules/hermes/profile-paseo-project-manager.nix) 与 [旧 manager 模块](../../modules/hermes/profile-manager.nix)。项目内历史设计见 [Manager Profile 与 Xavier Mesh](manager-profile-xavier-mesh-20261030.md)。
