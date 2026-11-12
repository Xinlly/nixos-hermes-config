# 多节点异地组网备选方案调研报告（EasyTier / Tailscale 之外）

- 调研日期：2026-09-27
- 调研者：Dora（独立只读 researcher，三路 worker 协助取证，主报告人逐条复核一手来源）
- 状态：**调研完成（仅文档结论，未部署、未改任何配置）**
- 一手明细：worker 原始报告见 `research/worker-a.md`、`research/worker-b.md`、`research/worker-c.md`；任务书 `research/task-worker-{a,b,c}.md`

---

## 1. 背景与硬约束

- 现状：Tailscale 已在用；自建 DERP 在雨云**共享 NAT VPS** 上受阻。EasyTier 由另一条线评估，**本报告不碰这两条线**。
- 硬约束（决定一切）：中继机
  - 公网**入站 UDP 不可用**（运营商/共享 NAT 不映射 UDP，外部主动 UDP 打不进来）；
  - 公网**入站 TCP 可用**（外部可主动连入 TCP 端口）；
  - 出站 TCP/UDP 均正常。
- 客户端：Windows 宿主机（江苏移动出口）、NixOS（含 raiyun/raiyun2），出站均正常。
- 目标：让国内多节点之间获得可靠的 IP 层异地互联/中继，且与现有 Tailscale 可共存。

**因此真正要回答的问题只有一个：哪些方案能让一台「仅公网入站 TCP 可用」的机器，充当有效的组网中继/接入节点？**

---

## 2. TL;DR（结论速览）

**最值得试的前三名（排序与理由见 §7，最小落地思路见 §8）：**

1. **ZeroTier + 自建 `pylon reflect` TCP 中继**（控制面先用官方 Central 免费版）——最快验证、Windows/NixOS 客户端最成熟、中继只需入站 TCP/443，且这是官方专门为此设计的组件。代价：官方明言 TCP 中继慢；自建 controller 有许可证门槛。
2. **NetBird 自建（management + signal + relay）**——WireGuard 内核直连优先，relay 自带 **WebSocket/TCP 自动回退**（官方文档明确「UDP 关了 WebSocket 照样扛，不报错」），NixOS 有 `services.netbird` 模块。代价：自建组件多、要域名/Docker、relay 等服务端组件为 AGPL-3.0。
3. **SoftEther VPN（中心 VPN Server + SecureNAT，纯 TCP listener）**——最传统稳妥的纯 TCP 中心 VPN，默认监听 443/992/5555 全是 TCP，完全不依赖入站 UDP，Windows 官方客户端+GUI 成熟。代价：中心辐射而非 mesh、概念重。

**一个需要交还 Tailscale 线核实的重大附带发现（§6.4）：** DERP 中继的**数据面本身就是 HTTPS/TCP 443**；UDP/3478 只是一个**可 `--stun=false` 关闭**的附属 STUN。源码与官方手册均如此。也就是说「自建 DERP 受阻于 UDP」很可能只卡在那个**可选 STUN / netcheck 调度**上，而**中继承载本来就不需要入站 UDP**。这可能影响既有判断，但因属 Tailscale 线，本报告只记录证据、不改动。

**直接排除（对本硬约束无效）：** Nebula（underlay 纯 UDP，2026-05 官方仍确认无 TCP）。
N2N 不作主力但需精确说明：dev 版 supernode 在 **Linux** 上有**实验性辅助 TCP 监听**（源码 `#ifdef N2N_HAVE_TCP`），edge 可 `-S2` 走 TCP；但该能力未进正式 manpage、Windows 构建被 `#undef`、federation 仍走 UDP，成熟度存疑（详见 §6.5）。

---

## 3. 先分清三类东西（避免选错）

| 类别 | 形态 | 能否多节点 IP 互通 | 代表 |
|---|---|---|---|
| A. IP 层组网 / overlay | 给每台机一个虚拟 IP，像在同一内网 | ✅ 本报告主战场 | ZeroTier、NetBird、Netmaker、Nebula、Tinc、N2N、SoftEther、OpenVPN、headscale |
| B. 端口隧道 / 反向代理 | 把内网某台的**某个端口**映射到公网 | ❌ 一般只做点到点端口暴露，不发虚拟 IP | frp、rathole、NPS、Cloudflare Tunnel |
| C. WireGuard-over-TCP 封装 | 把 WG 的 UDP 用「伪 TCP / WebSocket」承载 | ⚠️ 间接：本质是让「需 UDP」的方案能走 TCP | udp2raw、phantun、wstunnel |

> 关键：B 类**不是 IP 组网**，不能直接解决「多节点像在同一内网」。frp 的 `xtcp` 虽叫 P2P，但官方 README 明确「may not work with all types of NAT devices」，且其打洞仍走 UDP，对「双方对称 NAT / 入站 UDP 全封」不可靠。

---

## 4. 方案总清单

| # | 方案 | 类别 | 一句话 |
|---|---|---|---|
| 1 | ZeroTier（+pylon reflect） | A | 老牌 mesh，现官方提供 TCP/443 中继 |
| 2 | NetBird | A | WG + ICE，relay 有 QUIC/WebSocket 双栈 |
| 3 | Netmaker | A | WG 自动化，v1.7.0(2026-08) 才加 WSS/TCP uplink |
| 4 | headscale | A(仅控制面) | 开源 Tailscale 控制面，内嵌 DERP；本质属 Tailscale 线 |
| 5 | Nebula | A | Slack 出品，纯 UDP，无 TCP |
| 6 | Tinc | A | 老牌 mesh，`TCPonly=yes` 可纯 TCP |
| 7 | N2N | A | supernode/edge，正式走 UDP；dev 版 Linux 有实验性 TCP 辅助口 |
| 8 | SoftEther | A | 中心 VPN，listener 全 TCP，含 SecureNAT |
| 9 | OpenVPN(TCP) | A | 成熟，`proto tcp`+`client-to-client` |
| 10 | frp | B | 最流行端口反向代理 |
| 11 | rathole | B | Rust 高性能端口隧道 |
| 12 | NPS | B | 带 Web 面板的端口隧道，低活跃 |
| 13 | Cloudflare Tunnel | B | 依赖 CF 边缘+域名+WARP |
| 14 | 蒲公英/贝锐 | A(商业) | 国产 SD-WAN，免费版有限制 |
| 15 | udp2raw | C | raw socket 伪 TCP，需 root |
| 16 | phantun | C | userspace 伪 TCP（TUN），多线程 |
| 17 | wstunnel | C | WebSocket 隧道，可承载 UDP/WG |

---

## 5. 逐维度对比总表

> 「TCP 中继可行」= 该方案能否让**仅入站 TCP** 的机器当中继/接入点（本报告的命门）。NixOS 模块/包均以 nixpkgs `nixos-unstable` 2026-09-27 实测 HTTP 200 为准。

| 方案 | 组网模型 | 数据面 / 传输 | 公网入站 UDP 依赖 | **TCP 中继可行** | 自建中继 | NixOS | Windows 客户端 | 许可证 | 成熟度/生态 | 与 Tailscale 共存 |
|---|---|---|---|---|---|---|---|---|---|---|
| **ZeroTier** | mesh+中继 | VL1，UDP9993；**TCP relay HTTPS/443** | 直连要 UDP，中继不要 | ✅ pylon reflect，仅 TCP443 | ✅ | 包`zerotierone`；模块 `services.zerotierOne` | 官方安装包 | 客户端/中继 **MPL-2.0**；**controller 2025 起 source-available 仅非商业** | 高（v1.16.2，17k★） | ✅ 独立网卡网段 |
| **NetBird** | mesh+中继 | WG；relay **QUIC(UDP)+WebSocket(TCP)** 竞速 | 直连要 UDP，中继不要 | ✅ WSS/TCP443，自动回退 | ✅ | 包 + 模块 `services.netbird` | 官方客户端 | 客户端 **BSD-3**；**relay/management/signal/combined 为 AGPL-3.0** | 高（活跃） | ✅ 独立 WG 网卡 |
| **Netmaker** | mesh+网关 | WG/UDP；**v1.7.0 起 WSS/TCP uplink** | v1.7.0 前必须；之后网关可仅 TCP443 | ✅(2026-08 起，特性极新) | ✅ | **nixpkgs 无包无模块** | netclient/Desktop | 核心 Apache-2.0；`pro/` 商业 | 中高（11.8k★） | ✅ |
| **headscale** | 仅控制面 | 数据面仍是 tailscale 客户端 WG；内嵌 DERP | 本体不要；DERP 的 STUN 可选 UDP | ✅ DERP 中继 TCP443 | ✅(内嵌/独立 derper) | 包 + 模块 `services.headscale` | **用官方 Tailscale 客户端** | BSD-3 | 高（44k★，v0.29.4） | ⚠️ 它就是 Tailscale 控制面，非并行 |
| **Nebula** | mesh+lighthouse | **纯 UDP** 4242 | 必须 | ❌ | relay 也是 UDP | 包 + 模块 `services.nebula` | 官方二进制 | MIT | 高（18k★，活跃） | ✅ |
| **Tinc** | mesh | UDP 默认；**`TCPonly=yes`** | TCPonly 后不要 | ✅ TCP（meta 连接承载数据） | 任何节点可转发 | 包 + 模块 `services.tinc` | MinGW+tap64，体验老 | GPL-2.0-or-later | 中（1.1 仍 pre，2.2k★） | ✅ |
| **N2N** | supernode/edge | UDP 默认；**dev 版 Linux supernode 有实验性 TCP 辅助口**，edge `-S2` | 正式路径要 UDP | ⚠️ 实验性（未进 manpage、Win 被关） | supernode | 包 `n2n`（**无服务模块**） | 有构建（TCP 被 `#undef`） | GPL-3.0 | 中 | ✅ |
| **SoftEther** | 中心 VPN | **listener 全 TCP**（443/992/5555） | **不需要** | ✅ 纯 TCP，SecureNAT 互访 | VPN Server 即中心 | 包 + 模块 `services.softether` | 官方客户端+GUI | Apache-2.0（历史 GPLv2） | 高（老牌） | ✅ |
| **OpenVPN** | 中心/可组网 | **`proto tcp`**；`client-to-client` | TCP 模式不要 | ✅ TCP（中心辐射） | server | 包 + 模块 `services.openvpn` | 官方客户端 | GPL | 很高 | ✅ |
| **frp** | 端口隧道(+实验VirtualNet) | 端口转发 TCP/UDP；**v0.62 VirtualNet 经 TUN 做 IP 组网(Alpha,仅 Linux/macOS)** | xtcp 要 UDP；VirtualNet 走 stcp/TCP | ⚠️ 端口隧道非IP组网；VirtualNet 可行但 **Alpha 且不支持 Windows** | frps | 包 + 模块 `services.frp` | frpc（VirtualNet 不支持） | Apache-2.0 | 很高 | 不冲突 |
| **rathole** | 端口隧道 | TCP（可转 UDP 服务） | 不涉及 | ⚠️ 仅端口暴露 | server | 包 + 模块 `services.rathole` | client | Apache-2.0 | 中（活跃低） | 不冲突 |
| **NPS** | 端口隧道 | TCP | 不涉及 | ⚠️ 仅端口暴露 | nps 服务端 | 包 `nps`（无模块） | 有 | GPL-3.0 | 低（近无更新） | 不冲突 |
| **Cloudflare Tunnel** | 隧道+WARP | 出站到 CF，TCP/HTTP | 不涉及 | ⚠️ 依赖 CF 云+域名+WARP | 中继在 CF（不可自建到自家机） | 包`cloudflared`+模块 | WARP | cloudflared Apache-2.0 | 高，但**国内 CF 边缘可达性差** | 不冲突 |
| **蒲公英** | 商业 SD-WAN | P2P/转发，二层/三层 | 厂商云协调 | ✅ 但中继在厂商，数据经其服务器 | 硬件/云（非自建协议） | — | 官方客户端（主打） | **闭源商业** | 很高（千万设备） | ✅ |
| **udp2raw** | WG/UDP 封装 | raw socket **伪 TCP**/ICMP | 外层 TCP，服务端仅监听一个 TCP 口 | ⚠️ 需服务端 **root + Linux + raw socket** | 自架两端 | 包 `udp2raw` | 仅客户端（multiplatform） | **MIT**（unified 分支 LICENSE.md） | 中 | 辅助 |
| **phantun** | WG/UDP 封装 | userspace 伪 TCP（TUN） | 外层 TCP | ⚠️ 两端跑，可非root | 自架 | 包 `phantun` | 支持 Windows | Apache-2.0/MIT | 中 | 辅助 |
| **wstunnel** | 隧道/封装 | **WebSocket(TCP)**，可转发 UDP | 外层 TCP | ✅ 可承载 WG UDP over WSS | 自架 | 包 `wstunnel` | 有二进制 | BSD-3 | 中高（活跃） | 辅助 |

---

## 6. 重点方案详评（含一手证据原文）

### 6.1 ZeroTier + `pylon reflect`（推荐 #1）

- 模型：默认节点间 UDP P2P；打洞/无 UDP 时走中继。
- **TCP 中继是官方现役组件**，不是民间偏方。官方 TCP Relay 文档（2026-09-27 抓取，https://docs.zerotier.com/relay/）：
  > "Out of box and for best results, ZeroTier makes direct, peer to peer connections over UDP."
  > "But sometimes your on a network that doesn't allow NAT hole punching or UDP at all."
  > "ZeroTier Inc. runs a TCP relay service that the ZeroTierOne agent will fall back to if it can't make UDP connections."
  > "This relay service is slow for various reasons. **You can host your own TCP relay service for better results.**"
  > "Traffic flows through the relay server via HTTPS..."
- `pylon reflect` 定位（https://raw.githubusercontent.com/zerotier/pylon/main/README.md）：
  > "`pylon reflect` | This relays traffic over `TCP/443` | No（不是一个 ZeroTier 节点）"
  > "If you have a tricky NAT situation and can allow `TCP/443`, you can specify a relay on a machine with a static IP."
  > "a `reflect` instance is just a tcp-proxy and can be used by a regular ZeroTier client just the same."
  > "Finally, Pylon only supports IPv4 TCP..."
- 客户端可设 `tcpFallbackRelay`，甚至 `forceTcpRelay`（同 Relay 文档）。
- **许可证（决定性）**：`ZeroTierOne/dev/nonfree/LICENSE.md`：
  > "# ZeroTier SOURCE-AVAILABLE LICENSE Version 1.0 Copyright (c) 2025 ZeroTier, Inc."
  > "The 'Controller' ... located in the 'nonfree' source directory, are licensed under this Source-Available License for Non-Commercial Use. Use ... for Commercial Use requires a separate commercial license..."
  - 客户端、pylon 为 MPL-2.0。
- 私有 moon 已被官方废弃（https://docs.zerotier.com/zerotier/moons，Last updated Jan 28 2026）："Private moons are no longer recommended ... not supported under the ... SLA ... We strongly discourage setting up new private moons."
- 判定：**硬约束下中继路径明确成立**，雨云机跑 `pylon reflect`，只需入站 TCP/443。控制面先用官方 Central 免费版可绕开 controller 许可证；要完全自建 controller 才有非商业门槛。
- 代价/不确定：官方反复说 TCP 中继慢（具体吞吐 [UNCERTAIN]，未实测）；docker 示例同时映射 9993/udp，但文档明确 reflect「relays traffic over TCP/443」「only supports IPv4 TCP」。

### 6.2 NetBird 自建（推荐 #2）

- 模型：WireGuard 全互联 + ICE/STUN；失败走 relay。
- relay 双栈竞速（官方 NAT 文档，页面 Updated June 12 2026，https://docs.netbird.io/about-netbird/understanding-nat-and-connectivity）：
  > "Transport protocols: QUIC: A modern UDP-based protocol... WebSocket: An HTTP-based protocol that works over TCP. This serves as a fallback when UDP is blocked..."
  > "When a client connects to a relay server, it races both protocols simultaneously... If QUIC (UDP) fails... WebSocket (TCP) automatically takes over."
  > "Self-hosted deployments can run their own relay servers."
- 自建外部 relay 的端口与「UDP 缺失也能跑」（官方 external-relays 页，Updated September 25 2026）：
  > "Firewall ports open: 443/tcp and 443/udp (relay), and 3478/udp (STUN)."
  > "The relay serves two transports on that port: WebSocket over TCP and QUIC over UDP. Clients race both... **With 443/udp closed the QUIC attempt runs until it times out, WebSocket carries the connection, and nothing reports an error**..."
  > "A relay behind a TLS-terminating reverse proxy ... cannot serve QUIC, so it does not need 443/udp."
- **许可证（需显著注意）**：根 LICENSE：
  > "This BSD-3-Clause license applies to all parts of the repository except for the directories management/, signal/, relay/ and combined/. Those directories are licensed under the GNU Affero Public License 3.0..."
  - 即：客户端/数据面 BSD-3，但你要自建的 management/signal/**relay** 是 **AGPL-3.0**（自用/内部网络服务一般可接受，但分发/SaaS 需法务评估）。
- 自建 quickstart 要求（https://docs.netbird.io/selfhosted/selfhosted-quickstart）：一台 Linux（1C2G）、TCP 80/443 + UDP 3478、域名、Docker Compose，脚本一键拉起 management/signal/relay/coturn 等全套。
- NixOS：nixpkgs 有包且有 `services.netbird`（实测模块文件 HTTP 200，`options.services.netbird`），但**自建服务端官方路线是 Docker compose**，NixOS 原生托管全套服务端不在官方文档内（客户端可走模块）。
- 判定：**硬约束下成立且回退是自动的**，长期工程性好；代价是组件多、要域名与 Docker、服务端 AGPL。

### 6.3 SoftEther VPN（推荐 #3）

- 模型：**中心 VPN Server**，客户端接入虚拟 L3/L2 HUB；SecureNAT 提供 DHCP+NAT+客户端互访。非 mesh。
- listener 默认全是 TCP（官方规格 https://www.softether.org/3-spec；手册 3.3）：
  > "Initially, the three TCP/IP port numbers 443, 992 and 5555 are allocated to the VPN Server as listener ports."
  > 手册 1.6：443 与 HTTPS 同端口，便于让中继设备把它识别为 HTTPS。
- 特性（仓库 README）："Revolutionary VPN over ICMP and VPN over DNS features."；"Embedded dynamic-DNS and NAT-traversal..."
- 许可证：仓库根 LICENSE 现为 Apache-2.0（早期版本为 GPLv2，当前 master 为 Apache）。
- 平台：Windows 官方 Server/Client + GUI 成熟；nixpkgs 有 `softether` 包与 `services.softether` 模块（均实测 200）。
- 判定：**完全不依赖入站 UDP**，把雨云机当纯 TCP 中心 VPN 即可让所有节点互访，是最稳的「老派兜底」。代价：中心拓扑（中继机带宽/单点）、SecureNAT/HUB 概念与 NixOS 声明式对接比前两者繁琐。

### 6.4 headscale + 内嵌 DERP（重大附带发现，建议交还 Tailscale 线）

- 定位（https://raw.githubusercontent.com/juanfont/headscale/main/docs/ref/derp.md）：
  > "A DERP ... server is mainly used to relay traffic between two nodes in case a direct connection can't be established. Headscale provides an embedded DERP server..."
- 端口（docs/setup/requirements.md）：
  > "tcp/443 ... required to make Headscale available to Tailscale clients ... Required if the embedded DERP server is enabled"
  > "udp/3478 ... STUN, required if the embedded DERP server is enabled"
- derper 源码（https://raw.githubusercontent.com/tailscale/tailscale/main/cmd/derper/derper.go）：
  - L60：`addr ... :443 ... Serves HTTPS...`（中继监听 TCP/443）
  - L62：`stunPort ... 3478, "The UDP port on which to serve STUN."`
  - L71：`runSTUN ... "whether to run a STUN server."`（**可关**）
  - L185-187：仅当 `runSTUN` 才起 STUN 监听。
- derper README：防火墙「permit TCP ports 80 and 443 and UDP port 3478」；且「DERP protocol does a protocol switch inside TLS from HTTP to a custom bidirectional binary protocol」。
- 判定：**DERP 中继承载 = TLS/TCP443；UDP3478 只是可关的 STUN**。「自建 DERP 受阻于 UDP」若成立，精确位置应是 netcheck/STUN 导致的**区域调度与打洞辅助**，而**不是中继本身不通**。这意味着：即便入站 UDP 全封，只要 `-stun=false`（或不依赖该 DERP 打洞）且客户端能 outbound TCP443，DERP 中继在协议上仍有效，代价是更难从 relay 回升为 P2P。
- 边界：headscale 是 Tailscale 客户端的控制面，属 Tailscale 线，本报告**不切控制面、不改动**，仅把证据交给该线核实（可能需要复测现有 raiyun/raiyun2 derper 配置与 netcheck 行为）。

### 6.5 其余方案简评

- **Netmaker**：数据面 WireGuard/UDP，历史上 relay 也要 UDP（旧 issue #426 官方："we do have relay servers ... however, fallback is not automatic"）。据 worker 实读 release，**v1.7.0（2026-08-31）** 才新增「TCP Proxy / WSS Uplink」："Gateways can publish a TCP/WSS uplink ... when UDP is blocked."；netclient `internal/proxyuplink` 走 userspace WG、默认 443。判定：硬约束在 v1.7.0 后才可解，但**特性仅上线不到两个月、无 nixpkgs 打包**，不进本轮 Top3，宜观察。
- **Nebula**：underlay 纯 UDP。官方 issue #1001，维护者 nbrownus 2026-05-19："It is not currently possible to use TCP in the underlay. We are evaluating it but no concrete plans to date." → **本场景无效**。
- **Tinc**：1.1 manpage（`doc/tinc.conf.5.in` L712-721）：
  > "TCPOnly = yes | no ... packets are tunnelled over the TCP connection ... especially useful ... from behind a masquerading firewall, or if UDP packet routing is disabled..."
  > "Since version 1.0.10, tinc will automatically detect whether communication via UDP is possible or not."（L574：UDP 不通会 fall back to TCP）
  → 功能满足；扣分项是 1.1 至今 pre、Windows MinGW/tap64 体验老旧、TCP-over-TCP 损耗未量化。作为轻量备选。
- **N2N（需精确，不能简单说无 TCP）**：
  - 正式 manpage `supernode.1` 只描述 UDP："begins listening on the specified UDP port ..."，`-p` 绑固定 UDP（默认 7654），federation 也走 UDP。
  - 但 dev 源码里**确有实验性 TCP**：`src/supernode.c` 在 `#ifdef N2N_HAVE_TCP` 下 `open_socket(..., 1 /* TCP */)` 开一个与 UDP **同端口的辅助 TCP** 并 listen，日志 "supernode is listening on TCP %u (aux)"；`edge.8` 有 `-S1 = via UDP, -S2 = via TCP`（"do not connect p2p, always use the supernode"）。
  - 限制：该能力未进 supernode 正式 manpage；`include/n2n.h` 在 Windows 下 `#undef N2N_HAVE_TCP`；federation 仍 UDP。
  - 判定：**仅 Linux dev 构建可让雨云机以「实验性辅助 TCP」承载 edge(-S2)，功能上摸到了硬约束的边，但文档化/成熟度极低，不进推荐，仅可作为技术验证项。**
- **OpenVPN(TCP)**：2.6 官方手册：
  > "--proto p ... p can be udp, tcp-client, or tcp-server..."
  > "For TCP operation, one peer must use --proto tcp-server and the other must use --proto tcp-client."
  > "--client-to-client ... internally route client-to-client traffic..."（服务器即多客户端路由器）
  → 纯 TCP 中心组网成立、成熟；扣分项是手工 PKI/证书分发、无自动 UDP↔TCP 竞速（要双实例）、多节点中心辐射。适合作为「最熟、最可控」的兜底，不进 Top3 仅因落地分发与体验略逊 SoftEther。
- **frp**：端口隧道标杆（Apache-2.0，nixpkgs 包+模块）。
  - `xtcp`（README L457/459）："A frps server is still needed ... may not work with all types of NAT devices. You might want to fallback to stcp..." → 打洞靠 UDP，不适合本场景。
  - **新增 VirtualNet（v0.62.0，Alpha）**：官方 README 与 `doc/virtual_net.md`："enables frp to create and manage virtual network connections ... through a TUN interface ... IP-level routing"；但官方明确 "currently supported on **Linux and macOS**"、"Do not use ... in production"、建 TUN 需 root/admin。它基于 `stcp`（走 TCP）建立 IP 组网，理论上能让仅 TCP 的 frps 中继 IP，但 **Windows 宿主机不被支持**，直接卡住我们的 Windows 节点 → 只能作为非 Windows 节点的实验项，不进 Top3。
- **rathole**：Rust，Apache-2.0，主打比 frp 省资源、TCP_NODELAY 默认开（README L33/L193）；同样是端口隧道、无 IP 组网；据 worker 实读其 release 停滞在 v0.5.0(2023-10)、官方 out-of-scope 不做组网并推荐 WireGuard/ZeroTier（版本细节 [UNCERTAIN：本轮主报告人未直接复核 release 页]）。
- **NPS**：GPL-3.0，带 Web 面板；近几无更新，端口隧道，不推荐。
- **Cloudflare Tunnel**：cloudflared 出站连 CF 边缘，无需公网 IP；四层 TCP 可经 WARP 客户端访问私有源（GitHub README：「use WARP client to access private origins ... Layer 4」）。→ **中继在 Cloudflare、且需域名+WARP，不可用自家雨云机当 relay**；中国大陆到 CF 边缘的可达性/延迟不稳定 [UNCERTAIN，未实测当前质量]，不作为国内组网主力。
- **蒲公英/贝锐**：闭源商业 SD-WAN，主打「无需公网IP」「二层组网」「转发/P2P」（官网原文）。价格页：付费档「P2P直连不限速不限流量」「中国大陆转发…8Mbps/授权数（可扩容）」等；**免费版成员数/转发速率具体数值本轮未在价格页直接取到 [UNCERTAIN]**。优点零运维、Windows 友好；缺点数据经厂商服务器、闭源不可审计、不能用雨云机自建中继。适合「愿意付费买省心」，不符合自控前提。
- **C 类封装工具**：
  - `udp2raw`：raw socket 把 UDP 伪装成 FakeTCP/ICMP（README："A Tunnel which turns UDP Traffic into Encrypted FakeTCP... by using Raw Socket"），需 **Linux + root**；服务端命令仅监听一个 TCP 端口即可承载，不需入站 UDP。许可证已核实为 **MIT**（`unified` 分支 LICENSE.md："Copyright (c) 2017 Yu Wang"；master 默认分支未带该文件）。Windows 仅能通过官方 udp2raw-multiplatform 做客户端、不能做服务端。伪 TCP 不跑真实拥塞控制是其固有风险。
  - `phantun`：userspace、多线程、TUN，伪 TCP（官方对比表：多线程✅、MTU 开销 12B vs udp2raw 44B、无加密/反重放），Apache-2.0/MIT，支持 Windows。
  - `wstunnel`：Rust，WebSocket(TCP) 隧道，支持 TCP/UDP/反向/SOCKS5（README："tunnel whatever traffic you want"），BSD-3，活跃；**可把 WG 的 UDP 经 WSS 承载到仅 TCP 的雨云机**，是 C 类里最干净、最契合 443/TLS 的一种。

---

## 7. 针对本场景的选型排序

**第一梯队（建议优先试）**

1. **ZeroTier + pylon reflect**：验证「仅 TCP 中继」成本最低、侵入最小、两端客户端成熟、不抢 Tailscale 网卡；先不碰 controller（用官方 Central 免费版），只验证 pylon 中继链路质量。
2. **NetBird 自建全套**：若希望 WG 原生 + 中继自动 TCP 回退 + 长期可自控，选它；接受 Docker/域名与 AGPL 服务端的运维/合规成本。
3. **SoftEther**：若要纯 TCP、不赌任何 UDP 打洞、且能接受中心辐射，它是最稳的传统兜底。

**第二梯队（备选/特定取向）**

4. **headscale + 内嵌/独立 DERP**：技术上高度契合，但属 Tailscale 线——建议先核实 §6.4 的证据，可能直接改善现有 Tailscale 方案，而非另起 overlay。
5. **wstunnel（承载 WireGuard）**：想保留 WireGuard 又要走 443/TLS 时，比 udp2raw 更干净、无需 raw socket。
6. **Tinc（TCPonly）/ OpenVPN(TCP)**：能满足，但分别输在 Windows 体验/手工证书与中心辐射。

**观察/排除**

- 观察：Netmaker（WSS uplink 太新、无 nixpkgs）；**frp VirtualNet（Alpha、IP 组网走 TCP 但不支持 Windows，仅可作非 Windows 节点实验）；N2N Linux dev 实验性 TCP（未文档化）**。
- 排除：Nebula（纯 UDP，无任何 TCP）；frp/rathole/NPS 的常规形态（仅端口隧道，非 IP 组网）。
- 不作主力：Cloudflare Tunnel（中继不在自家、国内可达性）、蒲公英（闭源、数据过厂商、不能自建中继）；udp2raw（需服务端 root/raw socket、Windows 不能当服务端；许可证已确认 MIT，排除原因仅是部署形态）。

---

## 8. 三个推荐的最小落地思路（仅思路，不实施）

> 均为「先小后大」的验证路径，任何一步都需另行批准且不与 Tailscale/EasyTier 线冲突。

### 8.1 ZeroTier + pylon reflect（最小验证）

1. 雨云机：`docker run --init -p 9443:443 zerotier/pylon:latest reflect`（先只映 TCP，不映 UDP，验证「纯 TCP 入站」假设）。
2. 官方 Central 免费版建一个网络，把 Windows 宿主机、一台 NixOS 节点加入（装 ZeroTier 客户端，授权）。
3. 两端客户端通过本地配置把 `tcpFallbackRelay` 指向 `雨云IP:9443`，验证中继握手与互 ping/吞吐；必要时临时 `forceTcpRelay` 排除直连干扰。
4. 验收：两端虚拟 IP 互通、经中继（非直连）可 RDP/传文件，记录吞吐与延迟；确认全程未用到入站 UDP。
5. 风险闸：TCP 中继若过慢，则转 #2；controller 若需完全自控再评估非商业许可。

### 8.2 NetBird 自建（最小验证）

1. 准备一个域名（relay/management 走 TLS）；雨云机 Docker Compose 跑官方 getting-started 脚本，先按默认全组件起。
2. **关键验证**：只放通 443/tcp（不放 443/udp、3478/udp），确认 relay 以 WebSocket/TCP 承载、客户端不报错（对应官方「With 443/udp closed…WebSocket carries the connection」）。
3. Windows 装 NetBird 客户端、一台 NixOS 用 `services.netbird` 接入同一自建管理面，互 ping + 测吞吐；再放开 UDP 对比直连/QUIC 提升。
4. 验收：纯 TCP 入站下多节点 IP 互通成立；记录 WSS 中继 vs QUIC/直连性能差。
5. 合规闸：上线前确认 relay/management 的 AGPL-3.0 对自用/团队网络可接受。

### 8.3 SoftEther（最小验证）

1. 雨云机起 SoftEther VPN Server，保留 TCP 443（或 992）listener，建一个虚拟 HUB，开启 SecureNAT（给客户端分虚拟 IP、允许互访）。
2. Windows 装官方 SoftEther Client 接入；NixOS 经 `services.softether` 或客户端接入同一 HUB。
3. 仅放通入站 TCP 443，验证两端拿到同网段虚拟 IP 并互访（ping/RDP/文件）。
4. 验收：全程零入站 UDP 的多节点互通成立，记录中心中继吞吐/延迟与单点风险。
5. 后续再评估是否需要多 HUB/站点到站点，而非一次做全。

---

## 9. 与现有 Tailscale 的共存性

- ZeroTier / NetBird / SoftEther / Tinc / OpenVPN / 蒲公英均使用**独立虚拟网卡与独立虚拟网段**，可与 Tailscale 同机并存，不抢同一 tun；真正要小心的是**默认路由与路由优先级、MTU**（多套默认路由会决定走哪条线）[未实测，属配置阶段事项]。
- headscale 不是并行隧道，而是「给现有 Tailscale 客户端换控制面」，因此不存在双隧道，但改动的是 Tailscale 本身——归 Tailscale 线决策。
- 建议试点期间不给任何新 overlay 配默认路由（只做内网网段），避免影响现有 Tailscale 出网。

---

## 10. 未验证项 / [UNCERTAIN]

1. **所有性能数字均未实测**：ZeroTier TCP relay 官方只说 slow；Tinc/OpenVPN 的 TCP-over-TCP 损耗、SoftEther/NetBird WSS 中继实际吞吐与延迟，均需真机在江苏移动↔雨云路径实测（本任务禁止部署）。
2. **pylon reflect 是否任何代码路径仍监听 UDP**：文档明确仅 TCP443，docker 示例却映 9993/udp；未逐行读其 tcp-proxy 源码（残留不确定，但不影响「可纯 TCP」的文档结论）。
3. **蒲公英免费版成员数/转发速率具体值**：未在官方价格页直接取到，仅有付费档 8/15/20/35 Mbps·授权数 等表述。
4. **Cloudflare Tunnel 当前中国大陆到 CF 边缘的可达性/质量**：未实测，不作结论。
5. **rathole release/ out-of-scope 的精确版本表述**：worker-C 实读为停滞在 v0.5.0(2023-10)、官方 scope 不做组网；主报告人本轮未直接复核其 release 页，按 [UNCERTAIN] 处理（不影响「仅端口隧道」的定性）。
6. **N2N 实验性 TCP 的可用性/性能**：源码证据成立，但未实测其 Linux dev 构建的稳定性与吞吐，且 Windows 不支持 → 不据此下生产结论。
7. **frp VirtualNet 实测**：官方明确 Alpha、仅 Linux/macOS；其 IP 组网经 stcp/TCP 的实际质量未测，且 Windows 节点无法使用。
8. **多 overlay 与 Tailscale 同机的路由优先级/MTU 实际表现**：属配置与实测事项。
9. **Netmaker v1.7.0 WSS uplink**：关键 release/源码证据由 worker-A 实读（GitHub API 当时对主报告人限流），因特性上线不足两月、无 nixpkgs，结论按「可行但待验证」处理。
10. 各项目 star/版本为 2026-09-27 时点快照，会随时间变化。

> 已消除的旧不确定项：udp2raw 许可证已确认 **MIT**（`unified` 分支 LICENSE.md，"Copyright (c) 2017 Yu Wang"；master 分支未带该文件，故先前在 master 上检索为 404）。

---

## 11. 证据来源索引（均为本轮实读的一手页面）

**ZeroTier**
- TCP Relay 文档：https://docs.zerotier.com/relay/
- pylon README：https://raw.githubusercontent.com/zerotier/pylon/main/README.md
- 非商业 controller 许可：https://raw.githubusercontent.com/zerotier/ZeroTierOne/dev/nonfree/LICENSE.md
- 根 LICENSE 指引：https://raw.githubusercontent.com/zerotier/ZeroTierOne/dev/LICENSE.txt
- moon 废弃：https://docs.zerotier.com/zerotier/moons
- 端口说明：https://docs.zerotier.com/routertips/
- TCP transport issue #816（创始人 2019 关闭原文）：https://github.com/zerotier/ZeroTierOne/issues/816

**NetBird**
- NAT/中继双栈：https://docs.netbird.io/about-netbird/understanding-nat-and-connectivity
- 外部 relay（443/udp 关闭仍可跑）：https://docs.netbird.io/selfhosted/maintenance/scaling/set-up-external-relays
- 自建 quickstart：https://docs.netbird.io/selfhosted/selfhosted-quickstart
- 许可证（AGPL 目录）：https://raw.githubusercontent.com/netbirdio/netbird/main/LICENSE

**Netmaker**
- develop README：https://raw.githubusercontent.com/gravitl/netmaker/develop/README.md
- 旧 relay issue #426：https://github.com/gravitl/netmaker/issues/426
- relay 文档：https://docs.netmaker.io/docs/features/relay-servers-pro
- netclient proxyuplink：https://raw.githubusercontent.com/gravitl/netclient/develop/internal/proxyuplink/doc.go

**headscale / DERP**
- headscale DERP：https://raw.githubusercontent.com/juanfont/headscale/main/docs/ref/derp.md
- 端口要求：https://raw.githubusercontent.com/juanfont/headscale/main/docs/setup/requirements.md
- derper 源码：https://raw.githubusercontent.com/tailscale/tailscale/main/cmd/derper/derper.go
- derper README：https://raw.githubusercontent.com/tailscale/tailscale/main/cmd/derper/README.md

**Nebula / Tinc / N2N / SoftEther / OpenVPN**
- Nebula README：https://raw.githubusercontent.com/slackhq/nebula/master/README.md
- Nebula TCP issue #1001：https://github.com/slackhq/nebula/issues/1001
- Tinc manpage：https://raw.githubusercontent.com/gsliepen/tinc/1.1/doc/tinc.conf.5.in
- N2N supernode manpage：https://raw.githubusercontent.com/ntop/n2n/dev/supernode.1
- N2N 实验性 TCP 源码：https://raw.githubusercontent.com/ntop/n2n/dev/src/supernode.c （`#ifdef N2N_HAVE_TCP`）；edge 选项：https://raw.githubusercontent.com/ntop/n2n/dev/edge.8 （`-S2 = via TCP`）
- SoftEther 规格：https://www.softether.org/3-spec ；README：https://raw.githubusercontent.com/SoftEtherVPN/SoftEtherVPN/master/README.md
- OpenVPN 2.6 手册：https://openvpn.net/community-resources/reference-manual-for-openvpn-2-6/

**隧道 / 商业 / 封装**
- frp README（xtcp L457/459）：https://raw.githubusercontent.com/fatedier/frp/dev/README.md
- frp VirtualNet 文档：https://raw.githubusercontent.com/fatedier/frp/dev/doc/virtual_net.md （Alpha，仅 Linux/macOS）
- rathole README：https://raw.githubusercontent.com/rapiz1/rathole/main/README.md
- cloudflared README：https://github.com/cloudflare/cloudflared
- 蒲公英官网 / 价格：https://pgy.oray.com/ ；https://pgy.oray.com/price/
- udp2raw README：https://raw.githubusercontent.com/wangyu-/udp2raw/master/README.md ；许可证 MIT：https://raw.githubusercontent.com/wangyu-/udp2raw/unified/LICENSE.md
- phantun README：https://raw.githubusercontent.com/dndx/phantun/master/README.md
- wstunnel README：https://raw.githubusercontent.com/erebe/wstunnel/main/README.md

**NixOS 打包（nixos-unstable，HTTP 状态实测 2026-09-27）**
- 模块：`services.netbird / nebula / tinc / softether / frp / rathole / cloudflared / openvpn / headscale / zerotierOne`
- 包（by-name）：zerotierone、zeronsd、netbird、nebula、tinc、n2n、softether、frp、rathole、nps、cloudflared、openvpn、udp2raw、phantun、wstunnel、headscale
- 未打包：netmaker（无包无模块）；n2n/nps 有包无服务模块
