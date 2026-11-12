# Worker B 报告：EasyTier 部署成本、NixOS 打包、许可证与成熟度生态

- 上游源码：`research/easytier-src`，commit ff3921ce6842f9660d629eafac499498026c6784（2026-09-24 main），workspace 版本 **2.7.0**（`Cargo.toml:41-46`、`easytier-core/Cargo.toml:6`）。
- 网页取证通道：**Paseo Playwright MCP**（browser_new_tab / browser_navigate / browser_snapshot / browser_evaluate 真实打开并读取），满足任务书要求。取证时间 2026-09-27。
- 任务等级自判：M（只读调研，无修改）。

---

## Q1. NixOS/Nixpkgs 打包现状

**结论：nixpkgs 已同时收录 easytier 软件包与官方 NixOS 模块（services.easytier），无需自行打包。**

### 1.1 软件包（search.nixos.org/packages 实开）
- URL：https://search.nixos.org/packages?query=easytier
- 原文引句（页面 innerText 实读）："Showing results 1-1 of 1 packages … **easytier / Simple, decentralized mesh VPN with WireGuard support / Name: easytier Version: 2.6.0 … License: Apache-2.0**"，维护者 "Maintainers / **Luo Chen**"，平台 "x86_64-linux / i686-linux / aarch64-linux / x86_64-darwin / aarch64-darwin"，索引数据 "Data from 5e2305d5"。
- 即：nixpkgs 包版本 **2.6.0**（落后上游最新 tag 2.6.4、main 2.7.0）。
- nixpkgs 源路径（GitHub blob 页实开确认存在）：https://github.com/NixOS/nixpkgs/blob/nixos-unstable/pkgs/by-name/ea/easytier/package.nix
- 注意：**nixpkgs 包元数据标注 License 为 Apache-2.0，与上游实际的 LGPL-3.0 不一致（见 Q5）**，疑为打包元数据错误；[UNCERTAIN] 是否有历史原因，需读 package.nix 全文确认（本次未读到代码内容，见未验证项）。

### 1.2 NixOS 模块（search.nixos.org/options 实开）
- URL：https://search.nixos.org/options?query=easytier
- 原文引句（snapshot 实读）："Showing results 1-19 of 19 options."，服务名 **`services.easytier`**，19 个选项：
  - 顶层：`services.easytier.enable`、`services.easytier.package`、`services.easytier.allowSystemForward`
  - 多实例：`services.easytier.instances.<name>.enable` / `.settings` / `.extraArgs` / `.extraSettings` / `.configFile` / `.configServer` / `.environmentFiles`
  - settings 子项：`.network_name`、`.network_secret`、`.ipv4`、`.listeners`、`.peers`、`.hostname`、`.instance_name`、`.dhcp`
- 模块源（GitHub blob 页实开确认存在）：https://github.com/NixOS/nixpkgs/blob/nixos-unstable/nixos/modules/services/networking/easytier.nix
- 即模块支持**多实例 + 声明式 settings（network_name/secret/ipv4/listeners/peers）+ 额外参数/配置文件/远端配置服务器**，形态完善。

### 1.3 nixpkgs issue/PR 现状（GitHub 实开）
- URL：https://github.com/NixOS/nixpkgs/issues?q=easytier
- 原文引句（snapshot 实读）："6 Open / 125 Closed"（搜索维度计数），列出的 6 个 issue：
  - **#399065 OPEN** "Easytier NixOS Module Request"（zhujinming01 提交，2026）——模块请求在 open 状态，但模块实际已落地（1.2），该 issue 可能尚未关闭。
  - #342800 closed "easytier: 2.1.4 -> 2.2.2"；#348140 closed "easytier: add passthru tests"；#331026 closed "easytier: 1.13.4 -> 2.1.4"；#328549 closed "easytier: 1.13.3 -> 1.13.4"；#303747 closed "easytier: init at 1.10.1"（**初始打包 PR**，作者 zzy-ac，2024）。
- 社区：未发现被广泛使用的第三方 NixOS module（官方模块已覆盖）；上游自身 `flake.nix` 只提供开发环境（见 Q2）。

## Q2. 部署形态、二进制构成与配置方式

### 2.1 发布形态
- **预编译二进制（GitHub Releases，releases 页实开 v2.6.4，"26 Assets"）**：
  - Linux：`easytier-linux-x86_64`、`-aarch64`、`-riscv64`、`-armv7hf`、`-armhf`（均为 zip/tar.gz 资产名，releases 页实读）；
  - Windows：x86_64 / aarch64 / i686；macOS：aarch64 / x86_64；FreeBSD：x86_64（asset 名实读）。
- **Docker**：`.github/workflows/Dockerfile:1-48`，Alpine 镜像，把发布包内二进制拷入 `/usr/local/bin`；
  - 原文：`ENTRYPOINT ["/sbin/tini", "--", "easytier-core"]`（`Dockerfile:48`）；
  - 暴露端口 `EXPOSE 11010/tcp`、`11010/udp`、`11011/udp`、`11011/tcp`、`11012/tcp`（`Dockerfile:35-43`）；
  - 健康检查 `easytier-cli --rpc-portal 127.0.0.1:15888 --output json node info`（`Dockerfile:45-46`）。
  - README 亦有 "Install via Docker"（`README.md:74`）。
- **安装脚本**：`script/install.sh`（install/uninstall/update，默认走 GitHub 代理 ghfast.top）、`script/install.ps1`、`script/install.cmd`。

### 2.2 服务端/客户端是否同一二进制
- **是同一套程序、无服务端客户端之分**。README 原文（`README.md:176` 小节）："EasyTier is fundamentally decentralized, **with no distinction between server and client**."
- 两个可执行文件（源码实证，`easytier/src/`）：
  - **easytier-core**：组网守护进程（入口 `easytier/src/easytier-core.rs:24-26` → `core::main()`，CLI 定义在 `easytier/src/core.rs`）；
  - **easytier-cli**：通过 RPC 管理本机/远端 core 的管理客户端（`easytier/src/easytier-cli.rs`，默认 RPC 端口 `default_value = "127.0.0.1:15888"`，`easytier-cli.rs:92`）。
- workspace 默认构建成员：`Cargo.toml:17` `default-members = ["easytier", "easytier-web"]`；`easytier/Cargo.toml` 产出上述两个 bin。
- core 启动后默认监听（`README.md:147-153` 原文）："TCP: 11010 / UDP: 11010 / WebSocket: 11011 / WebSocket SSL: 11012 / WireGuard: 11013"。

### 2.3 配置方式
- **CLI flags + TOML 文件并存**：`-c/--config-file`（`easytier/src/core.rs:107-111`，原文 `help = ... "config_file"`，可多次指定）；TOML 结构定义在 `easytier-core/src/config/toml.rs`。
- **"纯 TCP 公共中继/公共节点"最小参数集**（参数名均有实证）：
  - CLI 形态（README 实读）：
    - 首节点：`sudo easytier-core -i 10.144.144.1`（`README.md:143`）
    - 带网络名/秘钥的公共节点：`sudo easytier-core -d --network-name abc --network-secret abc -p tcp://<SharedNodeIP>:11010`（`README.md:130` 原文）
  - TOML 形态（`easytier-core/src/config/toml.rs` 内嵌示例实读）：
    - `listeners = ["tcp://0.0.0.0:11010"]`（`toml.rs:1228`）
    - `ipv4 = "10.144.144.10"`（`toml.rs:1889`）
    - 对端 `peers` 示例：`uri = "tcp://public.kkrainbow.top:11010"`（`toml.rs:1898`）
  - 协议默认值：`default_protocol: "tcp"`（`toml.rs:32`，gen_default_flags）。
  - 最小集合即：**网络身份 `network_name` + `network_secret`（或默认网络）+ 虚拟 IP `ipv4`/`-i` + TCP 监听 `listeners = ["tcp://0.0.0.0:11010"]`**；无需 TUN 的纯中继可考虑 `no_tun`（flags 字段存在，`toml.rs:40`，默认 false）——[UNCERTAIN] 公共中继是否必须 TUN 未经运行验证。
- RPC portal 默认 127.0.0.1:15888（`easytier-core/src/rpc/standalone.rs:426` 测试示例；core.rs:809-811 `--rpc-portal`）。

## Q3. NixOS 最小落地方案工作量评估

**由于 nixpkgs 已有包（2.6.0）+ 官方模块 services.easytier（多实例/settings），落地工作量评级：小。** 只需在 host 配置中启用：

```nix
services.easytier.instances.pub = {
  enable = true;
  settings = {
    network_name = "xxx";
    network_secret = "xxx";
    ipv4 = "10.144.144.1";
    listeners = [ "tcp://0.0.0.0:11010" ];
  };
};
```
（字段名全部来自 Q1.2 实读选项；以上仅为评估示例，未实施。）

若 nixpkgs 无包/需跟进上游 2.6.4/2.7.0 时，自建打包评估如下：
- **需打包的 crate**：workspace 共 13 个成员（`Cargo.toml:3-16`），但核心服务只需 `easytier-proto` + `easytier-core` + `easytier`（CLI）三个 crate 及其依赖；GUI/web/移动端成员不需要。
- **工具链要求**：edition 2024、rust 1.95（`Cargo.toml:21-22`、`rust-toolchain.toml`），nixpkgs-unstable 可满足；prost 需要 protobuf（上游 flake 的 nativeBuildInputs 含 `protobuf`，`flake.nix:70`）。
- **系统库**：参考上游 flake buildInputs——openssl、zstd、jemalloc、libclang（`flake.nix:86-94`）；其中 zstd/pkg-config、jemalloc override 有专门 env（`flake.nix:100-102`）。
- **常规做法**：`rustPlatform.buildRustPackage`（Cargo.lock 已在仓库，含 cargoHash/sha256、features 选择、workspace 打包），与 #303747 初始打包一致。
- **systemd 能力**：创建 TUN 与配置路由需要 **CAP_NET_ADMIN**，访问 `/dev/net/tun`；若启用出口节点还需转发（模块已有 `allowSystemForward` 选项对应）。模块由 nixpkgs 提供，无需自写。
- **"需要新建哪些文件"清单（仅在不用 nixpkgs 模块时）**：
  1. `overlays/easytier.nix`（或 `pkgs/easytier/default.nix`，buildRustPackage 定义 + cargoLock）；
  2. `modules/easytier.nix`（systemd 服务：CapabilityBoundingSet=[CAP_NET_ADMIN]、DeviceAllow=/dev/net/tun、Restart、StateDirectory、ExecStart=easytier-core -c 配置）；
  3. host（如 `hosts/raiyun2/default.nix`）引入 overlay + 模块；
  4. 可选：TOML 配置由 module 生成到 /etc。
- 与本仓库现有约定的关系：`hosts/raiyun2/derper.nix`（Tailscale DERP 自写模块形态）是最接近的参照；因官方模块存在，不需要重复这种自写工作。

## Q4. 与 Tailscale 共存

### 4.1 默认网段与 TUN 设备名（源码/文档实证）
- **文档约定虚拟网段为 10.144.144.0/24**：`README.md:143` `easytier-core -i 10.144.144.1`，节点 B `-i 10.144.144.2`（`README.md:157`）；`docs/quic-proxy-memory-benchmark-2026-07-27.md:50-51` "EasyTier 虚拟地址为 `10.144.144.1/24` 和 `10.144.144.2/24`"。
- **IP 无内置硬编码默认值**：TOML 字段 `ipv4: Option<String>`（`easytier-core/src/config/toml.rs:524`），即需显式 `-i` 指定或走 DHCP（settings 有 `dhcp` 选项，Q1.2）。
- **TUN 设备名**：flags `dev_name` 默认空字符串（`toml.rs:33`）。Linux 上 dev_name 为空即不指定名称、由内核命名（通常为 tun0；代码 `easytier/src/instance/virtual_nic.rs:510-513`：仅在非空时 `config.tun_name(&dev_name)`）；Windows 未指定时随机生成 `et_<iface序号>_<4位随机串>`（`virtual_nic.rs:554` 原文 `format!("et_{}_{}", c, s)`）。
- **是否占用 100.64.0.0 网段：否。** 全仓库（排除 .git/target）检索 `100.64`，仅命中 `easytier-core/src/gateway/proxy/wrapped_tcp_proxy.rs` 中的**单元测试字符串**（`:257` `mapped_cidr: Some("100.64.0.0/16"...)`、`:282/:300/:317` 测试参数），生产默认配置不使用 CGNAT 网段。
- 网络身份默认 network name "default"（`easytier-core/src/config/mod.rs:685-688` 测试 `NetworkIdentity::new("default".to_string(), "".to_string())`）；MTU 默认 1380（`toml.rs:36`）。

### 4.2 共存注意事项
- **网段不冲突**：Tailscale 用 100.64.0.0/10（tailscale0），EasyTier 用自选 10.x（示例 10.144.144.x），默认虚拟网段互不重叠，可同时运行。
- **TUN 设备名不冲突**：tailscale0 名称固定，EasyTier Linux 默认内核自命名（tun*），不会覆盖 tailscale0。
- **需人工注意的三点**（均为 flags，默认安全）：
  - 出口节点：`enable_exit_node` 默认 **false**（`toml.rs:38`）——开启后会争抢默认路由，可能影响 Tailscale 流量走向，不建议与 tailscale exit-node 同时启用。
  - DNS：`accept_dns` 默认 **false**（`toml.rs:56`）；默认 TLD DNS zone 为 `et.net.`（`toml.rs:21,66`），不接管系统 DNS，与 Tailscale MagicDNS 不冲突，不要轻易开启 accept_dns。
  - Subnet proxy（`-n 10.1.1.0/24`，`README.md:209`）：通告的子网路由不得与 Tailscale `--advertise-routes`/接受路由重叠，否则两条路由产生二义；自动下发的路由检查用 `easytier-cli route`。
- [UNCERTAIN] 同时启用双方 exit node / 重叠子网时的具体路由优先级未经实测。

## Q5. 许可证

- **协议：LGPL-3.0（GNU Lesser General Public License v3）**。
  - 根 `LICENSE:1-2` 原文："GNU LESSER GENERAL PUBLIC LICENSE / Version 3, 29 June 2007"。
  - README 声明：`README.md:299-301` "## License / EasyTier is released under the [LGPL-3.0]"；`README_CN.md:300` "EasyTier 在 [LGPL-3.0] 许可下发布"。
- **各 crate 一致性**：
  - `easytier-core/Cargo.toml:12` `license-file = "../LICENSE"`；`easytier/Cargo.toml:12` `license-file = "LICENSE"`；
  - md5 比对：根 `LICENSE`、`easytier/LICENSE`、`easytier-go/LICENSE` 内容完全相同（md5 3000208d…）；`easytier-core`、`easytier-proto` 等子 crate 无独立 LICENSE 文件，随根 LICENSE 授权。
  - 仓内另有第三方子组件自带 LICENSE（vendored）：`easytier/src/igd_next/LICENSE`、`fast_socks5/LICENSE`、`fake_tcp/LICENSE`、`tracing_rolling_appender/LICENSE` 等，属上游依赖的独立授权。
  - 例外：`easytier-contrib/easytier-ohrs/package/LICENSE` md5 与根相同（同为 LGPL-3.0）。
- **商业/内部使用与传染性评估**：
  - LGPL-3.0 允许**内部部署与商业使用**；copyleft 仅在**修改 EasyTier 库本身**或以不满足 LGPL 条件的方式**链接**时触发（需允许用户替换库版本/提供可重链接材料）。`easytier-core` crate-type 含 `cdylib`（`easytier-core/Cargo.toml:14-15`），动态链接路径天然合规。
  - 我们的场景是**运行官方二进制/自行编译部署，不修改、不分发**，对自有 NixOS 配置与业务代码**无传染性**；如未来分发含 EasyTier 的产品，需履行 LGPL 告知与提供源码的义务。
  - 再次提示：nixpkgs 包元数据写 Apache-2.0（Q1.1），与上游 LGPL-3.0 不符，合规判断应以**上游 LICENSE 原文 LGPL-3.0** 为准。

## Q6. 成熟度与生态（GitHub 页面实读）

- **Stars：13.8k**（tags 页与 repo 导航实读："Star 13.8k"）；Fork 1.4k。
- **Open issues：388；Open PR：58**（tags 页导航原文 "Issues 388"、"Pull requests 58"；issues 列表页 header 同示 388）。数量级中等，issue 有持续流转（closed 125+）。
- **发版节奏（tags 页实读日期）**：
  | tag | 日期 |
  |---|---|
  | v2.6.4 | May 12, 2026 |
  | v2.6.3 | May 1, 2026 |
  | v2.6.2 | Apr 26, 2026 |
  | v2.6.1 | Apr 19, 2026 |
  | v2.6.0 | Apr 6, 2026 |
  | v2.5.0 | Dec 31, 2025 |
  | v2.4.5 | Sep 25, 2025 |
  | v2.4.4 | Sep 18, 2025 |
  | v2.4.3 | Aug 27, 2025 |
  | v2.4.2 | Aug 11, 2025 |
- 节奏特征：2025 年约每 2-4 个月一次 minor；2026 年 4 月密集发布 2.6.0→2.6.4（约每周一个 patch）；**v2.6.4 后至本次取证（2026-09-27）约 4.5 个月无新 release tag**。
- **是否活跃维护：是（活跃开发但近期未发版）**。main 已为 2.7.0（`Cargo.toml:41`），2026-09 仍有设计/验证文档与代码合入（`docs/kcp-control-reliability-validation-2026-09-14.md`、`docs/tcp-proxy-half-close-validation-2026-09-14.md`、commit 日期 2026-09-24），58 个 open PR 说明持续迭代。
- **公司/商业实体支持：无独立公司，社区/个人项目 + 实物赞助**。
  - 作者署名 `kkrainbow`（`easytier-core/Cargo.toml:9` `authors = ["kkrainbow"]`）；
  - `README.md:309-319` 原文："CDN acceleration and security protection for this project are **sponsored by Tencent EdgeOne**"、"Special thanks to **Langlang Cloud** and **RainCloud** for sponsoring our public servers"；
  - 有 Sponsor 章节接受个人赞助（`README.md:335`）。即：无商业公司治理与 SLA，长期支持依赖核心维护者个人。

## Q7. 性能 benchmark

- **未找到官方与 WireGuard/Tailscale 的吞吐/延迟对比数据。**
- 仓内与性能相关的实际材料：
  - `script/benchmark-two-node.sh`：两节点 network namespace + **iperf3** 单条 TCP 流双向测量脚本（usage 原文 "measures a single iperf3 TCP flow in both directions"），但**只有脚本、无结果数字**；
  - `easytier/benches/packet_bytes_extraction.rs`：数据包字段提取的 Rust 微基准（非网络吞吐）；
  - `docs/quic-proxy-memory-benchmark-2026-07-27.md`：QUIC proxy **内存**基准（非吞吐/延迟）；
  - `docs/kcp-control-reliability-validation-2026-09-14.md:295` 明确写道 "Windows/macOS 原生 TUN 端到端、生产规模长期负载、吞吐与容量上限仍（未覆盖）"（原文语境）。
- 结论：**无官方性能数字可引述；真实性能需自行用 benchmark-two-node.sh / iperf3 实测**（本次受红线限制未运行）。

---

## 来源清单

| 编号 | URL | Playwright 是否实开 | 一句原文引述 |
|---|---|---|---|
| S1 | https://search.nixos.org/packages?query=easytier | 是（new_tab+evaluate innerText） | "Name: easytier Version: 2.6.0 … License: Apache-2.0" |
| S2 | https://search.nixos.org/options?query=easytier | 是（navigate+snapshot） | "Showing results 1-19 of 19 options."（services.easytier.*） |
| S3 | https://github.com/NixOS/nixpkgs/issues?q=easytier | 是（new_tab+snapshot） | "6 Open / 125 Closed"；#399065 "Easytier NixOS Module Request" |
| S4 | https://github.com/NixOS/nixpkgs/blob/nixos-unstable/pkgs/by-name/ea/easytier/package.nix | 是（blob 页打开；代码区文本未读入） | 页面标题 "nixpkgs/pkgs/by-name/ea/easytier/package.nix at nixos-unstable" |
| S5 | https://github.com/NixOS/nixpkgs/blob/nixos-unstable/nixos/modules/services/networking/easytier.nix | 是（blob 页打开；代码区文本未读入） | 页面标题 "nixpkgs/nixos/modules/services/networking/easytier.nix at nixos-unstable" |
| S6 | https://github.com/EasyTier/Easytier/releases | 是（snapshot） | "v2.6.4 … Latest … 26 Assets"（linux/win/mac/freebsd 资产名） |
| S7 | https://github.com/EasyTier/Easytier/tags | 是（snapshot） | "v2.6.4 … May 12, 2026"；"Star 13.8k / Issues 388 / Pull requests 58" |
| S8 | https://github.com/EasyTier/Easytier | 是（new_tab，大快照） | 标题 "A simple, decentralized mesh VPN with WireGuard support." |
| S9 | 本地 `.github/workflows/Dockerfile` | 本地文件 | `ENTRYPOINT ["/sbin/tini", "--", "easytier-core"]`（:48） |
| S10 | 本地 `README.md` / `README_CN.md` | 本地文件 | "no distinction between server and client"（:176）；"released under the LGPL-3.0"（:301） |
| S11 | 本地 `easytier-core/src/config/toml.rs` | 本地文件 | `listeners = ["tcp://0.0.0.0:11010"]`（:1228）；dev_name 默认 ""（:33） |
| S12 | 本地 `script/benchmark-two-node.sh` | 本地文件 | "measures a single iperf3 TCP flow in both directions" |

## NixOS 落地工作量评级：**小**

理由：
1. nixpkgs（unstable，数据版本 5e2305d5）已收录包 easytier 2.6.0 与官方 NixOS 模块 `services.easytier`，模块原生支持多实例、声明式 settings（network_name/secret/ipv4/listeners/peers）、extraArgs/configFile/configServer，覆盖"纯 TCP 公共中继节点"全部所需参数；
2. 落地仅需在一个 host 配置加约 10 行模块声明 + 开放防火墙 11010/tcp，无需打包、无需自写 systemd；
3. 残余成本仅在：nixpkgs 版本 2.6.0 落后上游（最新 tag 2.6.4 / main 2.7.0），如需新版要做一次版本 bump（走 nixpkgs 贡献或本地 overlay，属"中"里的小项）；以及真机共存验证（Tailscale 网段本身不冲突）。

## 未验证项

1. **nixpkgs package.nix / easytier.nix 模块的具体代码内容未读入**：GitHub blob 页已真实打开，但代码区在折叠的 a11y 快照之外，且 GitHub CSP 禁止 evaluate 字符串脚本（unsafe-eval），未取得逐行内容；故打包 features、cargoHash、systemd 具体限制集、Apache-2.0 元数据来源未逐行确认。
2. **未运行 easytier-core --help / 未实际启动**（任务书禁止构建/试装）；CLI 全量 flag 清单以源码 clap 定义与 README 示例为准，`no_tun` 纯中继可行性标 [UNCERTAIN]。
3. **easytier.cn 官方文档站（含网络共存/Docker 详细指南）未实开**：本报告以仓库内 README/docs 源码为主。
4. **26.05 stable 频道中的版本/选项状态未单独区分**：search.nixos.org 页面同时含 26.05 与 unstable 索引，未逐一切频道核对（选项页数据来自 5e2305d5）。
5. **性能无任何实测数据**：未运行 benchmark-two-node.sh/iperf3（红线禁止），无吞吐/延迟数字。
6. 共存路由优先级（双方 exit node / 重叠子网）未实测，标 [UNCERTAIN]。
