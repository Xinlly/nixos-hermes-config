# 规划/现状：manager profile + xavier-mesh 接入（feat/manager-profile）

- 文档定位：**现状记录 + 应用预案**（代码已落仓；本文的应用预案均未执行。历史上 3b855c2 曾以 `nixos-rebuild test` 落位 manager profile，但 1361f98/ac3c19e 的最终态从未激活，详见 1.3 运行态时间线）
- 日期：2026-10-30
- 所属：nixos-hermes-config 仓库，WSL 主机（flake attr `nixos`）
- 分支：`feat/manager-profile`
- 状态：声明源代码已在三个提交中落地；按 xavier 冻结令，**当前禁止一切非 dry-activate 的激活与服务重启**，应用计划见第 7 节（均为待执行预案）。

---

## 0. 结论速览（TL;DR）

1. **Hermes 管理者 profile**：default 声明源已禁用 `hermes-lark-streaming`；新增 `manager` profile 的声明式落位模块（仅一个幂等 activation script，不新增 systemd 服务）。
2. **Paseo 新 provider**：新增并列 provider `hermes-manager`（`hermes --profile manager acp`），存量 `hermes` provider 逐字未动；daemon 无配置文件热监听，**须重启 `paseo.service` 才生效**。paseo 于 10-30 23:49 有一次重启（原因 [UNVERIFIED]），但其加载的 active generation 不含 hermes-manager，该 provider 至今未生效；使其生效的重启仍待解冻窗口（见 1.3）。
3. **EasyTier WSL**：从旧 `xinlly-mesh` 切到 `xavier-mesh`，DHCP 动态取址（无静态 IPv4），纯客户端零监听，唯一对端 peer 改为 `tcp://cn.xinlly.top:17017`；`easytier-wsl` 自 10-30 02:11:52（MainPID 800784）未再重启，仍加载旧 toml（xinlly-mesh / 静态 10.144.144.20 / 旧 peer），xavier-mesh+DHCP+cn:17017 从未激活（见 1.3）。
4. **两个未决项（[UNCERTAIN]）**：入网 secret 是否匹配 xavier-mesh、对端是否确为 xavier-mesh 节点——均须应用连接后才能证实，见第 8 节。

---

## 1. 背景与范围

### 1.1 本分支涉及的提交（均已入库，本文只引用不改写）

| 提交 | 主题 | 改动文件 |
|---|---|---|
| `422b421`（父提交） | raiyun 部署 EasyTier 公共节点，独立网络 **xavier-mesh，虚拟 IP 10.122.122.1** | `hosts/raiyun/easytier.nix`、`hosts/raiyun/default.nix` |
| `3b855c2` | manager profile activation + default 声明源禁用 hermes-lark-streaming | `modules/hermes/hermes-plugins.nix`、`modules/hermes/manager-profile.nix`（新增）、`hosts/wsl/hermes.nix` |
| `1361f98` | WSL 以 DHCP 加入 xavier-mesh + 新增 hermes-manager provider | `hosts/wsl/easytier.nix`、`modules/paseo.nix` |
| `ac3c19e` | WSL xavier-mesh 的 peer 指向 `cn.xinlly.top:17017` | `hosts/wsl/easytier.nix` |

### 1.2 范围边界

- 本文只记录**声明源现状**与**待执行的应用/回滚预案**。须区分两层：**历史中间态**——3b855c2 曾以 `nixos-rebuild test` 激活并落位 manager profile（见 1.3）；**最终态**——1361f98/ac3c19e 的完整改动（xavier-mesh+DHCP+cn:17017、hermes-manager provider）从未 test/switch/boot 激活，`easytier-wsl` 也未按新配置重启。本文不再使用「未跑任何 test / 未做任何 restart」这类与时间线矛盾的全称否定。
- 不回显任何密钥/token；secret 只述键名是否存在。
- 不写公网 IP；对端只用域名 `cn.xinlly.top` / `ry.xinlly.top` 指代。

### 1.3 运行态时间线（历史中间态 vs 最终态）

区分「曾经激活到哪一步」与「声明源最终态是否生效」，两者不得混淆。以下均为只读命令取证。

**(1) 历史中间态：3b855c2 曾以 `nixos-rebuild test` 激活（rc0）**

- 证据：`~/.hermes/profiles/manager/` 已实际落位——`config.yaml`、`SOUL.md` 的 mtime 均为 2026-10-30 02:11:51，config.yaml mode 0660、4919 字节；`.env` / `.env.secrets` / `skills` 为 root 属主软链；该 config.yaml 中 `plugins.disabled=[hermes-knowledge-curator, hermes-lark-streaming]`、`enabled=[matt-workflows]`，正是 3b855c2 activationScript 的产物。
- 佐证是 test 而非 switch/boot：`/run/current-system` 指向 store `0mykgwvc…`，`/run/booted-system` 指向 store `mm97fi2w…`，两者不同（test 只改 current、不改 boot 默认 generation）。
- activationScript 设计为幂等，将来重复激活无害。

**(2) 10-30 晚 hermes-agent / paseo 各有一次重启（原因 [UNVERIFIED]）**

- 时间戳（`systemctl show`）：hermes-agent MainPID 2437445、ActiveEnter 2026-10-30 23:40:33；paseo MainPID 2437476、ActiveEnter 2026-10-30 23:49:55。
- hermes 用户无 journal 读取权限，重启触发原因查不到 → 标 **[UNVERIFIED]**，只陈述时间戳事实，不臆断。
- 与本分支 provider 功能无关：active generation（current=`0mykgwvc…`）的 paseo 渲染件不含 hermes-manager；live `~/.paseo/config.json` `grep -c hermes-manager` = 0（rc1，mtime 2026-10-30 23:49:54）。即晚间重启并未、也无法使 1361f98 的新 provider 生效。

**(3) 最终态（1361f98 / ac3c19e）从未激活**

- 三个 store 互不相同：worktree 最终态构建目标 `sazrz5s4…` ≠ current `0mykgwvc…` ≠ booted `mm97fi2w…`。
- `easytier-wsl` MainPID 800784、ActiveEnter 2026-10-30 02:11:52 至今未变，进程仍 `-c /nix/store/j2743pb…-easytier-wsl.toml`（内容为 xinlly-mesh / dhcp=false / 静态 10.144.144.20 / 旧 peer ry.xinlly.top:51010）。
- 故 network_name=xavier-mesh、dhcp=true、peer=cn.xinlly.top:17017、hermes-manager provider 这一完整最终态，尚未进入运行态。

---

## 2. Hermes manager profile（提交 3b855c2）

### 2.1 default 声明源禁用 hermes-lark-streaming

文件 `modules/hermes/hermes-plugins.nix`：

- `settings.plugins.enabled` 现仅含 `"matt-workflows"`（:33-35）——`"hermes-lark-streaming"` 已从启用集移除。
- `settings.plugins.disabled` 含 `"hermes-knowledge-curator"` 与 `"hermes-lark-streaming"`（:43-46）。disabled 恒优先，双保险。
- **禁装≠不加载**：`extraPlugins`（:27-30，两个 `runCommand` 包：lark-streaming-aowen、matt-workflows）与上游 activation 建 `nix-managed-*` 软链的机制**全部保留**，插件包仍安装、软链仍在，便于未来恢复。恢复方式（注释 :39）：把该名从 disabled 移除并加回 enabled。
- 已知接受后果：gateway 重启后飞书流式卡片不再加载；其替代安排由管理者窗口另排，不属本分支。

### 2.2 新增 manager profile 落位模块

文件 `modules/hermes/manager-profile.nix`（88 行，新增）。只注册一个 `system.activationScripts.hermes-manager-profile`，`deps = [ "hermes-agent-setup" ]`（对齐上游同名 activation 脚本），**不新增任何 systemd 服务、无 restart trigger**。落位根目录 `~/.hermes/profiles/manager`（即 `/var/lib/hermes/.hermes/profiles/manager`），脚本幂等：

- **(a) config.yaml**（:21-30、:51）：由 `config.services.hermes-agent.settings` 经 `lib.recursiveUpdate` 深拷贝渲染（`builtins.toJSON`，与上游 `hermes-config.yaml` 同款），唯一覆盖是 `plugins.disabled` 在基准值上追加 `"hermes-lark-streaming"` 并 `lib.unique` 去重；每次激活以声明源覆盖回写，权限 0660。
- **(b) skills / plugins 只读软链**：`skills` 整目录软链到 default（:64）；`plugins` 先建目录，再对 `extraPlugins` 逐条建 `nix-managed-<lib.getName>` 软链（:69-79，含 plugin.yaml 校验、死链清理、`chown -h`，与上游规则逐字对齐）；default 中 extraPlugins 之外的实体插件目录（如 `hermes-achievements`）以只读软链一并对齐（:83-85），不收编、不重构。
- **(c) .env / .env.secrets**（:55-56）：仅 `ln -sfn` 软链到 default 同名仓外文件，**密钥内容绝不进 nix store / git**。
- **(d) 全新空数据目录**（:46-48）：`memories sessions state logs cron plans workspace home` 全部 `install -d -m 2770 hermes:hermes`，不克隆、不迁移任何历史；不预建 MEMORY.md 等文件（首写时自建）。
- **(e) SOUL.md**（:59-61）：仅当目标不存在时从 default 拷贝实体文件（0640），已存在则绝不覆盖，保留未来个性化空间。

引入点：`hosts/wsl/hermes.nix:11` 在 `hermes-plugins.nix` 之后 import 该模块；仅 WSL 变体引入，云主机变体不受影响。

---

## 3. Paseo 新增并列 provider hermes-manager（提交 1361f98）

文件 `modules/paseo.nix`，在存量 `providers.hermes`（:60-68）之下新增**并列** key `providers."hermes-manager"`（:73-85）：

- `extends = "acp"`（:74）；
- `label = "哆啦（管理者）"`（:75），中文 description 写明管理者专用、该 profile 已禁 lark-streaming（:76）；
- `command = [ "/run/current-system/sw/bin/hermes" "--profile" "manager" "acp" ]`（:77-83，argv 数组）；
- `env.HOME = "/var/lib/hermes"`（:84），与存量 hermes provider 同样的最小注入，不臆造其他 env。

**存量 `providers.hermes` 逐字未动**（command 仍为 `hermes acp`、label「哆啦」、env HOME 一致）。

### 3.1 生效路径（无热加载，须重启）

- Paseo nix module 把 `settings` 以 `pkgs.formats.json` 渲染成 `paseo-config.json`，并在 `paseo.service` 的 **preStart** 里 `install -m 0600 <store config> ~/.paseo/config.json`——即配置只在**服务启动时**落盘覆盖。
- daemon 启动时一次性读入 config（配置存储在启动期加载）；**对 `~/.paseo/config.json` 没有文件监听式热加载**。因此要让 `hermes-manager` 进入 live 配置，路径只有：
  1. **重启 `paseo.service`**（preStart 重写 config + daemon 重读）；或
  2. 手动把渲染 config 落盘后，显式发起一次 `reloadConfig` RPC（本阶段冻结，不采用）。
- 内置 `claude`/`codex`/`copilot`/`opencode`/`pi` 等 provider 由 daemon 代码注入、不在声明 config 内，**重启不会丢失**。
- daemon 于 10-30 23:49 有一次重启（原因 [UNVERIFIED]，见 1.3）；但 live `~/.paseo/config.json` 至今不含 hermes-manager（`grep -c`=0），本分支的 provider 改动未生效。

---

## 4. EasyTier WSL 最终态（提交 1361f98 + ac3c19e）

文件 `hosts/wsl/easytier.nix`，`services.easytier.instances.wsl.settings` 最终态（已经 `nix eval --json` 复核，rc=0）：

| 字段 | 最终值 | 说明 |
|---|---|---|
| `network_name` | `"xavier-mesh"` | 网络隔离/身份键 |
| `dhcp` | `true` | 动态分配虚拟网 IPv4 |
| `ipv4` | `null`（toml 中无该键） | 不写死任何静态地址 |
| `listeners` | `[]` | **纯客户端，本机零监听** |
| `peers` | `[ "tcp://cn.xinlly.top:17017" ]` | **唯一**对端，替换而非并列旧值 |
| `hostname` | `"nixos-wsl"` | 不变 |
| `network_secret` | `null`（toml 无该键） | 密钥走 EnvironmentFile，不入 store |

- 实例级 `environmentFiles = [ "/var/lib/hermes/.easytier/client.env" ]` 保持不变。
- **端口语义**（据 nixpkgs easytier 模块 option 定义）：`listeners` 为本机监听地址（显式 `[]` 即不监听）；`peers` 为初始连接的对端。故 **17017 是对端公网目的端口，只出现在 peer URL 中**；本机没有、也不得添加 17017 监听。模块不暴露 `rpc_port`/portal 等管理端口 option（仅有 `extraSettings`/`extraArgs` 逃生口，本配置未用），故无任何 RPC/管理端口字段；未新增防火墙规则。
- **对端 NAT 事实**（见 `422b421` commit body）：雨云控制台 DNAT **公网 17017 → raiyun 内网 11010（TCP，规则 ID 273001）**；raiyun 侧 `listeners = tcp://0.0.0.0:11010`、xavier-mesh 虚拟 IP 10.122.122.1。
- 旧 peer `tcp://ry.xinlly.top:51010` 已被整体替换，生成配置中不得、也确实不再出现该域名或 51010。

---

## 5. xavier 已拍板决策（明确记为「决策」）

1. **虚拟 IP 维持 `dhcp=true`，不改静态。**
   - 依据 `easytier-core --help` 的 `-d/--dhcp` 文案：地址由 EasyTier 自动确定，**默认从 10.0.0.1 起分配（10.0.0.0/24），遇 IP 冲突自动更换**。
   - 因此 DHCP **不保证**节点落在 xavier-mesh relay 所在的 10.122.122.0/24，也不会保留旧静态地址 10.144.144.20；实际分到的地址待应用后观测（见第 8 节）。
2. **`client.env` 维持现状，不代填、不回显。**
   - 仅记录事实：`/var/lib/hermes/.easytier/client.env` 中**键名 `ET_NETWORK_SECRET` 已配置（键存在）**；该密钥是否匹配 xavier-mesh 公共节点**未验证**（见第 8 节 [UNCERTAIN]）。严禁在仓库/store 中写入其值。

---

## 6. 风险

1. **入网/认证失败的第一嫌疑＝secret 仍属旧 xinlly-mesh。** 现 `client.env` 历史上服务于 xinlly-mesh；若其 `ET_NETWORK_SECRET` 与 raiyun xavier-mesh 节点的密钥不一致，重启 `easytier-wsl` 后将无法通过网络校验、入不了网。不重启就无法在真实链路上验证，这是当前最大未决风险。
2. **对端身份 [UNCERTAIN]。** `cn.xinlly.top` 与旧 `ry.xinlly.top` 经 DNS 解析为**不同主机**（本文按禁令不写公网 IP）；而 `AGENT.md` 载明 raiyun/raiyun2「公网地址/端口不入库」，故无法用仓内证据 100% 反查 `cn.xinlly.top` 即 422b421 的那台 raiyun。端口 17017 与 commit 记载的 NAT 规则精确吻合，但其对端网络名是否确为 xavier-mesh，须应用连接后才能分晓。
3. **DHCP 地址不确定。** 自动分配可能落在 10.0.0.0/24 而非 10.122.122.0/24；若后续有「必须同 /24」的连通诉求，需回头评估静态方案（第 7 节回滚/备选）。
4. **重启 paseo 会扰动在跑 ACP。** daemon 重启会影响其托管的 agent 会话，必须选空闲窗口。

---

## 7. 应用计划与回滚（ac3c19e 最终态的待执行预案，当前冻结）

> 以下为 ac3c19e 最终态的应用预案，均待解冻；历史 test 与 10-30 晚重启见第 1.3 节时间线，二者不得混淆——那些历史动作并未使最终态生效。每项附回滚，待 xavier 另行通知解冻后由有权角色执行。

### 预案 ① 重启 `easytier-wsl.service`（应用 xavier-mesh + DHCP + cn:17017）

- 待执行动作：在新 generation 激活后重启该服务，使其加载新渲染 toml（network_name=xavier-mesh、dhcp=true、peer=cn.xinlly.top:17017）。
- 验证（待执行）：`systemctl is-active easytier-wsl`、查看 TUN 虚拟 IP（DHCP 实分地址）、`ping 10.122.122.1` 验证到 xavier-mesh relay 的连通、查看 peers 状态确认入网。
- 回滚：回到 422b421 时的旧声明（network_name=xinlly-mesh、静态 ipv4=10.144.144.20、旧 peer=ry.xinlly.top:51010）重新构建并激活；或直接 `systemctl stop easytier-wsl.service` 停用该服务。

### 预案 ② 重启 `paseo.service`（使 hermes-manager 进入 live config）

- 待执行动作：重启服务，由 preStart 把含 `hermes-manager` 的渲染 config 安装到 `~/.paseo/config.json` 并由 daemon 重读。
- 影响：重启会扰动 daemon 托管的在跑 ACP agent，**须选空闲窗口**。
- 验证（待执行）：重启后只读列出 providers，确认 `hermes` 与 `hermes-manager` 并存、存量 hermes 配置不变。
- 回滚：重启即由 preStart 按当时（或回滚 generation 后的旧）渲染 config 重写；或先还原 `~/.paseo/config.json` 的备份再重启。

### 预案 ③ NixOS `nixos-rebuild test/switch/boot`

- 状态：**待 xavier 另行通知，当前冻结**。
- 待执行差异：`test` 立即激活但不改 boot 默认（重启即退）；`switch` 激活并设为 boot 默认；`boot` 仅设下次启动。
- 回滚：`nixos-rebuild switch --rollback`，或切回旧 generation（`--profile /nix/var/nix/profiles/system` 指定），或在 boot 菜单选择旧的 booted system。

### 附：dry-activate 只读预演（已观察事实，非已激活）

- 由有权角色以 `dry-activate` 做过只读预演，**DRY_RC=0**。
- 预演预测：真正激活时会 **stop/start `easytier-wsl.service` 与 `paseo.service`**，**未列出 `hermes-agent.service`**（即本分支不触发 gateway 重启）。
- 该结果仅为 dry-run 预测，不代表已发生任何激活或重启。

---

## 8. 未决 / 待验证

1. **secret 匹配性 [UNCERTAIN]**：`client.env` 的 `ET_NETWORK_SECRET`（键存在、值未读）是否 == raiyun xavier-mesh 节点所用密钥，未验证；须在应用窗口由有权角色核对，不匹配则需更换为 xavier-mesh 密钥。
2. **对端网络名归属 [UNCERTAIN]**：`cn.xinlly.top:17017` 对端是否确为 xavier-mesh（raiyun 10.122.122.1 那台），仓内证据无法 100% 反查，须应用连接后确认。
3. **DHCP 实际分配地址**：待服务重启后观测虚拟 IP（默认 10.0.0.0/24 起、冲突漂移），确认与 xavier-mesh 内节点的可达性。
4. **跨网段连通（条件项）**：若将来改回静态且落在与 relay 不同的 /24（例如保留 10.144.144.20），能否跨网段互通，须以 `ip route` / `ping` 实测为准，本文不预设结论。
