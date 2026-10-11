# hosts/raiyun2/treehole.nix — Tree Hole Sites (Next.js standalone)
# 应用代码手工部署到 /opt/tree-hole（外部 Node 应用，参照 mihomo 配置惯例）；
# 用户、目录与 systemd 单元在此声明式管理。密钥走 EnvironmentFile，不入库。
{ config, lib, pkgs, ... }:
{
  # ── 专用系统用户/组（994 空闲；勿用 996，与 systemd-oom 冲突）──
  users.groups.treehole = { gid = 994; };
  users.users.treehole = {
    uid = 994;
    group = "treehole";
    isSystemUser = true;
    home = "/opt/tree-hole";
    shell = "${pkgs.shadow}/sbin/nologin";
  };

  # ── 持久目录 ──
  systemd.tmpfiles.rules = [
    "d /opt/tree-hole 0755 treehole treehole -"
    "d /etc/tree-hole 0755 root root -"
    "d /var/lib/tree-hole 0750 treehole treehole -"
  ];

  # ── 服务 ──
  systemd.services.tree-hole = {
    description = "Tree Hole Sites (Next.js standalone)";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      User = "treehole";
      Group = "treehole";
      WorkingDirectory = "/opt/tree-hole";
      EnvironmentFile = "/etc/tree-hole/tree-hole.env";
      ExecStart = "${pkgs.nodejs_22}/bin/node server.js";
      Restart = "always";
      RestartSec = 5;
      NoNewPrivileges = true;
      PrivateTmp = true;
    };
  };
}
