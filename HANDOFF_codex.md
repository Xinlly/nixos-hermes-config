# Paseo 与 Hermes 编排交接

2026-11-21。用户要求暂停实施，先交接。当前目标是沿用已经运行的 Paseo 编排，把 Hermes 的角色与工具逐个配齐。先完成 Project Manager，再做协调者、Planner、Worker、Reviewer。验收从用户实际使用的入口发起，使用现有 `testpro`。常规编排使用 Paseo 原生 MCP，不通过 CLI 代跑。

## 暂停时的状态

| 项目 | 状态 |
| --- | --- |
| Windows Git 工作目录 | `D:/Users/Admin0/source/repos/nixos`，`develop`。第一阶段配置提交 `f4794d0` 已推送到 `origin/develop`。 |
| WSL 部署目录 | NixOS 主机 `nixos` 的 `/etc/nixos` 已快进至 `f4794d0`。 |
| 正在运行及持久化配置 | 两者仍是 `3b4d5d0`。当时的系统路径为 `/nix/store/nssq72q5m7r5rxh849b2s0vypb6kbg8w-nixos-system-nixos-26.11.20260616.567a49d`。 |
| 新配置构建 | 已启动 `codex-paseo-manager-stage.service`，命令为 `nixos-rebuild build --offline --flake /etc/nixos#nixos --no-link`。最后读到日志时在构建 Paseo 和 Profile。这个任务只构建，未执行 `test`、`switch` 或重启。 |
| 角色阶段 | Project Manager 的清单和配置已提交，新版本尚未在原会话验收。其余四个角色尚未按这次逐角色计划调整。 |

可用 Electerm 的 NixOS WSL 标签页检查 `journalctl -u codex-paseo-manager-stage.service`。真正的部署入口是 `/etc/nixos#nixos`，Windows 工作目录用于 Git 管理。Paseo 保持钉在 `v0.16.2`。

## Project Manager 已做的工作

- [逐步配置与验收清单](docs/plans/paseo-project-manager-rollout.md) 已写明查询、识别直属协调者、转发、回报、缺失项目和退场各自的触发条件、工具与通过标准。
- `f4794d0` 把正常查询改为原生 `list_workspaces`。需要时才用 Hermes `read_file` 核对 Paseo 注册表。派单使用原生 `list_agents`、`get_agent_status`、`send_agent_prompt`。纠正了 `v0.16.2` 的 Agent 间消息参数，按默认排队投递，使用 `notifyOnFinish` 表达是否需要完成回执。
- 从新版 Paseo 的工具清单移除了自定义 `list_projects`。保留原有的直属关系检查和独立退场能力。归档及目录删除属于明确退场时的分支，日常接单不触发。Project Manager 的文件写入范围仍是整个 `/var/lib/hermes/workspace`，外部只读。
- 修正已有主工作区的识别。项目内已有开发 worktree 不妨碍复用主工作区，仍拒绝创建第二名活跃协调者。

## 原会话与现有测试项目

| 对象 | 记录 |
| --- | --- |
| 用户日常使用的 Project Manager | `30a3de67-cc8b-41fc-98f2-14d232b6c188`，Provider `project-manager`，主工作区 `wks_da31dc90c203f02c`。 |
| 已有 `testpro` | `prj_415e1d5752d3aacf`，主工作区 `wks_9547e642c6039c25`，实际目录 `/var/lib/hermes/workspace/temp/testpro`。本地 `develop` 基线 `40f514a`，工作树干净，未配置远端。 |
| 已有测试协调者 | `cfd06ff6-082e-4d80-b9d7-383525525b1e`，旧 `hermes` Provider，角色标签 `orchestrator`。有两个未归档的下级，位于现有 `pilot-team-01` worktree。 |

已使用 Paseo 的 `update_agent` 给这名测试协调者补登记 `paseo.parent-agent-id` 和 `paseo.parent-server-id`，并用 `get_agent_status` 回查生效。它现在直属上面的原 Project Manager。没有换 Provider、另建协调者、归档旧会话或修改测试项目文件。新配置允许经过这类直属关系核对的旧 Hermes 协调者接单，便于先验收入口。协调者自身切换到新 Profile 属于下一阶段。

旧参考是 Home 的 Project Manager `2b6f929a-c014-4d7e-a72b-7688c2591064`。其工作区标题为 `home`，底层项目登记名 `hermes`，根路径 `/var/lib/hermes`。主要参考是 `/var/lib/hermes/.hermes/skills/paseo-orchestration/SKILL.md`、`/var/lib/hermes/.hermes/skills/devops/paseo-orchestration-discipline/SKILL.md` 和同目录 `paseo-role-system/SKILL.md`。旧交接和 EPL-AddIns 历史会话可交叉核对真实分工。旧文件里存在不同阶段的口径，按用户最新要求和明确标为定稿的角色规则取舍。

## 恢复后的验收顺序

1. 确认后台构建完成，按正常流程测试切换 NixOS，重新载入原 Project Manager 会话。只发一次针对现有 `testpro` 的只读任务。核对它实际用原生 MCP 找到项目和直属协调者，协调者收到的任务保留原要求，原 Project Manager 得到真实结果后作出汇总。
2. 核对找不到项目时只提出新建建议，未经请求不创建实体。核对主动给非直属目标派单被服务端拒绝。项目清单或路径清理与这次入口验收无关。
3. Project Manager 通过后才继续协调者。协调者先开当前项目的托管 worktree，再在该工作区开 Planner。当前 Planner 只有只读文件工具并且没有 Paseo MCP，这是和目标流程最明显的差异。后续逐个核实 Planner 能按线内职责落方案、派工和处理复审，Worker 能实施自测，Reviewer 能独立审查，最后由协调者回报入口。先复用现成工具和 Skill。

此前 `CHAIN-01` 在另建的 `testpro-chain-20261121` 跑过研发与归档，提交 `426d4f7`、5 项测试通过。那次由协调者直接派 Worker 和 Reviewer，不能算 Planner 在线内派工的验收，也不能算 `f4794d0` 已验证。该项目已归档，目录和独立 Git bundle 已保留，无须用户现在确认或处理任何路径。
