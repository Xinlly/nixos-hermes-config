# Hermes identities and Paseo providers for project-internal roles on WSL.
{ config, lib, pkgs, ... }:

let
  hermes = config.services.hermes-agent;
  profileRoot = "${hermes.stateDir}/.hermes/profiles";
  blockWrite = pkgs.writeShellScript "hermes-paseo-block-write" ''
    printf '%s\n' '{"action":"block","message":"This role can inspect project files but cannot edit them."}'
  '';
  roles = {
    coordinator = {
      description = "Coordinate a Paseo project, verify and integrate work, and report to Project Manager";
      toolsets = [ "file" "terminal" ];
      paseoTools = true;
      soul = ''
        你是本项目唯一常驻协调者。Project Manager 负责项目归属和入口，你负责本项目内的派工、集成和收尾。开始前核对 Paseo 的项目、普通主工作区、Git 基线和用户授权。跨项目任务交回 Project Manager。

        任务始终带任务 ID。范围清楚时直接派 Worker，跨模块、依赖不明或范围不清时请 Planner 拆分。使用 Paseo 创建子 Agent，角色 Provider 分别为 planner、worker 和 reviewer。先核对可用 Provider、模型和目标工作区。跨 Provider 创建前用 inspect_provider 查询目标支持的模式，显式传 settings.modeId。可以并行的实现任务各用独立托管 worktree。同一片代码或相互依赖的改动按顺序做。审核者只读核对指定 SHA、改动和你提供的测试证据。Worker 和你负责实际运行测试，无需给审核者派运行命令的任务。Worker 更新 SHA 后按新差异复审。

        区分已派发、Agent 已结束和验收通过。按任务 ID、Agent ID 与提交 SHA 复核结果。收到重复完成通知时复用已存在的评审会话。验收后串行集成。多轮派工完成后，用 send_agent_prompt 将最终结果、命令和证据主动回传给直属 Project Manager，设置 notifyOnFinish=false，使用默认排队投递。根据你自己的状态快照核对 paseo.parent-agent-id。等待子任务时结束的轮次只算进度。项目退场时，你完成并核验 Git 收尾和项目内其他 Agent、工作区的处置。所有收尾完成后向 Project Manager 回报「已收尾，可以归档」，由它处置你的会话及普通主工作区。
      '';
    };
    planner = {
      description = "Read the project and return a plan with dependencies and acceptance criteria";
      toolsets = [ "file" ];
      readOnly = true;
      soul = ''
        你是计划者，向本任务的协调者交付计划。以任务 ID、基线和验收目标为起点，只读核对相关项目文件。输出范围、假设、每个子任务的输入和交付物、可并行项、相互依赖及可执行的验收步骤。遇到授权或需求冲突时报告阻塞。把实施、派工、评审和集成交回协调者处理。
      '';
    };
    worker = {
      description = "Implement one assigned task in its worktree and return the commit and tests";
      toolsets = [ "file" "terminal" ];
      soul = ''
        你是工作者，只在协调者给出的 worktree 内实施当前任务。先检查分支、基线和工作树，按写入范围完成改动并运行约定的测试。规格冲突时停在提交前，说明哪两项无法同时满足。协调者澄清后在同一会话和 worktree 续接。

        按任务授权处理本地提交，回报任务 ID、工作区、完整 SHA、改动范围、测试命令与结果。由协调者负责派工、集成、推送和归档。
      '';
    };
    reviewer = {
      description = "Independently review the assigned change and report evidence per commit";
      toolsets = [ "file" "paseo_review_git" ];
      readOnly = true;
      inspectGit = true;
      soul = ''
        你是独立审核者。协调者应提供任务 ID、基线 SHA、待审 SHA、测试结果和验收条件。先用 inspect_git_commit 检查目标 SHA、差异及工作树，再按需用 read_file 阅读关联文件。指出证据与验收条件的具体不符。差异截断或缺少证据时，回报 blocked 并说明需要什么。

        回报目标 SHA 和 pass、needs_changes 或 blocked，并列出能定位的问题与证据。由 Worker 修改，由协调者安排复审和集成。
      '';
    };
  };
  renderProfile = role: settings:
    let
      name = "paseo-${role}";
      readOnly = settings.readOnly or false;
      inspectGit = settings.inspectGit or false;
      profile = "${profileRoot}/${name}";
      roleConfig = (lib.getAttrs [ "model" "fallback_model" "terminal" "logging" "security" ] hermes.settings) // {
        providers.ark = hermes.settings.providers.ark;
        platforms.feishu.enabled = false;
        secrets.command = import ./profile-environment.nix { inherit lib pkgs hermes; };
        platform_toolsets.acp = settings.toolsets;
        toolsets = settings.toolsets;
        memory = {
          provider = "none";
          memory_enabled = false;
          user_profile_enabled = false;
        };
      } // lib.optionalAttrs inspectGit {
        plugins.enabled = [ "paseo-review-git" ];
      } // lib.optionalAttrs readOnly {
        hooks_auto_accept = true;
        hooks.pre_tool_call = [ {
          matcher = "^(write_file|patch)$";
          command = "${blockWrite}";
          fail_closed = true;
        } ];
      };
      configFile = pkgs.writeText "${name}-config.yaml" (builtins.toJSON roleConfig);
      metadataFile = pkgs.writeText "${name}-profile.yaml" (builtins.toJSON {
        inherit (settings) description;
        description_auto = false;
      });
      soul = pkgs.writeText "${name}-SOUL.md" settings.soul;
      installProfile = ''
        install -d -o ${hermes.user} -g ${hermes.group} -m 2750 "${profile}"
        ln -sfnT "${configFile}" "${profile}/config.yaml"
        ln -sfnT "${metadataFile}" "${profile}/profile.yaml"
        ln -sfnT "${soul}" "${profile}/SOUL.md"
        ${lib.optionalString inspectGit ''
          install -d -o ${hermes.user} -g ${hermes.group} -m 0750 "${profile}/plugins"
          ln -sfnT "${./plugins/paseo-review-git}" "${profile}/plugins/paseo-review-git"
        ''}
        if [ ! -e "${profile}/.no-bundled-skills" ]; then
          install -o ${hermes.user} -g ${hermes.group} -m 0640 /dev/null "${profile}/.no-bundled-skills"
        fi
      '';
      provider = {
        extends = "acp";
        label = role;
        inherit (settings) description;
        command = [ "/run/current-system/sw/bin/hermes" "--profile" name "acp" ];
        env.HOME = hermes.stateDir;
        paseoTools.enabled = settings.paseoTools or false;
      } // lib.optionalAttrs (!(settings.paseoTools or false)) { options.supportsMcpServers = false; };
    in
    { inherit installProfile provider; };
  profiles = lib.mapAttrs renderProfile roles;
in
{
  services.paseo.settings.agents.providers = lib.mapAttrs (_: profile: profile.provider) profiles;
  system.activationScripts.hermes-paseo-roles = {
    deps = [ "hermes-agent-setup" ];
    text = ''
      set -e
      ${lib.concatMapStringsSep "\n" (profile: profile.installProfile) (lib.attrValues profiles)}
    '';
  };
}
