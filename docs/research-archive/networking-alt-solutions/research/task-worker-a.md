# Worker-A 调研任务书：中心协调型 Mesh Overlay 方案

你是独立只读 research worker。你没有任何会话上下文，严格按本任务书执行。

## 背景（你需要知道的全部）
- 我们有一台雨云**共享 NAT VPS**：公网**入站 UDP 不可用**（运营商 NAT 不映射 UDP），公网**入站 TCP 可用**。出站 TCP/UDP 均正常。
- 国内节点：Windows 宿主机（江苏移动出口 WAN_EGRESS_IP）、NixOS 服务器（raiyun/raiyun2）。目标：国内节点之间可靠异地组网/中继互联。
- Tailscale（自建 DERP 受阻于 UDP）、EasyTier 已由其他线评估，**你不要调研这两个**。
- 硬约束问题：**该方案能否让一台「仅公网入站 TCP 可用」的机器充当有效组网协调/中继节点？** 这是第一判据。

## 你负责的方案（中心协调型 mesh）
1. **ZeroTier**（含自建 planet/moon 的可行性与 TCP 回退）
2. **Netmaker**（含 Netclient 的 TCP/relay 机制，以及 2024-2025 架构变化）
3. **NetBird**（自建 Management/Signal/Relay，Relay 是否支持 TCP/TLS）
4. **headscale**（与 Tailscale 客户端配合；DERP 是否只能 UDP、自建 DERP over TCP443 的实际行为；用户已用 tailscale 但仍需说明作为独立控制面的价值与局限）

## 每个方案必须回答的维度
- 组网模型（P2P / 中心中继 / 混合）与数据面协议（WireGuard? 自研?）
- 对「公网入站 UDP 不可用、仅 TCP」的适配性：**是否依赖公网入站 UDP 打洞；打洞失败后的回退是什么；回退能否走 TCP/443/TLS/WebSocket**
- 能否完全自建控制面与中继；自建中继对网络的要求
- NixOS 部署成本（nixpkgs 是否有包/模块，以 search.nixos.org 实时结果为准）
- Windows 部署成本（官方客户端情况）
- 许可证（以仓库 LICENSE 原文/当前版本为准，注意 Netmaker 等的许可证变更历史）
- 成熟度/生态（stars、发版活跃度、最近 release 时间——实时取）
- 与现有 Tailscale 共存性（是否冲突、能否同机并存）

## 证据纪律（硬约束，缺一不合格）
1. **必须真实读取一手页面**：官方文档站、GitHub 仓库 README/docs/源码、官方 issue。禁止只用 web_search 的摘要拼凑结论。
2. 读取通道优先级：`web_extract` 对官方文档页可先用（注意：本环境 web_extract 可能报 cannot extract，若报错立即改用其他通道，不要反复试）；失败则用终端 `curl -sL` 抓 raw.githubusercontent.com 上的文档/源码（终端侧 raw 可解析，已实证）；JS 渲染页可用 browser_exec（若 chrome 不可用则放弃该通道）。
3. **每条关键结论必须附证据**：完整 URL + 原文关键句照抄（英文原文，不改写），源码结论给 `file:line`（以你 curl 下来的当前默认分支版本为准，注明 commit short SHA 与抓取日期 2026-09-27）。
4. 不确定/查不到的标 **[UNCERTAIN]** 并说明缺什么证据。禁止编造许可证、命令、性能数字。
5. 特别要钉死的事实（举例，不限于此）：
   - ZeroTier 是否有 TCP fallback（官方手册原文怎么说；moon 节点能否只靠 TCP；planet 自建的官方/非官方地位）
   - NetBird relays 用什么协议（STUN? WireGuard over UDP? 有无 TCP 回退），客户端在对称 NAT 下的行为
   - Netmaker 的 Ingress/relay（原 egress/relay 机制）是否依赖公网 UDP
   - headscale 本身只是控制面；DERP 中继 derper 是否强制 UDP（HTTPS/TCP 443 客户端访问 DERP 的路径与 UDP 入站的关系）
6. **边查边写**：每查完一个方案立即把该方案完整条目追加写入输出文件，不要攒到最后。

## 输出契约
- 报告写到绝对路径：`/var/lib/hermes/.paseo/worktrees/0tnh6fc8/research-networking-alt-solutions/research/worker-a.md`（目录不存在先创建；只允许写本 worktree 内文件）。
- 报告结构：每个方案一节，含「维度表 + 关键结论原文引述（带URL）+ 对硬约束的判定（可行/不可行/[UNCERTAIN]及理由）」；末尾给「证据来源清单表」（编号|URL|取证方式|关键引述一句）和「未验证项」。
- 写完后自行 read_file 验证落盘并统计行数。
- 最终回报只给：报告路径 + 每个方案一句话判定 + 未验证项数量。预算 ≤ 30 次工具调用。

## 红线
只读调研；不安装、不部署、不改配置、不重启任何东西、不碰 Tailscale/EasyTier 的在研文件；不写本 worktree 之外的任何路径。
