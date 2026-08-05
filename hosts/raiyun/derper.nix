# hosts/raiyun/derper.nix — Tailscale DERP + 树洞反代（仅雨云）
# 端口映射: 公网 52443→443, 53478→3478（雨云网关层转发）
# 证书: 外部 ACME 分发客户端 → /opt/acmeDeliverClient/
{ config, lib, pkgs, ... }:
let
  certPath = "/opt/acmeDeliverClient/certs/xinlly.top_ecc";
in
{
  services.tailscale.derper = {
    enable = true;
    domain = "derp.cn.xinlly.top";
    port = 8010;              # DERP 内部端口，nginx 反代到它
    stunPort = 3478;          # 映射自公网 53478
    configureNginx = false;    # 禁用内置 nginx/Let's Encrypt（无公网 80/443）
    openFirewall = true;
  };

  networking.firewall.allowedTCPPorts = [ 443 ];

  # tailscaled 走代理连协调服务器
  systemd.services.tailscaled.serviceConfig.Environment = [
    "HTTP_PROXY=http://127.0.0.1:35353"
    "HTTPS_PROXY=http://127.0.0.1:35353"
    "ALL_PROXY=socks5://127.0.0.1:35353"
  ];

  services.nginx = {
    enable = true;

    # DERP — derp.cn.xinlly.top
    virtualHosts."derp.cn.xinlly.top" = {
      onlySSL = true;
      listen = [{ port = 443; addr = "0.0.0.0"; ssl = true; }];
      sslCertificate = "${certPath}/fullchain.pem";
      sslCertificateKey = "${certPath}/key.pem";
      locations."/" = {
        proxyPass = "http://127.0.0.1:8010";
        proxyWebsockets = true;
        extraConfig = ''
          proxy_buffering off;
          proxy_read_timeout 3600s;
        '';
      };
    };

    virtualHosts."mihomo.cn.xinlly.top" = {
      onlySSL = true;
      listen = [{ port = 443; addr = "0.0.0.0"; ssl = true; }];
      sslCertificate = "${certPath}/fullchain.pem";
      sslCertificateKey = "${certPath}/key.pem";
      locations."/" = {
        proxyPass = "http://127.0.0.1:9090";
        proxyWebsockets = true;
        extraConfig = ''
          proxy_buffering off;
          proxy_read_timeout 3600s;
        '';
      };
    };

    # 测试页 — test.cn.xinlly.top
    virtualHosts."test.cn.xinlly.top" = {
      onlySSL = true;
      listen = [{ port = 443; addr = "0.0.0.0"; ssl = true; }];
      sslCertificate = "${certPath}/fullchain.pem";
      sslCertificateKey = "${certPath}/key.pem";
      locations."/" = {
        return = "200 '<!DOCTYPE html><html><head><meta charset=utf-8><title>Test</title></head><body><h1>✅ TLS OK</h1><p>test.cn.xinlly.top | 证书正常</p></body></html>'";
        extraConfig = ''
          default_type text/html;
        '';
      };
    };

    # 树洞反代 — nginx → socat(localhost:18080) → SOCKS5 → 目标
    virtualHosts."treehole.cn.xinlly.top" = {
      onlySSL = true;
      listen = [{ port = 443; addr = "0.0.0.0"; ssl = true; }];
      sslCertificate = "${certPath}/fullchain.pem";
      sslCertificateKey = "${certPath}/key.pem";
      locations."/" = {
        proxyPass = "https://127.0.0.1:18080";
        proxyWebsockets = true;
        extraConfig = ''
          proxy_ssl_verify off;
          proxy_ssl_server_name on;
          proxy_ssl_name personal-tree-hole.blowout44-juicerzmco.chatgpt.site;
          proxy_set_header Host personal-tree-hole.blowout44-juicerzmco.chatgpt.site;
        '';
      };
    };
  };

  # socat 转发：localhost:18080 → 目标:443，走 SOCKS5 代理
  systemd.services.treehole-socat = {
    description = "Tree Hole socat forwarder via SOCKS5";
    after = [ "network.target" "mihomo.service" ];
    wants = [ "mihomo.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      User = "root";
      ExecStart = toString [
        "${pkgs.socat}/bin/socat"
        "TCP4-LISTEN:18080,reuseaddr,fork"
        "SOCKS5:127.0.0.1:personal-tree-hole.blowout44-juicerzmco.chatgpt.site:443,socksport=35353"
      ];
      Restart = "always";
      RestartSec = 10;
    };
  };
}
