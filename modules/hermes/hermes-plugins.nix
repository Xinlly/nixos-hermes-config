# modules/hermes-plugins.nix — Hermes 插件声明式部署
#
# Aowen-Nowor hermes-lark-streaming v1.5.0
# 目录插件（lark-oapi 已在 Hermes 密封 venv 中）
{ pkgs, ... }:

let
  # 目录插件：直接复制源码到 Nix store
  hermesLarkStreamingAowen = pkgs.runCommand "hermes-lark-streaming-aowen-1.5.0" { } ''
    mkdir -p $out
    cp -R ${/var/lib/hermes/workspace/projects/upstream/hermes-lark-streaming-aowen}/. $out/
    # 清理非必要文件
    rm -rf $out/.git $out/graphify-out $out/tests
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
