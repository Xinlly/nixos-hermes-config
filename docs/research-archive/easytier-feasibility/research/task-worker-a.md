# Worker A 任务书：EasyTier 组网/中继/传输协议模型源码实证

## 背景（你无本会话上下文，先读这些）
- 我们在用 Tailscale 组网，自建 DERP 中继节点位于一台雨云共享 NAT VPS（仅 TCP 入站可用，公网 UDP DNAT 不生效），导致该节点无法成为 Tailscale 可用中继（DERP 虽可 TCP/TLS 建连，但 netcheck 依赖 STUN/UDP 探测，节点恒不被调度）。
- 现调研 EasyTier 是否对"无公网入站 UDP、仅有 TCP"的节点更宽容。
- EasyTier 源码已克隆到本机（只读，勿改）：
  `/var/lib/hermes/.paseo/worktrees/0tnh6fc8/research-easytier-feasibility/research/easytier-src`
  commit ff3921ce6842f9660d629eafac499498026c6784（2026-09-24 上游 main）。
- 重点目录：`easytier-core/src/connectivity/`（connector：direct/hole_punch/manual/stun/transport/protocol）、`easytier-core/src/listener/`、`easytier-core/src/tunnel/`、`easytier-core/src/peers/`、`easytier-core/src/gateway/`、`easytier-proto/proto/`、`easytier/src/`（CLI）。

## 必须回答的问题（每条结论必须给 file:line 证据）
1. 组网模型：网络身份如何建立（network name/secret？）、是否必须有中心节点、节点间路由如何学习、虚拟 IP 如何分配（默认网段是什么，在源码哪里定义）。
2. 传输协议清单：节点互联支持哪些 connector/listener 协议（TCP/UDP/WSS/WS/QUIC/KCP…）？各自在源码哪个模块、如何配置（CLI flag/配置项名称，从 easytier/src 或 config 模块实证）。
3. **核心问题**：一台只有公网 TCP 入站（UDP 入站全部不通）的机器：
   a) 能否作为公共节点被其他节点通过 TCP/WSS 连入？
   b) 它能否为两个不能直连的对端节点**中继转发数据面流量**？EasyTier 有没有 DERP 式中继机制（查 relay/cascade/转发/中继相关代码与 peer_rpc.proto）？中继是自动的还是要显式开启（如 `--relay-network-whitelist`/`default-relay` 之类，以源码实际名称为准）？
   c) 打洞（hole punching）是否强依赖公网 UDP 入站/STUN？纯 TCP 节点之间有没有 TCP 打洞或直接放弃打洞走中继？
4. 数据面：中继链路是否 TCP-over-TCP（性能隐患定性）？隧道加密用什么（查 tunnel/encrypt 与 web_security），密钥如何协商。
5. NAT 容忍度：对 symmetric NAT、仅出向 UDP、严格防火墙的处理逻辑（hole_punch 目录实证），打洞失败后的回退路径。
6. WSS 支持的具体形态：是否自带 TLS/证书配置、能否走 443 端口纯 WSS 接入。

## 取证规则
- 用 search_files/read_file 实读源码，结论标注 `相对路径:行号` + 关键代码原文短句。
- 官方文档（easytier.cn 及其 docs 子站）只能作辅助，且必须用 Playwright MCP 真实打开页面读正文，禁止用 web_search 摘要充当已读；文档说法与源码矛盾时以源码为准并注明。
- 推断不出的标 [UNCERTAIN]，禁止编造函数/机制。

## 边界（红线）
- 只读源码；唯一允许写入的目录：`/var/lib/hermes/.paseo/worktrees/0tnh6fc8/research-easytier-feasibility/research/out/`（先 mkdir -p）。
- 禁止：构建/cargo run/试跑任何二进制、改动网络、连真实节点、写 /tmp 或 worktree 外路径。
- 工具调用预算 ≤25 次；**边查边写**：每答完一个问题即把结论追加写入报告文件，不要攒到最后。

## 输出契约
- 报告写到：`.../research/out/worker-a-protocol.md`（绝对路径：/var/lib/hermes/.paseo/worktrees/0tnh6fc8/research-easytier-feasibility/research/out/worker-a-protocol.md）
- 结构：逐题回答（含 file:line 与原文引句）→ 一页纸总结（"纯 TCP 节点能否当中继"的直接回答）→ 未验证项清单。
- 写完后自行 read_file 验证落盘；最终回报给报告路径 + 3-5 句结论摘要。
