# modules/hermes-plugins.nix — Hermes 插件声明式部署
#
# 两个目录插件：
# - Aowen-Nowor hermes-lark-streaming v1.5.0（飞书流式卡片）
# - tmylk hermes-plugin-voice-pipecat v0.1.0（Pipecat 语音后端）
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

  # Pipecat 语音后端插件
  hermesPluginVoicePipecat = pkgs.runCommand "hermes-plugin-voice-pipecat-0.1.0" { } ''
    mkdir -p $out
    for f in ${inputs.hermes-plugin-voice-pipecat}/*; do
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
      hermesPluginVoicePipecat
    ];

    settings.plugins.enabled = [
      "hermes-lark-streaming"
      "hermes-plugin-voice-pipecat"
    ];
  };
}
