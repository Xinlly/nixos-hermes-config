# Worker-B 调研报告：去中心化 P2P VPN / Overlay 方案

- 调研日期：2026-09-27
- 硬约束：雨云共享 NAT VPS，公网**入站 UDP 不可用**、公网**入站 TCP 可用**，出站 TCP/UDP 正常。问题＝该机器能否充当有效 supernode / lighthouse / 中继。
- 证据均为 2026-09-27 实时抓取的一手页面（官方文档 / GitHub 仓库 / 官方 issue）。原文引述照抄不译。

---

## 1. Nebula（slackhq/nebula）

### 维度表

| 维度 | 结论 |
|---|---|
| 组网模型 | P2P mesh + lighthouse（仅做成员发现/坐标，不转发数据）；NAT 打洞（punchy）；另有 relay 功能（relay 节点转发**UDP underlay** 流量） |
| 数据面协议 | **仅 UDP**（underlay），默认端口 4242 |
| TCP 支持 | **不支持**；截至 2026-05 官方维护者明确表态 underlay 无法用 TCP，仅在评估、无具体计划 |
| 入站 UDP 不可用机器能否当 lighthouse/中继 | **不能（有效）**。lighthouse 需接收节点 UDP 上报并回应；relay 也是在 UDP underlay 上转发。仅入站 TCP 的机器无法承担 |
| 自建 lighthouse | 可以，配置 `lighthouse` 启用即可；但要求 lighthouse 有可公网达的 UDP 地址（官方示例注释） |
| NixOS 部署 | [待第 5 节统一核查] |
| Windows 部署 | 官方支持，README 明列 Windows；GitHub Releases 提供 Windows 二进制 |
| 许可证 | MIT（GitHub License API: MIT） |
| 成熟度/生态 | 18,393 stars；最近 push 2026-09-25（活跃）；Slack 出品，Defined.net 维护文档 |
| 与 Tailscale 共存 | overlay 各自独立网卡/网段，可共存；但两者都做 UDP 打洞，无互操作，lighthouse 仍需另找 UDP 可达点 |

### 原文引述

1. 官方配置文档 listen 页（明确"UDP port"）：
   URL: https://nebula.defined.net/docs/config/listen/
   > "listen.port ​ port is the UDP port nebula should use on a host."
   > "listen.read_buffer, listen.write_buffer ​ Configure socket buffers for the udp side (outside), leave unset to use the system defaults."

2. 官方配置示例（lighthouse 节点需定义端口；static_host_map 指向 lighthouse 公网 IP:4242）：
   URL: https://raw.githubusercontent.com/slackhq/nebula/master/examples/config.yml
   > "# Example, if your lighthouse has the nebula IP of 192.168.100.1 and has the real ip address of 100.64.22.11 and runs on port 4242:"
   > "# Port Nebula will be listening on. The default here is 4242. For a lighthouse node, the port should be defined,"
   （抓取于 2026-09-27；注：master 分支该示例文件中 lighthouse 启用键在源文件里被写成占位符 `***`，应为模板处理所致，不影响结论。）

3. 官方 issue #1001「Support TCP protocol (or TCP relaying) for networks that block or shape UDP traffic」：
   URL: https://github.com/slackhq/nebula/issues/1001
   - 提问（2023-10-21）："Is it possible to use tcp protocol for relay forwarding?"
   - 维护者 **nbrownus** 关单回复（2026-05-19，原文照抄）：
   > "It is not currently possible to use TCP in the underlay. We are evaluating it but no concrete plans to date."

### 硬约束判定：❌ 不满足
Nebula underlay 纯 UDP，官方 2026-05 仍确认无 TCP、无具体计划。仅公网入站 TCP 的雨云机器**不能**充当有效 lighthouse 或 relay（lighthouse 收不到节点 UDP 上报；relay 转发的也是 UDP）。

---

## 2. Tinc（gsliepen/tinc，1.1pre 预版）

### 维度表

| 维度 | 结论 |
|---|---|
| 组网模型 | P2P mesh（默认 router 模式，按 Subnet 路由；也可 switch/hub）；节点间先建 TCP meta connection 交换信息，默认数据面走 UDP，支持 UDP 打洞，失败时经其他节点转发（IndirectData） |
| 数据面协议 | 默认 UDP；**可用 `TCPonly = yes` 改为纯 TCP 封装数据** |
| TCP 支持 | **官方原生支持**：`TCPonly` 主机配置变量；TCP 是 tinc 的 meta 连接本身，控制面天然 TCP。代价：TCP-over-TCP 在丢包链路上拥塞控制叠加，性能/延迟变差；官方文档未给性能数字 |
| 入站 UDP 不可用机器能否当节点/中继 | **可以**。在相关 host 配置设 `TCPonly = yes`，该机器仅入站 TCP 即可参与 mesh 并为其他节点转发流量（转发在 mesh 层、TCP meta 连接上承载数据） |
| 自建中继 | 无独立"supernode"概念；任何有可达地址的节点都能转发；TCPonly 节点作为纯 TCP 入口点成立 |
| 1.1 成熟度 | 最新 tag 为 **release-1.1pre18**（仍为 pre 预版）；1.1pre 系列长期被发行版实际采用（Debian/Ubuntu 的 tinc 即 1.1pre）；仓库最近 push 2026-06-27 |
| NixOS 部署 | [待统一核查]（Nixpkgs 有 tinc 及 services.tinc 模块） |
| Windows 部署 | 官方支持 MinGW 原生构建（Windows 2000…10）+ tap64 驱动；但构建/驱动获取偏手工，无现代签名安装器体验 |
| 许可证 | GPLv2-or-later（COPYING）；GitHub License API 显示 NOASSERTION |
| 成熟度/生态 | 2,251 stars；老牌项目（1998 起），低频但持续维护 |
| 与 Tailscale 共存 | 可共存（独立 tun/tap 接口与网段）；无互操作 |

### 原文引述

1. tinc 1.1 手册「Host configuration variables」TCPonly 原文：
   URL: https://www.tinc-vpn.org/documentation-1.1/Host-configuration-variables.html
   > "TCPonly = <yes|no> (no) If this variable is set to yes, then the packets are tunnelled over a TCP connection instead of a UDP connection. This is especially useful for those who want to run a tinc daemon from behind a masquerading firewall, or if UDP packet routing is disabled somehow. Setting this options also implicitly sets IndirectData."

2. tinc 1.1 手册「Main configuration variables」Mode 原文：
   URL: https://www.tinc-vpn.org/documentation-1.1/Main-configuration-variables.html
   > "Mode = <router|switch|hub> (router) This option selects the way packets are routed to other daemons. router In this mode Subnet variables in the host configuration files will be used to form a routing table. Only packets of routable protocols (IPv4 and IPv6) are supported in this mode. This is the default mode, and unless you really know you need another mode, don’t change it."
   （Mode 决定路由/交换语义，与是否用 TCP 正交；TCP 由 TCPonly 控制。）

3. 平台支持（Windows 现状）：
   URL: https://www.tinc-vpn.org/platforms/
   > "Windows (MinGW) i386, x86_64 with tap64 driver Runs natively under Windows 2000, XP, Vista, 7, 8 and 10"

4. 许可证：
   URL: https://raw.githubusercontent.com/gsliepen/tinc/master/COPYING
   > "Copyright (C) 1998-2026 Ivo Timmermans, Guus Sliepen and others."
   > "This program is free software ... under ... the GNU General Public License ... either version 2 of the License, or (at your option) any later version."
   tags（GitHub API 实时取）：release-1.1pre18 为最新；仓库最近 push 2026-06-27。

### 硬约束判定：✅ 满足（功能满足，成熟度/性能有代价）
官方 `TCPonly = yes` 即为"NAT 后 / UDP 被禁"场景设计，仅公网入站 TCP 的机器可作为 mesh 节点并转发流量。代价：① 1.1 至今仍是 pre 预版；② TCP-over-TCP 性能损失，官方未量化（具体数值 [UNCERTAIN]）；③ Windows 客户端体验老旧。

---
