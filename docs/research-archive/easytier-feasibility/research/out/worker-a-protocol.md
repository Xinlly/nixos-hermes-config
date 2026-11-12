# Worker A 报告：EasyTier 组网 / 中继 / 传输协议模型（源码实证）

- 源码：`research/easytier-src`，commit ff3921ce6842f9660d629eafac499498026c6784（2026-09-24 上游 main）
- 取证方式：实读源码（search_files/read_file/ripgrep），未构建、未运行、未联网
- 路径均为相对 `easytier-src/` 的相对路径

---

## 1. 组网模型

### 1.1 网络身份：network name + secret（参与方共享密钥模型）

`easytier-core/src/config/mod.rs:136-150`
```rust
pub struct NetworkIdentity {
    pub network_name: String,
    pub network_secret: Option<String>,
    pub network_secret_digest: Option<NetworkSecretDigest>,
}
...
pub fn new(network_name: String, network_secret: String) -> Self {
    Self { network_secret_digest: Some(network_secret_digest(&network_name, &network_secret)), ... }
}
```
- 同一网络的节点凭 `(network_name, network_secret)` 相认；线上只比对 **digest**：`config/mod.rs:202-204` `fn network_secret_digest(...)` 产出 32 字节摘要。
- 默认身份：`config/mod.rs:234-237`
```rust
impl Default for NetworkIdentity {
    fn default() -> Self { Self::new("default".to_string(), "".to_string()) }
}
```
- CLI：`easytier/src/core.rs:144-156` `--network-name`（env `ET_NETWORK_NAME`）、`--network-secret`（env `ET_NETWORK_SECRET`）。

### 1.2 是否必须有中心节点：无强制中心节点，但入网需"先认识至少一个对等端"

- 节点通过 `--peers`（`easytier/src/core.rs:208-216`，可逗号分隔多个 URL）主动拨入已有节点；没有内置"官方自动发现的唯一协调者"角色。
- 入网后通过 **全局 peer 地图同步** 学习全网节点（RPC 通道名见 `easytier-core/src/peers/route/peer_ospf_route.rs:57-63` 的引用：`OspfRouteRpc`、`OspfRouteRpcClientFactory`、`OspfRouteRpcServer`、`sync_route_info_request::ConnInfo`）。
- 任何一个可达节点（包括纯 TCP 公网节点）都可以充当这个"介绍人"，角色上不是特权 server。

### 1.3 路由学习：类 OSPF 的路由同步 + 全局 peer 视图

- 模块：`easytier-core/src/peers/route/peer_ospf_route.rs`，快照结构 `OspfRouteSnapshot`（:153）含 `peer_infos` / `conn_map`，下一跳解析 `OspfNextHopInfo`（:206）。
- 路由随 peer RPC 在节点间同步（`SyncPeerRouteInfo` 等），并支持 cost 选路：`easytier-core/src/peers/peer_manager.rs:184-190`
```rust
pub(crate) fn get_next_hop_policy(is_latency_first: bool) -> NextHopPolicy {
    if is_latency_first { NextHopPolicy::LeastCost } else { NextHopPolicy::LeastHop }
}
```

### 1.4 虚拟 IP 分配：静态指定优先；DHCP 模式从对端路由中学习网段并自动挑空闲地址

- CLI：`--ipv4`（`core.rs:158-164`）、`--ipv6`（:166-171）、`--dhcp`（:198-206，默认开）。
- DHCP 分配器：`easytier-core/src/gateway/dhcp.rs:25-83`
```rust
pub struct DhcpIpv4Allocator { default_subnet: Option<Ipv4Inet>, current: Option<Ipv4Inet> }
...
// 没有路由（还没认识任何节点）时等待
if !has_routes { return DhcpIpv4Decision::WaitForPeers; }
// 网段来源：配置的 default_subnet，否则取已观测到的对端网段
let Some(subnet) = self.default_subnet.as_ref().or_else(|| used_ipv4.iter().next()) ...
// 在该网段内顺序找首个未被占用、非网络/广播地址
let next = subnet.network().iter().find(|candidate| { ... !used_ipv4.contains(candidate) });
```
- 已用地址来自全网路由表：`dhcp.rs:97-111` `PeerManagerCore::dhcp_ipv4_route_snapshot()` 从 `get_route().list_routes()` 收集。
- **默认网段**：本版本 core 中 **没有硬编码默认网段常量**（全仓非测试代码搜 `10.144.144.0`、`new(10,144,...)` 无定义点；DHCP 网段靠从对端路由学习）。`10.144.144.0/24` 是文档/测试中贯穿的约定网段（如 `easytier/src/common/config.rs:401` 示例 `ipv4 = "10.144.144.1"`；`easytier-core/src/instance/config.rs:529` 示例 `listeners = ["tcp://0.0.0.0:11010"]`）。[UNCERTAIN] 首个无静态 IP 的全新网络中由哪个节点最先"定型"网段——从代码看需有对端路由后才分配，冷启动顺序未在本次取证中完整追踪。

---

## 2. 传输协议清单

### 2.1 URL scheme → 底层传输映射（协议解析核心）

`easytier-core/src/connectivity/protocol/mod.rs:25-31`
```rust
b"tcp" | b"ws" | b"wss" => Some(ProtocolTransport::Tcp),
...
b"udp" => Some(ProtocolTransport::Udp(UdpSessionMode::EasyTierMux)),
...
b"quic" => Some(ProtocolTransport::Udp(UdpSessionMode::Classified(...))),
```
- scheme 默认端口：`protocol/mod.rs:57-58` `b"ws" => Some(80)`、`b"wss" => Some(443)`。
- listener 侧支持的 scheme：`easytier-core/src/listener/plan.rs:142-148`
```rust
.support("tcp", ListenerKind::TcpStream)
.support("udp", ListenerKind::UdpSession)
... ("ws", ListenerKind::TcpStream), ("wss", ListenerKind::TcpStream),
... ("quic", ListenerKind::UdpSession),
```

| 协议 | 形态 | 模块位置 |
|---|---|---|
| `tcp://` | TCP 裸流 + EasyTier 自有分帧 | `connectivity/transport/tcp.rs`；`protocol/mod.rs` |
| `udp://` | UDP + EasyTier mux/可靠化 | `connectivity/transport/udp.rs`（`UdpSessionMode::EasyTierMux`） |
| `ws://` | WebSocket（明文，跑在 TCP 上） | `easytier/src/tunnel/websocket.rs`；`easytier/src/tunnel/protocol/adapters/websocket.rs` |
| `wss://` | WebSocket over TLS（rustls） | 同上 |
| `quic://` | QUIC（基于 UDP） | `easytier/src/tunnel/protocol/adapters/quic.rs`；`easytier/src/tunnel/quic/` |
| `faketcp` | 伪造 TCP 包（抓包重注入，Linux BPF/WinDivert 等） | `easytier/src/socket/fake_tcp/`；识别于 `protocol/mod.rs:356` `b"tcp" | b"faketcp"` |
| `wg` | WireGuard 入站（vpn portal 相关） | `easytier/src/tunnel/protocol/adapters/wireguard.rs`；`easytier/src/vpn_portal/wireguard/` |

注意：**没有独立的"KCP listener"**。KCP/QUIC 在本版本首先是"网关代理/可靠化"开关（见下）。

### 2.2 配置方式（CLI flag / 配置项，均有实证）

- `--listeners`（`core.rs:235-243`，env `ET_LISTENERS`）：本节点监听 URL 列表，如 `tcp://0.0.0.0:11010`、`wss://0.0.0.0:443`。
- `--mapped-listeners`（`core.rs:245-252`）：NAT 场景下对外映射地址。
- `--no-listener`（`core.rs:254-260`，默认 false）：纯客户端模式。
- `--peers`（`core.rs:208-216`）：对端 URL。
- `--default-protocol`（`core.rs:307-312`，env `ET_DEFAULT_PROTOCOL`）。
- TOML 全量模型与默认值：`easytier-core/src/config/toml.rs:29-77` `gen_default_flags()`：
```rust
default_protocol: "tcp",
enable_encryption: true,
mtu: 1380,
relay_network_whitelist: "*".to_string(),
disable_tcp_hole_punching: false,
disable_udp_hole_punching: false,
disable_sym_hole_punching: false,
enable_kcp_proxy: false, disable_kcp_input: false, disable_relay_kcp: false,
enable_relay_foreign_network_kcp: false,
enable_quic_proxy: false, disable_quic_input: false, disable_relay_quic: false,
enable_relay_foreign_network_quic: false,
disable_relay_data: false,
prefer_peer_relay: false,
```
- KCP/QUIC 代理为 feature-gated 的网关模块：`easytier/src/gateway/mod.rs:1-8`
```rust
#[cfg(any(feature = "kcp", feature = "quic"))]
#[cfg(feature = "kcp")] pub mod kcp_proxy;
```
（即 KCP/QUIC 还承担"在对等链路上提供可靠/低阻塞输入"的代理职责，而非额外的公网监听协议。）
- STUN 是出向探测，默认服务器：`easytier-core/src/config/mod.rs:21-23`
```rust
pub(crate) const DEFAULT_UDP_STUN_SERVERS: &[&str] = &[
    "stun.easytier.cn", "stun.miwifi.com", ...
```
收集器同时支持 UDP/TCP STUN：`connectivity/stun/collector.rs:46-48`（`udp_servers / tcp_servers / udp_v6_servers`）。

---

## 3. 核心问题：只有公网 TCP 入站（UDP 入站全不通）的机器

### 3a) 能否作为公共节点被 TCP/WSS 连入？——**能**

- TCP 与 WSS 的建连**不依赖任何入向 UDP**：scheme→transport 映射中 `tcp/ws/wss` 全部走 `ProtocolTransport::Tcp`（`protocol/mod.rs:25`）。
- 只需配置 `--listeners tcp://0.0.0.0:<port>`（或 `wss://0.0.0.0:443`），对端用 `--peers tcp://<公网IP>:<port>` 拨入。示例配置见 `instance/config.rs:529`。
- 该节点的 STUN/UDP 探测即使全失败，也不影响接受 TCP 入站（监听路径 `listener/plan.rs:142-146` 与 STUN 收集器是独立模块）。

### 3b) 能否为两个不能直连的对端中继数据面流量？——**能，且中继默认开启**

EasyTier 没有名为 DERP 的模块，但有等价的"逐包转发"数据面：

`easytier-core/src/peers/peer_manager.rs:3078-3113`（PeerPacketRouter 收包循环）
```rust
if to_peer_id != self.my_peer_id {
    if drop_relay_data { ... "drop forwarded relay data while relay data is disabled"; return; }
    if hdr.forward_counter > 7 { ... "forward counter exceed, drop packet"; return; }
    ...
    hdr.forward_counter += 1;
```
- 即：**任何节点收到 to_peer_id 不是自己的包就按下一跳转发**，最大转发跳数 7。转发字节/包还单独计量（`peer_manager.rs:3136-3145`，`forward_data_tx_bytes` / `TrafficBytesForwarded` 等）。
- 中继默认就是开的：`toml.rs:72` `disable_relay_data: false`；关闭开关为 `disable_relay_data`（CLI 对应 `--disable-relay-data` 类，core.rs:642 区段），关闭时日志为 `"drop forwarded relay data while relay data is disabled"`（peer_manager.rs:3086）。
- **中继网络白名单**（DERP 没有对应物，EasyTier 特有）：
  - 实现：`easytier-core/src/peers/whitelist.rs:5-17`
    ```rust
    pub(crate) fn check_network_in_relay_whitelist(relay_network_whitelist: &str, network_name: &str) ...
        relay_network_whitelist.split(' ').map(wildmatch::WildMatch::new)
            .any(|whitelist| whitelist.matches(network_name))
    ```
  - 默认值 `relay_network_whitelist: "*"`（`toml.rs:42`）＝默认允许为任意网络中继。
  - CLI：`--relay-network-whitelist`（`easytier/src/core.rs:438-444`，空格分隔、支持通配符），另有 `--enable-relay-network-whitelist` 开关（core.rs:446 起）。
  - 白名单不匹配会影响中继数据偏好：`easytier-core/src/peers/context.rs:160-164`
    ```rust
    let avoid_relay_data_preference = check_network_in_relay_whitelist(
        &flags.relay_network_whitelist, &network_identity.network_name).is_err();
    ```
- 中继路径选择：节点维护"经谁可达谁"的中继映射 `easytier-core/src/peers/relay_peer_map.rs`（`RelayPeerMap`，在 peer_manager.rs:72,764 注入）。另有 `prefer_peer_relay` 标志（`toml.rs:73`，默认 false）控制是否偏好 peer 中继路径（`peers/route/peer_ospf_route.rs:2469-2471` `peer_relay_projection_enabled`）。

**结论：纯 TCP 公网机配 `--listeners tcp://0.0.0.0:11010`（默认白名单 `*`）后，就是一个可用的 TCP 中继节点——不需要 UDP、不需要 STUN、不需要被"调度选举"。** 这与 Tailscale DERP 的关键差异正在于此：DERP 中继可用性由 netcheck(STUN/UDP) 决定，而 EasyTier 的中继资格只取决于"TCP 能否连上 + 白名单"。

### 3c) 打洞是否强依赖公网 UDP/STUN？纯 TCP 节点有无 TCP 打洞？

- **UDP 打洞**：强依赖双方出向 UDP 与 NAT 类型探测（STUN）。目录 `connectivity/hole_punch/udp/`，按 NAT 类型决定打洞方法：`connectivity/hole_punch/udp/task.rs:67-80`
  ```rust
  if !my_nat_type.can_punch_hole_as_client(peer_nat_type, ...) { ... }
  ... dst_nat_type: peer_nat_type, my_nat_type,
  ```
- **有独立的 TCP 打洞**（simultaneous open），模块 `connectivity/hole_punch/tcp.rs`：
  - `tcp.rs:232` 注释：`// TCP supports simultaneous connect, so both peers may dial from the mapped port.`
  - 在映射端口上起监听并对连：`tcp.rs:218-276`（`"tcp hole punch server start connect loop"`，每次尝试 `timeout(... Duration::from_secs(3), host.connect_tcp(options))`）。
  - 可用 `disable_tcp_hole_punching`（默认 false，`toml.rs:47`）关闭；节点侧查询函数 `tcp_hole_punching_disabled()`（tcp.rs:78）。
- **纯 TCP 公网节点根本不需要打洞**：它有 TCP 入站能力，对端直接经 listener 建连即可；打洞只发生在"双方都在 NAT 后"的链路上。
- 打洞尝试的门控策略：`connectivity/hole_punch/policy.rs:36-49` `should_try_p2p_with_peer(...)`，综合对端 `is_public_server` / 双方 `disable_p2p` / `need_p2p`；还支持 lazy/background p2p（policy.rs:51-64）。

---

## 4. 数据面

### 4.1 是否 TCP-over-TCP？

- **不是严格意义的 TCP-over-TCP 嵌套**。中继发生在 EasyTier 自己的**包层**：被转发的是带 `peer_manager_header` 的 ZCPacket（逐包、有 `forward_counter`），不是把一条 TCP 字节流塞进另一条 TCP。两端 peer 链路即使都是 TCP，中间节点也只做"收帧→查表→转发帧"，不维护内层 TCP 状态、不做内层重传，因此不会出现经典 TCP-in-TCP 的双重重传/拥塞控制崩溃。
- 但性能隐患仍定性存在：①两跳 TCP 各自的**队头阻塞**叠加；②中继点带宽与双程 RTM；③加密/分帧开销。可缓解项：KCP/QUIC 代理输入（`enable_kcp_proxy`/`enable_quic_proxy`，`toml.rs:52,58`）、`latency_first` 选路（`get_next_hop_policy`，peer_manager.rs:184）、数据压缩 `data_compress_algo`。
- 经中继跑 KCP/QUIC 输入也有独立开关：`disable_relay_kcp` / `disable_relay_quic` / `enable_relay_foreign_network_kcp|quic`（`toml.rs:54-55,60-61`）。

### 4.2 隧道加密与密钥协商

- 数据面为 AEAD 对称加密，trait：`easytier-core/src/tunnel/encrypt/mod.rs:41-53`
```rust
pub trait Encryptor: Send + Sync + 'static {
    fn decrypt(&self, zc_packet: &mut ZCPacket) -> Result<(), Error>;
    fn encrypt(&self, zc_packet: &mut ZCPacket) -> Result<(), Error>;
```
- 算法：AES-128-GCM、AES-256-GCM、ChaCha20-Poly1305（`encrypt/mod.rs:136-157`，按后端可用性选择，实现文件 `aes_gcm.rs`/`chacha20.rs`，可选 openssl/ring 后端）；可用 `--encryption-algorithm`（`toml.rs:64`）与 `--disable-encryption`（`core.rs:314-321`）控制；默认 `enable_encryption: true`（`toml.rs:34`）。
- 密钥由网络 secret 派生：`encrypt/mod.rs:60` `pub fn derive_key_128(secret: &str) -> [u8; 16]`、`:71` `derive_key_256(secret: &str) -> [u8; 32]`。
- 建链时的双向认证/密钥协商走 **Noise 握手**（snow 库）：
  - `easytier-core/src/peers/conn/peer_conn.rs:27` `use snow::{HandshakeState, params::NoiseParams};`
  - 握手消息类型 `PeerConnNoiseMsg1/2/3Pb`（peer_conn.rs:51），握手结果 `NoiseHandshakeResult { local_static_pubkey, remote_static_pubkey, secret_digest, client_secret_proof, ... }`（peer_conn.rs:78-91）。
  - 握手中互相验证 `network_secret_digest`（peer_conn.rs:499,545-547），静态密钥对来自节点配置 `cfg.private_key()/public_key()`（peer_conn.rs:427-434）。
  - [UNCERTAIN] peer 连接 Noise 的具体 pattern 字符串本次未读到（web 客户端那条是 `easytier-core/src/tunnel/web_security.rs:18-19` `Noise_NN_25519_ChaChaPoly_SHA256`、prologue `easytier-webclient-noise-v1`，注意那是 webclient 专用，不能直接当作 core peer 链路参数）。

---

## 5. NAT 容忍度

NAT 类型分级与归类，`connectivity/hole_punch/udp/common.rs:15-44`：
```rust
Unknown,
Open(NatType),
... FullCone | Restricted | PortRestricted => (锥形)，
NatType::Symmetric | NatType::SymUdpFirewall => UdpNatType::HardSymmetric(nat_type),
NatType::SymmetricEasyInc => UdpNatType::EasySymmetric(nat_type, true),
NatType::SymmetricEasyDec => UdpNatType::EasySymmetric(nat_type, false),
```
- **对称 NAT**：区分"易对称"（端口可预测递增/递减，`EasySymmetric`，可预测端口打洞）与"硬对称"（`HardSymmetric`）。硬对称有专门的打洞报文流程：`connectivity/hole_punch/udp/runtime.rs:108-117` `SendPunchPacketHardSym` / `SendPunchPacketHardSymResponse`；可用 `disable_sym_hole_punching`（默认 false，`toml.rs:65`）关闭，关闭后 sym↔cone 仍按锥形方法尝试（测试名 `"disabling_symmetric_hole_punch_keeps_sym_to_cone_as_cone_method"`，task.rs:203）。
- **仅出向 UDP**：只要能出向访问 STUN 与对端映射地址即可参与常规打洞；自己无入站能力则作为 client 侧（`can_punch_hole_as_client` 判定，task.rs:68）。
- **严格防火墙 / 打洞失败后的回退**：
  - p2p 不是连接成立的前提。打洞门控 `should_try_p2p_with_peer`（policy.rs:36）可因配置/对端标志直接跳过；存在 `lazy_p2p`（默认 false）与 `need_p2p` 语义。
  - 打洞失败时，节点之间仍经已建立的 peer 连接以**逐包中继**互通（§3b 的转发路径对所有包生效，与打洞成功与否无关）。
  - 其他补充：UPnP/IGD 端口映射（`easytier/src/common/upnp.rs`、`igd_next/`，`disable_upnp` 默认 false）、`--mapped-listeners` 显式宣告映射地址。
  - [UNCERTAIN] "打洞失败→自动切中继"的具体状态机切换点（任务调度代码）本次未逐行追踪，但中继路径在数据面默认存在、无需打洞即可用，这一点有直接代码证据。

---

## 6. WSS 支持的具体形态

实现在 `easytier/src/tunnel/websocket.rs`：
- scheme 判定：`:56-59` `fn is_wss(url ...) { "wss" => Ok(true), ... }`。
- **服务端证书：自动生成临时自签名证书，内置 TLS acceptor**，`websocket.rs:202-229`
```rust
fn get_insecure_tls_cert<'a>() -> (...) {
    let cert = rcgen::generate_simple_self_signed(vec!["localhost".into()]).unwrap();
    ...
}
...
let stream = if is_wss(&local_url)? {
    let (certificates, private_key) = get_insecure_tls_cert();
    ... .with_single_cert(certificates, private_key)
    Either::Left(TlsAcceptor::from(Arc::new(config)).accept(stream).await?)
```
- **客户端默认跳过证书校验**（配合自签证书）：`websocket.rs:135-200` `SkipServerVerification`（`verify_server_cert → ServerCertVerified::assertion()`）、`get_insecure_tls_client_config()`。
- **443 纯 WSS 接入可行**：`wss://0.0.0.0:443` 监听（wss 默认端口 443，`protocol/mod.rs:58`），对端 `--peers wss://<域名或IP>:443`。
- 在 core 配置模型中 **未发现用户自带证书/私钥/CA 的配置项**（`rg -i 'tls|cert'` 在 config 模块无命中）。形态结论：WSS 的设计用途是"穿 HTTPS 防火墙/CDN 友好的封装"，默认靠自签证书 + 客户端不校验（认证仍由上层 Noise + network secret digest 保证）；若需合法 CA 证书，典型路径是前置 nginx/Caddy 反代到 EasyTier 的 ws 监听。[UNCERTAIN] 是否存在其他 crate/平台版（如 easytier-js）的证书注入通道，未在本次范围内取证。

---

# 一页纸总结：纯 TCP 节点能否当中继？

**能。** EasyTier 的中继是"任何节点收到目标不是自己的数据包即按路由逐包转发"（`peers/peer_manager.rs:3078-3113`，最大 7 跳），默认开启（`disable_relay_data=false`）、默认中继白名单为 `*`（`config/toml.rs:42,72`）。TCP/WSS 建连全程不需要入向 UDP 或 STUN（`connectivity/protocol/mod.rs:25`），因此一台仅开放 TCP 入站的雨云机器，配置 `--listeners tcp://0.0.0.0:11010`（或 `wss://0.0.0.0:443`）即可被其他节点连入并为不能直连的对端中继数据面流量——不存在 Tailscale/DERP "netcheck(STUN) 不通过就不被调度"的门槛。中继是包级帧转发而非 TCP 字节流套 TCP，避免了经典 TCP-over-TCP 重传崩溃，但两跳 TCP 的队头阻塞与中继带宽/RTT 代价仍在；加密默认开启（AEAD，密钥由 network secret 派生，Noise 握手认证）。代价/注意点：对称 UDP NAT 的打洞与该 TCP 节点无关，经它中继的两端性能上限受其带宽约束；WSS 默认用自动自签证书且客户端不校验（认证靠上层），需合规证书应走反代。

---

# 未验证项清单

1. [UNCERTAIN] 全新网络中首个 DHCP 节点"定型"虚拟网段的冷启动顺序（core 无硬编码默认网段，网段从对端路由学习；10.144.144.0/24 仅为文档/测试约定）。
2. [UNCERTAIN] core peer 连接 Noise 握手的具体 pattern 字符串（只实证了 snow HandshakeState、消息类型与 secret digest 校验；web_security.rs 的 Noise_NN_25519_ChaChaPoly_SHA256 是 webclient 专用）。
3. [UNCERTAIN] "UDP 打洞失败 → 切换中继"的调度状态机具体位置；已实证中继数据面默认存在且与打洞解耦。
4. [UNCERTAIN] 除 Rust core 外（easytier-js/云函数版）是否有用户证书注入等 WSS 配置通道。
5. 未读取/未引用 `easytier-proto/proto/peer_rpc.proto` 的逐行 RPC 清单（本报告 RPC 名称来自 core 代码 import 实证，未逐一对 proto 字段）。
6. 全程未构建、未运行、未连真实节点：协议可用性结论为静态代码推断，真机 TCP 中继吞吐/稳定性需后续实测（不在本任务红线内）。
