# users.nix — 系统用户、SSH、sudo 权限配置
{ pkgs, ... }:
{
  # SSH: 允许密码登录，禁止 root
  services.openssh = {
    enable = true;
    ports = [ 2222 ];
    settings = {
      PasswordAuthentication = true;
      PermitRootLogin = "no";
    };
  };

  # 固定用户（不可变，NixOS 管理）
  users.mutableUsers = false;

  # 管理员账号 xavier — wheel + hermes 组
  users.users.xavier = {
    isNormalUser = true;
    description = "System Admin";
    home = "/home/xavier";
    createHome = true;
    homeMode = "700";
    hashedPassword = "$6$B7C84eutPivySsm7$TBHkj.e0NC9lDRPDsU/kzT.Rkl/i.uKaZuD2DIIoQwUE0LTO0uyq07JE62uA6Q8QSYFZAEF3XeLAgoexWnBc61";
    extraGroups = [ "wheel" "networkmanager" "hermes" ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJhH/o5wf7MrCd398BY/oKqYxQk63iOFxlidKaef1ZZk"
    ];
  };

  # Hermes Agent 运行账户已由 hermes-agent 模块定义，此处不需重复
  # 如需自定义 hermes 用户属性（如追加组），在 hermes.nix 中声明

  # Hermes Agent 内部 sudo 权限（podman 相关，免密）
  security.sudo.extraRules = [
    {
      users = [ "hermes" ];
      runAs = "ALL";
      commands = [
        { command = "/run/current-system/sw/bin/podman ps"; options = [ "NOPASSWD" ]; }
        { command = "/run/current-system/sw/bin/podman logs *"; options = [ "NOPASSWD" ]; }
      ];
    }
  ];

  # sudo 保留代理环境变量 — Nix 二进制缓存下载由 nix 客户端（非 daemon）负责
  # sudo 默认清除环境变量，导致客户端下载不走代理；env_keep 只放行代理变量
  security.sudo.extraConfig = ''
    Defaults env_keep += "http_proxy https_proxy HTTP_PROXY HTTPS_PROXY no_proxy NO_PROXY"
  '';
}
