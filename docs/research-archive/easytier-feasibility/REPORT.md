# EasyTier 可行性调研报告：能否解决无公网 UDP 入站节点的中继问题

- 工作线：research/easytier-feasibility（workspace wks_e84b76，worktree 本目录），planner 向 orchestrator 250e1cbc 负责
- 上游源码基线：commit `ff3921ce6842f9660d629eafac499498026c6784`（2026-09-24 上游 main，workspace 版本 2.7.0），本地只读克隆 `research/easytier-src/`
- nixpkgs 基线：nixos-unstable（本仓库 flake 即跟随该分支，`flake.nix`），其中 easytier 包版本 **2.6.4**
- 调研方式：Rust 源码逐行实读（file:line 实证）+ nixpkgs 打包/模块原文下载核读 + 官方页面 Playwright 实读；官网宣传语不直接作为结论
- 调研边界：只读取证。未构建、未试跑、未部署 EasyTier；未改动 Tailscale/雨云/任何现有网络与服务；未 commit/push

---

## 1. 背景与问题定义

### 1.1 当前阻塞（根因前序已钉死，本次不重查）

- 节点 derp-cn-raiyun2：雨云共享 NAT VPS（公网 RAIYUN2_PUBLIC_IP，内网 172.16.71.87），Tailscale DERP region 901。
- DERP TCP/TLS 中继（内部 8010）`tailscale debug derp` 可建立；但雨云共享 NAT 的**公网 UDP DNAT 不生效**：外部源到 STUN 53478 的包 0 到达主机（内网源可达、derper 健康；删重建规则无效；Google STUN 对照证明客户端正常）。
- 结果：Tailscale netcheck 对 region 901 恒无延迟，节点不被调度。
- 阻塞本质：**Tailscale 中继调度要求节点具备可达的 STUN/UDP 探测面。一台只有可用 TCP 入站、没有公网 UDP 入站的机器，无法在 Tailscale 体系内成为可用中继。** Tailscale 路线剩余选项仅雨云工单/弹性公网 IP。

### 1.2 裁决标准

本报告判据不是"EasyTier 能不能组网"，而是"**EasyTier 的中继资格是否把公网 UDP 入站作为必要条件**"，以及在 NixOS 上落地的真实成本与风险。

---

## 2. EasyTier 组网与中继模型（源码实证）

### 2.1 网络身份与去中心化

- 同网络节点凭 `(network_name, network_secret)` 相认，线上只比对 secret 的 32 字节 digest：`easytier-core/src/config/mod.rs:136-150,202-204`。
- 无强制中心节点：节点用 `--peers` 主动拨入任一可达节点入网（`easytier/src/core.rs:208-216`），入网后经类 OSPF 的路由同步学到全网节点（`easytier-core/src/peers/route/peer_ospf_route.rs`）。任何可达节点（含纯 TCP 公网节点）都可充当"介绍人"，无特权 server 角色。
- README 原文："EasyTier is fundamentally decentralized, with no distinction between server and client."（`README.md:176`）

### 2.2 传输协议：TCP/UDP/WS/WSS/QUIC/faketcp/WG

URL scheme → 底层传输映射（`easytier-core/src/connectivity/protocol/mod.rs:23-36`）：

```rust
b"tcp" | b"ws" | b"wss" => Some(ProtocolTransport::Tcp),
b"udp"                 => Some(ProtocolTransport::Udp(UdpSessionMode::EasyTierMux)),
b"quic"                => Some(ProtocolTransport::Udp(UdpSessionMode::Classified(...))),
```

- 即 **TCP / WS / WSS 全部只走 TCP 传输，建连路径上完全不涉及 UDP**。wss 默认端口 443（`protocol/mod.rs:57-58`）。
- listener 侧支持 tcp/udp/ws/wss/quic 等（`easytier-core/src/listener/plan.rs:142-148`）。
- STUN 仅用于 UDP NAT 类型探测（出向），默认服务器 `stun.easytier.cn` 等（`config/mod.rs:21-23`），且收集器同时支持 UDP/TCP STUN（`connectivity/stun/collector.rs:46-48`）。**STUN 模块与 TCP 监听路径相互独立。**

### 2.3 中继数据面：任何节点逐包转发，默认开启，不看 UDP

`easytier-core/src/peers/peer_manager.rs:3078-3112`（PeerPacketRouter 收包循环，已逐行核实）：

```rust
if to_peer_id != self.my_peer_id {
    if drop_relay_data { /* "drop forwarded relay data while relay data is disabled" */ return; }
    if hdr.forward_counter > 7 { /* "forward counter exceed, drop packet" */ return; }
    ...
    hdr.forward_counter += 1;
```

- 即**任何节点收到目标不是自己的包，就按下一跳逐包转发**，最大 7 跳；转发量单独计量（`peer_manager.rs:3136-3145`）。
- 中继默认开启：`config/toml.rs:72` `disable_relay_data: false`。
- 中继网络白名单默认 `"*"`：`config/toml.rs:42`；匹配实现 `peers/whitelist.rs:5-17`（空格分隔、wildmatch 通配）。
- 中继路径由 `peers/relay_peer_map.rs` 维护"经谁可达谁"，中继会话自带 Noise 握手（`relay_peer_map.rs:28-33`）。
- 数据面为**包级帧转发，不是把一条 TCP 字节流套进另一条 TCP**：中间节点不维护内层 TCP 状态/重传，因此不会出现经典 TCP-over-TCP 双重重传崩溃；但两跳 TCP 的**队头阻塞叠加、中继带宽/双程 RTT 代价仍定性存在**。

### 2.4 打洞模型

- UDP 打洞按双方 NAT 类型决定（`connectivity/hole_punch/udp/task.rs:67-80`），对称 NAT 再分"易对称/硬对称"，硬对称有专门报文流程（`udp/runtime.rs:108-117`）。
- 另有独立的 **TCP simultaneous-open 打洞**（`connectivity/hole_punch/tcp.rs:218-276`，注释 "TCP supports simultaneous connect..."，:232）。
- **纯 TCP 公网节点无需打洞**——它有 TCP 入站能力，对端直接经 listener 建连。打洞只发生在双方都在 NAT 后的链路上；打洞失败时数据面仍可经逐包中继互通（中继与打洞在代码上解耦）。

### 2.5 加密

- 默认 AEAD 加密（AES-GCM / ChaCha20-Poly1305），密钥由 network secret 派生：`tunnel/encrypt/mod.rs:41-53,60-71,136-157`；默认 `enable_encryption: true`（`toml.rs:34`）。
- 建链双向认证走 Noise（snow），互验 network_secret_digest：`peers/conn/peer_conn.rs:51,78-91,499,545-547`。具体 Noise pattern 字符串未读到，标 [UNCERTAIN]（见 §8）。

---

## 3. 核心问题裁决：raiyun2 这类机器能否利用？

**能。** 关键差异在于"中继资格"的判定条件：

| 判定环节 | Tailscale DERP | EasyTier |
|---|---|---|
| 中继节点如何被承认 | netcheck：客户端经 STUN/UDP 探测节点延迟，**UDP 不通则无延迟、不调度** | 对端能否经 **TCP** 建连 + 中继白名单；无选举/探测门槛 |
| 是否依赖公网 UDP 入站 | **是**（DERP 路径本身可 TCP，但调度依赖 STUN 面） | **否**（tcp/ws/wss 建连全程不涉及 UDP） |
| 仅 TCP 入站机能否中继 | 不能（本案实证） | **能**：`listeners = ["tcp://0.0.0.0:11010"]` 即生效 |
| 中继是否默认开启 | DERP server 独立角色 | 任意节点默认转发（`disable_relay_data=false`，白名单 `*`） |

因此在 raiyun2 上配置一个 EasyTier 纯 TCP 监听（雨云控制台加一条 TCP 端口转发，无需碰那条失效的 UDP 规则），它立刻是一个可用的 TCP 中继/组网介绍节点；国内其他节点拨入后，互相不能直连时经它逐包中继，能直连时仍走打洞直连。**这正是 Tailscale 在该机器上做不到、而 EasyTier 能做到的事。**

> 证据强度：上述机制均有 Rust 源码 file:line 一手证据并经 planner 逐行复核，非官网宣传语。但**真机连通性、中继吞吐/稳定性未实测**（边界禁止），属静态代码结论。

---

## 4. EasyTier vs Tailscale（本场景对比）

| 维度 | Tailscale | EasyTier |
|---|---|---|
| 协调/控制面 | 官方云协调（可 HEADSCALE 自建） | 全去中心化，network_name+secret 准入 |
| 中继 | DERP，可用性受 netcheck/STUN(UDP) 门控 | 任意节点逐包中继，TCP 即可，无 STUN 门槛 |
| 纯 TCP / 共享 NAT 节点 | 无法成为可用中继（本案） | **可成为有效中继/介绍节点** |
| 打洞 | UDP（STUN + 路径探测） | UDP（含对称分级）+ 独立 TCP simultaneous-open |
| 加密 | WireGuard（Noise IK） | AEAD（AES-GCM/ChaCha20），Noise 握手，secret 派生 |
| NixOS | 官方一等支持 | **nixpkgs 已收录包 + `services.easytier` 模块** |
| 许可证 | BSD-3-Clause（客户端/服务端开源） | LGPL-3.0（运行/内部使用无传染性，见 §6.1） |
| 成熟度/治理 | 商业公司、SLA、生态成熟 | 社区个人项目（作者 kkrainbow），13.8k stars，无 SLA |
| 性能数据 | 有大量第三方实测 | **官方无任何吞吐/延迟对比数字**，需自测 |
| 多平台/生态 | 全平台、ACL/MagicDNS/功能丰富 | 全平台 + 多语言 SDK；功能较精简 |

---

## 5. 部署成本（NixOS）

### 5.1 现成可用，无需自行打包（一手原文核实）

- nixos-unstable 的打包定义 `pkgs/by-name/ea/easytier/package.nix`（已下载至 `research/verify/package.nix`）：`pname="easytier"`、**`version="2.6.4"`**（:19-20），tag v2.6.4，rustPlatform 构建，`doCheck=false`（依赖网络，:52），QUIC 为可选 feature（:11,39）。
- 官方 NixOS 模块 `nixos/modules/services/networking/easytier.nix`（已下载至 `research/verify/module.nix`，292 行）提供 **`services.easytier`**：
  - 多实例 `instances.<name>` + 声明式 TOML settings（:13-32）；
  - settings 字段：`network_name` / `network_secret` / `ipv4` / `listeners` / `peers` / `hostname` / `dhcp`；
  - `extraArgs` / `extraSettings` / `configFile` / `configServer` / `environmentFiles`；
  - 每实例生成 systemd 服务 `easytier-<name>`（:230-281）。
- 关键点：**`ipv4` 为空时"only forward packets and no TUN device will be created"（module.nix:72-81）**——即存在官方支持的**纯中继无 TUN 形态**，无需 CAP_NET_ADMIN/`/dev/net/tun`（该模块实例以 root 运行但不建 TUN）。
- 注意 worker B 报告的版本差异：其取证时 search.nixos.org 索引显示 2.6.0；planner 直接下载 nixos-unstable 原文确认当前已是 **2.6.4**（以原文为准）。本仓库 flake 正跟随 nixos-unstable，rebuild 即可获得。

### 5.2 与 Tailscale 共存，不替换

- 网段不冲突：Tailscale 100.64.0.0/10（tailscale0）；EasyTier 生产默认**不使用** 100.64（全库仅命中单测字符串），文档约定 10.144.144.0/24，可自选。
- TUN 名不冲突：tailscale0 固定；EasyTier `dev_name` 默认空、内核自命名（`toml.rs:33`）。
- 默认安全开关：`enable_exit_node=false`（`toml.rs:38`）、`accept_dns=false`（:56），不抢默认路由、不接管 DNS。共存只需避免 subnet proxy 与 Tailscale 路由重叠。

### 5.3 运维复杂度

单守护 + `easytier-cli`（RPC 默认 127.0.0.1:15888），配置为一份 TOML，与现有一个 systemd 服务相当。新增运维面：一个独立网络的 secret 管理、版本跟进、中继质量观测（`easytier-cli peer/route`）。复杂度低，但多一个要长期维护的网络平面。

---

## 6. 风险与取舍

### 6.1 许可证

- 上游为 **LGPL-3.0**：根 `LICENSE:1-2` 原文 "GNU LESSER GENERAL PUBLIC LICENSE Version 3"；`README.md:299-301`、各 crate 随根 LICENSE（`easytier-core/Cargo.toml:12`）。
- 我们仅运行官方/自编译二进制、不修改不分发，**对自有 NixOS 配置与业务代码无传染性**；未来若分发含 EasyTier 的产品需履行 LGPL 告知/可重链接义务。
- **打包瑕疵（实证）**：nixpkgs 元数据误标 `license = lib.licenses.asl20`（`research/verify/package.nix:75`），与上游 LGPL-3.0 不符；合规判断以上游 LICENSE 原文为准。可考虑向上游 nixpkgs 提修正。

### 6.2 成熟度与治理

- 13.8k stars / 388 open issues / 58 open PR（worker B 页面实读）；无商业公司、无 SLA，长期支持依赖核心维护者 kkrainbow 个人（腾讯 EdgeOne/雨云等仅实物赞助）。
- 发版：2026 年 4 月密集发布 2.6.0→2.6.4，**v2.6.4（2026-05-12）后至本次取证约 4.5 个月无新 release tag**；但 main 2.7.0 在 2026-09 仍有代码与设计文档合入（commit 2026-09-24），属"活跃开发、近期未发版"，非弃坑。

### 6.3 性能与稳定性

- **官方无任何吞吐/延迟对比数字**；仓内仅有 iperf3 两节点脚本 `script/benchmark-two-node.sh`（有脚本无结果）。
- 经 raiyun2 中继的上限受：雨云带宽、双程 RTT、两跳 TCP 队头阻塞、加解密/分帧开销约束。能否满足"国内节点间可用中继"的实际体感，**必须真机 iperf3/ping 实测**后方可承诺。

### 6.4 安全面注意

- 网络准入仅凭共享 secret：secret 泄露即整网可入；建议 secret 走 `environmentFiles`（避免明文进 Nix store/world-readable，模块文档亦如此提示）。
- WSS 服务端默认**自动自签证书、客户端默认跳过证书校验**（`easytier/src/tunnel/websocket.rs:135-229`），认证依赖上层 Noise + secret digest；若需合规 CA 证书应前置 nginx/Caddy 反代到 ws 监听。纯中继走裸 `tcp://` 时链路加密仍由 EasyTier 自身 AEAD 保证。
- 模块 `services/networking/easytier.nix` 的 systemd 单元**无 DynamicUser/硬化选项**（以 root 运行）；同仓 `passthru` 的 `service.nix`（RFC-174 形态）才有完整硬化（DynamicUser、CAP_NET_ADMIN/RAW、ProtectSystem strict 等）。落地时如需更强隔离，可用 extraArgs + 自定义加固或等模块演进。

---

## 7. 可行性裁决（原文）

> **裁决：可行（作为"补齐"方案，与 Tailscale 共存，不替换）。**
>
> EasyTier 的中继资格只取决于"对端能否经 TCP 建连 + 中继白名单"，**不依赖公网 UDP 入站或 STUN 调度**（`connectivity/protocol/mod.rs:25`、`peers/peer_manager.rs:3078-3112`、`config/toml.rs:42,72`）。因此一台雨云共享 NAT、仅 TCP 入站可用的机器（raiyun2），配置一个 TCP 监听即可成为 EasyTier 的有效中继/组网介绍节点——这恰好绕开了 Tailscale DERP 在该机上"netcheck(STUN) 不过即不调度"的死结。NixOS 落地成本小：nixos-unstable 已含 easytier **2.6.4** 包与 `services.easytier` 模块（支持纯中继无 TUN 形态），且与 Tailscale 网段/设备默认不冲突。
>
> **附带限定**：该裁决是"机制上可行"的静态结论。真机中继吞吐/延迟/稳定性、国内节点实际拨连通断，尚未实测（调研边界禁止部署）；EasyTier 无 SLA、无官方性能数字、近期 4.5 个月未发 release，故定位应为**低成本试点的补充中继平面**，而非替换 Tailscale 的主用网络。

---

## 8. 最小落地方案（仅设计，不实施；实施需另行授权）

1. **raiyun2（中继节点）**
   - 雨云控制台新增一条 **TCP** 端口转发，如公网 `51010/tcp → 内网 172.16.71.87:11010`（不动现有 UDP 规则与 DERP）。
   - NixOS 配置（新建 `hosts/raiyun2/easytier.nix` 并在 default.nix import）约：
     ```nix
     services.easytier.instances.relay = {
       enable = true;
       settings = {
         network_name = "<定名>";
         # ipv4 留空 = 纯转发、不建 TUN（module.nix:72-81）
         listeners = [ "tcp://0.0.0.0:11010" ];
       };
       environmentFiles = [ /var/lib/easytier/relay.env ]; # ET_NETWORK_SECRET
     };
     networking.firewall.allowedTCPPorts = [ 11010 ];
     ```
2. **2 个以上国内节点（客户端）**：启用 `services.easytier`，各给 `ipv4`（如 10.144.144.11/12）+ `peers = [ "tcp://RAIYUN2_PUBLIC_IP:51010" ]`，同 network_name/secret；不开 exit_node、不重叠子网路由。
3. **验收（实测，达标才算落地）**：
   - `easytier-cli peer` 看到中继链路；停掉直连路径后两节点仍互通（证明中继生效）；
   - ping RTT、`iperf3`（单流/多流）经中继的吞吐与丢包，记录基线；
   - 与 Tailscale 并行跑 ≥ 数天观察稳定性，确认不影响 tailscale0 路由/DNS。
4. **回滚**：删除该 systemd 服务与雨云 TCP 转发规则即可，Tailscale 平面全程不动。
5. 部署前需 orchestrator/xavier 批准；本报告阶段未做任何上述变更。

---

## 9. 未验证项（[UNCERTAIN]）

1. **真机验证全缺**：未构建/运行 EasyTier，未在 raiyun2 或任何节点试连。纯 TCP 中继的连通率、吞吐、延迟、长期稳定性均未实测——这是裁决最大保留项。
2. [UNCERTAIN] core peer 连接 Noise 握手的具体 pattern 字符串（仅实证 snow HandshakeState、消息类型与 secret digest 互验）。
3. [UNCERTAIN] "UDP 打洞失败 → 自动切中继"的调度状态机具体切换点（已实证中继数据面默认存在且与打洞解耦）。
4. [UNCERTAIN] 全新网络中首个无静态 IP 节点的虚拟网段冷启动"定型"顺序（core 无硬编码默认网段）。
5. 纯中继以 root 运行（无 DynamicUser 硬化）的安全加固路径未落地验证；easytier.cn 文档站与 26.05 stable 频道的版本/选项未逐一分频道核对。
6. 双方 exit-node / 重叠子网并用时的路由优先级未实测（默认均关，当前不触发）。

---

## 10. 证据来源（含取证命令与退出码）

| # | 证据 | 取证方式 / 命令 | 退出码 |
|---|---|---|---|
| E1 | 上游源码 ff3921ce（2.7.0 dev / 2026-09-24） | `git clone --depth 1 https://github.com/EasyTier/Easytier.git` | 0 |
| E2 | 中继逐包转发逻辑 | read_file `easytier-core/src/peers/peer_manager.rs:3078-3112` | 0 |
| E3 | 中继默认开 / 白名单 `*` | read_file `easytier-core/src/config/toml.rs:29-77` | 0 |
| E4 | tcp/ws/wss→Tcp、不经 UDP | read_file `easytier-core/src/connectivity/protocol/mod.rs:23-40` | 0 |
| E5 | 白名单匹配实现 | read_file `easytier-core/src/peers/whitelist.rs`（18 行全读） | 0 |
| E6 | nixpkgs 包=2.6.4、license 误标 asl20 | `curl -fsSL …/ea/easytier/package.nix` → `research/verify/package.nix` | 0 |
| E7 | `services.easytier` 模块、纯中继无 TUN 语义 | `curl -fsSL …/networking/easytier.nix` → `research/verify/module.nix`（292 行全读） | 0 |
| E8 | 上游 LICENSE = LGPL-3.0 | read_file `research/easytier-src/LICENSE:1-2` | 0 |
| E9 | nixpkgs 页面（包/选项/issues）、Release/Tags/Stars | worker B 经 Playwright MCP 真实打开（S1–S8，见其报告 §来源清单） | 0 |
| E10 | 本仓库跟随 nixos-unstable | read `flake.nix` / `flake.lock` | 0 |

- 子报告（一手整理，含其各自未验证项）：`research/out/worker-a-protocol.md`（278 行）、`research/out/worker-b-deployment.md`（201 行）。
- planner 已对 §3 裁决所依赖的全部源码行（E2–E5）与 nixpkgs 原文（E6–E7）逐行独立复核，非仅转述子代理自报。
