# hosts/raiyun2/derper.nix — Tailscale DERP + 树洞反代（复制自 raiyun）
# 端口映射（雨云网关层转发，需在新机控制台对应配置）：公网 52443→443, 53478→3478
# 证书: 外部 ACME 分发客户端 → /opt/acmeDeliverClient/
{ config, lib, pkgs, ... }:
let
  certPath = "/opt/acmeDeliverClient/certs/xinlly.top_ecc";
in
{
  services.tailscale.derper = {
    enable = true;
    domain = "derp.ry.xinlly.top";
    port = 8010;              # DERP 内部端口，nginx 反代到它
    stunPort = 3478;          # 映射自公网 53478
    configureNginx = false;    # 禁用内置 nginx/Let's Encrypt（无公网 80/443）
    openFirewall = true;
  };

  networking.firewall.allowedTCPPorts = [ 443 ];

  # tailscaled 走代理连协调服务器；DERP 自有域名直连（NO_PROXY 放行）
  systemd.services.tailscaled.serviceConfig.Environment = [
    "HTTP_PROXY=http://127.0.0.1:35353"
    "HTTPS_PROXY=http://127.0.0.1:35353"
    "ALL_PROXY=socks5://127.0.0.1:35353"
    "NO_PROXY=xinlly.top,.xinlly.top,127.0.0.1,localhost"
  ];

  # derper 走 nixpkgs 默认：明文 HTTP:8010（hostname=derp.ry.xinlly.top），
  # TLS 由 nginx 用 hk 分发的 LE 证书在 443 终结后反代——与 raiyun 完全一致。

  services.nginx = {
    enable = true;

    # HSTS：浏览器经 https 访问一次后，对 *.ry.xinlly.top 永久强制 https，
    # 避免裸输域名发明文 HTTP 命中雨云网关的 307（→0.0.0.0）。
    commonHttpConfig = ''
      add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    '';

    # DERP — derp.ry.xinlly.top
    virtualHosts."derp.ry.xinlly.top" = {
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

    virtualHosts."mihomo.ry.xinlly.top" = {
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

    # 测试页 — test.ry.xinlly.top
    virtualHosts."test.ry.xinlly.top" = {
      onlySSL = true;
      listen = [{ port = 443; addr = "0.0.0.0"; ssl = true; }];
      sslCertificate = "${certPath}/fullchain.pem";
      sslCertificateKey = "${certPath}/key.pem";
      locations."/" = {
        return = "200 '<!DOCTYPE html><html><head><meta charset=utf-8><title>Test</title></head><body><h1>✅ TLS OK</h1><p>test.ry.xinlly.top | 证书正常</p></body></html>'";
        extraConfig = ''
          default_type text/html;
        '';
      };
    };

    # 树洞反代 — nginx → 本机 tree-hole 服务(127.0.0.1:3000)
    virtualHosts."treehole.ry.xinlly.top" = {
      onlySSL = true;
      listen = [{ port = 443; addr = "0.0.0.0"; ssl = true; }];
      sslCertificate = "${certPath}/fullchain.pem";
      sslCertificateKey = "${certPath}/key.pem";
      locations."/" = {
        proxyPass = "http://127.0.0.1:3000";
        proxyWebsockets = true;
        extraConfig = ''
          proxy_set_header Host              $host;
          proxy_set_header X-Forwarded-Proto $scheme;
          proxy_set_header X-Forwarded-Host  $http_host;
          proxy_read_timeout 3600s;
        '';
      };
    };
  };
}
