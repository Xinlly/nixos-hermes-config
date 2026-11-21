# Worker-C 调研报告：TCP 隧道 / 反向代理组网 + 商业 SD-WAN

- 调研日期：2026-09-27（抓取日）
- 硬约束场景：雨云共享 NAT VPS，**公网入站 UDP 不可用、入站 TCP 可用**；节点（江苏移动 Windows、NixOS raiyun/raiyun2）均在 NAT 后。
- 核心问题：**双方 NAT 后、仅一台 TCP 公网机，能否多节点 IP 层互通？哪些只能端口暴露？**
- 证据均为一手页面/源码实读；不确定项标 [UNCERTAIN]。

---

## 1. frp（fatedier/frp）

| 维度 | 结论 |
|---|---|
| 模型 | 反向端口隧道（TCP/UDP/HTTP/HTTPS/STCP/XTCP/tcpmux）；v0.62.0 新增 **VirtualNet TUN 虚拟组网（Alpha）** |
| 公网端要求 | frps 只需一个 TCP 端口（默认 7000）即可完成控制面+TCP 中继；UDP 代理/KCP/QUIC 才需 frps 入站 UDP |
| XTCP P2P | **依赖 UDP**：STUN 发现（UDP）、UDP 打洞、隧道承载为 KCP 或 QUIC（均 UDP）。frps 仅做信令交换，信令走 TCP 控制连接 |
| 硬约束适配 | ① STCP 中继：只需 frps TCP，可用，但本质是**端口隧道**；② XTCP：打洞成败取决于双方 NAT 类型（中国移动多为对称 NAT），且无法用禁 UDP 的 VPS 做辅助打洞；打洞失败官方建议 fallback stcp；③ **VirtualNet：直接给出 IP 层互通，承载于 stcp（即 frps TCP 中继），但仅 Linux/macOS、Alpha、无 Windows** |
| 多节点 IP 互通 | 官方原生能力 = VirtualNet（Alpha，无 Windows 端）；传统替代：frp TCP 隧道里跑 WireGuard（WG over TCP，如 udp2raw/wireguard-go TUN）属拼装方案 |
| 许可证 | Apache-2.0（LICENSE 原文；GitHub API 同） |
| 成熟度 | 109,645 stars（2026-09-27 API）；最新 release v0.71.0（2026-08-14）；仓库未 archived，2026-09-15 仍有 push；README 明示正在做不兼容的 v2 |
| NixOS/Windows | NixOS 有 frp 模块/包（见第 7 节实时查询）；Windows 官方提供 frpc.exe；VirtualNet 不支持 Windows |
| Tailscale 共存 | 纯客户端进程+独立端口，可共存；IP overlay 需注意路由表优先级 |

### 原文引述

1) README 定位（仅端口代理，P2P 是数据面直连）：
https://raw.githubusercontent.com/fatedier/frp/dev/README.md （抓取 2026-09-27）
> "frp is a fast reverse proxy that allows you to expose a local server located behind a NAT or firewall to the Internet. It currently supports **TCP** and **UDP**, as well as **HTTP** and **HTTPS** protocols … frp also offers a P2P connect mode."
> "**xtcp** is designed to transmit large amounts of data directly between clients. A frps server is still needed, as P2P here only refers to the actual data transmission."
> "Note that it may not work with all types of NAT devices. You might want to fallback to stcp if xtcp doesn't work."

2) XTCP 依赖 UDP 的源码铁证（dev 分支，2026-09-27 抓取）：
- `pkg/nathole/discovery.go:68` — `conn, err := net.ListenUDP("udp4", local)`；`:90` `serverAddr, err := net.ResolveUDPAddr("udp4", addr)`（STUN over UDP）
- `client/visitor/xtcp.go:247-252` 流程注释：
  > "// 0. PreCheck / 1. Prepare / 2. ExchangeInfo / 3. MakeNATHole / 4. Create a tunnel session using an underlying UDP connection."
- `client/visitor/xtcp.go:340` — `lConn, err := net.DialUDP("udp", laddr, raddr)`（KCP 模式承载于 UDP）
- `client/visitor/xtcp.go:409` — `quicConn, err := quic.Dial(...)`（QUIC 同样承载于 UDP）
- 即：STUN 解析、打洞、KCP/QUIC 数据面**全部 UDP**；frps 与 frpc 之间 NatHoleVisitor/NatHoleResp 信令消息走既有控制连接（默认 TCP 7000）。

3) VirtualNet（IP 层）官方文档：
https://raw.githubusercontent.com/fatedier/frp/dev/doc/virtual_net.md （抓取 2026-09-27）
> "The VirtualNet feature enables frp to create and manage virtual network connections between clients and visitors through a TUN interface. This allows for IP-level routing between machines, extending frp beyond simple port forwarding to support full network connectivity."
> "**Note**: VirtualNet is an Alpha stage feature and is currently unstable. … Do not use this feature in production environments …"
> 配置形态：服务端 `type = "stcp"` + `[proxies.plugin] type = "virtual_net"`；visitor 同样挂 stcp + virtual_net 插件，地址如 `100.86.0.1/24`、`100.86.0.2/24`。
> 限制原文："**Permissions**: Creating a TUN interface requires elevated permissions (root/admin)"；"**Platform Support**: Currently supported on Linux and macOS"（**无 Windows**）。
→ 含义：IP 包封在 stcp 字节流里经 frps TCP 中继，**恰好适配"仅 TCP 公网机"**；但 Windows 宿主机无法作为 VirtualNet 端点，且 Alpha 不稳定。

4) KCP/QUIC 才需 frps UDP；纯 TCP 控制面即可跑 stcp/tcp：
README "Support KCP Protocol"：> "KCP mode uses UDP as the underlying transport."；"Support QUIC Protocol"：> "QUIC is a new multiplexed transport built on top of UDP."

### 硬约束判定（frp）
- **端口隧道层面：完全可行**。frps 只占一个 TCP 公网端口；多个内网节点各跑 frpc，可用 stcp+secretKey 互访，或各自暴露 remotePort。
- **IP 层互通：官方新能力 VirtualNet 成立（TCP 中继、TUN、多节点可编同一 /24），但 Alpha 且仅 Linux/macOS——本场景 Windows 宿主机被排除在外；NixOS 两机之间可用它实验。**
- XTCP 不能指望：数据面 UDP，且双方移动 NAT 打洞成功率无保证；禁 UDP 的 VPS 也无法提供 assisted address 辅助打洞。

---

## 2. rathole（rathole-org/rathole，原 rapiz1/rathole）

| 维度 | 结论 |
|---|---|
| 模型 | **纯反向端口隧道**（Rust），定位 frp/ngrok 同类；无 visitor、无 P2P、无 TUN |
| 传输层 | `tcp` / `tls` / `noise` / `websocket`——**全部承载于 TCP**；支持 socks5/http 上游代理连出 |
| 业务协议 | 每服务 `type = "tcp"` 或 `"udp"`；注意 **UDP 服务要在公网机 bind UDP 端口**（入站 UDP），本场景不可用；TCP 服务仅需入站 TCP |
| 硬约束适配 | TCP 端口暴露：适配（一个 TCP 控制口 + 每服务一个 TCP 口）。**IP 层互通：官方明确不做**，out-of-scope 文档直接让用户用 WireGuard/ZeroTier |
| 许可证 | Apache-2.0（LICENSE 原文） |
| 成熟度 | 14,262 stars；仓库未 archived，2026-08-23 仍有 push（已迁至 rathole-org）；但**最新正式 release 仍为 v0.5.0（2023-10-01）**，近三年无新正式版，发布节奏停滞 |
| NixOS/Windows | NixOS 有 rathole 包（见第 7 节）；Windows 官方 release 提供 .exe；官方含 systemd 示例 |
| Tailscale 共存 | 单二进制+配置文件，无 TUN，完全不冲突 |

### 原文引述

https://raw.githubusercontent.com/rathole-org/rathole/main/README.md （抓取 2026-09-27）
> "A secure, stable and high-performance reverse proxy for NAT traversal, written in Rust"
> "rathole, like frp and ngrok, can help to expose the service on the device behind the NAT to the Internet, via a server with a public IP."
> 传输配置原文：`type = "tcp" # Possible values: ["tcp", "tls", "noise"]`（websocket 见 `[client.transport.websocket]`）；服务协议：`type = "tcp" # Possible values: ["tcp", "udp"]`。

Out-of-scope（明确拒绝组网/visitor 模式）：
https://raw.githubusercontent.com/rathole-org/rathole/main/docs/out-of-scope.md
> "- *`frp`'s STCP or other setup that requires visitors' side configuration* — If that kind of setup is possible, then there are a lot more tools available. You may want to consider secure tunnels like wireguard or zerotier. `rathole` primarily focuses on NAT traversal by forwarding, which doesn't require any setup for visitors."

官方 benchmark（注明条件，勿外推）：
https://raw.githubusercontent.com/rathole-org/rathole/main/docs/benchmark.md
> "Date: 2021/12/28 / Version: commit 1180c7e538564efd697453a1b74a5ed2 / Arch Linux … Intel Xeon E5-2620"
> README 同时警告："**However, don't take it from here that `rathole` can magically make your forwarded service faster several times than before.** The benchmark is done on local loopback …"
> 其数据：QPS≤3000 时两者延迟几乎相同（如 QPS=1000：rathole 1.723ms / frp 1.742ms）；QPS=4000 时 frp 7907ms、大量报错，rathole 2.569ms；"rathole uses much less memory than frp."

### 硬约束判定（rathole）
- **只能做端口暴露（TCP 适配、UDP 不适配入站禁 UDP 的 VPS）；无任何原生 IP 层/多节点互通路径，且官方明示该需求请用 WireGuard/ZeroTier。**
- 相对 frp 的价值：省内存、高并发更稳、Noise 免证书加密；但发布停滞（最新版停在 2023-10）。

---

## 3. NPS（ehang-io/nps）

| 维度 | 结论 |
|---|---|
| 模型 | 带 Web 管理面板的内网穿透代理服务器（反向隧道）；协议 tcp/udp/http(s)/socks5/http proxy/**p2p** |
| 架构 | nps 服务端（默认占用 80/443/8080/**8024 网桥口 TCP**）+ npc 客户端；网页配置即开隧道 |
| 硬约束适配 | TCP 端口隧道本身经 8024 TCP 网桥，**可在仅入站 TCP 的公网机上跑**；但其 **p2p 模式要求 nps 服务端监听 UDP（`net.ListenUDP`）→ 本场景不可用**；且仍是端口级，无 IP overlay |
| 维护状态（证据） | **事实停更**：最新 release v0.26.10（2021-04-08）；master 默认分支最新提交 2021-10-09；527 个未结 issue；仓库未显式 archived（`archived:false`）但 2024-05-30 后无 push |
| 许可证 | **GPL-3.0**（LICENSE 原文；注意与 frp/rathole 的 Apache-2.0 不同，二次分发/商用闭源受限） |
| 成熟度 | 34,237 stars；文档站仍在，但核心已 5 年无维护 |
| 安全历史 | 默认后台口令 admin/123（README 自述"must be modified when officially used"）；**CVE-2022-40494 认证绕过**（影响 0.26.10 之前版本）；社区有 NpsBypass 工具 |
| NixOS/Windows | NixOS 有 nps 打包（见第 7 节实时查询）；官方提供 Windows nps/npc.exe |
| Tailscale 共存 | 端口进程，可共存；面板暴露公网有安全面 |

### 原文引述

https://raw.githubusercontent.com/ehang-io/nps/master/README.md （抓取 2026-09-27，master HEAD 停在 2021-10）
> "NPS is a lightweight, high-performance, powerful **intranet penetration** proxy server, with a powerful web management terminal."
> "Comprehensive protocol support, compatible with almost all commonly used protocols, such as tcp, udp, http(s), socks5, p2p, http proxy ..."
> 默认端口说明："8024 for net bridge port, to communicate between server and client"；默认口令："Login with username and password (default is admin/123, must be modified when officially used)."

维护状态（GitHub API，2026-09-27 实读）：
- `releases/latest` → `"tag_name": "v0.26.10"`，`"published_at": "2021-04-08T06:32:17Z"`
- 默认分支最新提交（`/commits?per_page=3`）→ `"date": "2021-10-09T07:18:41Z"`，message "Merge pull request #866 … add build to apple silicon(M1)"
- `"open_issues": 527`；`"pushed_at": "2024-05-30T03:51:08Z"`；`"archived": false`
- LICENSE：https://raw.githubusercontent.com/ehang-io/nps/master/LICENSE → "GNU GENERAL PUBLIC LICENSE Version 3, 29 June 2007"

P2P 模式依赖服务端 UDP（源码铁证）：
https://raw.githubusercontent.com/ehang-io/nps/master/server/proxy/p2p.go （master，抓取 2026-09-27）
- `:16` `listener *net.UDPConn`
- `:34` `s.listener, err = net.ListenUDP("udp", &net.UDPAddr{net.ParseIP("0.0.0.0"), s.p2pPort, ""})`
- 文档侧 p2p 用法：https://raw.githubusercontent.com/ehang-io/nps/master/docs/use.md 「#### p2p代理模式」`mode=p2p`（中文原文照抄）。

安全：
- CVE-2022-40494（OSV 一手条目）：https://osv.dev/vulnerability/CVE-2022-40494
  > "NPS before v0.26.10 was discovered to contain an authentication bypass vulnerability via constantly generating and sending the Auth key and Timestamp parameters."
- Snyk 条目：https://security.snyk.io/vuln/SNYK-GOLANG-EHANGIONPSWEBCONTROLLERS-3041018 （"Authentication Bypass … CVE-2022-40494"，CVSS 5.3）
注：OSV 措辞为 0.26.10 之前受影响，但修复版本即最后一版且修复时间晚于 release 节奏，后续无任何安全维护窗口。

### 硬约束判定（NPS）
- **TCP 端口隧道：技术上能在仅 TCP 公网机上跑（8024 网桥 + TCP 转发），但项目事实停更 5 年、GPL-3.0、有认证绕过史和默认弱口令，不建议作为新建设施。**
- **p2p 打洞需服务端入站 UDP，本场景出局；无 IP 层组网能力。**
