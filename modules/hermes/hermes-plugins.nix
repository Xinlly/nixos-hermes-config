# modules/hermes-plugins.nix — Hermes 插件声明式部署
#
# Aowen-Nowor hermes-lark-streaming v1.5.0（飞书流式卡片）
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
in
{
  services.hermes-agent = {
    extraPlugins = [
      hermesLarkStreamingAowen
    ];

    settings.plugins.enabled = [
      "hermes-lark-streaming"
    ];
  };
}
