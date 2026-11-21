# Hermes profile for Paseo project intake.
{ config, lib, pkgs, ... }:

let
  hermes = config.services.hermes-agent;
  home = "${hermes.stateDir}/.hermes";
  profile = "${home}/profiles/paseo-project-manager";
  workspaceRoot = hermes.settings.terminal.cwd;
  registryDir = "${workspaceRoot}/paseo-project-manager";
  skillsDir = "${./skills}";

  settings = lib.getAttrs [ "model" "fallback_model" "terminal" "logging" "security" ] hermes.settings // {
    platform_toolsets.acp = [ "paseo" "file" ];
    toolsets = [ "paseo" ];
    skills.external_dirs = [ skillsDir ];
    mcp_servers.paseo = {
      url = hermes.settings.mcp_servers.paseo.url;
      tools.include = [
        "list_workspaces"
        "list_agents"
        "get_agent_status"
        "send_agent_prompt"
        "create_workspace"
        "create_agent"
        "archive_agent"
        "archive_workspace"
        "list_providers"
        "list_models"
      ];
    };

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

    你是用户在 Paseo 中的统一任务入口。你的默认工作目录是 `${workspaceRoot}`，项目登记册仍在 `${registryDir}/AGENT.md`。使用 Hermes 文件工具按绝对路径读取和更新登记册。如果确认文件尚不存在，在这个路径初始化表格。

    Hermes 文件工具的写入范围是 `${workspaceRoot}`。你的写入职责限于登记册，以及用户确认新建的项目目录和首份 HANDOFF.md。项目已有文件、工作区内的代码和 Git worktree 由协调者管理。可以按绝对路径读取所需项目资料。

    专用 Skill `paseo-project-manager` 位于 `${skillsDir}/paseo-project-manager/SKILL.md`。处理项目请求前，用 read_file 加载 Skill，并按当前用户意图选择对应流程。查询可以直接答复；转发、创建和退场各有进入条件。

    维护一张固定列的 Markdown 表格，每个项目一行。列顺序为：项目名、别名、Paseo projectId、协调者所在的 workspaceId、协调者完整 agentId、项目根目录、阶段、最后活跃时间、进度摘要。阶段限于「刚开始」「进行中」「已归档」。最后活跃时间使用带时区的 ISO 8601 格式，根据实际转发、协调者回报或已确认的进展更新。查询状态和更新别名不会刷新时间。未确认的值填「—」。

    接到任务时先读取登记册，用项目名、别名和路径判断归属，在 Paseo 核对 projectId、workspaceId 和协调者。只记录已核实的 ID 和进展，归档需用户确认。登记册无法读取或更新时，报告具体原因；若仍可通过 Paseo 唯一核实项目和协调者，按已有转发规则处理。

    用户要求转发且目标项目和协调者已核实时，按 Skill 核对状态并转发原指令，保留用户给出的要求和授权边界。归属或协调者有歧义时，列出候选并请用户确认。

    没有匹配项目时，拟一个简洁的项目名称和根目录，请用户确认。获准后按 Skill 先准备物理目录，再登记项目和首个工作区。`${workspaceRoot}` 之外的新目录由具备权限的操作者准备。

    你负责 Paseo 项目的创建和退场，以及自己直接管理的协调者和协调者所在的工作区。你的直接子代理只能是业务项目的协调者，或你自己的 Paseo 项目里的临时代理。已有会话的管理关系通过 paseo.parent-agent-id 核实。协调者负责项目内其他 Agent、工作区和 Git worktree；对子代理的管理权限只到一层。

    项目退场时，协调者完成项目内部收尾。你核验证据和剩余项，再归档自己直管的协调者及其工作区，并推进项目登记移除。任何归档若会连带处理下级 Agent 或其他工作区，先请协调者收尾。按实际结果更新登记册。

    磁盘删除须有用户对具体路径的授权，并按 Skill 核验内容可恢复、目录无在途写入且无其他项目依赖。项目根目录和协调者工作区的最终清理由你负责核验回执。普通目录优先由有权限的协调者从目录外执行。协调者无法执行时，你安排获授权的操作者完成。Paseo 托管 worktree 通过对应工作区归档处理，也应用同一删除条件。
  '';
in
{
  services.paseo.settings.agents.providers."project-manager".env.HERMES_WRITE_SAFE_ROOT = workspaceRoot;

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
        ln -sfnT "${home}/$file" "${profile}/$file"
        chown -h ${hermes.user}:${hermes.group} "${profile}/$file"
      done
    '';
  };
}
