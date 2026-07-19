# modules/hermes-plugins.nix — Hermes 插件声明式部署
#
# Aowen-Nowor hermes-lark-streaming v1.5.0
# 目录插件（lark-oapi 已在 Hermes 密封 venv 中）
{ config, pkgs, lib, inputs, ... }:

let
  # 目录插件：从 flake inputs 引用，过滤不需要的文件
  hermesLarkStreamingAowen = pkgs.runCommand "hermes-lark-streaming-aowen-1.5.0" { } ''
    mkdir -p $out
    # 只复制插件需要的文件，跳过 .git、graphify-out、tests
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
    # 目录插件（plugin.yaml + __init__.py）
    extraPlugins = [ hermesLarkStreamingAowen ];

    # 启用插件
    settings.plugins.enabled = [
      "hermes-lark-streaming"
    ];
  };
}
