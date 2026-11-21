# Worker-B 调研任务书：去中心化 P2P VPN / Overlay 方案

你是独立只读 research worker。你没有任何会话上下文，严格按本任务书执行。

## 背景（你需要知道的全部）
- 我们有一台雨云**共享 NAT VPS**：公网**入站 UDP 不可用**（运营商 NAT 不映射 UDP），公网**入站 TCP 可用**。出站 TCP/UDP 正常。
- 国内节点：Windows 宿主机（江苏移动出口 WAN_EGRESS_IP）、NixOS 服务器（raiyun/raiyun2）。目标：国内节点之间可靠异地组网/中继互联。
- Tailscale、EasyTier 已由其他线评估，**你不要调研这两个**。
- 硬约束问题：**该方案能否让一台「仅公网入站 TCP 可用」的机器充当有效 supernode/中继/lighthouse 节点？** 这是第一判据。

## 你负责的方案（去中心化/去服务器 P2P 类）
1. **Nebula**（Slack 开源）：lighthouse 机制、是否纯 UDP、TCP 支持现状（nebula 在 2023-2025 有无 TCP 模式的 issue/PR/现实结论）
2. **Tinc**（1.1 预版）：TCP-only 模式（Mode=switch/router 与 TCP 的关系）、tinc 1.1 的成熟度
3. **N2N**（ntop 版 n2n，含 3.0 supernode）：supernode 用 UDP 还是 TCP、能否 TCP 运行、federation
4. **SoftEther VPN**：VPN over ICMP/DNS/TCP（NAT-T）、SoftEther 协议的 TCP 能力、服务器端需求、许可证（GPLv2）与近年活跃度
5. （如预算允许，简评）**Fastd / Tinc 之外的轻量替代**：仅在它们对 TCP-only 有明确优势时写，否则跳过并说明

## 每个方案必须回答的维度
- 组网模型（P2P mesh / 中心 supernode / 桥接）与数据面协议
- 对「公网入站 UDP 不可用、仅 TCP」的适配性：能否配置成纯 TCP 或有 TCP 回退；TCP 模式的性能/成熟度代价
- 能否自建中继/supernode/lighthouse；对网络的要求
- NixOS 部署成本（search.nixos.org 实时查包与模块；softether/nebula/n2n/tinc 各自）
- Windows 部署成本（官方/社区客户端质量）
- 许可证（仓库 LICENSE 原文）
- 成熟度/生态（stars、最近 release/commit 活跃度，实时取）
- 与现有 Tailscale 共存性

## 证据纪律（硬约束，缺一不合格）
1. **必须真实读取一手页面**：官方文档、GitHub 仓库 README/docs/源码、官方 issue/PR。禁止只用 web_search 摘要拼凑。
2. 读取通道：终端 `curl -sL` 抓 raw.githubusercontent.com 上的 README/docs/源码（本环境终端侧 raw 可解析，已实证）；文档站用 web_extract（若报 cannot extract 则转 curl/browser，勿纠缠）；JS 页可用 browser_exec。
3. **每条关键结论附证据**：完整 URL + 原文关键句照抄（不改写）；源码给 `file:line`（注明 commit short SHA + 抓取日期 2026-09-27）。
4. 特别要钉死：
   - Nebula lighthouse 是否只说 UDP（官方 docs 原文）；GitHub issue 里对 TCP support 的官方表态与最新状态
   - tinc 文档中 `TCPonly`/tinc.conf 相关原文；tinc 1.1 平台支持
   - n2n supernode 监听协议（edge/supernode manpage 或源码里的 TCP 选项，如 `-t` tcp port 是否存在于当前版本）
   - SoftEther 官方手册关于 VPN over TCP/ICMP/DNS（NAT Traversal）的原文；SoftEther 服务端监听端口
5. 不确定标 **[UNCERTAIN]**。禁止编造。
6. **边查边写**：每完成一个方案立即追加写入输出文件。

## 输出契约
- 报告写到绝对路径：`/var/lib/hermes/.paseo/worktrees/0tnh6fc8/research-networking-alt-solutions/research/worker-b.md`（目录不存在先创建；只允许写本 worktree 内文件）。
- 报告结构：每方案一节（维度表 + 原文引述带URL + 硬约束判定）；末尾「证据来源清单表」+「未验证项」。
- 写完自行 read_file 验证落盘并统计行数。
- 最终回报只给：报告路径 + 每方案一句话判定 + 未验证项数量。预算 ≤ 30 次工具调用。

## 红线
只读调研；不安装、不部署、不改配置、不重启；不碰 Tailscale/EasyTier 在研文件；不写本 worktree 之外路径。
