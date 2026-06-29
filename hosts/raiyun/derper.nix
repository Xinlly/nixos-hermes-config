# hosts/raiyun/derper.nix — Tailscale DERP 中继（仅雨云）
# 端口映射: 公网 52443→443, 53478→3478（雨云网关层转发）
# 证书: 外部 ACME 分发客户端 → /opt/acmeDeliverClient/
{ config, lib, ... }:
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
  };
}
