# 诊断报告：其他设备经 Tailscale 无法访问旧机 raiyun

- 日期：2026-10-10（取证时间窗 13:14–13:57 CST）
- 对象：旧机 **raiyun**（公网入口 103.40.13.68，Tailscale 100.67.115.10）。注意区分 raiyun2（183.66.27.22），本报告不针对 raiyun2。
- 性质：只读诊断，未做任何改变态操作（未重启服务、未改 DNS/配置、未清缓存、未 switch）。
- 取证通道：raiyun 经 Electerm 已有 SSH 书签；宿主机经 Electerm 本地 PowerShell 标签；WSL 仅做 DNS/TLS 辅助；hk 以"宿主机 ping hk-server"作为对照（hk 的 SSH 书签 xinlly.top:22 当次连接失败，未登录 hk）。

---

## 一、结论（结论先行）

**根因：raiyun 自身的 tailscaled 无法保持任何一条 DERP 客户端长连接，导致入站中继与打洞都不通——而 raiyun 作为 DERP 服务器本身是健康的。**

- raiyun 的 tailscaled 被强制配置了 HTTP 代理（`hosts/raiyun/derper.nix:21-25`，`HTTP_PROXY/HTTPS_PROXY/ALL_PROXY → 127.0.0.1:35353 mihomo`），所有 DERP 连接都经 mihomo 绕出。
- 实测：tailscaled 到**本机 home DERP（902）的 Recv 长连接每约 10 秒被 EOF**；到备用区域 **900 derp-hk 持续 `GET failed: <html>`**，且 mihomo 实时连接显示 `derp.xinlly.top` 被错误地**走加拿大机场代理**（chains=`专线-加拿大-A→libcyber-自动→SELECT`）而非直连。
- raiyun 在 DERP 上没有稳定会话，直连 NAT 路径也未建立 → 外部节点（宿主机）的数据包投递不到 raiyun → `tailscale ping` 全部超时。

**置信度：高（~0.8）。** 高置信部分：DERP 服务器健康、DNS 无劫持、证书当前真实有效、病灶在 raiyun 客户端侧 DERP 链路、且与强制 mihomo 代理 + 分流错误强相关。

**关于用户看到的 `O=redirect-cnzz` 自签证书：当前不可复现，属瞬态。** 14 天日志内仅出现 **1 次（Oct 8 17:04:50）**；宿主机/WSL/raiyun 三处当前拿到的都是真实 Let's Encrypt 证书。Health 里这条是粘滞的历史告警。其精确来源见 [UNCERTAIN]。

---

## 二、客户端实际生效 DERP 配置（以 map 为准）

命令（raiyun）：`tailscale debug derp-map`

'Rainyun DERP 1' 段落（原始输出，derp-map 行 991–1003）：

```json
"RegionID": 902,
"RegionCode": "derp-cn-raiyun1",
"RegionName": "Rainyun DERP 1",
"Nodes": [
  {
    "Name": "cn-raiyun-1",
    "RegionID": 902,
    "HostName": "derp.cn.xinlly.top",
    "STUNPort": 53478,
    "DERPPort": 52443
  }
]
```

事实：**RegionID=902 / HostName=derp.cn.xinlly.top / DERPPort=52443 / STUNPort=53478**。
内部链路：雨云网关 52443→nginx 443→derper 8010；53478→STUN 3478（见 `hosts/raiyun/derper.nix:11-15,31-44`）。

`tailscale netcheck`（raiyun，原始）：

```
* UDP: true
* IPv4: yes, 103.205.253.159:35661
* IPv6: no, but OS has support
* Nearest DERP: Rainyun DERP 1
* DERP latency:
    - derp-cn-raiyun1: 700µs   (Rainyun DERP 1)
    - derp-hk:                 (Hong Kong DERP)        ← 空
    - derp-cn-raiyun2:         (Rainyun DERP 2)        ← 空
```

注意两点：
1. raiyun 仅能触达本机 home DERP（700µs 本地环回级），两个自定义备用 DERP 延迟均为空。
2. STUN 观测到的 raiyun **出向 NAT 地址为 103.205.253.159**，与入站 DERP 地址 103.40.13.68 不同——雨云入/出向公网 IP 不对称（雨云常见），相关于后续 hairpin/直连判定。

---

## 三、DNS 分层核查：当前无劫持

权威 NS：`host -t NS xinlly.top` → `leif.ns.cloudflare.com`、`selah.ns.cloudflare.com`。

| 解析层 | 命令 | derp.cn.xinlly.top 结果 |
|---|---|---|
| WSL 默认 | `host derp.cn.xinlly.top` | 103.40.13.68 |
| 阿里公共 | `host derp.cn.xinlly.top 223.5.5.5` | 103.40.13.68 |
| 腾讯公共 | `host derp.cn.xinlly.top 119.29.29.29` | 103.40.13.68 |
| DoH 阿里（直连） | `https://223.5.5.5/resolve?name=derp.cn.xinlly.top&type=A` | 103.40.13.68（TTL 297） |
| DoH DNSPod（直连） | `https://doh.pub/dns-query` | 103.40.13.68（TTL 300） |

DoH 阿里原始应答：

```json
{"Status":0,...,"Answer":[{"name":"derp.cn.xinlly.top.","TTL":297,"type":1,"data":"103.40.13.68"}]}
```

判定：**DNS 记录本身在权威/各公共解析/本机各层完全一致，均指向真实 raiyun DERP（103.40.13.68），当前不存在 DNS 劫持或记录被改。**

旁证（900 区域）：`getent ahosts derp.xinlly.top` → **14.1.99.5**（= hk-server 公网 IP）。

---

## 四、TLS 三点对照：当前证书均为真实 Let's Encrypt

目标端口以 DERP map 为准 = **52443**（直连 443 无证书，雨云仅做 52443→443 转发）。

| 观测点 | 出接口判定 | Subject | Issuer | 有效期 | 链校验 |
|---|---|---|---|---|---|
| 宿主机直连 | `Find-NetRoute` → 物理网卡 Realtek 2.5GbE，下一跳 192.168.0.1（非 TUN） | CN=xinlly.top | C=US,O=Let's Encrypt,CN=YE1 | 2026-08-25 ~ 2026-11-23 | ChainErr=None |
| WSL | — | CN=xinlly.top | Let's Encrypt YE1 | 同上 | VERIFY=0 |
| raiyun 本机 | nix store openssl | CN=xinlly.top | Let's Encrypt YE1 | 同上 | VERIFY=0 |

宿主机原始：

```
Subject=CN=xinlly.top
Issuer=CN=YE1, O=Let's Encrypt, C=US
NotBefore=08/25/2026 21:36:42 NotAfter=11/23/2026 21:36:41
ChainErr=None
```

WSL 对 52443 连续 12 次采样 issuer，**12 次全部为 `Let's Encrypt YE1`**，无一次 redirect-cnzz。
SAN：`DNS:*.cn.xinlly.top, DNS:*.xinlly.top, DNS:xinlly.top`。

判定：**三处当前拿到的都是真实 LE 证书，redirect-cnzz 此刻不可复现，MITM 不是当前持续状态。**

---

## 五、服务端只读检查（raiyun）：DERP 服务器健康

监听（`ss -tlnp/-ulnp`，原始）：

```
LISTEN 0.0.0.0:443   users:(nginx)
LISTEN *:8010        users:(derper)     ← DERP 内部端口
UNCONN *:3478        users:(derper)     ← STUN
LISTEN *:35353       users:(mihomo)
```

- 服务状态：derper / nginx / mihomo / tailscaled 均 `active`。
- 落盘证书目录 `/opt/acmeDeliverClient/certs/xinlly.top_ecc/`：`fullchain.pem`、`key.pem` 时间戳 **2026-09-25 14:57（新鲜，未过期）**。
- ACME 投递链路 `acmeDeliverClient`（`acmeDeliverClient.sh`、`run.sh`、`acmeDeliverClient.log`）存在，投递机制在位。
- 各本地探针：nginx :443 `CODE=200 VERIFY=0`；derper 明文 127.0.0.1:8010 `CODE=200`。

**关键：raiyun 正在作为 DERP 服务器为其他节点提供中继。**
`tailscale status --json` 中 Relay 字段统计：

```
9 × "Relay": "derp-cn-raiyun1"   ← 9 个在线 peer 正以本机 902 为中继
4 × "Relay": "derp-cn-raiyun2"
1 × "Relay": "derp-hk"
1 × "Relay": ""                  ← raiyun 自身
9 × Online:true / 6 × Online:false
```

判定：**902 DERP 服务本身、证书、投递、对外中继全部健康（还在给 9 个别的节点转发）。故障不是"DERP 服务器挂了"。**

---

## 六、可达性根因：raiyun 客户端侧 DERP 长连接不通

### 6.1 现象：宿主机 ping raiyun 全部超时，ping hk 正常

宿主机 PowerShell（Electerm）：

```
PS> 1..6 | ForEach-Object { tailscale ping -c 1 --timeout 5s raiyun }
ping "100.67.115.10" timed out / no reply   （6 次全部失败）

PS> 1..4 | ForEach-Object { tailscale ping -c 1 --timeout 5s hk-server }
pong from hk-server (100.125.224.24) via 14.1.99.5:41641 in 222ms   （4 次全部成功）
```

判定：**宿主机 Tailscale 网络正常（能到 hk-server），病灶在 raiyun 侧，不是宿主机单机代理污染。**

### 6.2 raiyun tailscaled 实时故障（journalctl，现在进行时）

到 home 902（13:45–13:46，每约 10 秒一次）：

```
derphttp.Client.Recv: connecting to derp-902 (derp-cn-raiyun1)
magicsock: derp.Recv(derp-902): derphttp.Client.Recv connect to region 902 (derp-cn-raiyun1): EOF
```

到备用 900（13:29，持续）：

```
magicsock: derp.Send ... region 900 (derp-hk): GET failed: <nil>: <html>
derphttp: CONNECT dial to derp.xinlly.top:443: 200 Connection established
```

tailscaled 的 TCP 连接全部指向 mihomo（`ss -tnp`，pid 20368）：

```
ESTAB 127.0.0.1:34628 → 127.0.0.1:35353   (共 4 条，均到 mihomo)
```

### 6.3 mihomo 分流错误实锤

mihomo 实时连接 API（`http://127.0.0.1:9090/connections`）：

```
"host":"derp.xinlly.top"  "destinationIP":"14.1.99.5"
"chains":["专线-加拿大-A","libcyber-自动","SELECT"]     ← 国内 DERP 被绕到加拿大代理
```

mihomo 规则尾部（`/opt/mihomo/config.yaml`）：

```
- RULE-SET,direct-china-domain,DIRECT
- RULE-SET,direct-china-ip,DIRECT
- GEOIP,CN,DIRECT
- MATCH,SELECT        ← 自定义私有域名不在 geosite CN；若 mmdb 未判 CN，则落入机场代理
```

自定义域名 `derp.cn.xinlly.top` 不属于公共 geosite CN；是否命中 `GEOIP,CN` 取决于 6 月 28 日的 mmdb 对 103.40.13.68 的判定，存在落到 `MATCH,SELECT` 被代理的风险。

### 6.4 对照实验：普通长连接不被切，但 DERP 协议流被 EOF

| 实验（raiyun） | 路径 | 结果 |
|---|---|---|
| TLS 长连 25s | 直连公网 103.40.13.68:52443（hairpin） | **满 25s 存活** |
| TLS 长连 30s | 经 mihomo CONNECT 到 902 | **满 30s 存活** |
| DERP 协议 Recv | tailscaled 经 mihomo 到 902 | **约每 10s EOF** |

判定：**EOF 不是简单的 hairpin/代理空闲超时（普通空闲长连 25–30s 都不断），而是 tailscaled 的 DERP 协议流经 mihomo（且 900 确定被绕到加拿大出口）这一特定路径上被中断。** 境外机场出口对"回国 + 长连接/二进制 DERP 流"不稳定或主动重置，与 900 的 `<html>`、902 的 ~10s EOF 相符。

### 6.5 redirect-cnzz 时间线

14 天 `journalctl -u tailscaled` 中仅 1 条：

```
Oct 08 17:04:50 raiyun tailscaled[20368]: health(warnable=tls-connection-failed):
  error: ... encrypted connection with '"derp.cn.xinlly.top"': likely intercepted
  connection; certificate is self-signed by O=redirect-cnzz
```

判定：**瞬态、单次、当前不可复现；Health 告警粘滞。** 与代理绕出路径上的重定向/门户相关，但当前三处证书均真实。

---

## 七、因果链汇总

```
tailscaled 强制走 mihomo(35353)                    [derper.nix:21-25]
        + mihomo 对自定义 DERP 域名缺显式直连规则 → 部分/全部落入 MATCH,SELECT 机场代理
        ├─ 900 derp.xinlly.top → 加拿大出口 → 收到 <html>/frp 页  → GET failed
        ├─ 902 derp.cn DERP 协议流经代理 → 约 10s EOF，无法保持会话
        └─ raiyun 在任何 DERP 上都无稳定会话，直连打洞亦未建立
              → 外部节点数据包投递不到 raiyun → tailscale ping raiyun 全部超时
（Oct 8 某次绕出还返回过 O=redirect-cnzz 自签证书，瞬态，告警粘滞至今）
```

[OWNER] 旁证：raiyun2 的 tailscaled 代理配置与 raiyun 完全相同（`hosts/raiyun2/derper.nix:21-25`），xavier 已观察到 raiyun2 存在同样故障——符合"强制 tailscaled 走 mihomo 且 DERP 分流错误"这一同类根因。本结论不以 raiyun2 为判定依据，但建议修复时同类一并处理。

---

## 八、排除项

- 非 DNS 劫持/记录被改：权威 + 多公共解析 + DoH + 本机全层一致（第三节）。
- 非证书过期：有效期至 2026-11-23，落盘证书 09-25 新鲜（第四、五节）。
- 非 DERP 服务器宕机：902 正在为 9 个 peer 中继（第五节）。
- 非宿主机侧代理污染：宿主机出物理网卡、ChainErr=None，且能 ping 通 hk-server（第四、六节）。
- 非当前持续 MITM：三处当前证书均真实 LE，redirect-cnzz 14 天仅 1 次。
- ACL 可能性低：raiyun 在 tailscale 网络中在线；ACL 不会产生 DERP 自签证书/EOF 现象（未完全排除，但证据不支持）。

---

## 九、最小修复方案（仅列步骤，未执行；待批准）

核心思路：**让 raiyun 的 DERP 流量直连，不再经 mihomo 绕出。** 建议两处同时改（一处在仓库 Nix，一处在 mihomo 手动配置）。

**步骤 1｜仓库 `hosts/raiyun/derper.nix:21-25`：给 tailscaled 的 DERP 目标放行代理**
- 首选（需拍板）：若 Tailscale 控制面在 raiyun 可直连，直接删除该 `Environment` 代理覆盖（最简单）。
- 稳妥：保留控制面代理，新增
  `NO_PROXY=derp.cn.xinlly.top,derp.xinlly.top,103.40.13.68,14.1.99.5`（同时给小写 `no_proxy`），使 DERP 直连、控制面仍走代理。

**步骤 2｜mihomo `/opt/mihomo/config.yaml`（手动维护文件，非 Nix 生成）：在 rules 顶部加显式直连**
- `- DOMAIN-SUFFIX,xinlly.top,DIRECT`（或至少 `DOMAIN,derp.cn.xinlly.top,DIRECT` 与 `DOMAIN,derp.xinlly.top,DIRECT`），置于所有 RULE-SET/MATCH 之前。

**步骤 3｜应用（改变态，须批准）**
- 改完 Nix 后经正规流程同步 + `nixos-rebuild switch`（交 NixOS 协调者执行）；mihomo 侧 reload 其服务。
- 即会重启/重载 tailscaled 与 mihomo。

**步骤 4｜验收（只读）**
- raiyun：`tailscale netcheck` 期望 derp-hk / 其他区域延迟不再为空；`journalctl -u tailscaled -f` 期望不再出现 902 EOF / 900 `<html>`。
- 宿主机 PowerShell：`tailscale ping raiyun` 期望 `pong`（先 DERP 后直连）。
- 三项全过才算恢复。

**残留风险**：若 DERP 直连（hairpin）后 902 仍 EOF，则根因偏向"节点连自身所在 DERP 区域"的自环问题；下一步再议（如让 tailscaled 以本地方式触达 home derper，或升级/调整 DERP 自处理；Tailscale 1.98.5 已较新）。当前证据（hairpin 25–30s 稳定、9 节点正常中继）支持直连即可恢复，置信度中高，待步骤 4 实测钉死。

---

## 十、回滚思路

- `derper.nix` 改回原 `Environment`（或移除 NO_PROXY 行）；mihomo `config.yaml` 删除新增直连规则；重新 switch / reload 即恢复现状。
- 不涉及数据库、磁盘、密钥变更，无持久化数据风险。建议改动前备份这两个文件。

---

## 十一、需 xavier 拍板的点

1. raiyun 的 Tailscale **控制面是否可直连**：可 → 直接删 tailscaled 代理（最简）；不可 → 用 NO_PROXY 只放行 DERP。
2. 是否批准修改 mihomo 手动配置（`/opt/mihomo/config.yaml`，不在仓库内）并 reload。
3. 是否批准 tailscaled/mihomo 的重启与 `nixos-rebuild switch`。
4. 备用区域 **900 derp-hk 自身已坏**（hk 443 由 frp 应答而非 derper）属 hk 侧独立问题，是否另立任务修复。
5. 是否对 raiyun2 同类配置一并修复（同根因）。

---

## 十二、[UNCERTAIN] 项

1. **`O=redirect-cnzz` 自签证书的精确来源**：瞬态单次、不可复现；推测为代理绕出路径上的重定向/门户设备，未钉死是 mihomo 上游机场出口、宿主链路还是对端门户。
2. **mihomo 当前把 `derp.cn.xinlly.top` 判为 DIRECT 还是代理**：14 秒内 7 次 connections API 采样均为 0（连接极短，未抓到）；900 已确定被代理，902 未直接观测到。
3. **直连/hairpin 是否 100% 恢复 902 自 DERP 会话**：需修复后实测确认（当前置信度中高）。
4. **900 在 hk 侧的服务端根因未上机核查**（hk SSH 书签当次连接失败）；仅从外部确认 14.1.99.5:443 = frp 而非 derper。

---

## 附：本次实际运行的主要命令

- raiyun：`tailscale debug derp-map`、`tailscale netcheck`、`tailscale status` / `status --json`、`ss -tlnp/-ulnp/-tnp`、`systemctl is-active`、`journalctl -u tailscaled`、`curl --noproxy/-x`、openssl（nix store）、mihomo `:9090/configs` 与 `:9090/connections`。
- 宿主机（Electerm PowerShell）：`Get-NetAdapter`、`Find-NetRoute`、`Get-ItemProperty WinINET`、`netsh winhttp show proxy`、`Resolve-DnsName`、`.NET TcpClient+SslStream` 取证书、`tailscale ping`（raiyun / hk-server）、`curl.exe latency-check`。
- WSL：`host`、`getent`、DoH（223.5.5.5 / doh.pub）、`openssl s_client :52443`。

全程未读取或打印任何密钥/口令/令牌；仅核对证书与投递文件的存在、时间戳与元数据。

---

## 附录：修复结果（2026-10-11）

- **raiyun（902）**：`hosts/raiyun/derper.nix` 给 tailscaled 加 `NO_PROXY=xinlly.top,.xinlly.top,127.0.0.1,localhost` 后 `nixos-rebuild switch`；宿主机 `tailscale ping raiyun` 稳定 pong via DERP(derp-cn-raiyun1) 37–51ms。根因确为 tailscaled 经 mihomo 代理连本机 home DERP 时 Recv 被 EOF，而非 902 自环。
- **raiyun2（901）**：同加 NO_PROXY，并在 `/opt/mihomo/config.yaml` rules 顶部加 `DOMAIN-SUFFIX,xinlly.top,DIRECT`（仓库外，热重载 204）。但 901 仍报 `certificate is not valid for any names` —— 该节点原用 **sha256-raw 自签 IP 证书（-certmode manual, hostname=IP，公网 58010→8010）**，Tailscale 1.98.5 客户端对 raw-point 校验不过（钉值三处一致仍拒）。
- **901 最终方案（与 raiyun 同模式）**：放弃自签 IP，改 derper 明文 :8010 + nginx 用 hk 分发的 Let's Encrypt 证书（SAN `*.ry.xinlly.top`）在 443 终结反代，公网 52443→443；控制台节点改为 `HostName=derp.ry.xinlly.top`、**删除 CertName 与 IPv4**、DERPPort=52443、STUNPort=53478。`switch` EXIT_0，`tailscale debug derp 901` = Successfully established a DERP connection（无 warning/error），宿主机 `tailscale ping raiyun2` pong via DERP(derp-cn-raiyun2)。
- 教训：自签 IP 证书的 raw-point 钉值以 derper 启动日志自报为准，勿用 openssl 手算（本报告期间曾得出错误中间值 bf55，已废弃；权威值为 derper 自报，但最终通过改用域名 LE 证书彻底绕开该路径）。
