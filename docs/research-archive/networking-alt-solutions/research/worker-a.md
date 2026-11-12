# Worker-A 调研报告：中心协调型 Mesh Overlay 方案

- 调研人：research worker A（只读）
- 日期：2026-09-27
- 硬约束问题：**一台「公网入站 UDP 不可用、仅公网入站 TCP 可用」的雨云共享 NAT VPS，能否充当有效组网协调/中继节点？**
- 说明：客户端均位于出站 TCP/UDP 正常的网络（江苏移动 Windows、NixOS raiyun/raiyun2）；问题只在中继/协调机的**入站**侧。
- 所有源码行号/版本以 2026-09-27 抓取的默认分支文件为准，标注 commit short SHA。

---

## 1. ZeroTier（含 moon / pylon TCP relay）

### 1.1 维度表

| 维度 | 结论 |
|---|---|
| 组网模型 | 混合：默认 P2P over UDP，打洞失败经中继（relay）转发；根服务器（planet roots/moon）做协调 |
| 数据面协议 | 自研 VL1 协议（非 WireGuard），默认 UDP/9993；**支持 TCP 中继回退（HTTPS/TCP 443）** |
| 是否依赖公网入站 UDP 打洞 | 直接路径依赖 UDP；但官方提供 **TCP relay 回退**，节点完全不能用 UDP 时可走 TCP/443 |
| 回退能否走 TCP/443/TLS | **能。** 官方 TCP relay（pylon `reflect`），流量经 HTTPS；可自建 |
| 自建中继的网络要求 | pylon `reflect` 只需一个静态 IP + 对外开放 **TCP/443**；文档 docker 示例还映射 UDP/9993，但 reflect 作为「dumb TCP relay」本身不要求入站 UDP |
| 自建控制面 | 网络控制器（controller）源码在 `nonfree/`，**2025 年起为 source-available、仅非商业用途**；商业用途须向 ZeroTier 购买商业授权。私有 moon 已被官方废弃（2026-01 更新） |
| moon 节点能否只靠 TCP | moon 属于根服务器体系，节点与 root 间的中继可走 TCP relay；但私有 moon 官方已 deprecated、不在 SLA 内。**当前推荐路径是 pylon TCP relay 而非 moon** |
| Windows 客户端 | 官方提供 Windows 安装包（zerotier.com/download） |
| NixOS 部署成本 | 见第 5 节 search.nixos.org 实时核验 |
| 许可证（当前版本，2026-09-27 抓取） | Agent 为 MPL-2.0；Controller 等 `nonfree/` 部分为 **ZeroTier Source-Available License v1.0（Copyright 2025），仅非商业使用**；pylon 为 MPL-2.0 |
| 成熟度/生态 | ZeroTierOne GitHub stars 17,132；最新 release v1.16.2（2026-05-28）；默认分支 dev，最近 push 2026-09-03 |
| 与 Tailscale 共存性 | 协议、子网、路由独立（ZeroTier 用自身虚拟网段 + 9993/UDP 或 TCP/443），可与 Tailscale 同机并存；两者不会抢占同一 tun，但需注意各自路由优先级 [UNCERTAIN：具体路由优先级依赖配置，未实测] |

### 1.2 关键结论原文引述（一手）

**(1) 默认 UDP、不能用 UDP 时有 TCP relay 回退，且可自建** —— 官方文档 TCP Relay 页
URL: https://docs.zerotier.com/relay/ （抓取 2026-09-27）
> "Out of box and for best results, ZeroTier makes direct, peer to peer connections over UDP."
> "But sometimes your on a network that doesn't allow NAT hole punching or UDP at all."
> "ZeroTier Inc. runs a TCP relay service that the ZeroTierOne agent will fall back to if it can't make UDP connections."
> "This relay service is slow for various reasons. You can host your own TCP relay service for better results."
> "Traffic flows through the relay server via HTTPS, allowing secure communication between networks that would otherwise be unable to connect directly."

自建命令与客户端配置（同页原文）：
> `export TCP_PORT=443 export UDP_PORT=9993 docker run --init -p $TCP_PORT:$TCP_PORT -p $UDP_PORT:9993/udp zerotier/pylon:latest reflect`
> `{ "settings": { "tcpFallbackRelay": "1.2.3.4/443", "forceTcpRelay": true  } }`
> "In this example, forceTcpRelay is enabled. This is helpful for testing or if you know you'll need tcp relay."

**(2) pylon reflect 就是 dumb TCP relay，只要静态 IP + TCP/443** —— 官方仓库 zerotier/pylon README（main 分支，抓取 2026-09-27）
URL: https://raw.githubusercontent.com/zerotier/pylon/main/README.md
> "| `pylon reflect` | This relays traffic over `TCP/443`  | No |"
> "If you have a tricky NAT situation and can allow `TCP/443`, you can specify a relay on a machine with a static IP."
> "Note: a `reflect` instance is just a [tcp-proxy](https://github.com/zerotier/ZeroTierOne/tree/dev/tcp-proxy) and can be used by a regular ZeroTier client just the same."
> "The default tcp relay is at `204.80.128.1/443` -an anycast address."
> "Finally, Pylon only supports IPv4 TCP but IPv6 and UDP support can be added if there is sufficient interest."

**(3) 私有 moon 已废弃、不推荐、不在 SLA** —— 官方文档 Private Root Servers 页
URL: https://docs.zerotier.com/zerotier/moons （抓取 2026-09-27，页脚 Last updated Jan 28 2026）
> "Private moons are no longer recommended for deployment and are are not supported under the ZeroTier Service Level Agreement (SLA). This deployment method is outdated and may cause reliability issues. We strongly discourage setting up new private moons."

**(4) 默认 P2P、不能 P2P 时走（较慢的）中继** —— 官方 manual
URL: https://docs.zerotier.com/zerotier/manual （抓取 2026-09-27）
> "All ZeroTier traffic is encrypted end-to-end using secret keys that only you control. Most traffic flows peer to peer, though we offer free (but slow) relaying for users who cannot establish peer to peer connections."
> "can continue through (slower) relaying. Direct connection attempts ..."

**(5) 许可证：Agent MPL-2.0；Controller 为 2025 起 source-available、仅非商业**
- 根 LICENSE.txt，URL: https://raw.githubusercontent.com/zerotier/ZeroTierOne/dev/LICENSE.txt
  > "See LICENSE-MPL.txt for all code in node/, osdep/. service/, and everywhere else except ext/ and nonfree/. See nonfree/LICENSE.md for all non-free ("source available") portions of this repository."
- nonfree/LICENSE.md，URL: https://raw.githubusercontent.com/zerotier/ZeroTierOne/dev/nonfree/LICENSE.md
  > "# ZeroTier SOURCE-AVAILABLE LICENSE  Version 1.0  Copyright (c) 2025 ZeroTier, Inc."
  > "The \"ZeroTier Agent\" component is licensed under the Mozilla Public License 2.0 (MPL-2.0). ... The \"Controller\" and other related components, located in the “nonfree” source directory, are licensed under this Source-Available License for Non-Commercial Use. Use of any of these components for Commercial Use requires a separate commercial license agreement with ZeroTier, Inc."
  > "\"Non-Commercial Use\" means use of the Software solely for: - Personal, non-commercial purposes ... - Educational or academic research purposes ... - Evaluation purposes for a period not exceeding 30 days"
- pylon LICENSE 为 MPL-2.0：URL: https://raw.githubusercontent.com/zerotier/pylon/main/LICENSE（首行 "Mozilla Public License Version 2.0"）

**(6) 版本/活跃度**（GitHub API，抓取 2026-09-27）
- https://api.github.com/repos/zerotier/ZeroTierOne ：`stargazers_count: 17132`，`default_branch: dev`，`pushed_at: 2026-09-03T17:04:55Z`，license `NOASSERTION/Other`
- https://api.github.com/repos/zerotier/ZeroTierOne/releases/latest ：`tag_name: 1.16.2`，`published_at: 2026-05-28T20:21:10Z`
- dev 分支最新 commit（抓取时）SHA `899352e38405968516bb12a770f0ac02f6058fa8`

### 1.3 对硬约束的判定：**可行（中继路径明确成立）；自建 controller 有许可证前提**

- 雨云这台「仅入站 TCP」的机器，可运行官方 **pylon `reflect`**，对外只需开放 **TCP/443（HTTPS）**，国内 ZeroTier 节点在 UDP 打洞失败/完全无 UDP 时可把它作为 `tcpFallbackRelay`（甚至 `forceTcpRelay`）中继互联。此为官方一手文档明确支持的部署形态，**不依赖任何入站 UDP**。
- 注意官方明言 TCP relay 比 UDP 直连慢、延迟更高（"more latency"）。
- 协调/控制面有两种处境：
  1. 直接用 ZeroTier 官方云 controller（Central），机器只做 TCP relay —— 无许可证问题；
  2. 想完全自建 controller —— **2025 起 controller 为 source-available、仅限非商业用途**，商业用途须付费授权；且自建「planet/私有 moon」官方已废弃，不应作为新方案。
- 因此「让这台 TCP-only 机器充当有效中继」判定**可行**；「让它充当完全自建的独立协调控制面」在商业场景下有授权门槛，且官方路线更偏向 relay + 官方/企业 controller。
- 残留不确定：docker 示例同时映射 `-p 9993/udp`，reflect 本身作为 tcp-proxy 是否在任何代码路径仍尝试监听 UDP，需读 pylon/tcp-proxy 源码确认（列入未验证项）；但文档已明确 reflect "relays traffic over TCP/443" 且 "only supports IPv4 TCP"。

---

## 2. Netmaker（含 netclient TCP/WSS uplink，2024–2026 架构变化）

### 2.1 维度表

| 维度 | 结论 |
|---|---|
| 组网模型 | 混合：WireGuard 全互联 mesh，STUN 做 NAT 探测/打洞；打洞失败经公网 relay/gateway 转发（老 Relay/Ingress/Egress，v0.90 起并入 Gateways；另有 Auto-Relay、Pro Failover） |
| 数据面协议 | **WireGuard（内核或 userspace/boringtun）**，默认 UDP；老中继本质仍是「公网 WG peer」，**也走 UDP** |
| 是否依赖公网入站 UDP | **2026-08 前：是**——relay/gateway 需公网 IP 且节点间/到 relay 的 WG 流量走 UDP，无 TCP 数据面 |
| TCP 回退（关键变化） | **v1.7.0（2026-08-31）新增 TCP Proxy / WSS Uplink**：gateway 可发布 `wss://…/uplink/v1`，客户端在 UDP 被封时把 WG 流量封装进 WSS（WebSocket over TLS/TCP，默认端口 **443**），支持自签 TLS 或外部 TLS 终止。特性很新 |
| 回退能否走 TCP/443/TLS | **能（v1.7.0 起）**，WSS over TCP 443；客户端需显式 `use_tcp_uplink` + `relayedby`，gateway 需 `tcp_proxy_enabled` |
| 自建中继的网络要求 | WSS gateway：一台公网可达机器 + 开放**入站 TCP 443**（走 userspace WG Bind），**不要求入站 UDP** |
| 自建控制面 | 可完全自建 Netmaker server（gRPC/REST + UI），核心 Apache-2.0；`pro/` 目录商业功能另授权（PRO_LICENSE） |
| Windows 客户端 | 官方 netclient + Netmaker Desktop（Windows 支持，含 relay_tcp_endpoint_windows.go） |
| NixOS 部署成本 | 见第 5 节 search.nixos.org 实时核验 |
| 许可证（抓取 2026-09-27） | Netmaker 核心 **Apache-2.0**，`pro/` 另见 pro/PRO_LICENSE；netclient **Apache-2.0**；底层 gravitl/proxy **Apache-2.0**。历史上曾有 SSPL/BSL 变更，当前 develop 为 Apache-2.0 [历史变更链条未逐一取证，见未验证项] |
| 成熟度/生态 | gravitl/netmaker stars 11,801；最新 release v1.7.0（2026-08-31）；develop 分支 push 2026-09-27（极活跃）；netclient stars 约 1k（API 限流未取准，见未验证项），develop push 2026-09-25 |
| 与 Tailscale 共存性 | WireGuard 接口独立，可与 Tailscale 同机并存；需注意 tun/路由优先级与 MTU [UNCERTAIN：实测路由优先级] |

### 2.2 关键结论原文引述（一手）

**(1) 数据面是 WireGuard；安装要求同时开放 443、51821 的 TCP 和 UDP** —— develop README（抓取 2026-09-27）
URL: https://raw.githubusercontent.com/gravitl/netmaker/develop/README.md
> "# WireGuard® automation from homelab to enterprise"
> "Allow inbound traffic on port 443,51821 TCP and UDP to the VM firewall ... and for simplicity, allow outbound on All TCP and All UDP."
> 许可证段："Content outside of the above mentioned directories or restrictions above is available under the \"Apache Version 2.0\" license"；"All details for the licenses used can be found here: LICENSE.md."

**(2) 老 Relay 要求中继节点有公网 IP；流量经 relay 转发** —— 官方文档 Relay Servers（标注 v0.90 已并入 Gateways 并下放到社区版）
URL: https://docs.netmaker.io/docs/features/relay-servers-pro （抓取 2026-09-27）
> "With the release of Netmaker v0.90.0, we've streamlined the Relay functionality by integrating it with Remote Access into a single feature called Gateways and it's available on community version now."
> "At any time you may designate a publicly reachable node (such as the Netmaker Server) as a Relay ... Then, all traffic routing to and from that machine will go through the relay."
> "To create a relay, you can use any node in your network, but it should have a public IP address (not behind a NAT)."

**(3) NAT 穿越用 WireGuard + STUN +（Pro）TURN 式 Failover** —— 官方文档 NAT Traversal
URL: https://docs.netmaker.io/docs/how-to-guides/nat-traversal （抓取 2026-09-27）
> "Netmaker leverages WireGuard, STUN, and TURN servers to achieve this when direct connections aren't possible."
> "It functions just like a TURN server."
> "As of v0.18.0, Netmaker use a stun server ... By default, netmaker uses publicly available STUN servers."

**(4) 老 issue 钉死：relay 节点连接同样走 UDP，没有 TCP 中继回退（2021 年官方答复）**
URL: https://github.com/gravitl/netmaker/issues/426 （抓取 2026-09-27）
> 用户："Tailscale provides DERP servers. Is it planned to support something to fallback on in case of failure to connect via UDPPunchHole ?"
> 官方 afeiszli："we do have relay servers in Netmaker today, however, fallback is not automatic."
> 用户："does connection to relai nodes is done through UDP as well ?"
> 官方随后建议 "UDP Hole Punching"，未提供 TCP 路径——证实当时中继仍为 UDP。

**(5) v1.7.0 发布说明明确新增 TCP/WSS uplink（决定性证据）** —— GitHub release（抓取 2026-09-27）
URL: https://api.github.com/repos/gravitl/netmaker/releases/latest （tag v1.7.0, published 2026-08-31）
> "### 🔌 TCP Proxy / WSS Uplink"
> "Gateways can publish a **TCP/WSS uplink** so clients can reach the mesh in restrictive environments when UDP is blocked."
> "Enable TCP proxy on the gateway/host (`tcp_proxy_enabled` and related listen/TLS settings)."
> "Clients can opt into a TCP uplink to the gateway when the proxy is enabled."
> "Supports self-signed and externally terminated TLS modes for WSS endpoints."

**(6) netclient 源码落地 WSS uplink（develop，commit `dd93f3f`，抓取 2026-09-27）**
- 包文档 internal/proxyuplink/doc.go，URL: https://raw.githubusercontent.com/gravitl/netclient/develop/internal/proxyuplink/doc.go
  > "// Package proxyuplink adapts netclient to gravitl/proxy WSS uplink."
  > "//   - Client: UseTcpUplink + RelayedBy + PeerIDs.tcp_proxy_endpoint (wss://…/uplink/v1) → uplink.Client + userspace Bind"
  > "//   - Gateway: TcpProxyEnabled + TcpProxyListenPort + TcpProxyTLSMode → uplink.Server (selfsigned WSS or proxy-mode WS) + userspace Bind"
- detect.go:11（默认端口 443），URL 同目录 /detect.go
  > `const DefaultListenPort = 443`
  > "NeedsUserspaceWG ... if ... n.UseTcpUplink || n.TcpProxyEnabled { return true }"（走 userspace WireGuard Bind）
- server.go（gateway 监听 WSS）：
  > "// Start listens for WSS (or WS in proxy mode) uplink clients."
  > `if listenPort <= 0 { listenPort = DefaultListenPort }`（server.go:53-56）
- 合并记录 PR #4106（merged 2026-08-18），URL: https://github.com/gravitl/netmaker/pull/4106
  > "Add gateway tcp_proxy_enabled/listen port and client use_tcp_uplink, and populate PeerIDs on host-level pulls so clients receive dial targets."

**(7) 许可证（抓取 2026-09-27）**
- https://raw.githubusercontent.com/gravitl/netmaker/develop/LICENSE.md ："Copyright (c) 2023 Netmaker,Inc."；"* All content that resides under the \"pro/\" directory ... is licensed under the license defined in \"pro/PRO_LICENSE\"."；"* Content outside ... is available under the \"Apache Version 2.0\" license"
- netclient https://raw.githubusercontent.com/gravitl/netclient/develop/LICENSE.txt ：首行 "Apache License Version 2.0"
- gravitl/proxy https://raw.githubusercontent.com/gravitl/proxy/master/LICENSE ：首行 "Apache License Version 2.0"

**(8) 版本/活跃度**（GitHub API，2026-09-27）：netmaker stars 11,801，default `develop`，pushed 2026-09-27；release v1.7.0 @ 2026-08-31。netclient default `develop`，pushed 2026-09-25。

### 2.3 对硬约束的判定：**v1.7.0 起可行（WSS/TCP443），此前不可行；但特性很新、成熟度待观察**

- 在 **2026-08 v1.7.0 之前：不可行**——Netmaker 全数据面（含 relay）都是 WireGuard/UDP，官方文档与旧 issue 证实没有 TCP 数据面；一台入站 UDP 被封的机器即便有公网 IP，也无法被其他 netclient 经 UDP 到达。
- **v1.7.0 起：可行**——可把这台 TCP-only 机器配置为开启 `tcp_proxy_enabled` 的 gateway，监听 WSS（默认 TCP/443，自签或外部 TLS 终止均可）；国内节点 netclient 设 `use_tcp_uplink` + `relayedby`，把 WG 流量封装进 WSS/TCP443 完成中继，**全程只需入站 TCP 443，不需要入站 UDP**。
- 风险：该特性 2026-08 才 GA，依赖 userspace WireGuard（性能通常低于内核 WG），且 netmaker/netclient 近年架构（Gateways、Auto-Relay、WSS）与许可证多次变动，生产前需实测稳定性、自签证书指纹分发、以及 Windows userspace WG 的实际表现。
- 自建控制面本身（Netmaker server）核心 Apache-2.0 可自建，但商业功能在 `pro/`。

---

## 3. NetBird（自建 Management/Signal/Relay；Relay 双传输 QUIC+WebSocket）

### 3.1 维度表

| 维度 | 结论 |
|---|---|
| 组网模型 | 混合：WireGuard 数据面 + P2P（STUN 探测/打洞、Signal gRPC 交换候选）；打洞失败经 NetBird Relay 中继；Management 下发策略与 relay 信息 |
| 数据面协议 | **WireGuard**（端到端加密后再交 relay）；relay 自身承载两种传输：**QUIC（UDP，主）与 WebSocket（TCP，回退）**，非传统 TURN |
| 是否依赖公网入站 UDP | **不强制**。客户端同时竞速 QUIC/UDP 与 WebSocket/TCP；443/udp 关闭时 QUIC 超时、**WebSocket over TCP/443 正常承载**，官方明确"nothing reports an error" |
| 打洞失败回退能否走 TCP/443/TLS | **能**：WebSocket over TLS/TCP443（在防火墙看来就是标准 HTTPS）；自动竞速，无需手动切换 |
| 对称 NAT 行为 | 官方专门说明对称/CGNAT 下 P2P 难，自动回退 relay（QUIC→WebSocket） |
| 自建控制面 | 可自建 Management + Signal + Relay + Coturn(STUN/TURN)，社区 quickstart 全部塞进 netbird-server 容器经 Traefik 收在 80/443 |
| 自建 relay 的网络要求 | 社区内嵌 relay：随 server 走 443/TCP。**独立 external relay 文档标注需 Commercial License**；external relay 需域名 + 入站 **443/tcp 与 443/udp**（+3478/udp STUN），仅开 443/tcp 也能靠 WebSocket 工作（QUIC 那条超时） |
| Windows 客户端 | 官方 NetBird Desktop（Windows）+ CLI |
| NixOS 部署成本 | 见第 5 节实时核验 |
| 许可证（main，抓取 2026-09-27） | 仓库整体 **BSD-3-Clause**；**management/、signal/、relay/、combined/ 目录为 AGPLv3**（各自带 LICENSE，relay/LICENSE 首行已核验 "GNU AFFERO GENERAL PUBLIC LICENSE Version 3"） |
| 成熟度/生态 | netbirdio/netbird stars **29,549**（GitHub HTML，2026-09-27）；最新 release **v0.81.0（约 2026-09-26）**；发版非常活跃 |
| 与 Tailscale 共存性 | 独立 WireGuard 接口，可并存；同机多 tun 需关注路由/MTU [UNCERTAIN：实测] |

### 3.2 关键结论原文引述（一手）

**(1) Relay 双传输，QUIC 主、WebSocket/TCP 回退，客户端竞速（决定性证据）** —— 官方 "Understanding NAT and Connectivity"（Updated 2026-06-12，抓取 2026-09-27）
URL: https://docs.netbird.io/about-netbird/understanding-nat-and-connectivity
> "The NetBird relay is a lightweight server that forwards encrypted WireGuard traffic between peers when they cannot connect directly. Unlike traditional TURN servers, NetBird's relay uses a custom protocol designed for efficiency."
> "QUIC: A modern UDP-based protocol with built-in encryption. This is the primary transport and offers lower latency."
> "WebSocket: An HTTP-based protocol that works over TCP. This serves as a fallback when UDP is blocked, as it appears as standard HTTPS traffic to firewalls."
> "When a client connects to a relay server, it races both protocols simultaneously and uses whichever succeeds first. If QUIC (UDP) fails due to network restrictions, WebSocket (TCP) automatically takes over."
对称 NAT："Many enterprise firewalls and some ISP-grade routers use Endpoint-Dependent Mapping (EDM) or \"Symmetric NAT\". ... Carriers often use symmetric NAT at the CGNAT layer."

**(2) External relay 端口：443/tcp + 443/udp；只开 TCP 时 WebSocket 承载，无报错** —— 官方 "External Relays"（Updated 2026-09-25，抓取 2026-09-27）
URL: https://docs.netbird.io/selfhosted/enterprise/external-relays
> "For each relay server you need: A domain name pointing at it ... These inbound ports open: 443/tcp and 443/udp (relay), 3478/udp (STUN)"
> "The relay serves two transports on that port: WebSocket over TCP and QUIC over UDP. Clients race both and keep whichever answers first. With 443/udp closed the QUIC attempt runs until it times out, WebSocket carries the connection, and nothing reports an error, so the missing rule is easy to overlook."
> 许可属性（标题/正文）："External Relays on a Commercial License"；"One thing makes Enterprise different, and it is the reason this page exists rather than the community guide."

**(3) 社区自建 quickstart 把 relay(WebSocket) 收在 443/TCP；Coturn STUN/TURN 走 UDP** —— 官方 Self-Hosted Guide（抓取 2026-09-27）
URL: https://docs.netbird.io/selfhosted/selfhosted-guide
> 端口表："443 TCP HTTPS (Dashboard, Management API/gRPC, Signal gRPC, Relay WebSocket)"；"3478 UDP Coturn STUN/TURN server"
> 拆分端口表："33080 TCP Relay (WebSocket/QUIC)"；"The default setup script configures a Traefik reverse proxy that consolidates all services behind ports 80 and 443."

**(4) relay 转发的是端到端加密的 WG 流量，relay 无法读取** —— Troubleshooting relayed connections（Updated 2026-08-25）
URL: https://docs.netbird.io/help/troubleshooting-relayed-connections
> "A relayed connection is just as secure as a direct one. Traffic is encrypted end to end with WireGuard before it leaves the device, and the relay only forwards packets it cannot read."
> 客户端 relay 地址示例："Relay server address: rels://us-nyc-2.relay.netbird.io:443"

**(5) 许可证（main，抓取 2026-09-27）**
- 根 LICENSE https://raw.githubusercontent.com/netbirdio/netbird/main/LICENSE
  > "This BSD‑3‑Clause license applies to all parts of the repository except for the directories management/, signal/, relay/ and combined/. Those directories are licensed under the GNU Affero General Public License version 3.0 (AGPLv3). See the respective LICENSE files inside each directory."
- relay/LICENSE https://raw.githubusercontent.com/netbirdio/netbird/main/relay/LICENSE ：首行 "GNU AFFERO GENERAL PUBLIC LICENSE Version 3, 19 November 2007"

**(6) 成熟度（2026-09-27 实时取，GitHub HTML 因 API 限流）**
- stars：https://github.com/netbirdio/netbird 页面 "aria-label=\"29549 users starred"（29,549）
- 最新 release：https://github.com/netbirdio/netbird/releases 最新 tag `v0.81.0`，页面 `datetime="2026-09-26"`（前一 v0.79.0 @ 2026-09-18）

### 3.3 对硬约束的判定：**可行（Relay WebSocket/TCP443），且为四方案中回退最自动化者**

- 这台共享 NAT 机器可部署 NetBird 自建服务：社区 quickstart 下 relay 的 WebSocket 传输随 Traefik 监听 **443/TCP**，配合 Management/Signal；国内节点客户端在 P2P 失败、QUIC/UDP 不通时，自动竞速落到 **WebSocket over TLS/TCP443**，全程只需入站 TCP443，relay 只转发端到端加密的 WireGuard 流量。
- 关键优势：**回退是客户端自动竞速、官方明确 UDP 关闭也不报错**，无需像 Netmaker 那样手动 `use_tcp_uplink`，且特性已随多个版本稳定（文档 2026 年内多次更新）。
- 限制与注意：
  1. **独立 external relay（把 relay 拆到专用主机）官方文档标注需 Commercial License**；若只用社区版，relay 需内嵌在 netbird-server（仍可对外提供 TCP443 relay，只是不能单独拆机）。是否能在社区版把这台机器纯作 relay-only 而不承担 management，需进一步核验授权/安装方式 → [UNCERTAIN，见未验证项]。
  2. Coturn 的 STUN/TURN 监听 UDP（3478 及高端口），但那只影响 P2P 打洞成功率，不影响 relay 的 TCP 回退可用性；在本场景可不开。
  3. management/signal/relay 为 **AGPLv3**，对二次开发/SaaS 提供有 copyleft 约束；仅自用组网无影响。

---

## 4. headscale（开源 Tailscale 控制面；配合官方 tailscale 客户端）

### 4.1 维度表

| 维度 | 结论 |
|---|---|
| 本质 | **headscale 只是控制/协调平面**（开源、社区维护，替代 Tailscale 官方 coordination server）；**它本身不是数据面、也不产生隧道**。数据面完全由各节点上的官方 **tailscale 客户端**用 WireGuard 建立 |
| 组网模型 | tailscale 客户端：P2P（STUN + MagicUDP/UPnP/NAT-PMP 打洞），失败经 **DERP** 中继；headscale 决定 ACL/路由/DERP map，并可**内嵌一个 DERP** |
| 数据面协议 | WireGuard（UDP，P2P）；**DERP 中继本体是 HTTPS（HTTP over TLS/TCP，默认 443），含 WebSocket 升级**——不是 UDP。DERP 另外带一个**独立的 STUN/UDP 3478**，但可用 `--stun=false` 关闭 |
| 是否依赖公网入站 UDP | **中继本身不依赖**：客户端访问 DERP 走 TCP/443 HTTPS。仅当需要该 DERP 同时充当 STUN 帮客户端打洞时才需要入站 UDP/3478；关掉 STUN 后 DERP over TCP443 仍可中继 |
| 回退能否走 TCP/443/TLS | **能**，DERP 就是 TLS/TCP443（derper.go 默认 `-a :443`，`derpserver.AddWebSocketSupport`）；这正是 Tailscale「UDP 全被封」时的兜底 |
| 自建控制面 | **可完全自建且开源**（BSD-3）；可启用内嵌 DERP，或自定义 DERP map 指向独立 derper |
| 自建 DERP 的网络要求 | 一台公网可达机器 + 入站 **TCP/443**（证书可用 Let's Encrypt 或 manual）；入站 UDP/3478 仅 STUN 用、可不开 |
| Windows 客户端 | **无需新客户端**——直接用官方 Tailscale Windows 客户端，登录指向自建 headscale 即可（用户已装 tailscale，改控制面即可） |
| NixOS 部署成本 | 见第 5 节实时核验 |
| 许可证（main，抓取 2026-09-27） | **BSD-3-Clause**，"Copyright (c) 2020, Juan Font" |
| 成熟度/生态 | juanfont/headscale stars **44,152**（GitHub HTML，2026-09-27）；最新 release **v0.29.4（约 2026-09-23）**；非常活跃 |
| 与 Tailscale 共存性 | **它就是 Tailscale 的控制面**，不是并行 overlay；同机只有一套 tailscale 数据面。把现有 tailscale 从官方登录切到 headscale 即可，不存在双隧道冲突 |

### 4.2 关键结论原文引述（一手）

**(1) headscale 定位 + 内嵌 DERP + STUN(UDP/3478)** —— 官方 docs/ref/derp.md（main，抓取 2026-09-27）
URL: https://raw.githubusercontent.com/juanfont/headscale/main/docs/ref/derp.md
> "A DERP (Designated Encrypted Relay for Packets) server is mainly used to relay traffic between two nodes in case a direct connection can't be established. Headscale provides an embedded DERP server to ensure seamless connectivity between nodes."
> "Headscale ships with an embedded DERP server ... The embedded DERP server is disabled by default and needs to be enabled."
> "Besides relaying traffic, it also uses STUN (udp/3478) to help clients discover their public IP addresses and perform NAT traversal."

**(2) 端口要求：DERP 中继用 TCP/443，STUN 才是 UDP/3478（钉死 TCP/UDP 关系）** —— docs/setup/requirements.md
URL: https://raw.githubusercontent.com/juanfont/headscale/main/docs/setup/requirements.md
> "- tcp/443 - Expose publicly: yes - HTTPS, required to make Headscale available to Tailscale clients - Required if the embedded DERP server is enabled"
> "- udp/3478 - Expose publicly: yes - STUN, required if the embedded DERP server is enabled"
（即：对"客户端接入控制面/DERP 中继"而言硬性要求是 TCP/443；UDP/3478 只是随 DERP 启用的 STUN。）

**(3) derper 源码：DERP 监听 TCP/443 HTTPS；STUN 是独立 UDP 监听且可 `--stun=false` 关闭；中继支持 WebSocket（决定性源码证据）**
—— tailscale/tailscale cmd/derper/derper.go（main，commit `fe0d7d1`，抓取 2026-09-27）
URL: https://raw.githubusercontent.com/tailscale/tailscale/main/cmd/derper/derper.go
> derper.go:60 `addr = flag.String("a", ":443", "server HTTP/HTTPS listen address ... Serves HTTPS if the port is 443 and/or -certmode is manual, otherwise HTTP.")`
> derper.go:62 `stunPort = flag.Int("stun-port", 3478, "The UDP port on which to serve STUN...")`
> derper.go:71 `runSTUN = flag.Bool("stun", true, "whether to run a STUN server. It will bind to the same IP (if any) as the --addr flag value.")`
> derper.go:185-187 `if *runSTUN { ss := stunserver.New(ctx); go ss.ListenAndServe(net.JoinHostPort(listenHost, fmt.Sprint(*stunPort))) }`
> derper.go:270-271 `derpHandler := derpserver.Handler(s); derpHandler = derpserver.AddWebSocketSupport(s, derpHandler); mux.Handle("/derp", derpHandler)`
——证明：DERP 中继与 STUN 是两个相互独立的监听器；中继 = TCP/TLS443（含 WebSocket），STUN = UDP3478 且可关。关掉 STUN 不影响 TCP443 中继。

**(4) 许可证** —— https://raw.githubusercontent.com/juanfont/headscale/main/LICENSE （抓取 2026-09-27）
> "BSD 3-Clause License  Copyright (c) 2020, Juan Font"

**(5) 成熟度（GitHub HTML，2026-09-27）**
- stars：https://github.com/juanfont/headscale "aria-label=\"44152 users starred"（44,152）
- 最新 release：https://github.com/juanfont/headscale/releases 最新 `v0.29.4`，`datetime="2026-09-23"`（前一 v0.29.3 @ 2026-07-29）

### 4.3 对硬约束的判定：**中继可行（DERP over TCP443）；但 headscale 本体不解决数据面，价值与局限都来自"它只是控制面"**

- **可行部分**：这台 TCP-only 机器可以跑 headscale 并启用内嵌 DERP（或独立 derper），对客户端只需开放**入站 TCP/443**；当国内节点间 P2P/UDP 打洞失败时，tailscale 客户端会经 **DERP/TLS-TCP443** 中继。源码证实 DERP 中继与 STUN 解耦，STUN(UDP3478) 可关，不影响 TCP443 中继。
- **必须澄清的因果关系（任务书特别要求）**：
  - headscale 自身监听的是给客户端拉配置的 HTTPS（TCP）；它**不转发节点数据**。
  - "自建 DERP 受阻于 UDP"这一说法若成立，只可能指 derper 上那个**可选的 STUN/UDP3478** 被封；而 **DERP 中继的数据承载本来就是 TCP/443 HTTPS**，并非 UDP。因此只要客户端能 outbound TCP443 到该机器，即使入站 UDP 全封，DERP 中继仍有效（代价：失去该 DERP 的 STUN 辅助打洞，更可能长期停留在中继而非回升 P2P）。
- **作为独立控制面的价值**：开源、可完全自控账号/ACL/路由/DERP map，不依赖 Tailscale 官方服务器；Windows/各端继续用成熟官方客户端，零新客户端成本；与现有 tailscale 是"换登录服务器"而非叠加隧道。
- **局限**：不改变 Tailscale 数据面行为与性能（DERP 仍是用户态、延迟较高的中继）；社区项目非 Tailscale 官方出品，版本与客户端协议兼容性需自行跟进；若诉求本就是"避免官方协调、但又想要 P2P 打洞的 STUN"，UDP 入站缺失会让节点更依赖 DERP 中继。



