# EasyTier 只能用 IP、无法用主机名/域名访问 —— 机制诊断与落地方案

- 日期：2026-10-01
- 网络：xinlly-mesh（10.144.144.0/24）
- 节点（实测）：raiyun2=10.144.144.1（公网中继，NixOS）、Windows 宿主机=10.144.144.3（easytier-gui 2.6.4）、ubuntu-test=10.144.144.11（裸 easytier-core）、手机（官方 App，已接入，本机未取证其具体配置）
- 调研性质：只读。未改任何配置、未重启进程、未安装软件、未写密钥。

---

## 0. 一句话结论

EasyTier **默认不带名字解析**：主机名虽随路由全网传播，但"主机名→IP"的解析依赖一个默认关闭的「魔法 DNS（Magic DNS / `--accept-dns`）」子系统，而且它**不是在 10.144.144.1:53 提供 DNS**，而是用假 IP `100.100.100.101` + TUN 包拦截实现；当前三节点均未启用，故只能用 IP。本环境推荐 **方案 d（公网真实子域返回 10.144.144.x，零端配置、手机任意网络可用）立即落地**，需要 `<hostname>.et.net` 裸主机名体验时再叠加方案 a。

---

## 1. EasyTier 名字解析的确切机制（源码 tag v2.6.4 + 本机实跑）

### 1.1. 主机名的发布：`--hostname`，缺省取系统主机名

实跑本机版本（Windows 宿主机 Temp 内的官方分发包，与运行中的 GUI 同源）：

```
PS> .\easytier-core.exe --version
easytier-core 2.6.4-8428a89d
```

`--help` 中：

```
--hostname <HOSTNAME>
    用于标识此设备的主机名 [env: ET_HOSTNAME=]
```

未显式传时，取操作系统主机名（EasyTier/EasyTier v2.6.4 `easytier/src/common/config.rs`）：

- `common/config.rs:654-673`：`hostname` 为 `None` 或空串时 `gethostname::gethostname()`，即系统主机名。

主机名随路由（Route）在网内传播，无需任何 DNS 开关。实测 `peer list` / `route list` 均有 `hostname` 列（见第 2 节）。

### 1.2. 解析靠「魔法 DNS」，默认关闭；监听点不是 vIP:53 而是假 IP 100.100.100.101

`easytier-core --help`：

```
--accept-dns <ACCEPT_DNS>
    如果为true，则启用魔法DNS。使用魔法DNS，您可以使用域名访问其他节点，例如：<hostname>.et.net。
    魔法DNS将修改您的系统DNS设置，请谨慎启用。
    [env: ET_ACCEPT_DNS=] [possible values: true, false]
--tld-dns-zone <TLD_DNS_ZONE>
    指定魔法DNS的顶级域名区域。如果未提供，默认使用 dns_server 模块中的值（et.net.）。
    [env: ET_TLD_DNS_ZONE=]
```

v2.6.4 源码常量（`easytier/src/instance/dns_server/mod.rs`）：

- `mod.rs:19` `MAGIC_DNS_INSTANCE_ADDR = "tcp://127.0.0.1:49813"`（easytier 内部 RPC 通道，非对外 DNS 端口）
- `mod.rs:20` `MAGIC_DNS_FAKE_IP = "100.100.100.101"`（**唯一对外的 DNS 地址**）
- `mod.rs:22` `DEFAULT_ET_DNS_ZONE = "et.net."`

工作链路（`instance/dns_server/runner.rs`、`server_instance.rs`、`client_instance.rs`）：

1. 启用 `accept_dns` 后，节点 `DnsRunner` 先尝试在**本机**起 DNS server（绑定 easytier 内部通道 127.0.0.1:49813），再起 client（`runner.rs:42-66`）。该端口是每台机器各自的本机通道，故每个节点都能本地充当 server，自己回答自己，不依赖全网选举。
2. client 把本机路由表中的**全部路由 + 本机自身**（hostname + vIP）通过内部 RPC 上报给本机 server（`client_instance.rs:63-83`）。server 据此生成 A 记录：`<hostname>.<zone>`，**TTL=1 秒**（`server_instance.rs:75-118`），并建 SOA/权威区。
3. 数据面：server 在本机 NIC 流水线里拦截 **dst=100.100.100.101** 的 IPv4 包 —— 只处理 UDP 目标端口 **53** 的 DNS 查询和 ICMP Echo（`server_instance.rs:294-356`，`if dst_ip != self.fake_ip { return None }`、`if dst_port != 53 { return None }`），交给内置 hickory DNS 应答后**原地交换源/目的地址回包**（`server_instance.rs:327-335`）。
4. 若 TUN 网段不含假 IP（本网络 10.144.144.0/24 不含 100.100.100.101），自动加一条 `100.100.100.101/32 → TUN` 的主机路由（`server_instance.rs:530-542`，Windows cost=4），保证本机 App 的 DNS 查询进 TUN。
5. server 负责把**系统 DNS 改成 100.100.100.101**（`server_instance.rs:155-164`，nameservers/search/match 都设为假 IP 与 zone）。
6. 非 `.et.net` 的查询转发到系统原有上游解析器（`dns_server/server.rs:91-116` hickory `ForwardAuthority`），并把假 IP 列入排除，防止环路（`server_instance.rs:525`）。

**关键平台差异（影响落地）**：自动改系统 DNS 只实现了 Windows 和 macOS，**Linux 返回 None、不自动改**：

- `server_instance.rs:492-510`：`#[cfg(target_os="windows")] → WindowsDNSManager`；`#[cfg(target_os="macos")] → DarwinConfigurator`；其余（Linux）`Ok(None)`。
- Windows 侧改动仅限 EasyTier TUN 接口对应的注册表项 `NameServer/SearchList`（`system_config/windows.rs:48-100`），不动物理网卡，并 `ipconfig /flushdns`。

即：**三节点当前都没开 `accept_dns` → 没有假 IP 路由、没有系统 DNS 改写、没有任何监听 53 的进程 → 全网只能用 IP。**

### 1.3. 端口实测（证明"vIP 上没有 DNS"）

在 WSL 对三节点 vIP 的 53 端口发真实 DNS 查询（UDP）并测 TCP（脚本手写 DNS 报文，查询 raiyun2.et.net / test.et.net / www.baidu.com）：

```
UDP 10.144.144.1:53  raiyun2.et.net  -> TimeoutError: timed out
UDP 10.144.144.1:53  test.et.net     -> TimeoutError: timed out
UDP 10.144.144.3:53  raiyun2.et.net  -> TimeoutError: timed out
UDP 10.144.144.11:53 raiyun2.et.net  -> TimeoutError: timed out
TCP 10.144.144.1:53  -> TimeoutError: timed out
TCP 10.144.144.3:53  -> Connection refused
TCP 10.144.144.11:53 -> Connection refused
```

Windows 宿主机 EasyTier TUN 接口 `et_8_pvnr` 当前 IPv4 DNS 为空（IPv6 为系统默认废弃站点本地地址）：

```
Get-DnsClientServerAddress -InterfaceAlias 'et_8_pvnr'
AddressFamily 2 (IPv4)  ServerAddresses : {}
```

旁证：路由表里存在一条 `100.100.100.100/32 → Tailscale`（Tailscale 占位，与 EasyTier 无关）；EasyTier 假 IP 是 **.101**，当前无该路由，与"未启用"一致。

### 1.4. easytier-cli 无 name/dns 子命令

实跑 `easytier-cli --help`（2.6.4），子命令为：

```
peer  connector  mapped-listener  stun  route  peer-center  vpn-portal
node  service  proxy  acl  port-forward  whitelist  stats  logger
credential  gen-autocomplete  help
```

**没有 name/dns 解析相关子命令**——名字解析完全是 core 内部能力，CLI 只通过 `peer list` / `route list` / `node info` 暴露 hostname 列。

---

## 2. 各节点当前 hostname 注册情况（逐个取证）

### 2.1 raiyun2（声明式 NixOS）

`projects/our/nixos/hosts/raiyun2/easytier.nix:10-16`：

```nix
settings = {
  network_name = "xinlly-mesh";
  ipv4 = "10.144.144.1";
  listeners = [ "tcp://0.0.0.0:11010" ];
};
environmentFiles = [ "/var/lib/easytier/relay.env" ];
```

未设 `hostname`（nixpkgs easytier 模块默认 `null`，取系统名，见 `/nix/store/6qwyfa76h4na0qq07rk359l3dk9ajkrh-source/nixos/modules/services/networking/easytier.nix:51-55`），也无任何 `accept_dns`。实测主机名 = `raiyun2`。

### 2.2 Windows 宿主机（easytier-gui 2.6.4，Tauri）

GUI 配置存在 WebView2 LocalStorage（`C:\Users\Admin0\AppData\Local\com.kkrainbow.easytier\EBWebView\Default\Local Storage\leveldb\000003.log`），其中 xinlly-mesh 网络配置关键字段：

```json
"hostname": null,
"network_name": "xinlly-mesh",
"peer_urls": ["tcp://ry.xinlly.top:51010"],
"enable_magic_dns": false,
"listener_urls": ["tcp://0.0.0.0:11010","udp://0.0.0.0:11010","wg://0.0.0.0:11011"]
```

即 GUI 也未设 hostname、未开魔法 DNS；系统名 `PC-XAVIER`。

### 2.3 ubuntu-test（Ubuntu，裸进程）

electerm（192.168.0.183）实跑 `ps aux`：

```
root 3150 ./easytier-core --network-name xinlly-mesh -i 10.144.144.11 -p tcp://183.66.27.22:51010
```

无 `--hostname`、无 `--accept-dns`；`easytier-cli` 未安装。系统名 `Ubuntu-Test`。

### 2.4 全网实测：hostname 已全部传播，仅缺解析

在 raiyun2 实跑（easytier-cli 2.6.4）：

```
# easytier-cli peer list
| ipv4             | hostname    | cost  | lat(ms) | tunnel | NAT       | version        |
| 10.144.144.1/24  | raiyun2     | Local | -       | -      | PortRestr | 2.6.4          |
| 10.144.144.3/24  | PC-XAVIER   | p2p   | 117.29  | tcp    | Symmetric | 2.6.4-8428a89d |
| 10.144.144.11/24 | Ubuntu-Test | p2p   | 87.64   | tcp    | Symmetric | 2.6.4-8428a89d |
```

结论：名字注册没问题，问题纯粹在"解析器"这一层。

### 2.5 手机

`[UNCERTAIN]` 未取证手机 App 版本与开关位置。官方 Android App 自带 VpnService，开启魔法 DNS 后通过 `Builder.addDnsServer(100.100.100.101)` 把解析器注入其 VPN 隧道（见 EasyTier PR #1862 的改动说明）。**注意该 PR 同时记载历史版本前端 bug：使用了已废弃字段 `enable_magic_dns` 导致 `addDnsServer` 未被调用、系统 DNS 未指向假 IP**；落地时需以实机解析结果验证，不能只看开关。

---

## 3. 手机/客户端接入方式与 Android 限制

### 3.1 Android「私人 DNS（Private DNS）」走不通假 IP 方案

依据 Google 官方文档（developers.google.com/speed/public-dns）：

- 私人 DNS「主机名」严格模式 = **DNS-over-TLS**：用户只能填**主机名**（不能填 IP、不能带端口），系统强制连 **853** 端口并校验 TLS 证书；连接失败是硬失败、无 DNS 可用。
- 「自动」模式同样先尝试对网络下发的解析器做 853 DoT，失败才回落 UDP/53。

因此 EasyTier 的 `UDP 53 @100.100.100.101` **无法**通过系统「私人 DNS」配置：非 TLS、非 853、且是 IP。手机要用魔法 DNS，**只能靠 EasyTier 官方 App 内部 VpnService 注入**（App 自己建隧道、自己指定 DNS，不受系统私人 DNS 限制）。

### 3.2 不用官方 App 时手机的选项

- 改系统 hosts：Android 不开放，需 root（部分厂商"私人 DNS"只能填 DoT 主机名，不能做 hosts）。
- 唯一零 root、零 App 依赖的路径：让**公网 DNS**直接把专用域名解析到 10.144.144.x（方案 d）——查询走手机当前任意网络，拿到私网 IP 后由 EasyTier App 的 10.144.144.0/24 路由进隧道，两者天然解耦。

---

## 4. 方案对比

| 方案 | 手机可用性 | 桌面改动 | 新增服务 | 名字形态 | 主要隐患/成本 | 结论 |
|---|---|---|---|---|---|---|
| **a. 内置魔法 DNS + hostname** | 仅官方 App 且开关有效；需实测防历史 bug | Win 一键；**Linux 不自动改系统 DNS**，需自行做分域解析（见下） | 无 | `<hostname>.et.net`（裸名） | Linux 端配置有讲究；依赖 App 版本 | 推荐作为主机名体验增强 |
| **b. 网内独立 DNS（dnsmasq/CoreDNS 绑 10.144.144.x，静态 A）** | 手机仍需能把 DNS 指向它——官方 App 不支持任意自定义 DNS（issue #1071 的诉求正是此点），实际仍需 root/App 支持 | 各端改 DNS | **要**（进程、监听、开机自启、防火墙） | 任意自定义域名 | 多一个要维护的服务，且手机问题并没真正解决 | **不推荐**（对单用户是过度工程） |
| **c. 各端本地 hosts** | Android 需 root，基本不可行 | 每端手工，新增节点全量改 | 无 | 任意 | 不可规模化 | 不推荐（桌面临时调试可用） |
| **d. 真实域名公网解析 → 10.144.144.x** | **任意网络、零端配置**（4G/WiFi 都可） | 无 | 无 | 固定域名（可通配 `*.mesh.xxx`） | 未连 mesh 时该域名为黑洞；名字公开可查（准入仍靠 network secret）；DNS rebinding 面 | **推荐立即落地** |

方案 a 的 Linux 细节（`[UNCERTAIN]` 项已在源码层面消除大部分）：

- Linux（raiyun2/ubuntu-test）不会自动改系统解析器。若简单把 `100.100.100.101` 与公共 DNS 并列写入 resolv.conf，公共 DNS 对 `xxx.et.net` 返回 NXDOMAIN 时 glibc 通常直接采用、不再问下一个解析器，不可靠。
- 可靠做法是**分域路由**：NixOS 用声明式 `networking.resolved`/resolvconf 让 `et.net` 仅走 100.100.100.101、其余走原上游；ubuntu-test 用 `resolvectl domain` 配置。这使方案 a 在 Linux 上的成本明显高于 Windows。

方案 d 隐患的具体缓解：

- 公网 DNS 返回 RFC1918 地址本身被允许（Cloudflare DNS-only 灰云记录可正常返回私网 IP；**不能开橙色代理**，代理只接受公网源站）。
- 用专用子域（如 `mesh.xinlly.top`）承载，不复用其他业务；不给公网网站使用这些名字。
- DNS rebinding：公网网页脚本拿到这些名字的私网地址后可尝试访问本机/私网服务（现代浏览器有防护但非全场景）。缓解：mesh 内服务不要把这些名字用于公网 Web、敏感服务自带鉴权。
- 未接入 mesh 时解析仍成功但连接黑洞——属预期；不影响其他域名。
- 准入安全不受影响：知道名字≠能进网，仍需 network secret。

### 推荐

1. **立即做 d**：在已有公网 DNS（xinlly.top 的 NS 实测为 Cloudflare：`leif/selah.ns.cloudflare.com`，`ry.xinlly.top` 现有 A=183.66.27.22 勿动）下新增一个专用子域，3~4 条 A 记录。手机立刻可用，桌面零改动。
2. **可选叠加 a**：仅当需要 `<hostname>.et.net` 裸名时。Windows GUI 开魔法 DNS 最省事；两台 Linux 需配分域解析，按第 5 节走声明式/系统配置。
3. b、c 不做。

---

## 5. 待批准实施步骤（本次不执行）

### 方案 d：公网专用子域（推荐先做）

改动位置：Cloudflare  DNS（控制台人工操作，或经 xavier 提供 API Token 后用 API；本环境不持有、不写入该 Token）。

1. 新建 A 记录（**灰云 DNS only**），建议：
   - `raiyun.mesh.xinlly.top → 10.144.144.1`
   - `pc.mesh.xinlly.top    → 10.144.144.3`
   - `ubuntu.mesh.xinlly.top→ 10.144.144.11`
   - 或通配 `*.mesh.xinlly.top →` 按需要（通配只能指向单一 IP，故多主机仍建议逐条）。
2. 验证（实跑命令）：
   - `curl -s "https://dns.google/resolve?name=pc.mesh.xinlly.top&type=A"` 期望 Answer=10.144.144.3；
   - 手机切 4G（关 WiFi）浏览器/SSH 工具访问 `ubuntu.mesh.xinlly.top`；
   - Windows `ping pc.mesh.xinlly.top`。
3. 影响面：仅新增公网 DNS 记录，不动任何节点系统/进程；对现有服务零影响（独立子域）。
4. 回滚：删除这几条记录，TTL 过后失效（记录 TTL 建议设 300）。

### 方案 a：魔法 DNS（可选增强）

1. **workspace（NixOS 配置仓库）**：编辑 `projects/our/nixos/hosts/raiyun2/easytier.nix`
   - 显式 `settings.hostname = "raiyun2";`（与现状同名，仅为固化）；
   - `extraSettings = { flags.accept_dns = true; };`（nixpkgs easytier 模块支持 `extraSettings` 透传 TOML `[flags]`，见 easytier.nix:174-180；`accept_dns` 为 core flags 键）。
   - Linux 系统侧分域解析（声明式，待按本机实际解析管理方式 resolved/resolvconf 确定具体选项后再写）：让 `et.net` → 100.100.100.101，其余域名维持原上游。
2. **Windows GUI**：编辑 xinlly-mesh 网络 → 高级/主机名填 `pc-xavier`（建议显式小写，避免系统名大小写进入 DNS label）→ 打开「魔法 DNS」开关 → 保存（GUI 自动重启 core，仅瞬断）。
3. **ubuntu-test（需 root，经 electerm，sudo 纪律）**：启动命令改为
   `./easytier-core --network-name xinlly-mesh -i 10.144.144.11 -p tcp://183.66.27.22:51010 --hostname ubuntu-test --accept-dns`，
   并配置系统分域解析（`resolvectl`/NetworkManager，仅 root 可改）。重启进程期间该节点短暂离线。
4. **手机**：官方 App 的 xinlly-mesh 网络设置里开「魔法 DNS」（具体菜单随版本，落地时截图/实测确认）。
5. 部署：NixOS 侧 `nixos-rebuild`（按既定 sudo/协调者纪律执行，需先 export 代理）。
6. 验证：
   - 各端 `ping raiyun2.et.net`、`ping pc-xavier.et.net`、`ping ubuntu-test.et.net` 期望解析到对应 vIP；
   - 手机同样验证；外部域名（如 www.baidu.com）解析必须仍正常（验证转发上游未环）；
   - `ip route get 100.100.100.101` 应走 EasyTier TUN。
7. 影响面：
   - Windows：仅 EasyTier TUN 接口注册表 DNS 项（源码已证，不动物理网卡）；
   - Linux：easytier 进程参数 + 系统解析分域配置；
   - mesh 断连时 `.et.net` 不可用（预期）；配置不当可能影响整机 DNS（故分域而非全局替换）。
8. 回滚：nix 改回后 rebuild；GUI 关魔法 DNS、清 hostname；ubuntu 去掉两个参数并还原 resolvectl；手机关开关。假 IP/32 路由由 core 在退出时自行移除（`server_instance.rs:583-597`）。

---

## 6. 本次调研的取证清单与未验证项

实跑取证（均为本次真实输出）：

- Windows 包：`easytier-core 2.6.4-8428a89d`；`easytier-core --help`（hostname / accept-dns / tld-dns-zone）；`easytier-cli --help`（无 dns 子命令）。
- 临时探测实例（独立网络 tmp-probe-only、`--no-tun`、随机 RPC 端口，跑完即杀）：`node info`（Hostname=PC-XAVIER）、`peer list`/`route list` 表头含 hostname 列。
- 三节点 vIP:53 UDP/TCP 实测无响应/拒绝；TUN 接口 DNS 为空。
- raiyun2：`easytier-cli 2.6.4 peer list` 三节点 hostname 实测。
- ubuntu-test：`ps aux` 裸进程命令行实测。
- 域名：xinlly.top NS=Cloudflare、ry.xinlly.top A=183.66.27.22（Google DNS API 实测）。
- 源码：EasyTier v2.6.4 `common/config.rs`、`instance/dns_server/{mod,runner,server_instance,client_instance,server}.rs`、`system_config/windows.rs`；nixpkgs easytier 模块 `/nix/store/6qwyfa76.../nixos/modules/services/networking/easytier.nix`。

未验证（`[UNCERTAIN]`）：

1. 手机 App 版本、魔法 DNS 开关实际位置与是否存在 PR #1862 所述字段 bug——需真机操作验证。
2. EasyTier 官方文档站（easytier.rs）经本机代理抓取失败（curl exit 56/92，TLS/传输层问题），机制结论以 v2.6.4 源码与实跑为准，未引用该站内容。
3. 方案 a 在 NixOS/Ubuntu 上系统分域解析的**确切配置选项**未在本次写入（需结合各机当前是 systemd-resolved 还是其他解析管理方式再定）；已确认"必须分域、不能简单并列 NS"。
4. 方案 d 记录尚未创建（待批准）。
