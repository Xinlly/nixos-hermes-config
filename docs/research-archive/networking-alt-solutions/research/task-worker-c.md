# Worker-C 调研任务书：TCP 隧道/反向代理组网 + 商业 SD-WAN 方案

你是独立只读 research worker。你没有任何会话上下文，严格按本任务书执行。

## 背景（你需要知道的全部）
- 我们有一台雨云**共享 NAT VPS**：公网**入站 UDP 不可用，入站 TCP 可用**。出站 TCP/UDP 正常。
- 国内节点：Windows 宿主机（江苏移动出口 WAN_EGRESS_IP）、NixOS 服务器（raiyun/raiyun2）。目标：国内节点之间可靠异地组网/中继互联（最好能像局域网一样互通 IP，而不只是单端口暴露）。
- Tailscale、EasyTier 已由其他线评估，**不要调研**。
- 硬约束问题：**这些方案在「节点双方都在 NAT 后、只有一台 TCP 公网机」时，能否实现多节点 IP 层互通？哪些只能做端口暴露？** 请严格区分「端口隧道」与「组网/IP overlay」两个层级。

## 你负责的方案
1. **frp (fatedier/frp)**：架构（server 需要公网）、TCP/HTTP/STCP/XTCP（XTCP P2P 打洞是否依赖 UDP）、visitor 模式能否做多点互联、性能
2. **rathole (rapiz1/rathole)**：与 frp 对比、是否纯 TCP、性能
3. **NPS (ehang-io/nps)**：内网穿透面板、支持的协议、近年维护状态（仓库是否 archived/停更）、安全历史
4. **Cloudflare Tunnel（cloudflared）**：能力边界（能否暴露任意 TCP/UDP、能否 IP 组网/WARP 互访、中国大陆访问 cloudflare 边缘的现实——有实测证据才写，否则标 [UNCERTAIN]）
5. **蒲公英 / 贝锐（Oray）**：商业方案，P2P+服务器转发、免费版带宽限制、客户端平台（Windows/Linux/有无 headless Linux）、能否纯 TCP 中继、企业版成本；以官网当前页面为准
6. （简评，如预算允许）**ZeroTier 商业 moon/替代商业 SD-WAN（如 OmniEdge、Tailscale 竞品如 Twingate/Grapho）**：仅在与「TCP 中继组网」直接相关时简述

## 每个方案必须回答的维度
- 模型：反向端口隧道 / P2P 打洞 / IP 层组网 / 商业 SD-WAN
- 对硬约束的适配：frp server 只需 TCP 公网即可？XTCP 打洞是否依赖 UDP（frp 文档/源码原文）；能不能用 frp 拼出多节点 IP 互通（如配合 WireGuard over TCP）
- 自建程度；NixOS（search.nixos.org 实时查）与 Windows 部署成本
- 许可证（LICENSE 原文；NPS 等注意）；成熟度/活跃度（stars、最近 release，实时取；NPS 停更要拿证据）
- 性能数据有无官方基准（如 rathole/frp README 的 benchmark，原文引用并注明其测试条件）
- 与现有 Tailscale 共存性

## 证据纪律（硬约束，缺一不合格）
1. **必须真实读取一手页面**：GitHub 官方 README/docs/源码、官网当前页面、官方 issue。禁止只用 web_search 摘要拼凑。
2. 读取通道：终端 `curl -sL` 抓 raw.githubusercontent.com（本环境终端侧 raw 可解析）；官网/文档用 web_extract（报 cannot extract 即转通道，勿纠缠）；JS 渲染或需交互的商业官网可用 browser_exec（chrome 不可用则放弃并如实记录）。
3. **每条关键结论附证据**：完整 URL + 原文关键句照抄（中文官网原文照抄）；源码给 `file:line`（commit short SHA + 抓取日期 2026-09-27）。
4. 不确定标 **[UNCERTAIN]**（尤其是 Cloudflare 中国大陆访问质量、蒲公英免费版实时带宽政策——官网没写清就标 UNCERTAIN，不采信旧博客）。禁止编造。
5. **边查边写**：每完成一个方案立即追加写入输出文件。

## 输出契约
- 报告写到绝对路径：`/var/lib/hermes/.paseo/worktrees/0tnh6fc8/research-networking-alt-solutions/research/worker-c.md`（目录不存在先创建；只允许写本 worktree 内文件）。
- 报告结构：每方案一节（维度表 + 原文引述带URL + 硬约束判定）；末尾「证据来源清单表」+「未验证项」。
- 写完自行 read_file 验证落盘并统计行数。
- 最终回报只给：报告路径 + 每方案一句话判定 + 未验证项数量。预算 ≤ 30 次工具调用。

## 红线
只读调研；不安装、不部署、不改配置、不重启；不碰 Tailscale/EasyTier 在研文件；不写本 worktree 之外路径。
