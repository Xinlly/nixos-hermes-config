# modules/hermes-plugins.nix — Hermes 插件声明式部署
#
# Aowen-Nowor hermes-lark-streaming v1.5.0（飞书流式卡片）
# Matt workflows：经审核的 Matt Pocock workflow 显式插件适配层
{ config, pkgs, lib, inputs, ... }:
let
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
in
{
  services.hermes-agent = {
    extraPlugins = [
      hermesLarkStreamingAowen
      mattWorkflows
    ];

    settings.plugins = {
      enabled = [
        "hermes-lark-streaming"
        "matt-workflows"
      ];
      # lark-streaming 启用（飞书流式卡片，gateway 用）；仅保持 curator 禁用。
      # 注意：该插件 v1.5.0 无 ACP 模式门控，hermes 身份的 ACP（Zed“哆啦”）加载可能卡死，
      # 按既定决策暂不处理，若复现再改其启动方式。
      disabled = [
        "hermes-knowledge-curator"
      ];
    };
  };
}
