# EasyTier 实测部署方案（raiyun2 修订版）：Windows 宿主机 + 现有 raiyun2

- 工作区：lab/easytier（workspace wks_e84b76，worktree 本目录）
- 配套依据：`REPORT.md`（可行性裁决）、`research/out/worker-a-protocol.md`（协议源码实证）、`research/out/worker-b-deployment.md`（打包/共存）、`research/out/worker-c-docs.md`（官方文档实读，6 页 Playwright 实开 + planner 抽验 2 页为真）
- 上游基线：EasyTier v2.6.4（release）/ 源码 ff3921ce；nixpkgs nixos-unstable 已含 easytier 2.6.4 + `services.easytier`
- 状态：**仅规划，未部署**。控制台动作 / 重建 / Windows 运行均按 §7 逐项报 xavier 确认

> **修订标记（2026-09-27，xavier 定）**：雨云节点 = **现有 raiyun2**（不是新购机、不新建 host）。EasyTier 作为 `hosts/raiyun2` 上的**附加服务**与现有 DERP / Nginx / socat 共存。变更走 `nixos-rebuild test`（不写 boot），`switch` 需 xavier 明确指令。

---

## 1. 测试目标与环境参数（已只核实）

### 1.1 目标
在"仅能提供 TCP 入站（共享 NAT、公网 UDP 入站 DNAT 失效）的 raiyun2 + Windows 宿主机（江苏移动出口 WAN_EGRESS_IP）"条件下，实测：
1. 不经公网 UDP 入站、仅凭 TCP 完成组网；
2. raiyun2 作为可用公共中继节点（与现有 DERP 共存、互不影响）；
3. 两节点虚拟 IP 互通、真实服务可达；（中继数据面需 ≥3 节点，见 §2.3）
4. 与现有 Tailscale 零影响、可回滚。

### 1.2 环境（planner 经 SSH 一手核实，2026-09-27）
| 项 | 值 | 核实方式 / 状态 |
|---|---|---|
| Windows 公网出口 | WAN_EGRESS_IP（江苏移动） | xavier 给定 |
| 雨云节点 | **raiyun2**，NixOS，本仓库 flake `hosts/raiyun2` | xavier 定 / SSH `hostname`=raiyun2 |
| raiyun2 公网 IP | RAIYUN2_PUBLIC_IP（共享 NAT） | xavier 给定 |
| raiyun2 内网 IP | **172.16.71.87/16**（ens18） | SSH `ip -4 addr` 实测 |
| Tailscale | tailscale0=100.125.56.1/32 | SSH 实测 |
| EasyTier 内网监听 | **11010/tcp（实测空闲，`ss` 计数=0）** | SSH 实测 |
| 新增公网 DNAT | `<NEW_PUB_PORT>`（建议 51010）→ 172.16.71.87:11010 | **待 xavier 批准控制台变更** |
| network_name / secret | `<NET_NAME>` / `<NET_SECRET>`（强随机，environmentFile） | 部署前生成，不入 Nix store |
| 虚拟 IP | raiyun2 10.144.144.1；Windows 10.144.144.11 | 方案设定 |

---

## 2. 网络架构

### 2.1 角色
- **raiyun2 = 公共节点 / 中继（附加服务）**：监听 `tcp://0.0.0.0:11010`，经控制台**新增 1 条 TCP DNAT** 暴露公网。
  - 阶段1 配虚拟 IP 作普通对端；阶段2 **ipv4 留空 = 纯转发、不建 TUN**（nixos 模块语义，`research/verify/module.nix:72-81`）。
- **Windows 宿主机 = 客户端节点**：自带 wintun.dll 建虚拟网卡（10.144.144.11），主动拨入 `tcp://RAIYUN2_PUBLIC_IP:<NEW_PUB_PORT>`。

### 2.2 不依赖公网 UDP 入站（源码实证）
- tcp/ws/wss URL 全部映射到 `ProtocolTransport::Tcp`，建连路径无 UDP：`easytier-core/src/connectivity/protocol/mod.rs:25`。
- 中继为任意节点逐包转发、默认开启、白名单默认 `*`：`peers/peer_manager.rs:3078-3112`、`config/toml.rs:42,72`、`peers/whitelist.rs:5-17`。
- 官方文档互证（planner Playwright 抽验 `document.body.innerText.includes(...)` 均 true）：快速组网示例即 `-p tcp://<共享节点>:1010`，原文"P2P 失败时由共享节点中转数据"；安装页"下载后为 ZIP 压缩包，解压后既可直接使用"。
- 故 raiyun2 的 UDP DNAT 失效**不影响** EasyTier；纯 TCP 即可跑通，WSS(443) 为备选。

### 2.3 拓扑与两阶段
```
阶段1（2 节点，验证纯 TCP 组网）
  Windows(10.144.144.11) ──TCP──> raiyun2(10.144.144.1, listeners tcp 11010)
  公网: RAIYUN2_PUBLIC_IP:<NEW_PUB_PORT> --新增DNAT/TCP--> 172.16.71.87:11010

阶段2（3 节点可选，验证"中继数据面"）
  Windows(10.144.144.11) ┐
                         ├─TCP─> raiyun2(纯转发,无 ipv4/TUN) ─TCP─┐
  节点C(10.144.144.12, 不同出口) ─────────────────────────────────┘
```
- 2 节点验证"仅 TCP 建连 + 虚拟 IP 互通"；证明逐包中继需第 3 节点（不同出口/阻断直连），raiyun2 ipv4 留空只转发。
- [UNCERTAIN] 节点 C 若与 Windows 同出口会走直连，不能代表中继——作为可选扩展。

---

## 3. raiyun2 现有服务与无冲突核实（已实测）

### 3.1 现有监听（SSH `ss -lntu` 一手输出）
| 服务 | 内网监听 | 公网 DNAT（xavier 给定） |
|---|---|---|
| SSH | tcp 22 | 16467→22 |
| Nginx | tcp 443（+树洞 vhost） | 52443→443、52081→443 |
| Nginx/HTTP | tcp 80（**实测无 LISTEN**，仅 443；52080→80 DNAT 当前无本机后端） | 52080→80 |
| Tailscale DERP | tcp 8010 | 58010→8010 |
| DERP STUN | udp 3478 | 53478→3478（UDP DNAT 失效，与本测试无关） |
| treehole-socat | tcp 18080（localhost/0.0.0.0 转发） | 无 |
| tailscaled | tcp 36532（IPv6） | — |
| **EasyTier（新增）** | **tcp 11010（实测空闲）** | **<NEW_PUB_PORT>→11010** |

### 3.2 无冲突结论
- 内网 11010 `ss` 计数=**0**，与现有任何服务不冲突。
- 新增公网口须避开已用：58010、52443、52080、52081、16467、53478。**建议 `<NEW_PUB_PORT>`=51010**（备选 51011），最终由 xavier 在控制台定。
- EasyTier 不改动 DERP(8010)/STUN(3478)/Nginx(443,80)/socat(18080) 任何现有规则。

---

## 4. 安装步骤

### 4.1 Windows 侧（解压即用，release 已静态核查）
- v2.6.4 x86_64 zip 内容（`research/dist/win-x86_64.zip` 已 zipfile 解包核查）：
  `easytier-core.exe`、`easytier-cli.exe`、`easytier-web.exe`、`easytier-web-embed.exe`、**`wintun.dll`、`WinDivert64.sys`、`Packet.dll`** → 自带 TUN 驱动、解压即用，wintun.dll 须与 exe 同级。
- 步骤：
  1. 建 `C:\EasyTier`，解压入内（**执行前报 xavier 确认**）；
  2. **管理员** PowerShell（wintun 需管理员）；
  3. 测试期前台运行：
     ```powershell
     cd C:\EasyTier
     .\easytier-core.exe --network-name <NET_NAME> --network-secret <NET_SECRET> `
       -i 10.144.144.11 -p tcp://RAIYUN2_PUBLIC_IP:<NEW_PUB_PORT>
     ```
  - 参数一手出处：`easytier/src/core.rs:145-154`（network-name/secret）、`:159-162`（-i）、`:209-213`（-p）、`:236-240`（-l）。
  - xavier 已批准用 Electerm 跑**非破坏性** PowerShell 采集（arch / 管理员 / 是否已装 EasyTier）；**解压 + 管理员运行 easytier-core 仍属需确认动作**。
  - [UNCERTAIN] `--daemon`（core.rs:135）Windows 服务化行为未实证，测试期前台，不用。

### 4.2 raiyun2 NixOS 侧（现有 host 加附加服务，nixpkgs 官方模块）
- **新增** `hosts/raiyun2/easytier.nix`（不动 derper.nix / 现有文件逻辑）：
  ```nix
  # hosts/raiyun2/easytier.nix — EasyTier 公共节点（与 DERP 共存）
  { ... }:
  {
    services.easytier.instances.relay = {
      enable = true;
      settings = {
        network_name = "<NET_NAME>";
        listeners = [ "tcp://0.0.0.0:11010" ];
        # 阶段1: ipv4 = "10.144.144.1";  阶段2: 不写 ipv4 = 纯转发无 TUN
      };
      environmentFiles = [ "/var/lib/easytier/relay.env" ]; # ET_NETWORK_SECRET=<NET_SECRET>
    };
    networking.firewall.allowedTCPPorts = [ 11010 ];
  }
  ```
- 在 `hosts/raiyun2/default.nix` 的 `imports` 中**仅追加一行** `./easytier.nix`。
- secret：手动 SFTP 上传 `/var/lib/easytier/relay.env`（`chmod 600`，root only），**不入 world-readable Nix store**（模块明确建议 environmentFiles，`research/verify/module.nix:63-70`）。
- 部署命令（在 raiyun2，**先 test 不写 boot，执行前报确认**）：
  ```bash
  export https_proxy=http://127.0.0.1:35353 http_proxy=http://127.0.0.1:35353   # raiyun2 经验：先 export 代理再 rebuild
  nixos-rebuild test --flake .#raiyun2        # 仅运行代验证，不写 boot，重启即回退
  ```
- **`nixos-rebuild switch` 必须等 xavier 明确指令**；test 通过且确认无影响后再议。
- nixpkgs 模块单元含硬化（DynamicUser、CAP_NET_RAW/ADMIN、ProtectSystem 等，`research/verify/service.nix:185-201`）；environmentFiles 需对服务可读。

---

## 5. 验证步骤与金标准（G1–G8 不变）

CLI 一手出处（`easytier/src/easytier-cli.rs`）：`peer list`（:197-198）、`route list/dump`（:222-225）、`statistics`。

| 级别 | 验收点 | 命令 | 环境 | 预期 / 判定 |
|---|---|---|---|---|
| G1 | Windows 虚拟网卡 | `ipconfig` | Windows(管理员) | wintun/EasyTier 网卡 IPv4=10.144.144.11 |
| G2 | raiyun2 监听就绪 | `ss -lntp \| grep 11010`；`systemctl status easytier-relay` | raiyun2 | LISTEN 0.0.0.0:11010；active(running) |
| G3 | 公网 TCP 可达 | `Test-NetConnection RAIYUN2_PUBLIC_IP -Port <NEW_PUB_PORT>` | Windows | `TcpTestSucceeded : True` |
| G4 | 对端建立 | `.\easytier-cli.exe peer list` | Windows | 列出 raiyun2（tcp / 虚拟 IP / 时延），无 DOWN |
| G5 | 路由学到 | `.\easytier-cli.exe route list` | Windows | 含 10.144.144.0/24 经 raiyun2 |
| G6 | **虚拟 IP 双向互通（核心）** | Windows `ping 10.144.144.1`；raiyun2 `ping 10.144.144.11` | 两侧 | 双向回显、0% 丢包 |
| G7 | **真实服务可达（核心）** | raiyun2 `python3 -m http.server 18081`；Windows `curl.exe -i http://10.144.144.1:18081/` | 两侧 | HTTP 200 + HTML（端口用 18081 避开现有 18080） |
| G8 | 端口转发（可选） | `[[port_forward]]` 后访问 | — | config/toml.rs:1919-1922 |

- G6/G7 为"真正组网"硬判定，只看 G4 不算；输出贴原文，失败即记证据。

### 5.1 阶段2（可选）：第 3 节点不同出口，raiyun2 ipv4 留空纯转发；`ping`/`iperf3 -c 10.144.144.11` 通，`easytier-cli statistics` 转发字节增长，产出真机吞吐/RTT 基线。

---

## 6. 回滚与隔离

### 6.1 隔离保证
- EasyTier 网段 10.144.144.0/24，不碰 Tailscale 100.64.0.0/10；独立 TUN（raiyun2 不建 TUN 时为纯 socket 转发），非 tailscale0。
- `enable_exit_node=false`、`accept_dns=false`（`config/toml.rs:38,56`）：不改默认路由、不接管 DNS。
- 不动现有 DERP(8010)/STUN(3478)/Nginx/socat；仅新增独立 11010 监听 + 1 条控制台 TCP DNAT。

### 6.2 停用与清理
- **因先用 `nixos-rebuild test`（不写 boot）**：任何异常，重启 raiyun2 即回退到 boot 代（EasyTier 不随启动）；这是首选回退。
- 主动停用：移除 `hosts/raiyun2/easytier.nix`（并撤 default.nix 那行 import）→ `nixos-rebuild test --flake .#raiyun2` 验证 → 再按 xavier 指令决定是否 `switch`；删 `/var/lib/easytier/relay.env`。
- Windows：Ctrl+C 断链（wintun 随进程移除），彻底清理删 `C:\EasyTier`，`ipconfig` 复核无残留。
- 控制台：**仅删除本次新增的 `<NEW_PUB_PORT>` TCP DNAT**，不碰既有任何规则。
- 回滚后核对：DERP/Tailscale `tailscale status`、Nginx vhost 全部不变。

---

## 7. 待 xavier 批准的控制台 / 部署动作清单

| # | 动作 | 类型 | 本线建议 |
|---|---|---|---|
| A | raiyun2 控制台**新增 1 条 TCP DNAT**：`<NEW_PUB_PORT>`(建议 **51010**) → 172.16.71.87:**11010** | 控制台变更（影响网络暴露面） | 批准后由 xavier/授权操作 |
| B | 新增 `hosts/raiyun2/easytier.nix` + default.nix 追加 1 行 import | 仓库改动（仅 EasyTier 相关） | 不夹带其他改动、不 commit |
| C | SFTP 上传 `/var/lib/easytier/relay.env`（secret，600） | 凭据落主机 | 用强随机 secret |
| D | `nixos-rebuild test --flake .#raiyun2`（export 代理；**不写 boot**） | 主机临时运行 | 批准后执行，重启即回退 |
| E | Windows 解压 zip 到 `C:\EasyTier` + 管理员前台运行 easytier-core | 真机改动 | 仍需确认（非破坏性 PS 采集已批） |
| F | （可选）阶段2 第 3 节点 + `nixos-rebuild switch` | 后续 | 均需 xavier 明确指令 |

**还需 xavier 定 / 提供**：`<NEW_PUB_PORT>` 最终取值（默认 51010）；`<NET_NAME>`；确认 secret 由我方生成。

---

## 8. 证据与未验证项

### 8.1 关键机制证据
- raiyun2 身份/内网 IP/11010 空闲：Electerm SSH（tab HXGJkN7_…）`hostname`/`ip -4 addr`/`ss -lntu` 一手输出。
- 不经 UDP/纯 TCP：`connectivity/protocol/mod.rs:25`；逐包中继默认开：`peer_manager.rs:3078-3112`、`config/toml.rs:42,72`、`peers/whitelist.rs:5-17`。
- TOML 范式：`config/toml.rs:1886-1923`；Windows CLI：`easytier/src/core.rs:145-240`；cli 子命令：`easytier-cli.rs:124-225`。
- release 自带 wintun/WinDivert：`research/dist/win-x86_64.zip` 解包清单；nixos 模块：`research/verify/{module,service,package}.nix`（2.6.4、纯转发语义、硬化）。
- 官方文档 6 页实开：`research/out/worker-c-docs.md`；planner Playwright 抽验快速组网/安装页关键句 = true。

### 8.2 未验证项 [UNCERTAIN]
1. 真机一切：纯 TCP 连通率、ping/iperf3、稳定性（待执行）；
2. 新增 TCP DNAT(51010) 在 raiyun2 共享 NAt 是否与现有 52443 一样外部可入（待 G3）；
3. `--daemon` Windows 服务化（测试期不用）；阶段2 阻断直连做法；
4. 文档 config-file 页 yaml/toml 扩展名混用（解析格式实为 TOML，是否兼容 YAML 未查）；
5. WSS 正式证书路径（默认自签/跳校验），主路径用裸 tcp（自带 AEAD）；
6. primary 工作区存在**非本线**未提交的 `hosts/raiyun2/derper.nix`(+21/-6)：本线修订/后续提交**严禁夹带**，只触碰 EasyTier 相关文件，且不 commit。
