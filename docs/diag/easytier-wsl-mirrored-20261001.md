# EasyTier → WSL2(Mirrored) 入站不可达诊断报告

- 日期：2026-10-01
- 报告人：Dora（Hermes Agent, xavier 的工程助手）
- 性质：**只读诊断**。未改任何配置、未重启/杀进程、未安装软件。
- 执行环境：WSL(NixOS 6.18.33 WSL2) 本机 + Windows 宿主 PowerShell（只读）+ EasyTier 另一节点 ubuntu-test(192.168.0.183 / 10.144.144.11)
- 取证脚本（可复跑，均在本目录）：`.win-diag.ps1`、`.win-diag2.ps1`、`.win-test.ps1`、`.win-cfg.ps1`

---

## 一句话结论

**根因是 WSL2 Mirrored 模式下的 Hyper-V 防火墙：对 WSL 虚拟机默认 `DefaultInboundAction=Block`，WSL creator 入站只放行了 ICMP 与 mDNS，没有任何 TCP 端口规则——所以外部（EasyTier/LAN）到 Windows 宿主服务（RDP 等）走 Windows 网络栈可达，而同地址进入 WSL 的 TCP SYN 在 vSwitch 边界被丢弃；宿主 loopback→WSL 因 `LoopbackEnabled=True` 仍直通。** 置信度约 90%。监听地址、rp_filter、WSL 本机防火墙均已排除。

---

## 1. EasyTier 拓扑取证

### 1.1 WSL 内没有 EasyTier 节点

```
$ pgrep -af easytier
（仅匹配到执行命令的 shell 自身，无 easytier-core）
```

### 1.2 真正的节点在 Windows：easytier-gui（内嵌 core）

```
PID=17156 NAME=easytier-gui.exe
（easytier-core.exe 无独立进程 —— GUI 内嵌运行 core）
监听端口（Get-NetTCPConnection）:
  0.0.0.0:11010  PID=17156  easytier-gui   ← EasyTier listener
  [::]:11010     PID=17156  easytier-gui
  0.0.0.0:3389   svchost                    ← Windows RDP
```

Windows wintun 虚拟网卡（EasyTier）：

```
Name       InterfaceDescription   Status
et_8_pvnr  et_8_pvnr Tunnel       Up

IPv4: 10.144.144.3/24   （接口 et_8_pvnr）
路由: 10.144.144.0/24 → et_8_pvnr (on-link, RouteMetric 256)
配置文件: Private
```

> 注意：`C:\EasyTier\start-node.ps1`（独立 CLI 方案）里写的虚拟 IP 是 **10.144.144.11**，但当前实际在跑的是 GUI，节点 vIP 为 **10.144.144.3**。两套方案并存，以实测 .3 为准。`start-node.ps1` 的 peer 为 `tcp://183.66.27.22:51010`（公网 relay）。

### 1.3 EasyTier 另一节点 ubuntu-test（外部对照源）

```
$ hostname; ip -br addr | grep -E 'tun|10.144'
Ubuntu-Test
tun0  UNKNOWN  10.144.144.11/24
$ pgrep -af easytier-core
3150 ./easytier-core --network-name xinlly-mesh -i 10.144.144.11 -p tcp://183.66.27.22:51010
```

### 1.4 手机访问"宿主服务"时的目标 IP（含不确定性）

- EasyTier 网络中本机（Windows 节点）虚拟 IP = **10.144.144.3**。
- 实测从 ubuntu-test 经 EasyTier 访问 `10.144.144.3:3389` = **OPEN**（见 §6），证明"经 EasyTier → 宿主 RDP"这条路径成立，手机大概率用的就是 `10.144.144.3`。
- `[UNCERTAIN]` 无法直接从手机取连接记录；若手机用的是 LAN IP `192.168.0.205`（手机与宿主同局域网时），则流量不经 EasyTier。但 §6 显示两条目标路径结果完全一致，**不影响根因结论**。

---

## 2. WSL 网络模式与接口 —— 判定为 Mirrored

### 2.1 .wslconfig（实据）

`/mnt/c/Users/Admin0/.wslconfig`：

```ini
[wsl2]                    # 第1行
networkingMode=Mirrored   # 第2行
memory=21474836480        # 第3行
swap=0                    # 第4行
processors=16             # 第5行
```

**无任何 `networkingModeToggles` / `ignoreLoopback` 等附加项** → mirrored 全部采用系统默认行为（含默认启用的 Hyper-V 防火墙）。

### 2.2 接口地址（Mirrored 的镜像特征）

```
$ ip -br addr
lo        UNKNOWN  127.0.0.1/8  10.255.255.254/32
eth0      DOWN
eth1      UP       192.168.0.205/24        ← 镜像 Windows「以太网」(同 IP)
loopback0 UP
eth2      UP       100.104.108.126/32      ← 镜像 Tailscale
eth3      UP       172.30.215.118/32       ← 镜像 vgate0 (Rust Wintun)
eth4      UP       10.144.144.3/24         ← 镜像 EasyTier et_8_pvnr (同 IP)
```

Windows 侧对应地址：`以太网=192.168.0.205`、`Tailscale=100.104.108.126`、`vgate0=172.30.215.118`、`et_8_pvnr=10.144.144.3`——逐一对应，是 mirrored 模式的确凿特征。

### 2.3 路由 / 策略路由

```
$ ip route
default via 192.168.0.1 dev eth1
10.144.144.0/24 dev eth4 proto kernel scope link
192.168.0.0/24 dev eth1 proto kernel scope link
（eth2 上为对端 /32 的 Tailscale 点对点路由）

$ ip rule
0: from all iif eth0/eth1/loopback0/eth2/eth3/eth4 ipproto tcp/udp lookup local
1: from all ipproto tcp/udp lookup 127
1: from all ipproto tcp/udp lookup 128
2: from all lookup local
32766: from all lookup main
32767: from all lookup default
```

多条 `iif ... lookup local` 是 mirrored 模式为让各镜像接口本地 socket 可达而注入的策略规则。

### 2.4 DNS

```
$ cat /etc/resolv.conf
nameserver 10.255.255.254          ← mirrored DNS 中继地址
search qilin-stargazer.ts.net
```

---

## 3. WSL 内服务监听（ss -tlnp）

```
LISTEN 127.0.0.1:43311   Paseo Daemon        ← 仅本机
LISTEN 0.0.0.0:2222                          ← sshd，全网卡（含 [::]:2222）
LISTEN 127.0.0.1:8642    hermes              ← 仅本机
LISTEN 0.0.0.0:6767      Paseo Daemon        ← 全网卡
LISTEN 10.255.255.254:53                     ← WSL DNS
LISTEN 0.0.0.0:8888                          ← 全网卡
LISTEN 0.0.0.0:9999                          ← 全网卡
LISTEN 127.0.0.1:8080    python3.13          ← 仅本机
LISTEN 127.0.0.1:5432                        ← postgres，仅本机
LISTEN *:35353 / *:9090   mihomo
```

要点：

- **SSH 只监听 2222（0.0.0.0 + ::），根本没有监听 22**。声明见 `hosts/wsl/users.nix:7 ports = [ 2222 ];`。xavier 现象中的"22/2222"需修正：连 22 必然失败（无服务），连 2222 失败则另有原因（防火墙，见后）。
- 2222/6767/8888/9999 均绑 `0.0.0.0`，**监听地址不构成外部不可达的原因**。
- 8642/8080/5432 仅绑 127.0.0.1，外部本就不可达（这些不在本次申诉范围）。

---

## 4. 防火墙两侧取证

### 4.1 WSL/NixOS 侧：防火墙未启用

```
$ systemctl cat firewall
# Unit firewall.service is masked.
$ systemctl is-active firewall
inactive
$ readlink -f /etc/systemd/system/firewall.service
/dev/null
$ cat /proc/net/ip_tables_names        ← 空（无任何表）
$ nft list ruleset
bash: nft: command not found
```

`hosts/wsl/default.nix` 与 `common/base.nix` 中**均无 `networking.firewall` 配置**，且生成的系统把 firewall 单元 mask 到 /dev/null（WSL 变体行为）。**WSL 内无 netfilter 规则阻断入站**，此因素排除。

### 4.2 Windows 常规防火墙：开启，但管的是 Windows 本机 socket

```
Get-NetFirewallProfile:
Name    Enabled  DefaultInboundAction
Domain  True     NotConfigured      ← NotConfigured = 生效默认值 Block，靠 allow 规则
Private True     NotConfigured
Public  True     NotConfigured
```

RDP(3389) 等 Windows 服务由常规防火墙的内置 allow 规则放行，故外部可达。

### 4.3 ★ Hyper-V 防火墙（Mirrored 模式下管控 WSL 入站）—— 关键证据

**配置态（ConfigurablePolicyStore 默认值）：**

```
Get-NetFirewallHyperVVMSetting:
Enabled=NotConfigured  DefaultInboundAction=NotConfigured  LoopbackEnabled=NotConfigured
```

**生效态（ActiveStore，实际执行的策略）：**

```
Get-NetFirewallHyperVVMSetting -PolicyStore ActiveStore:
Name                  : {40E0AC32-46A5-438A-A0B2-2B479E8F2E90}   ← WSL creator
Enabled               : True
DefaultInboundAction  : Block      ★
DefaultOutboundAction : Allow
LoopbackEnabled       : True       ★（宿主 loopback→WSL 放行）

VMCreator: FriendlyName = "WSL", VMCreatorId = {40E0AC32-...}
```

**WSL creator 的入站 allow 规则全量（共 152 条规则中仅以下 4 条针对 WSL 且为 Allow）：**

```
WslCore Inbound ICMPv4 Default Allow Rule   Allow  {WSL creator}
WslCore Inbound ICMPv6 Default Allow Rule   Allow  {WSL creator}
WslCore Inbound IPv4 mDNS Default Allow Rule Allow {WSL creator}
WslCore Inbound IPv6 mDNS Default Allow Rule Allow {WSL creator}
```

另有 `MPSSVC Default Rule ... Block {WSL creator}`。

**结论：进入 WSL 的入站 TCP/UDP（除 mDNS 5353）默认全部 Block；ICMP 放行。** 这与实测"ping 通、TCP 全超时"精确吻合。

官方依据（web 取证，2026-10-01）：

- Microsoft Learn《Accessing network applications with WSL》：mirrored 模式需用 Hyper-V 防火墙放行 WSL 入站，示例 `Set-NetFirewallHyperVVMSetting -Name '{40E0AC32-...}' -DefaultInboundAction Allow`。
  https://learn.microsoft.com/en-us/windows/wsl/networking
- Microsoft Learn《Hyper-V Firewall》：用 `New-NetFirewallHyperVRule` 为 WSL 建端口级入站规则。
  https://learn.microsoft.com/en-us/windows/security/operating-system-security/network-security/windows-firewall/hyper-v-firewall

---

## 5. 反向路径过滤 / 转发

```
$ sysctl net.ipv4.conf.all.rp_filter net.ipv4.conf.default.rp_filter net.ipv4.ip_forward
net.ipv4.conf.all.rp_filter = 0        ← 全接口关闭（all 与 per-if 取或逻辑，all=0 即宽松）
net.ipv4.conf.default.rp_filter = 2
net.ipv4.ip_forward = 0                ← WSL 不做转发（本次流量目标是 WSL 本地 socket，无需 forward）

per-interface rp_filter：eth1/eth2/eth3/eth4 = 2 (loose)，loopback0=0
```

- `rp_filter(all)=0` 不会丢弃从 tun/镜像接口入站的包；且外部 **ICMP ping 正常返回**，证明入站/回程路由完好，仅 TCP 数据面被 §4.3 的防火墙丢弃。**rp_filter/路由因素排除。**
- `ip_forward=0` 无影响：手机的目标是 WSL 本机 socket，不是经 WSL 转发。

---

## 6. 分层对照测试（每条含命令与结果）

| # | 源 | 目标 | 结果 |
|---|----|------|------|
| 1 | WSL | 127.0.0.1:{2222,6767,8888,9999} | **全部 OPEN**（`/dev/tcp`，exit 0） |
| 2 | WSL | 10.144.144.3:2222 | **OPEN**（本地经镜像回环） |
| 3 | WSL | 10.144.144.3:6767 | **OPEN** |
| 4 | WSL | 10.144.144.3:3389 | CLOSED（WSL 内无 RDP，符合预期） |
| 5 | WSL | 192.168.0.205:{2222,6767} | **OPEN**（本地回环） |
| 6 | WSL | ping 10.144.144.3 | 0% loss, rtt 0.05ms |
| 7 | **Windows** | **10.144.144.3:3389** | **OPEN**（Windows 本机 RDP） |
| 8 | **Windows** | **10.144.144.3:{2222,6767,8888,9999}** | **全部 TIMEOUT**（TcpClient 2.5s） |
| 9 | **Windows** | **192.168.0.205:{2222,6767}** | **全部 TIMEOUT** |
| 10 | Windows | 127.0.0.1:2222 | **OPEN**（mirrored loopback 直通 WSL） |
| 11 | **ubuntu-test** (10.144.144.11) | ping 10.144.144.3 | **0% loss**, rtt 1.4ms |
| 12 | **ubuntu-test** | 10.144.144.3:**3389** | **OPEN**（经 EasyTier 到 Windows RDP） |
| 13 | **ubuntu-test** | 10.144.144.3:{**2222,6767**} | **CLOSED/timeout** |
| 14 | **ubuntu-test** | 192.168.0.205:3389 | **OPEN** |
| 15 | **ubuntu-test** | 192.168.0.205:{2222,6767} | **CLOSED/timeout** |

命令例（#12–15，在 ubuntu-test 执行）：

```bash
for p in 3389 2222 6767; do
  timeout 3 bash -c "echo > /dev/tcp/10.144.144.3/$p" && echo "vIP:$p OPEN" || echo "vIP:$p CLOSED"
done
# vIP:3389 OPEN / vIP:2222 CLOSED / vIP:6767 CLOSED
```

### 关键判读

- **同一目标 IP `10.144.144.3`，端口 3389 OPEN、2222 TIMEOUT**：区别只在监听者属于 Windows 还是 WSL —— 流量到达 Windows 后，去 Windows socket 走常规栈放行，去 WSL 须穿 vSwitch，被 Hyper-V 防火墙 Block。
- **Windows→127.0.0.1:2222 OPEN，但外部→10.144.144.3:2222 BLOCKED**：差异正是 `LoopbackEnabled=True`（回环路径放行）与外部入站默认 Block。
- WSL 本机经 vIP/LAN IP 自访 OPEN（#2–5）：因流量是本机发起、走镜像回环，不经过"外部入站"管控面。

---

## 7. 数据流图

```
手机 (EasyTier 客户端)
  │  目标 10.144.144.3:3389 / :2222
  ▼
EasyTier 公网 relay 183.66.27.22:51010
  │
  ▼
Windows 宿主 wintun: et_8_pvnr (10.144.144.3/24)
  │
  ├─► :3389  Windows 网络栈 → RDP socket
  │         常规防火墙有 RDP allow 规则            ★ 可达
  │
  └─► :2222  需穿 Hyper-V vSwitch 进入 WSL VM
            Hyper-V 防火墙 (WSL creator):
              Enabled=True, DefaultInboundAction=Block
              仅 ICMP/mDNS allow，无 TCP 规则        ✗ SYN 被丢弃
                                                        不可达

宿主自身 127.0.0.1:2222 ──LoopbackEnabled=True──► WSL sshd   ★ 可达
```

---

## 8. 根因排序（含置信度）

| 排序 | 类别 | 结论 | 置信度 | 主要证据 |
|------|------|------|--------|----------|
| 1 | **③ Mirrored 模式对 WSL 入站的限制（Hyper-V 防火墙默认 Block）** | **根因** | **~90%** | ActiveStore Enabled=True/Inbound=Block；WSL creator 仅 ICMP+mDNS allow；外部两路径 TCP 全 timeout、ICMP 通；loopback 直通 OPEN；同 IP 的 RDP OPEN。 |
| 2 | ② 常规 Windows 防火墙二次过滤 | 可能叠加，但非主因 | ~5% | `[UNCERTAIN]` Hyper-V 放开后，转发入 WSL 的包是否再经常规 profile 过滤，需在修复时一并验证。 |
| 3 | ① 服务监听地址 | **已排除** | —— | sshd 等绑 0.0.0.0（§3）；但注意**无 22 端口**，仅 2222。 |
| 4 | ④ EasyTier tun 入站 / rp_filter / 路由 | **已排除** | —— | rp_filter(all)=0；外部 ping 正常、RDP 同路径可达，路由与隧道完好。 |

---

## 9. 待批准修复建议（本次一律未执行）

### 方案 A（推荐）：端口级 Hyper-V 入站放行 —— 最小暴露

Windows **管理员** PowerShell 执行（每个需要的端口一条）：

```powershell
New-NetFirewallHyperVRule -Name "WSL-SSH2222" -DisplayName "WSL SSH 2222" `
  -Direction Inbound -VMCreatorId '{40E0AC32-46A5-438A-A0B2-2B479E8F2E90}' `
  -Protocol TCP -LocalPorts 2222 -Action Allow
# 如需：-LocalPorts 8888 / 9999 / 6767 分别建规则
```

- 所需权限：**Windows 管理员**（xavier 在管理员 PowerShell 直接执行；或我拟好 .ps1 由管理员运行）。**无需改 NixOS 声明式，无需 sudo。**
- 影响面：仅 WSL VM 对指定 TCP 端口入站放行，对 Windows 本机服务无影响；所有网卡（含 EasyTier/LAN）均可达这些端口。如需限制来源，可加 `-LocalAddresses`/按接口收敛（Hyper-V 规则支持的匹配项有限，来源限制能力 `[UNCERTAIN]`，需实测）。
- 验证：在 ubuntu-test 跑 `timeout 3 bash -c "echo >/dev/tcp/10.144.144.3/2222" && echo OPEN`；手机复测。
- 回滚：`Remove-NetFirewallHyperVRule -Name "WSL-SSH2222"`（即时生效）。

### 方案 B（不推荐）：WSL 入站整体放行

```powershell
Set-NetFirewallHyperVVMSetting -Name '{40E0AC32-46A5-438A-A0B2-2B479E8F2E90}' -DefaultInboundAction Allow
```

- 影响面：WSL 内**所有**监听端口对全部网络暴露（含仅绑 0.0.0.0 的 8888/9999 等），攻击面大。
- 回滚：`... -DefaultInboundAction Block`。
- 仅适合临时调试，用后即恢复。

### 方案 C：.wslconfig 关闭 Hyper-V 防火墙（影响最大，需重启 WSL）

在 `/mnt/c/Users/Admin0/.wslconfig` 的 `[wsl2]` 下加 `firewall=false`（较新版本 WSL 支持的开关）。

- `[UNCERTAIN]` 需先 `wsl --version` 确认本机 WSL 支持该键（微软较新 WSL 版本提供；我未在只读任务中变更）。
- 前置/后果：需 `wsl --shutdown` 才生效，**会中断当前 WSL 全部进程（含 Hermes、Paseo、mihomo）**——属需明确批准的 CRITICAL 级动作。
- 影响面：等价于方案 B 且全局关闭，不建议。
- 回滚：删除该行 → `wsl --shutdown` 重启。

### 方案 D（仅当需要 22 端口时）：让 sshd 同时监听 22

改 `hosts/wsl/users.nix:7` 为 `ports = [ 22 2222 ];`，经 NixOS 声明式重建（需 sudo/electerm 流程）。

- 注意：22 放行后**仍受方案 A 的 Hyper-V 入站 Block 约束**，必须同时对 22 建 Hyper-V allow 规则。
- 影响面：WSL sshd 增加监听端口。回滚：改回 `[ 2222 ]` 重建。

### 建议执行顺序

1. 先做 **方案 A**（仅放行确实需要的 2222 及各 web 端口）→ ubuntu-test + 手机双重验证。
2. 若方案 A 后仍不通，再取证排查 §8 排序 2（常规防火墙叠加），不预先扩大放行。
3. 确有 22 需求时再做方案 D。

---

## 10. 未验证项 / 不确定性清单

- `[UNCERTAIN]` 手机侧实际目标 IP 与连接记录无法直接读取（推断为 10.144.144.3；两路径实测结果一致，不影响结论）。
- `[UNCERTAIN]` easytier-gui 的节点配置文件位置未找到明文（仅见 WebView2 缓存）；节点 vIP 以 `et_8_pvnr=10.144.144.3` 实测为准。
- `[UNCERTAIN]` Hyper-V 防火墙放行后，常规 Windows 防火墙是否对"进入 WSL 的转发流量"二次过滤，需在方案 A 落地时实测。
- `[UNCERTAIN]` `.wslconfig` 的 `firewall` 键需匹配本机 WSL 版本，未做版本核实与变更。
- 本次未执行任何修改；以上修复建议均待 xavier 批准后实施。
