# NixOS 配置状态只读核查报告

- 核查时间：2026-09-27
- 执行环境：WSL 本机 NixOS（hostname=`nixos`，当前身份 uid=998 `hermes`）
- 核查方式：全程只读取证；未执行 nixos-rebuild / switch / 重启 / sudo / chown / commit / push
- 核查人：Dora（协调者）

> 说明：本机为 WSL 控制端（跑 paseo、mihomo）；配置仓库同时管理远端主机 raiyun2（DERP）等。报告区分「本机运行系统」与「远端 raiyun2 在途事项」。

---

## 一、配置仓库状态

仓库：`/var/lib/hermes/workspace/projects/our/nixos`

### 1.1 分支与 HEAD
- 分支：`develop`
- HEAD：`dc339e19f2cc572494791b2980294433300677eb`
  - 作者/时间：Dora，2026-09-27 06:04:44 +0800
  - message：`paseo: restore mcp/browserTools/skills/appendSystemPrompt settings`
- 实据：`git rev-parse --abbrev-ref HEAD`；`git log -1`

### 1.2 与 origin/develop 的差异
- `git rev-list --left-right --count origin/develop...HEAD` → `0  1`
- 含义：本地 develop **领先 origin 1 个 commit、落后 0**
- 未推送 commit：
  - `dc339e1 paseo: restore mcp/browserTools/skills/appendSystemPrompt settings`
- origin/develop 当前顶点：`5cb8040`（`hosts/raiyun2: DERP domain -> derp.ry.xinlly.top`，2026-09-26）

### 1.3 工作区未提交/未跟踪改动（逐项标注）

| 状态 | 路径 | 是什么 | 性质 |
|---|---|---|---|
| `M` | `hosts/raiyun2/derper.nix` | +21/-6，见下 | 在途功能改动（DERP 直连 TLS / HSTS / 域名 cn→ry） |
| `??` | `docs/` | 含 `docs/diag/paseo-mcp-injection.md`（24K）及本报告 | 诊断文档，未跟踪 |
| `??` | `.playwright-mcp/` | Playwright MCP 运行产物（72K） | 工具产物，疑似应入 `.gitignore` 而非提交 |

实据：`git status --porcelain`；`du -sh .playwright-mcp docs`

#### `hosts/raiyun2/derper.nix` diff 明细（+21/-6）
1. 防火墙放行新增 TCP 8010：`allowedTCPPorts = [ 443 ]` → `[ 443 8010 ]`；
2. 覆盖 `tailscale-derper` ExecStart（`lib.mkForce`）：
   - 新增 `-certmode manual -certdir /var/lib/derper -http-port=-1`，`-hostname=183.66.27.22`；
   - 注释意图：derper 在 8010 直跑 TLS（自签 IP 证书、不发 SNI），经 NAT 58010→8010 直连；`-http-port=-1` 关闭默认 80 明文监听（DynamicUser 无 CAP_NET_BIND_SERVICE）；
3. nginx 新增全局 HSTS（`commonHttpConfig`，`max-age=31536000; includeSubDomains`）；
4. vhost 域名修正 `cn` → `ry` 三处：`mihomo` / `test` / `treehole`（测试页正文同步改 ry）。

实据：`git diff hosts/raiyun2/derper.nix`

### 1.4 哪些已评审待提交 / 哪些在途
- `dc339e1`（modules/paseo.nix 四项恢复）：**已经完整评审链（planner→reviewer→Gate）并提交**，仅差 push。
- `hosts/raiyun2/derper.nix` 工作区改动：**在途**，已在 raiyun2 做 `nixos-rebuild test` 验证，但未经正式评审、未提交。
- `docs/`：在途文档，未跟踪、未评审。

---

## 二、运行系统状态

### 2.1 版本与 generation
- `nixos-version`：`26.11.20260616.567a49d (Zokor)`
- `/run/current-system` → `/nix/store/knws1mjv2qas7s50n56di3ly4k59slw9-nixos-system-nixos-26.11.20260916.567a49d`
- `/run/booted-system` → `/nix/store/rw8lgxvyysi9pb981v8a403dwimgrfp9-nixos-system-nixos-26.11.20260616.567a49d`
- `/nix/var/nix/profiles/system` → 同 current（`knws1…`）
- **关键判断：current(`knws1`) ≠ booted(`rw8l`) → 本机处于 `nixos-rebuild test` 已激活但未 `switch` 持久化的状态；一旦重启，回退到 booted 代 `rw8l`。**
- 实据：`readlink -f` 三条 profile/symlink
- 注：`nix-env --list-generations` 需对 system profile 加锁，hermes 身份 `Permission denied`，故未列全代（[UNCERTAIN] 完整代列表，但 current/booted 指向已足够判定 test 未 switch）。

### 2.2 关键服务状态（本机实际）
| 服务 | is-active |
|---|---|
| paseo | active |
| mihomo | active |
| tailscaled | inactive（本机不跑，在远端） |
| nginx | inactive（本机不跑，在远端） |
| tailscale-derper | inactive（在远端 raiyun2） |
| hindsight | inactive（本机不跑） |
| docker | inactive |

实据：`systemctl is-active …`

### 2.3 `~/.paseo/config.json` 运行态四项
文件：`/var/lib/hermes/.paseo/config.json`（mode 0600，属 hermes）

| 字段 | 现值 |
|---|---|
| `daemon.mcp.injectIntoAgents` | **true** |
| `daemon.browserTools.enabled` | **true** |
| `daemon.appendSystemPrompt` | **存在，长度 558**（含身份红线，非空） |
| `agents.skills.selection.mode` | **`all`** |

实据：`jq -r`；appendSystemPrompt 用 `length` 取值（不打印正文以免无关展开）
结论：dc339e1 对应的四项设置在**运行态已实际生效**。

### 2.4 git objects 属主阻断
- `.git/objects/bb/`：目录及对象（`441c…`、`948d…`）均属 `hermes:hermes`；
- `.git/objects/18/`：对象 `8661…` 属 `hermes:hermes`；
- `git fsck --connectivity-only` → 无错误，**rc=0**。
- 结论：此前「objects 属主阻断 commit」的问题**已消除**，git 对象可正常访问（已被 dc339e1 成功提交印证）。

---

## 三、远端 raiyun2 DERP 在途事项（本次相关，纳入未闭环）

来自 worker（d1e5955）双端定位，证据落 `workspace/temp/host-derp-raiyun2/diagnosis.md`（15753B），协调者已核对其结论文本：

- **TCP/TLS 中继链路正常**：`tailscale debug derp 901` 返回 `Successfully established a DERP connection with node "183.66.27.22"`（经 NAT 58010→8010）。
- **STUN 不响应**：
  - 外部标准 RFC5389 STUN 打 `183.66.27.22:53478` 多次 SILENCE；同刻 Google/Cloudflare STUN 正常 → 外部 UDP 出口正常；
  - worker 进一步报告：在 raiyun2 **本机回环**（127.0.0.1 / ::1 / 内网IP）直接打 3478，derper 亦不回包（socket bind 在、日志写 listening，但 handler 不应答）；
  - worker 判定主要矛盾偏向 **derper 本地 STUN handler 失效（B）**，而非雨云 NAT（A）；建议重启 `tailscale-derper` 后先在本机验证回环出包，再分离 NAT 因素。
- 协调者保留意见：worker 回环测试方法的可靠性（bash `/dev/udp`/nc 类探针）协调者未在主会话内独立复跑，**「derper handler 死」这一具体归因标注 [UNCERTAIN]**；但「外部 STUN 无应答、netcheck 901 恒空、节点未被调度」是多方实测一致的确证。
- 雨云线路属性（用户截图）：重庆电信 / 低价 NAT / 20G 防御，「NAT 模式下封海外」「建站请勿使用 NAT」——故不走建站/工单路线。

---

## 四、未闭环项清单（阻塞原因 + 责任方 + 待执行命令）

| # | 未闭环项 | 现状/阻塞 | 责任方 | 需要做什么 |
|---|---|---|---|---|
| 1 | dc339e1 未推送 | 本地领先 origin 1；按惯例 push 需指令 | xavier 下令 → Dora 执行 | push：`git push origin develop`（用 .env token + 代理35353） |
| 2 | raiyun2/derper.nix 工作区改动未提交 | +21/-6 在途，仅 test 验证、未评审 | xavier 定评审/提交 | 走评审链后提交；或 xavier 明确直接提交 |
| 3 | 本机 test 未 switch | current(`knws1`)≠booted(`rw8l`)，重启回退 | xavier 授权 | 确认无观察问题后 `nixos-rebuild switch`（CRITICAL，需明确批准） |
| 4 | raiyun2 STUN 不响应、901 不被调度 | 外部 STUN 确证无应答；handler 根因 [UNCERTAIN] | xavier 授权变更 → worker 执行 | 先重启 `tailscale-derper`，本机验 `127.0.0.1:3478` 出包，再外部验 53478 |
| 5 | raiyun2 derper 改动仅 test 未持久化 | 远端同样重启回退 | 随 #4/正式部署 | 远端验证稳定后 `nixos-rebuild switch` |
| 6 | docs/ 未跟踪 | paseo-mcp-injection.md + 本报告 | xavier/Dora | 确认纳入版本控制后 `git add` 提交 |
| 7 | .playwright-mcp/ 未跟踪 | 工具运行产物（72K） | Dora 建议 | 加入 `.gitignore`（需 xavier 同意，属变更） |

---

## 五、一句话结论

**当前 NixOS 配置总体可控、git 属主阻断已清除、paseo 四项运行态已生效；最大遗留是「1 个已评审 commit（dc339e1）未 push」+「本机与 raiyun2 均处于 test 未 switch」+「raiyun2 STUN 不响应导致 901 中继实际未被调度」三处未闭环，且关键持久化/推送动作都在等 xavier 指令。**
