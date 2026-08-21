# hosts/wsl/default.nix — WSL2 变体：Hermes 全功能开发工作站
#
# 变体身份常量 + 模块聚合。新增云服务器变体时复制此文件改名即可。
{ config, lib, pkgs, ... }:
let
  # ═══════════════════════════════════════════════════════════
  # kdocs-cli — 金山文档官方 CLI（预编译二进制打包）
  # ═══════════════════════════════════════════════════════════
  # 从官方 CDN 下载预编译的 Node.js pkg 二进制。
  # 版本与 kdocs-skill v2.6.3 对应，升级时改 version + hash 即可。
  kdocs_cli = pkgs.stdenv.mkDerivation rec {
    pname = "kdocs-cli";
    version = "2.6.3";

    src = pkgs.fetchurl {
      url = "https://wpsai.wpscdn.cn/skillhub/pro/v${version}/releases/${pname}-${version}-linux-amd64.tar.gz";
      hash = "sha256-ByhrsjEH9IduMyJawJETZAYGinZjE72cTKxHyefIELk=";
    };

    dontBuild = true;
    dontStrip = true;
    doCheck = false;
    sourceRoot = ".";  # tar 是扁平的，没有顶层目录

    installPhase = ''
      mkdir -p $out/bin
      # 预编译二进制可能在 tar 根目录也可能在子目录，用 find 定位
      bin=$(find . -name kdocs-cli -type f | head -1)
      if [ -z "$bin" ]; then
        echo "ERROR: kdocs-cli binary not found in archive" >&2
        find . -type f | head -20 >&2
        exit 1
      fi
      cp "$bin" $out/bin/kdocs-cli
      chmod +x $out/bin/kdocs-cli
    '';

    meta = with lib; {
      description = "Kingsoft Docs official CLI — 金山文档命令行工具，支持智能文档/表格/PDF/多维表格等";
      homepage = "https://github.com/kdocs-app/kdocs-skill";
      license = licenses.unfree;
      mainProgram = "kdocs-cli";
      platforms = [ "x86_64-linux" ];
    };
  };

  # ═══════════════════════════════════════════════════════════
  # lark-cli — 官方飞书 CLI（buildGoModule 自建）
  # ═══════════════════════════════════════════════════════════
  # nixpkgs 中尚无此包，参照 nixos-hermes 的 linear-cli 模式自行打包。
  # 首次构建时 hash 会报错，按报错提示替换下方的 fakeHash 值。
  lark_cli = pkgs.buildGoModule rec {
    pname = "lark-cli";
    version = "1.0.85";

    src = pkgs.fetchFromGitHub {
      owner = "larksuite";
      repo = "cli";
      rev = "v${version}";
      hash = "sha256-NLSTxgIfHAzZ0PT2+zfKdOYSMFwmCWA26rQcD/WUnQ0=";
    };

    vendorHash = "sha256-WClES7ilNmQ0018Qf13tNHouE/SIwh99MaewZ7VGQ2E=";

    preBuild = ''
      export GOPROXY=https://goproxy.cn,https://goproxy.io,direct
    '';

    subPackages = [ "." ];

    ldflags = [
      "-s" "-w"
      "-X github.com/larksuite/cli/internal/build.Version=v${version}"
    ];

    postInstall = ''
      mv $out/bin/cli $out/bin/lark-cli
    '';

    meta = with lib; {
      description = "Official Lark/Feishu CLI tool — 200+ commands, 26 AI Agent Skills";
      homepage = "https://github.com/larksuite/cli";
      license = licenses.mit;
      mainProgram = "lark-cli";
    };
  };
in
{
  imports = [
    ../../common/base.nix
    ../../common/proxy.nix
    ./users.nix
    ./hermes.nix
  ];

  # ══ 主机身份 ══
  networking.hostName = "nixos";
  system.stateVersion = "26.05";

  # nix 源用清华镜像 + fallback 到官方源
  nix.settings.substituters = [
    "https://mirrors.tuna.tsinghua.edu.cn/nix-channels/store"
    "https://cache.nixos.org/"
  ];
  nix.settings.trusted-public-keys = [
    "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
  ];

  # 允许金山文档 kdocs-cli（专有二进制）
  nixpkgs.config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) [
    "kdocs-cli"
  ];

  # 限制编译时CPU使用
  nix.settings.max-jobs = 4;
  nix.settings.cores = 4;

  # WSL2 特性
  wsl.enable = true;
  wsl.defaultUser = "xavier";

  # WSL Interop — 隔离 Windows PATH + 持久化 binfmt 注册
  wsl.interop.register = true;                          # 显式注册 binfmt，允许执行 .exe
  wsl.interop.includePath = false;                       # NixOS 不注入 Windows 路径到 PATH
  wsl.wslConf.interop.appendWindowsPath = false;         # WSL 也不注入 Windows 路径

  # Podman 容器运行时
  virtualisation.podman = {
    enable = true;
    dockerCompat = true;
  };

  # WSL2 独有工具（Node.js、GitHub CLI、飞书 CLI）
  environment.systemPackages = with pkgs; [ nodejs_22 gh feishu-cli jq tcpdump openssl libreoffice poppler-utils ] ++ [ lark_cli kdocs_cli ];

  # Mihomo 代理 — 极简 systemd 服务
  # 不用 nixpkgs services.mihomo，避免 PrivateUsers/DynamicUser 沙箱冲突
  systemd.services.mihomo = {
    description = "Mihomo Proxy";
    after = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      User = "hermes";
      Group = "hermes";
      WorkingDirectory = "/var/lib/hermes/workspace/projects/our/mihomo";
      ExecStart = "${pkgs.mihomo}/bin/mihomo -d /var/lib/hermes/workspace/projects/our/mihomo -f /var/lib/hermes/workspace/projects/our/mihomo/config.yaml";
      Restart = "always";
      RestartSec = 5;
    };
  };
}
