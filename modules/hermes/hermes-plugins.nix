# modules/hermes-plugins.nix — Hermes 插件声明式部署
#
# Aowen-Nowor hermes-lark-streaming v1.5.0（飞书流式卡片）
# Matt workflows：经审核的 Matt Pocock workflow 显式插件适配层
# Hindsight：官方目录插件，复用本机 Hindsight 服务。
{ config, pkgs, lib, inputs, ... }:
let
  ha = config.services.hermes-agent;
  hermesHome = "${ha.stateDir}/.hermes";

  # 飞书流式卡片插件
  hermesLarkStreamingAowen = pkgs.runCommand "hermes-lark-streaming-aowen-1.5.0" { } ''
    mkdir -p $out
    for f in ${inputs.hermes-lark-streaming-aowen}/*; do
      base=$(basename "$f")
      case "$base" in
        .git|graphify-out|tests) ;;
        *) cp -R "$f" $out/ ;;
      esac
    done
  '';

  # 从锁定的 Xinlly/skills flake input 复制审核后的插件到 Nix store。
  mattWorkflows = pkgs.runCommand "matt-workflows-hermes-plugin" { } ''
    mkdir -p $out
    cp -R ${inputs.matt-workflows}/hermes/plugin/. $out/
  '';
  hindsightProvider = pkgs.runCommand "hindsight-1.2.4" { } ''
    mkdir -p "$out"
    cp -R ${inputs.hindsight-hermes}/hindsight-integrations/hermes/. "$out/"
  '';

  python = ha.package.python;
  hindsightClientWheel = pkgs.fetchurl {
    url = "https://files.pythonhosted.org/packages/5b/9b/aef41711ea4ea419386a10d7b5b52cebd9aac380127897629508ddff12b9/hindsight_client-0.10.1-py3-none-any.whl";
    sha256 = "04e03353a0f9dcfa7b1b1000cccc8f077a93a788b27af62cc5e014b2dd3b960c";
  };
  aiohttpRetryWheel = pkgs.fetchurl {
    url = "https://files.pythonhosted.org/packages/1a/99/84ba7273339d0f3dfa57901b846489d2e5c2cd731470167757f1935fffbd/aiohttp_retry-2.9.1-py3-none-any.whl";
    sha256 = "66d2759d1921838256a05a3f80ad7e724936f083e35be5abb5e16eed6be6dc54";
  };
in
{
  # local_external 复用现有容器，只需要 HTTP 客户端。
  services.hermesRuntime.hindsightClient = pkgs.runCommand "hermes-hindsight-client" {
    nativeBuildInputs = [ pkgs.unzip ];
  } ''
    mkdir -p "$out/${python.sitePackages}"
    unzip -q ${hindsightClientWheel} -d "$out/${python.sitePackages}"
    unzip -q ${aiohttpRetryWheel} -d "$out/${python.sitePackages}"
  '';

  # Memory provider 按目录名查找，不能用上游 extraPlugins 的 nix-managed- 前缀。
  system.activationScripts.hermes-hindsight-provider = {
    deps = [ "hermes-manager-profile" ];
    text = ''
      for home in ${hermesHome} ${hermesHome}/profiles/manager; do
        target="$home/plugins/hindsight"
        if [ -e "$target" ] || [ -L "$target" ]; then
          case "$(readlink "$target" || true)" in
            /nix/store/*-hindsight-[0-9]*) ;;
            *) echo "Keeping existing Hindsight plugin at $target" >&2; continue ;;
          esac
        fi
        ln -sfnT "${hindsightProvider}" "$target"
        chown -h ${ha.user}:${ha.group} "$target"
      done
    '';
  };

  services.hermes-agent = {
    extraPlugins = [
      hermesLarkStreamingAowen
      mattWorkflows
    ];

    settings.plugins = {
      enabled = [
        "matt-workflows"
      ];
      # 2026-10-30 决定：hermes-lark-streaming 在 default 声明源即不启用——
      # 从 enabled 移除并加入 disabled（disabled 恒优先，双保险）。gateway 重启后
      # 也不再加载；飞书流式卡片停用是已知接受后果，由管理者窗口另排，不属本改动。
      # 恢复方式：把 "hermes-lark-streaming" 从 disabled 移除并加回 enabled。
      # 注意：extraPlugins 包安装与 nix-managed-* 软链全部保留——禁加载≠不安装，
      # 保留便于未来恢复；manager profile（modules/hermes/profile-manager.nix）
      # 亦只读共享同一插件包并在其 config 中禁用。
      disabled = [
        "hermes-knowledge-curator"
        "hermes-lark-streaming"
      ];
    };
  };
}
