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

  networking.firewall.allowedTCPPorts = [ 443 8010 ];

  # tailscaled 走代理连协调服务器
  systemd.services.tailscaled.serviceConfig.Environment = [
    "HTTP_PROXY=http://127.0.0.1:35353"
    "HTTPS_PROXY=http://127.0.0.1:35353"
    "ALL_PROXY=socks5://127.0.0.1:35353"
  ];

  # derper 直跑 TLS（自签 IP 证书，不发 SNI），外部经 NAT 58010→8010 直连。
  # 覆盖 nixpkgs 默认 ExecStart：-certmode manual + hostname=IP 自动自签；
  # -http-port=-1 关闭默认 80 明文监听（DynamicUser 无 CAP_NET_BIND_SERVICE，绑 80 会 fatal 崩环）。
  systemd.services.tailscale-derper.serviceConfig.ExecStart = lib.mkForce (
    "${lib.getExe' config.services.tailscale.derper.package "derper"}"
    + " -a :8010 -c /var/lib/derper/derper.key -hostname=183.66.27.22 -stun-port 3478"
    + " -certmode manual -certdir /var/lib/derper -http-port=-1"
  );

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
          proxy_read_timeout 3600s;
        '';
      };
    };
  };
}
