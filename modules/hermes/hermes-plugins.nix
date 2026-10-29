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
        "matt-workflows"
      ];
      # 2026-10-30 决定：hermes-lark-streaming 在 default 声明源即不启用——
      # 从 enabled 移除并加入 disabled（disabled 恒优先，双保险）。gateway 重启后
      # 也不再加载；飞书流式卡片停用是已知接受后果，由管理者窗口另排，不属本改动。
      # 恢复方式：把 "hermes-lark-streaming" 从 disabled 移除并加回 enabled。
      # 注意：extraPlugins 包安装与 nix-managed-* 软链全部保留——禁加载≠不安装，
      # 保留便于未来恢复；manager profile（modules/hermes/manager-profile.nix）
      # 亦只读共享同一插件包并在其 config 中禁用。
      disabled = [
        "hermes-knowledge-curator"
        "hermes-lark-streaming"
      ];
    };
  };
}
