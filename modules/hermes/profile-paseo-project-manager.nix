# Hermes profile for Paseo project intake.
{ config, lib, pkgs, ... }:

let
  hermes = config.services.hermes-agent;
  home = "${hermes.stateDir}/.hermes";
  profile = "${home}/profiles/paseo-project-manager";
  workspaceRoot = hermes.settings.terminal.cwd;
  registryDir = "${workspaceRoot}/paseo-project-manager";
  registryPath = "${registryDir}/AGENT.md";
  skillsDir = "${./skills}";
  guard = pkgs.writeText "hermes-project-manager-file-guard.py" ''
    import json
    import stat
    import sys
    from pathlib import Path

    event = json.load(sys.stdin)
    workspace = Path(${builtins.toJSON workspaceRoot})
    arguments = event.get("tool_input") or {}

    def can_write():
        if event.get("tool_name") == "patch" and arguments.get("mode", "replace") != "replace":
            return False
        raw_path = arguments.get("path")
        if not isinstance(raw_path, str) or not Path(raw_path).is_absolute():
            return False
        path = Path(raw_path)
        # Do not hand a symlink or a traversal to a second path resolver.
        if not path.is_relative_to(workspace) or path == workspace or path.resolve() != path:
            return False
        try:
            entry = path.lstat()
        except FileNotFoundError:
            return True
        return stat.S_ISREG(entry.st_mode) and entry.st_nlink == 1

    print(json.dumps({} if can_write() else {
        "action": "block",
        "message": "Use write_file or single-file patch with an absolute path under ${workspaceRoot} that does not cross a symlink or modify a hard-linked file.",
    }))
  '';

  settings = lib.getAttrs [ "model" "fallback_model" "terminal" "logging" "security" ] hermes.settings // {
    providers.ark = hermes.settings.providers.ark;
    platforms.feishu.enabled = false;
    secrets.command = import ./profile-environment.nix { inherit lib pkgs hermes; };
    platform_toolsets.acp = [ "file" ];
    toolsets = [ "file" ];
    hooks_auto_accept = true;
    hooks.pre_tool_call = [ {
      matcher = "^(write_file|patch)$";
      command = "${lib.getExe pkgs.python3} ${guard}";
      fail_closed = true;
    } ];
    skills.external_dirs = [ skillsDir ];

    memory = {
      provider = "none";
      memory_enabled = false;
      user_profile_enabled = false;
    };
  };
  configFile = pkgs.writeText "paseo-project-manager-config.yaml" (builtins.toJSON settings);
  metadataFile = pkgs.writeText "paseo-project-manager-profile.yaml" (builtins.toJSON {
    description = "Paseo task intake, project routing, and coordinator handoff";
    description_auto = false;
  });
  soulFile = pkgs.writeText "paseo-project-manager-SOUL.md" ''
    # Paseo project manager

    你是用户在 Paseo 中的统一任务入口。项目登记册位于 `${registryPath}`。使用 Hermes 文件工具按绝对路径读取登记册，用 write_file 更新。如果确认文件尚不存在，在这个路径初始化表格。

    文件工具的读写范围是整个 Workspace，即 `${workspaceRoot}` 及其所有子目录；Workspace 外只可读取系统允许读取的资料。使用绝对路径写文件或逐文件修改。登记册只是你负责维护的文件之一。新建项目时可在 Workspace 下准备协调者的目录和首份 HANDOFF.md；项目代码及开发 worktree 日常由协调者管理。

    专用 Skill `paseo-project-manager` 位于 `${skillsDir}/paseo-project-manager/SKILL.md`。处理项目请求前，用 read_file 加载 Skill，并按当前用户意图选择对应流程。查询可以直接答复；转发、创建和退场各有进入条件。

    维护一张固定列的 Markdown 表格，每个项目一行。列顺序为：项目名、别名、Paseo projectId、协调者所在的 workspaceId、协调者完整 agentId、项目根目录、阶段、最后活跃时间、进度摘要、磁盘清理状态、待清理绝对路径、待确认起始时间、上次清理提醒时间。阶段限于「刚开始」「进行中」「已归档」。最后活跃时间和清理时间使用带时区的 ISO 8601 格式。实际转发、协调者回报或已确认的进展才更新最后活跃时间。已有表格按 Skill 补列并保留原记录。未确认的值填「—」。

    接到任务时先读取登记册，用项目名、别名和路径判断归属，在 Paseo 核对 projectId、workspaceId 和协调者。只记录已核实的 ID 和进展，归档需用户确认。登记册无法读取或更新时，报告具体原因；若仍可通过 Paseo 唯一核实项目和协调者，按已有转发规则处理。

    用户要求转发且目标项目和协调者已核实时，按 Skill 核对状态并转发原指令，保留用户给出的要求和授权边界。归属或协调者有歧义时，列出候选并请用户确认。

    没有匹配项目时，拟一个简洁的项目名称和根目录，请用户确认。获准后按 Skill 先准备物理目录，再登记项目和首个工作区。`${workspaceRoot}` 之外的新目录由具备权限的操作者准备。

    你负责 Paseo 项目的创建和退场，以及自己直接管理的协调者和协调者所在的工作区。你的直接子代理只能是业务项目的协调者，或你自己的 Paseo 项目里的临时代理。已有会话的管理关系通过 paseo.parent-agent-id 核实。协调者负责项目内其他 Agent、工作区和 Git worktree；对子代理的管理权限只到一层。

    项目退场时，通知协调者完成并核验项目的 Git 收尾，包括它自己所在的分支。协调者可归档本项目内除自己以外的 Agent，以及除自身所在工作区以外的工作区。收到协调者「已收尾，可以归档」的确认后，只核对 Paseo 的归档对象和范围，再归档直属协调者及其工作区。按实际结果更新登记册。

    协调者及其普通主工作区均已归档后，由你负责最后清理主目录。仅在用户已授权具体路径，并核对内容可恢复、路径已停用且无其他依赖后才能执行。缺少确认时把项目标为「已归档 / 待确认清理」，按 Skill 在后续会话提醒用户。缺少目录删除工具时，记录阻塞并保留目录。
  '';
in
{
  system.activationScripts.hermes-paseo-project-manager = {
    deps = [ "hermes-agent-setup" ];
    text = ''
      install -d -o ${hermes.user} -g ${hermes.group} -m 2750 "${profile}"
      install -d -o ${hermes.user} -g ${hermes.group} -m 2770 "${registryDir}"
      install -o ${hermes.user} -g ${hermes.group} -m 0640 "${configFile}" "${profile}/config.yaml"
      install -o ${hermes.user} -g ${hermes.group} -m 0640 "${soulFile}" "${profile}/SOUL.md"
      if [ ! -e "${profile}/profile.yaml" ]; then
        install -o ${hermes.user} -g ${hermes.group} -m 0640 "${metadataFile}" "${profile}/profile.yaml"
      fi
      if [ ! -e "${profile}/.no-bundled-skills" ]; then
        install -o ${hermes.user} -g ${hermes.group} -m 0640 /dev/null "${profile}/.no-bundled-skills"
      fi
      for file in .env .env.secrets; do
        if [ "$(readlink "${profile}/$file" || true)" = "${home}/$file" ]; then
          unlink "${profile}/$file"
        fi
      done
    '';
  };
}
