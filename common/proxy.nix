{
  programs.bash.interactiveShellInit = ''
    # shell 代理
    set-proxy() {
      local port=''${1:-35353}
      local host=''${2:-127.0.0.1}
      export http_proxy=http://$host:$port
      export https_proxy=http://$host:$port
      export HTTP_PROXY=http://$host:$port
      export HTTPS_PROXY=http://$host:$port
      export no_proxy=localhost,127.0.0.1,::1,192.168.0.0/16,10.0.0.0/8,172.16.0.0/12
      export NO_PROXY=localhost,127.0.0.1,::1,192.168.0.0/16,10.0.0.0/8,172.16.0.0/12
      echo "✓ Shell 代理已开启: http://$host:$port"
    }
    unset-proxy() {
      unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY no_proxy NO_PROXY
      echo "✓ Shell 代理已关闭"
    }
    get-proxy() {
      echo "=== Shell 代理 ==="
      echo "HTTP_PROXY:  ''${HTTP_PROXY:-<未设置>}"
      echo "HTTPS_PROXY: ''${HTTPS_PROXY:-<未设置>}"
      echo "NO_PROXY:    ''${NO_PROXY:-<未设置>}"
    }
    # nix-daemon 代理
    set-nix-proxy() {
      local port=''${1:-35353}
      local host=''${2:-127.0.0.1}
      local conf="/run/systemd/system/nix-daemon.service.d/proxy.conf"
      sudo mkdir -p "$(dirname "$conf")"
      sudo tee "$conf" > /dev/null << EOF
[Service]
Environment="http_proxy=http://$host:$port"
Environment="https_proxy=http://$host:$port"
Environment="no_proxy=localhost,127.0.0.1,::1,192.168.0.0/16,10.0.0.0/8,172.16.0.0/12"
Environment="HTTP_PROXY=http://$host:$port"
Environment="HTTPS_PROXY=http://$host:$port"
Environment="NO_PROXY=localhost,127.0.0.1,::1,192.168.0.0/16,10.0.0.0/8,172.16.0.0/12"
EOF
      sudo systemctl daemon-reload
      sudo systemctl restart nix-daemon
      echo "✓ nix-daemon 代理已开启: http://$host:$port"
    }
    unset-nix-proxy() {
      local conf="/run/systemd/system/nix-daemon.service.d/proxy.conf"
      sudo rm -f "$conf"
      sudo systemctl daemon-reload
      sudo systemctl restart nix-daemon
      echo "✓ nix-daemon 代理已关闭"
    }
    get-nix-proxy() {
      echo "=== nix-daemon 代理 ==="
      local envs=$(sudo cat /proc/$(pidof nix-daemon)/environ 2>/dev/null | tr '\0' '\n' | grep -i proxy)
      if [ -n "$envs" ]; then
        echo "$envs"
      else
        echo "<未配置>"
      fi
    }
  '';
}
