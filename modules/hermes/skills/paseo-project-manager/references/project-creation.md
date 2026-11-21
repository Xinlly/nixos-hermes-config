# 创建项目和协调者

进入条件为用户已确认新项目，或明确授权为现有项目补建协调者。

这个流程只创建业务项目的协调者工作区和协调者。Project Manager 如需创建临时子代理，使用自己所在 Paseo 项目的现有工作区。项目内的其他 Agent、工作区和 Git worktree 由协调者创建和管理。

Git 项目的协调者通常驻主工作区的 `develop` 分支。让协调者在首轮核对实际分支并按项目约定准备。各开发工作区通常对应各自的 worktree，由协调者统一管理。新目录尚未初始化 Git 时，先按普通目录登记。

1. **确认项目。** 没有匹配项目时，拟定项目名和 NixOS 上的项目根目录，请用户确认是否新建。用绝对路径核对登记。已有项目时，先确认整个项目是否已有协调者。有就沿用。
2. **准备物理目录。** 目标目录已存在时就使用原目录，保留已有文件。用户确认新建且目录在 `SOUL.md` 指定的 Workspace 内时，用 `write_file` 写入新项目的首份 `HANDOFF.md`。Hermes 会创建缺失的父目录。交接文件只需记录项目名、用户确认的目标和授权范围。写入后读回验证。如果目标目录超出写入范围，或路径的存在状态和归属无法确认，先请用户或有权限的操作者处理。
3. **登记协调者的工作区。** 用 `list_workspaces` 确认项目是否已有合适的主工作区，有就复用。否则调用 `create_workspace`，传 `isolation: local`、已准备好的绝对路径 `path` 和工作区 `title`。已有项目必须传核实过的 `projectId`。首次登记才省略 `projectId`，由 Paseo 按根目录登记项目并创建首个工作区，默认项目名取自根目录名。
4. **核对工作区，再创建 Agent。** 确认 `projectId`、`workspaceId` 和 `cwd` 与目标项目相符。`create_agent` 必须显式传这个 `workspaceId`。跨 Provider 创建前，用 `inspect_provider` 核实协调者支持的模式并传 `settings.modeId`，通常使用 `default`。一次传全 `title`、已核实的 `provider/model`、`workspaceId`、`labels` 和实际 `initialPrompt`。设置 `role=orchestrator` 和项目的 `project` 标签。`initialPrompt` 交代项目归属、协调职责、用户授权和根目录的 `HANDOFF.md`。通过 `list_providers` 和 `list_models` 核实不确定的能力或模型。
5. **核对并登记。** 以返回的完整 `agentId` 调用 `get_agent_status`，核对 `workspaceId`、`cwd` 和角色。创建回执为 `running` 时，先记为已创建、启动验证中。根据首轮回报检查协调者是否在目标目录正常运行，再报告启动通过。项目或工作区已创建、协调者尚未成功创建时，先把真实 `projectId` 和 `workspaceId` 写入 `AGENT.md`，协调者 ID 留空，注明进度。后续从已确认的步骤继续。任一步超时或返回不明时，先用根目录、工作区及完整 ID 查实际结果，再决定是否重试。
