# modules/hermes/manager-profile.nix — 管理者专用 Hermes profile 落位（阶段 0）
#
# 在 ${stateDir}/.hermes/profiles/manager/ 下落位一个 default 的声明式克隆：
#   - config.yaml 由 services.hermes-agent.settings 深拷贝渲染，唯一差异是
#     plugins.disabled 追加 "hermes-lark-streaming"（ACP 不加载飞书流式卡片插件）。
#   - skills / plugins / .env / .env.secrets 只读软链对齐 default（同机同用户）。
#   - 数据目录全新空目录，不克隆历史；SOUL.md 仅首次拷贝，之后不覆盖。
#
# 不新增任何 systemd service（该 profile 只跑 `hermes --profile manager acp`，
# 由 Paseo 按需拉起）；本模块只注册一个幂等 activation script。
# 渲染与软链规则逐字对齐上游 hermes-agent nixosModules.nix（v2026.8.13）。
{ config, lib, pkgs, ... }:
let
  ha = config.services.hermes-agent;
  root = "${ha.stateDir}/.hermes";
  profileDir = "${root}/profiles/manager";

  # 克隆声明源 settings；唯一覆盖：plugins.disabled 在基准值上追加
  # hermes-lark-streaming。基准取运行期合并后的实际值（不硬编码 curator），
  # unique 去重保证该名最终恰好出现一次（改动 hermes-plugins.nix 后基准已含它）。
  managerSettings = lib.recursiveUpdate ha.settings {
    plugins.disabled = lib.unique ((ha.settings.plugins.disabled or [ ]) ++ [
      "hermes-lark-streaming"
    ]);
  };

  # JSON 是 YAML 子集——与上游 configJson（builtins.toJSON settings）同款渲染，
  # Hermes 可直接读取。
  managerConfig =
    pkgs.writeText "manager-hermes-config.yaml" (builtins.toJSON managerSettings);
in
{
  system.activationScripts.hermes-manager-profile = {
    # 在 default（config/env/软链落位）之后跑。上游脚本名为 "hermes-agent-setup"
    # （upstream nixosModules.nix system.activationScripts."hermes-agent-setup"）。
    deps = [ "hermes-agent-setup" ];
    text = ''
      set -e

      # ── profile 根（父目录 profiles/ 已存在 2775；install -d 不改既有父目录权限）──
      install -d -o ${ha.user} -g ${ha.group} -m 2770 ${profileDir}

      # ── (d) 全新空数据/运行态目录，不克隆历史 ──
      # 对齐 hermes_cli/profiles.py _PROFILE_DIRS（memories/sessions/plans/
      # workspace/cron/home/logs），另补 state（SessionDB 等运行库容器）。
      for d in memories sessions state logs cron plans workspace home; do
        install -d -o ${ha.user} -g ${ha.group} -m 2770 ${profileDir}/$d
      done

      # ── (a) config.yaml：声明源覆盖回写（与上游 default 同策略），0660 对齐 ──
      install -o ${ha.user} -g ${ha.group} -m 0660 ${managerConfig} ${profileDir}/config.yaml

      # ── (c) .env / .env.secrets：软链对齐仓外既有文件（同机同用户）。──
      # 仅落符号链接，密钥内容绝不进 nix store / git。
      ln -sfn ${root}/.env ${profileDir}/.env
      ln -sfn ${root}/.env.secrets ${profileDir}/.env.secrets

      # ── (e) SOUL.md：仅首次拷贝实体文件；已存在绝不覆盖（保留未来个性化）──
      if [ ! -f ${profileDir}/SOUL.md ]; then
        install -o ${ha.user} -g ${ha.group} -m 0640 ${root}/SOUL.md ${profileDir}/SOUL.md
      fi

      # ── (b) skills：整目录只读软链共享（同技能集，随 default 联动）──
      ln -sfn ${root}/skills ${profileDir}/skills

      # ── (b) plugins：先建目录，再与上游规则逐字对齐 nix-managed-<name> 软链 ──
      install -d -o ${ha.user} -g ${ha.group} -m 2770 ${profileDir}/plugins
      find ${profileDir}/plugins -maxdepth 1 -type l -name 'nix-managed-*' -delete 2>/dev/null || true
      ${lib.concatStringsSep "\n" (map (plugin:
        let
          name = lib.getName plugin;
        in ''
          if [ ! -f "${plugin}/plugin.yaml" ]; then
            echo "ERROR: extraPlugins entry '${plugin}' has no plugin.yaml" >&2
            exit 1
          fi
          ln -sfn ${plugin} ${profileDir}/plugins/nix-managed-${name}
          chown -h ${ha.user}:${ha.group} ${profileDir}/plugins/nix-managed-${name}
        '') ha.extraPlugins)}

      # default plugins/ 内 extraPlugins 之外的实体插件目录，只读软链对齐（同插件）。
      # hermes-achievements 为 default 既有实体目录（盘点确认，2026-10-30）；不做收编/重构。
      if [ -d ${root}/plugins/hermes-achievements ]; then
        ln -sfn ${root}/plugins/hermes-achievements ${profileDir}/plugins/hermes-achievements
      fi
    '';
  };
}
