# 规划：声明式新建 `paseo` Hermes Agent Profile

- 文档定位：实施前规划（planner 产出，待 xavier 拍板后交 worker 执行）
- 日期：2026-10-03
- 所属：nixos-hermes-config 仓库，WSL 主机（flake attr `nixos`）
- 任务来源：xavier → Paseo 管理者（2b6f929）→ 本 planner
- 状态：**待批准，尚未实施**（本文档是本阶段唯一落地产物）

---

## 0. 目标与关键边界（必读）

### 目标

用 NixOS **声明式**方式新建名为 `paseo` 的 Hermes Agent profile，专供 Paseo 管理者使用（管理者以后不再用 default profile）：

1. `paseo` 与 `default` 在**配置层**完全一致，唯一差异＝禁用 `hermes-lark-streaming` 这一个插件。
2. 可重建、可审计、可回滚；**禁止** `hermes profile create` 运行时生成再手改。

### 边界定义（硬约束）

- **「与 default 一致」仅指【配置层一致】**：config.yaml 渲染内容、.env 中的非密/凭证键集合、SOUL、skills 集合、MCP servers、toolsets、provider、其余插件 enabled 集合。
- **数据层【全新起步】**：`paseo` 的 sessions、`state.db`、`memories/*`、cron 历史、日志等一律为空，**不克隆、不复制、不迁移** default 的任何运行时数据，也不设计任何数据迁移路径。
- **密钥纪律**：密钥、`.env`、token、证书一律不进 Nix store、不进 git 仓库。profile 所需凭证在**激活期**从仓库外既有 secrets 文件合并（复用 default 的 `environmentFiles` 机制），或经 systemd `EnvironmentFile`；本文不回显任何密钥值。

---

## 1. 调研结论

> 证据约定：
> - 本机源码＝已安装的 patched source：`/nix/store/y3vh9qfksn89vy9d84km9d22jfckzyy0-hermes-agent-source-patched`（下文记为 `$SRC`），对应 input `hermes-agent` pin `v2026.8.13` + 本地 ACP 补丁。
> - GitHub 浏览入口：https://github.com/NousResearch/hermes-agent/tree/v2026.8.13 （行号以本机 `$SRC` 为准；引用文件均非本地补丁改动文件）。
> - 仓库＝`/var/lib/hermes/workspace/projects/our/nixos`（下文记为 `$REPO`）。

### A. Hermes 官方多 profile 机制

#### A1. default 是特殊别名，指向 home 根本身；命名 profile 在 `profiles/<id>/`

- `get_profile_dir(name)`（`$SRC/hermes_cli/profiles.py:374-379`）：
  - `default` → `_get_default_hermes_home()`，即默认 HERMES_HOME 根（标准部署＝`~/.hermes`）；
  - 其他 → `_get_profiles_root() / canon`＝`<root>/profiles/<id>`（`profiles.py:271-282`）。
- profile id 正则：`^[a-z0-9][a-z0-9_-]{0,63}$`（`profiles.py:40`），`paseo` 合法。保留名（`hermes/test/tmp/root/sudo`）被拒（`profiles.py:328-355`）。
- 本机布局实测（2026-10-03）：`/var/lib/hermes/.hermes/profiles/` 存在且为空（前置清理已完成）。

#### A2. `--profile`/`-p` 是全局参数，在 CLI 最早阶段解析并重写 HERMES_HOME

- 入口早期函数 `_apply_profile_override()`（`$SRC/hermes_cli/main.py:592-693`）：
  1. 扫描 argv 中的 `--profile <name>` / `-p <name>` / `--profile=<name>`（main.py:592-601），并拒绝会被误读的值如 pytest 的 `-p no:xdist`（main.py:618-624）。
  2. 解析成功后 `resolve_profile_env(profile_name)`（`profiles.py:2358-2374`）得到目录，执行 **`os.environ["HERMES_HOME"] = hermes_home`**（main.py:686），并把该 flag 从 argv 剥离以免 argparse 报错（main.py:688-690）。
  3. profile 目录不存在则报错退出（`profiles.py:2368-2372`）。

#### A3. `--profile` 与 HERMES_HOME / active_profile 的优先级

按 main.py:571-663 的实际逻辑，优先级为：

1. **显式 `--profile/-p` 最高**——它直接重写 HERMES_HOME（main.py:592-601、686），无论 HERMES_HOME 原值是什么。
2. 无显式 flag 时，若 `HERMES_HOME` 已指向「父目录名为 `profiles`」的路径（如 `.../profiles/coder`），则信任、直接返回（main.py:635-638）。
3. 否则读取 root 下粘性文件 `active_profile`（`hermes profile use` 写入；main.py:652-663；路径定义 `profiles.py:296-298`）。
4. 都没有 → default（`~/.hermes` 根）。
- s6 容器托管子进程例外（`HERMES_S6_SUPERVISED_CHILD`），与本机 native 模式无关（main.py:642-651）。
- 本机实测：`active_profile` 文件不存在（无粘性覆盖）。

#### A4. profile 包含的内容：profile 即独立 HERMES_HOME，无私有/共享之分

- 官方文档原文（https://hermes-agent.nousresearch.com/docs/user-guide/profiles ）：*"A profile is a separate Hermes home directory. Each profile gets its own directory containing its own config.yaml, .env, SOUL.md, memories, sessions, skills, cron jobs, and state database."*
- 新建 profile 时预置的子目录 `_PROFILE_DIRS`（`profiles.py:44-58`）：`memories, sessions, skills, skins, logs, plans, workspace, cron, home`。
- 即：config.yaml/.env/SOUL/memories/sessions/skills/cron/state.db 等**全部 profile 私有**，不存在「从 home 共享的子目录」。
- **但随安装包分发的 bundled 资源对所有 profile 可见**：hermes 二进制 wrapper 注入 `HERMES_BUNDLED_SKILLS` / `HERMES_BUNDLED_PLUGINS` / `HERMES_BUNDLED_LOCALES`（`$SRC/nix/hermes-agent.nix:188-191`）；解析函数 `get_bundled_skills_dir()` 优先读该 env（`$SRC/hermes_constants.py:243-256`）。
- 重要细节：**运行时** skills 发现路径 `get_all_skills_dirs()` ＝`[$HERMES_HOME/skills] + skills.external_dirs`（`$SRC/agent/skill_utils.py:582-590`；`get_skills_dir`＝`$HERMES_HOME/skills`，`hermes_constants.py:1314-1316`）。bundled skills 需经 `sync_skills`/`seed_profile_skills`（`tools/skills_sync.py:675`；`profiles.py:1224`）**落一份到 `$HERMESHOME/skills/` 才会出现在运行时**——`HERMES_BUNDLED_SKILLS` 只作为 seed 源，不是运行时发现路径。

#### A5. 官方 NixOS 模块【没有】profiles 选项

- `$SRC/nix/nixosModules.nix` 全文 1008 行，检索 `profile` 仅命中两处语义，且都是 **Nix per-user profile**（`/etc/profiles/per-user/<user>`，用于挂 `extraPackages`），与 Hermes 多 profile 无关：
  - `nixosModules.nix:482-483`、`:686-688`。
- 即：**不存在声明式创建多个 Hermes profile 的现成选项**。上游模块是 `services.hermes-agent` 单实例（单一 `stateDir`/`settings`/HERMES_HOME）。
- 官方文档 profiles 页给出的创建入口仅为运行时 CLI `hermes profile create`（本任务禁止）；另见 Profile Commands Reference（https://hermes-agent.nousresearch.com/docs/reference/profile-commands ）。

> A 块小结：命名 profile ＝`<root>/profiles/<id>/` 独立 HERMES_HOME；`--profile` 最高优先级；**无现成 Nix 声明选项，需自写模块管理该目录**（见 §2）。

---

### B. 如何在单个 profile 只禁用一个插件

#### B1. 字段结构：`plugins.enabled`（允许列表）＋`plugins.disabled`（禁止列表），均为字符串列表

- 读取来源就是**当前 HERMES_HOME 的 config.yaml**：
  - `_get_disabled_plugins()`（`$SRC/hermes_cli/plugins.py:472-485`）：`load_config()` → `plugins.disabled`，转 set。
  - `_get_enabled_plugins()`（`plugins.py:488-515`）：`plugins.enabled`，转 set；键缺失返回 None（opt-in 默认）。

#### B2. disabled 恒优先——同时出现在两个列表时不加载

- 加载主循环（`plugins.py:3785-3804`）先取 disabled/enabled，逐插件判断：
  - **`lookup_key in disabled or manifest.name in disabled` → 直接跳过**，记录 `error="disabled via config"`（plugins.py:3797-3804）。该判断先于 enabled 判断。
  - 其余 standalone/用户插件必须在 `enabled` 中才加载（plugins.py:3859-3878）。
- 同样的 deny 优先逻辑也用于启动期 portable MCP 探针（`plugins.py:4008-4028`）。
- 匹配同时接受 path-derived key 与 legacy 裸名（plugins.py:3795-3799）。

#### B3. 作用域与影响面

- 配置读取绑定当前 HERMES_HOME，天然 **profile 作用域**：在 `paseo/config.yaml` 写 disabled 只影响 paseo。
- 无「单插件粒度」环境变量。相关 env 只有粗粒度开关：`HERMES_SAFE_MODE`（跳过全部插件发现，plugins.py:3674-3677）、`HERMES_ENABLE_PROJECT_PLUGINS`（项目插件发现，plugins.py:3976-3987）。不适用本需求。
- 插件发现扫描三类来源（`plugins.py:3940-3989`）：bundled（`HERMES_BUNDLED_PLUGINS`）→ **用户目录 `$HERMES_HOME/plugins/`** → 项目目录。因此 paseo 要让 `matt-workflows` 等用户插件可用，**其 `$HERMES_HOME/plugins/` 下必须有对应条目**（default 是 `nix-managed-*` 符号链接）。

#### B4. default 当前启用证据 —— 以及一个必须上报的矛盾

**声明式源（Nix）：default 启用 lark-streaming。**

- `$REPO/modules/hermes/hermes-plugins.nix:32-43`（`/etc/nixos` 与 workspace 内容经 `diff` 确认完全一致）：
  - `plugins.enabled = ["hermes-lark-streaming" "matt-workflows"]`；
  - `plugins.disabled = ["hermes-knowledge-curator"]`（仅此一项）。
  - 注释（:37-39）明确："lark-streaming 启用（飞书流式卡片，gateway 用）……v1.5.0 无 ACP 模式门控，hermes 身份 ACP 加载可能卡死，暂不处理"。
- 对应 git 提交 `341501b`（2026-09-10）"hermes: enable lark-streaming plugin (keep knowledge-curator disabled)"。
- 插件实体：`/var/lib/hermes/.hermes/plugins/nix-managed-hermes-lark-streaming-aowen` → `/nix/store/vcryv0idyjlvw9zpm1ajawab2pv0glnf-hermes-lark-streaming-aowen-1.5.0`；其 `plugin.yaml:1-5`：`name: hermes-lark-streaming`，`kind: standalone`。

**运行时现状（磁盘 config.yaml）：lark-streaming 当前实际被禁用。**

- `/var/lib/hermes/.hermes/config.yaml`（mtime **2026-10-03 19:53:24**）实测：
  - `plugins.enabled = [hermes-lark-streaming, matt-workflows]`（config.yaml:141-144）；
  - **`plugins.disabled = [hermes-knowledge-curator, hermes-lark-streaming]`**（config.yaml:145-147）。
  - 按 B2，disabled 胜出 ⇒ **lark-streaming 此刻在 default 实际未加载**。
- 多份历史备份（09-10、09-15、09-28）也都同时在两列表中出现该插件，说明该状态已长期/反复存在，与声明源不一致。
- `[UNCERTAIN]` 该运行时条目的产生原因与今天 19:53 重写 config.yaml 的触发者：可能是运行时 `hermes plugins disable` 类操作，或某进程写回；**无法从现有证据确认**。另：上游激活脚本的合并是 `deep_merge(existing, nix)`，**nix 侧列表整体覆盖**（`$SRC/nix/configMergeScript.nix:21-30`），故**下次 nixos-rebuild 激活后 default 的 disabled 会被 Nix 值覆盖回仅 knowledge-curator**（即 lark-streaming 恢复启用）。

**paseo 单点禁用的最小写法**（以声明源为基准）：

```yaml
plugins:
  enabled:
    - hermes-lark-streaming
    - matt-workflows
  disabled:
    - hermes-knowledge-curator
    - hermes-lark-streaming   # ← paseo 唯一新增的一行
```

> B 块小结：profile 级 `plugins.disabled` 列表加入插件名即可，deny 恒优先、作用域仅限该 profile。**但 default「运行时实际禁用、声明源启用」的矛盾必须由 xavier 先拍板（见 §8 Q1）**，否则「唯一差异」的参照基准不成立。

---

### C. 现有 NixOS 如何管理 default（~/.hermes）

#### C1. 模块来源与引用链

- 使用上游官方模块：`$REPO/flake.nix:10`（input `hermes-agent` pin tag `v2026.8.13`），`:38` 挂 `hermes-agent.nixosModules.default`。**未使用 rzp-labs 等第三方 hermes Nix 模块**。
- WSL 引用链：
  - `flake.nix:33-45` → `hosts/wsl/default.nix`
  - `hosts/wsl/default.nix:89-96`（imports）→ `hosts/wsl/hermes.nix`
  - `hosts/wsl/hermes.nix:6-13` → `modules/hermes/{runtime,agent,services,hermes-plugins,vban-receiver,hindsight}.nix`
- 仓库内**无任何多 profile 抽象**（grep 全仓，profiles 概念仅存在于文档）。

#### C2. default profile 各配置由哪些声明式字段产出

本机 default HERMES_HOME 实际是 **`/var/lib/hermes/.hermes`**（注意 hermes 用户真实 HOME＝`/var/lib/hermes`，不是 `/home/hermes`）：

| 产物 | 声明位置 | 上游机制 |
|---|---|---|
| HERMES_HOME 定位 | `modules/hermes/agent.nix:16` `stateDir="/var/lib/hermes"` | native 模式 `HERMES_HOME=${stateDir}/.hermes`（`nixosModules.nix:880-883`） |
| `config.yaml` | `agent.nix:20-266` 的 `settings`（+`hermes-plugins.nix` 的 plugins） | 激活期调 merge 脚本深合：`nixosModules.nix:756`；脚本 `nix/configMergeScript.nix`（Nix 键覆盖用户键） |
| `.env`（非密＋凭证） | `agent.nix:283-303` `environment`；`:305` `environmentFiles=["/var/lib/hermes/.hermes/.env.secrets"]` | 激活期生成：`nixosModules.nix:830-845`（`install 0640` → 写非密 → 逐文件 cat secrets） |
| 用户插件目录 | `hermes-plugins.nix:27-30` `extraPlugins` | 激活期清旧链并建 `nix-managed-<name>` 符号链接：`nixosModules.nix:852-866` |
| 目录权限/tmpfiles | — | `nixosModules.nix:711-718`（2770 hermes:hermes）、激活脚本 `:725-764` |
| `.managed` 标记 | — | `nixosModules.nix:761-764` |
| gateway systemd 服务 | 上游模块（`nixosModules.nix:873+`）+ 本地追加 ReadWritePaths（`agent.nix:311-313`）、PYTHONPATH 等（`services.nix:17-23`） | — |

- 不由 Nix 声明、属于运行时文件的配置（paseo 需另行对齐，见 §2.3）：`SOUL.md`、`hindsight/config.json`、`skills/` 树（sync seed 产物）。
- `skills.external_dirs`（`agent.nix:210-211`）＝`/var/lib/hermes/workspace/projects/our/skills/hermes/skills`，是运行时 skills 发现的第二路径。

#### C3. 复用 default 配置、防漂移的设计

**首选：在 paseo 模块里「函数式读取」已合并的 default settings，再单点覆盖。**

- `paseoSettings = lib.recursiveUpdate config.services.hermes-agent.settings { plugins.disabled = <default已声明的 disabled> ++ [ "hermes-lark-streaming" ]; };`
- 优点：
  - model/provider/MCP/toolsets/auxiliary/compression/... 全部直接引用**实际渲染 default 的同一份 attrset**，零复制、零漂移；今后只改 `agent.nix` 一处，两个 profile 同时生效。
  - 唯一显式覆盖＝plugins.disabled 追加一项，可逐行追溯到任务要求。
- 注意：读取的是**声明源**值（不含运行时 config.yaml 的历史残留键）。这与「配置层一致＝以声明源为基准」的定义吻合（见 §0、§8 Q1）。
- disabled 基准值直接从 `config.services.hermes-agent.settings.plugins.disabled`（或带默认 `[]`）取，避免硬编码。

**不采用的方案：**
- 把 `agent.nix` 的 settings 整体抽成独立 lambda 再让两边 import：需要大段移动现有代码，扰动 git blame、且与「读 option」效果相同，违反 K2/K3。
- 复制一份 settings 到新文件：必然漂移，否决。

> C 块小结：default 全部经上游官方模块单实例管理；paseo 通过读 `config.services.hermes-agent.settings` 复用，仅追加一个 disabled 项。

---

### D. 管理者切换到 paseo profile 的落地方式

#### D1. provider 启动命令的确切改法

- 当前声明：`$REPO/modules/paseo.nix:60-68`：
  - `command = [ "/run/current-system/sw/bin/hermes" "acp" ];`（:65）
  - `env.HOME = "/var/lib/hermes";`（:67）
- 改为（全局参数置于子命令前最规范）：

```nix
command = [
  "/run/current-system/sw/bin/hermes"
  "--profile" "paseo"
  "acp"
];
```

- 证据：
  - `--profile` 为全局参数，A2 已证其在 main 早期被解析并剥离，不影响后续 `acp` 子命令 argparse。
  - 实测（本机，2026-10-03）：`hermes acp -p default --check` → 输出 **`Hermes ACP check OK`，退出码 0**。证明 acp 子命令接受 profile 参数且解析链路正常。
  - 注释 main.py:571-572 亦说明历史上 `--profile` 放在子命令后也能识别；但推荐前置。
- `env.HOME` 保持不变；HERMES_HOME 不需在此设置（由 `--profile paseo` 在进程内解析为 `/var/lib/hermes/.hermes/profiles/paseo`，见 A2/A3）。

#### D2. 对 agentId / 在跑会话 / 完成通知链的影响

- **Paseo agentId 与 Hermes profile 无关**：`PASEO_AGENT_ID` 由 Paseo daemon 在 spawn 时分配并注入（`/nix/store/8aqadp0l6rdg1dcx5n865c73xaf8zkxm-paseo-0.8.0-beta.1/lib/paseo/packages/server/dist/server/server/agent/agent-manager.js:3558-3563`），`callerAgentId: agentId`（同文件 :3570）。
- 完成通知走 **ACP 通道回 daemon**（Paseo ↔ `hermes acp` stdio），其路由依据是 Paseo 侧 agent 身份与该 ACP 连接，不依赖 Hermes HERMES_HOME。因此**切 profile 本身不改 agentId、不改通知归属**；profile 切换后 `callerAgentId` 回调仍回到同一 Paseo 会话。
- MCP paseo url 中 `callerAgentId=${PASEO_AGENT_ID}`（`agent.nix:246-248`）的机制不变：daemon 注入 env，hermes 侧由 `_expand_env_vars`（`$SRC/hermes_cli/config.py:2613-2627`）展开 `${VAR}`。paseo profile 渲染配置保留同一字符串即可。
- **关键区分：改 `modules/paseo.nix` 的 provider command 只影响「此后新 spawn 的 hermes 子进程」**。当前正在跑的管理者（及其 hermes acp 进程）仍是 default，直到该进程结束、断线重连触发 respawn，或重启 daemon。
- `[UNCERTAIN]` Paseo 对「agent 断线重连」是复用旧进程还是按最新 provider command 重新 spawn（未在本轮用长连接实测；涉及 agent-manager 生命周期）。为确定性，推荐以 **daemon 重启**作为切换动作（见 D3），不依赖重连语义。

#### D3. 最安全的切换时序（需逐轮授权）

1. **先只部署 paseo profile 模块（不动 provider command）** → `nixos-rebuild test`；按 §6 验证 paseo 目录/config/插件/模型全部正确。此步 default 与在跑管理者完全不受影响。
2. **再改 provider command**（第二次 test）；此时旧管理者仍在跑，不受影响。
3. **等待空闲窗口**：确认 Paseo 无 running/pending agent（在跑 turn 会被 daemon 重启以 SIGTERM 硬中断且不恢复——历史教训）。
4. 授权后 `systemctl restart paseo`（仅引用，不由 planner 执行）。daemon 数据在 `/var/lib/hermes/.paseo`，重启不丢 Paseo 侧编排数据；重启后所有 hermes agent 在被唤起时按新 command 以 paseo profile spawn。
5. 重启后建立/唤起管理者会话，按 §6 复验 HERMES_HOME、插件状态、通知链回到同一 Paseo 会话。
6. 全部验证通过后，按仓库闸门走 master → `nixos-rebuild switch` 固化（见 E）。

> D 块小结：provider command 加 `--profile paseo`（前置）；agentId/通知链不受影响；采用「先部署 profile → 再改 command → 空闲重启 daemon」两段式时序最安全。

---

### E. 生效路径与回滚

#### E1. test 与 switch 的区别

- `nixos-rebuild test`：构建并**立即激活**新 system，但**不更新 boot 默认 generation**；重启（WSL 为 `wsl --shutdown` 后重进）即回退到旧默认。适合本任务首次验证（仓库 `AGENT.md:55-56`）。
- `nixos-rebuild switch`：激活并**设为 boot 默认**（`AGENT.md:58`），需明确授权，且按闸门从 master 走。
- 本任务路径：develop → 同步 /etc → **test 验证全部通过** → 合 master → **switch 固化**（遵循 `AGENT.md:45-61` 硬闸门，含代理与 diff 核验）。

#### E2. profile 文件如何从 store 落位

- 声明式渲染产物（paseo 的 `config.yaml` 文本、插件 store path）在 **NixOS activation script**（`system.activationScripts`）阶段执行：mkdir → install/写 config.yaml → 建 plugins/skills 等符号链接 → 设权限。与上游 `hermes-agent-setup`（`nixosModules.nix:725-867`）同类机制，在新系统激活时于切根后运行。
- 密钥值不经过 store：paseo 的 `.env` 在激活期从仓库外 `/var/lib/hermes/.hermes/.env.secrets` 等文件读取合并（复用 `services.hermes-agent.environmentFiles`），仅落盘到 paseo 目录（0640）。

#### E3. 回滚方案

- **NixOS 层**：
  - 测试期：重启即回退（test 未改 boot 默认）；或 `nixos-rebuild --rollback switch` 切回上一 generation。
  - generation 回滚后，`modules/paseo.nix` 的 command 与 paseo 模块一并回退；重启 `paseo` 服务后新 spawn 的 agent 恢复 default profile。
- **残留目录处理**：回滚到「不含 paseo 模块」的 generation 后，旧激活脚本不会清理新目录，`/var/lib/hermes/.hermes/profiles/paseo` 会残留。因其**数据层全新、无历史价值**，可在授权后 `rm -rf` 该目录删除（删除操作，需 xavier 确认；本文不执行）。
  - 建议 paseo 激活脚本本身设计为**幂等**（每次激活对齐内容与权限），降低反复 test 的脏状态风险。
- **启动参数层**：随 generation 回滚自动恢复；无需单独改 Paseo。
- 数据层无迁移，故**无需任何反向数据恢复**。

> E 块小结：先 test（重启可退）验证，再 switch 固化；回滚＝generation 回退 +（可选）删空的 paseo 目录 + 重启 paseo，无数据恢复负担。

---

## 2. 声明式设计（待批准实施）

### 2.1 新建文件

**`modules/hermes/paseo-profile.nix`**（自写模块，native/WSL 专用）：

职责（全部在 `system.activationScripts` 中幂等完成；目录/权限亦可辅以 `systemd.tmpfiles.rules`）：

1. 读取 `config.services/hermes-agent.settings`，构造 `paseoSettings`：
   - `plugins.disabled`＝该 settings 中现有 disabled（默认 `[]`）**＋`"hermes-lark-streaming"`**；其余键原样。
2. 渲染 config.yaml：`pkgs.writeText "paseo-hermes-config.yaml" (builtins.toJSON paseoSettings)`（JSON 为 YAML 子集，同上游 `nixosModules.nix:55`）。
3. 激活时：
   - `mkdir -p /var/lib/hermes/.hermes/profiles/paseo`，chown `hermes:hermes`，chmod `2770`；
   - 预置**空**数据/运行子目录：`memories sessions logs cron home`（对齐 `_PROFILE_DIRS`，数据层全新、不拷任何文件）；`home` 用 0750；
   - 安装 config.yaml（0660，与上游 group-writable 模式一致），写 `.managed`（0644）；
   - **plugins**：遍历 `config.services.hermes-agent.extraPlugins`，在 `paseo/plugins/` 建 `nix-managed-<getName>` **符号链接**（同 `nixosModules.nix:852-866`），并先清理旧 `nix-managed-*` 死链。保证 matt-workflows 等用户插件可被发现，且与 default 同 store path；
   - **.env**：复用 `config.services.hermes-agent.environment`（非密）与 `.environmentFiles`（secrets 路径），按 `nixosModules.nix:833-845` 同法在激活期生成 paseo `.env`（0640，密钥值只从仓库外文件合并、不进 store）；
   - **SOUL / skills / hindsight**：按 §2.3 策略建符号链接。

### 2.2 改动文件（每处均可追溯）

1. **`hosts/wsl/hermes.nix:6-13`**：imports 增加一行 `../../modules/hermes/paseo-profile.nix`。
   - 仅 WSL 变体引入；raiyun/raiyun2 不受影响。
2. **`modules/paseo.nix:65`**：command 改为带 `--profile paseo`（见 D1）。
   - 该行可与 paseo-profile 模块同批或分两次落地（推荐分两次，时序见 D3）。

不改动：`flake.nix`（无需新 input）、上游模块、default 的任何现有字段、gateway 服务。

### 2.3 SOUL / skills / hindsight config 的对齐策略（推荐：符号链接共享）

这三者 default 侧不是 Nix 声明产物，为实现「配置层一致、零漂移、不复制数据」：

| 项 | paseo 落点（推荐） | target | 说明 |
|---|---|---|---|
| SOUL | `paseo/SOUL.md`（符号链接） | `/var/lib/hermes/.hermes/SOUL.md` | 与 default 同一人格文件；激活脚本 `ln -sfn` |
| skills | `paseo/skills`（**整目录**符号链接） | `/var/lib/hermes/.hermes/skills` | 整个 skills 树共享（含其内 lark-* 相对链接，沿实体所在目录解析，已验证语义正确）；default 增删技能 paseo 自动对齐 |
| hindsight | `paseo/hindsight/config.json`（符号链接） | `/var/lib/hermes/.hermes/hindsight/config.json` | 内容本身无密钥（mode/bank_id/base_url…），保证 `memory.provider: hindsight` 在 paseo 可用，连同一本地 hindsight 服务 |

- 选中整目录链接（而非逐条目链接/独立 seed）：实现最简、天然防漂移，符合「完全对齐」目标；代价是 paseo 不能独立安装技能（写入会落到共享树）。当前需求下可接受，将来要分化再改为实体目录（列于 §8 Q2）。
- hindsight 记忆库数据（`pg0`）仍属于 default 侧容器；paseo 经同一服务读写同一 bank。**注意**：这意味着记忆【内容】会互通（同一 hindsight bank `hermes`）。这与「memories 数据层全新、不迁移」的边界存在张力——见 §8 Q3，请 xavier 明确 paseo 的 memory.provider 是否保留 hindsight（共享 bank）还是初始关闭记忆。

---

## 3. 「与 default 配置层一致」逐项清单（唯一差异＝禁用该插件）

以**声明源**为基准，paseo 渲染 config.yaml 应与 default 声明的 settings 逐项相同，仅一项差异：

| # | 配置项（config.yaml） | default 声明源 | paseo | 对齐 |
|---|---|---|---|---|
| 1 | `model.default` / `model.provider` | `ark-code-latest` / `ark`（agent.nix:36-39） | 同 | ✅ 同源引用 |
| 2 | `fallback_model` | MiniMax-M3 / minimax-cn（:42-45） | 同 | ✅ |
| 3 | `providers.*`（ark/xfyun/poloapi） | :143-160 | 同 | ✅ |
| 4 | `mcp_servers.*`（playwright/context7/electerm/paseo/siyuan/cua-driver） | :230-265 | 同（含 `${PASEO_AGENT_ID}`/`${SIYUAN_TOKEN}` 占位串） | ✅ |
| 5 | `toolsets`（25 项） | :206 | 同 | ✅ |
| 6 | `plugins.enabled` | hermes-lark-streaming, matt-workflows（hermes-plugins.nix:33-36） | 同 | ✅ |
| 7 | **`plugins.disabled`** | **仅** hermes-knowledge-curator（:40-42） | hermes-knowledge-curator **＋ hermes-lark-streaming** | ⚠️ **唯一差异** |
| 8 | `auxiliary.*`（vision/compression/title/... 共 10 组） | :48-65 | 同 | ✅ |
| 9 | `tts`（mimo command provider） | :68-78 | 同 | ✅ |
| 10 | `stt` | :81-85 | 同 | ✅ |
| 11 | `streaming` | :88 | 同 | ✅ |
| 12 | `hermes_lark_streaming.*` | :91-107 | 同（该段保留无副作用；插件本身不加载） | ✅ |
| 13 | `display`（zh/…） | :110-114 | 同 | ✅ |
| 14 | `terminal`（backend/timeout/cwd） | :115-119 | 同 | ✅ |
| 15 | `memory`（provider=hindsight 及限额） | :122-128 | 同（共享 bank 问题见 §8 Q3） | ✅* |
| 16 | `compression`（阈值/保护/裁剪） | :131-140 | 同 | ✅ |
| 17 | `platforms.feishu/telegram` | :163-200 | 同 | ✅ |
| 18 | `agent.max_turns` | 500（:204） | 同 | ✅ |
| 19 | `skills.external_dirs` / `skills.disabled` | :210-227 | 同 | ✅ |
| 20 | `approvals` / `security` / `privacy` / `logging` | :22-33 | 同 | ✅ |
| 21 | `.env` 键集合（非密＋secrets） | agent.nix:283-305 | 同一组来源生成 | ✅ |
| 22 | SOUL | 同一文件（符号链接） | 同 | ✅ |
| 23 | skills 集合 | 同一目录树（符号链接） | 同 | ✅ |
| 24 | 用户插件实体 | extraPlugins 同 store path（符号链接） | 同 | ✅ |
| — | **数据层** sessions / state.db / memories/* / cron 历史 / logs | default 现有数据 | **空，全新，不克隆不迁移** | ⛔ 明确不对齐（边界） |

---

## 4. 影响面分析

- **新增**：`modules/hermes/paseo-profile.nix`（1 个文件）。
- **改动**：`hosts/wsl/hermes.nix`（+1 import）、`modules/paseo.nix`（command +2 元素）。
- **运行中进程**：
  - 部署 profile 模块（test）只在激活期操作新目录，**不触碰** hermes-agent gateway 与 paseo daemon，不中断任何在跑 turn。
  - 改 command 不影响已 spawn 的旧进程；**仅 `systemctl restart paseo` 会中断在跑 turn**（须空闲窗口 + 授权）。
- **其他主机**：raiyun / raiyun2 不 import 该模块，零影响。
- **gateway（飞书入口）**：继续用 default，不受影响（lark-streaming 在 default 的启用/禁用状态本身有矛盾，见 §8 Q1）。
- **磁盘**：新增内容仅小文本 + 若干符号链接 + 空目录，占用可忽略；state.db 等首次运行后在 paseo 目录自增长。
- **凭证**：只读引用 `/var/lib/hermes/.hermes/.env.secrets`，不修改、不复制值进 store；paseo `.env` 与 default `.env` 各自独立但同源生成。
- **权限**：paseo 树 2770 hermes:hermes，xavier 经 hermes 组可读写（与 default 一致）。
- 主要风险：①激活脚本权限/路径写错（用与上游一致的命令并在 test 期验证）；②共享 hindsight bank 与「数据全新」边界冲突（§8 Q3）；③daemon 重启时机不当中断在跑 turn（以空闲门禁规避）。

---

## 5. 前置异常思考（什么会出错 & 防御）

1. paseo 目录先于模块存在 / 残留 pilot 内容 → 激活脚本先校验目录为空或仅含受管条目；现状 profiles 为空（已复核）。
2. 读取 `settings.plugins.disabled` 键缺失 → 取默认 `[]` 再追加，不假设键存在。
3. extraPlugins 中某条目无 plugin.yaml → 上游激活即校验失败（`nixosModules.nix:860-863`）；paseo 建链前同样校验，fail-fast。
4. skills/SOUL 符号链接目标缺失（default 被改动）→ 用绝对路径 `ln -sfn`，目标恢复后自动可用；验证步骤检查链接有效性。
5. paseo 首次启动缺凭证（ARK key 等）→ 激活期必须生成 `.env`；验证步骤显式核对关键键存在（只查键名不回显值）。
6. `${PASEO_AGENT_ID}` 在 paseo 未被展开 → 保留原占位串，依赖 daemon 注入与 `_expand_env_vars`；验证时检查展开后 URL 含真实 agentId。
7. 反复 test 产生脏状态 → 激活脚本全程幂等（mkdir -p / ln -sfn / install 覆盖 / 先清死链）。

---

## 6. 批准后的验证步骤（真实验证，不凭自报）

### 6.1 部署 profile 后（test，未改 command）

1. 目录与权限：`stat /var/lib/hermes/.hermes/profiles/paseo`（2770，hermes:hermes）；子目录存在且为空。
2. config 渲染：
   - `hermes -p paseo config get` 或直接读 `paseo/config.yaml`；
   - 与 default 声明渲染做**归一化 diff**，确认除 `plugins.disabled` 外完全一致。
3. 插件单点禁用：
   - `hermes -p paseo plugins list`（或等价 status）确认 `hermes-lark-streaming` 状态为 disabled/未加载，`matt-workflows` 可用；
   - 对照 `hermes -p default plugins list`，确认仅该一项差异。
4. 模型/其余配置：`hermes -p paseo model` 显示 `custom:ark:ark-code-latest`；MCP/toolsets/provider 与 default 一致。
5. .env：检查 paseo `.env` 存在（0640）且含 `ARK_API_KEY=` 等关键**键名**（不回显值）；确认 store 路径下无密钥（`grep -R` store 渲染产物仅为非密配置）。
6. ACP 链路：`hermes --profile paseo acp --check` 应输出 `Hermes ACP check OK`、退出码 0（对照已实测的 `-p default`）。
7. 链接：`readlink` paseo 的 SOUL/skills/hindsight/plugins 链接，目标正确且有效。

### 6.2 重启 daemon 后

8. 唤起管理者，进程内确认 HERMES_HOME＝`/var/lib/hermes/.hermes/profiles/paseo`（如经日志/状态，不整库 grep）。
9. 完成通知：派发一个最小任务，确认完成回调回到**同一 Paseo 会话**、agentId 不变。
10. 数据全新：确认 paseo 的 sessions/memories 初始为空，未出现 default 的历史会话/记忆文件（hindsight bank 共享情况按 §8 Q3 结论另行核对）。

---

## 7. 回滚方案（操作清单，需授权）

1. 测试期：`wsl --shutdown` 重进（test 未改 boot 默认）即回退；或 `nixos-rebuild --rollback test/switch`。
2. 回滚 generation 后授权 `systemctl restart paseo`，新唤起的管理者恢复 default profile。
3. 授权后删除残留：`rm -rf /var/lib/hermes/.hermes/profiles/paseo`（数据全新、无保留价值；删除前再次确认路径）。
4. 无数据迁移，故无数据恢复动作；default 全程未被改动，可继续使用。

---

## 8. 需要 xavier 拍板的开放问题

### Q1（阻塞项）default 的参照基准：声明源＝启用，运行时＝实际禁用，以哪个为准？

- 现状矛盾见 B4：磁盘 config.yaml（今天 19:53）把 lark-streaming 列入 disabled，实际未加载；Nix 声明源为启用，且下次 rebuild 会覆盖回启用。
- 选项：
  - **(A，推荐)** 以**声明源为准**：default 应启用 lark-streaming（下次激活自动恢复），paseo 额外禁用。符合任务书原话与模块注释；但需确认 default gateway 飞书卡片恢复流式卡片是否符合预期（今天被禁用是否为临时有意操作，原因 [UNCERTAIN]）。
  - (B) 以**运行时现状为准**：先把 default 声明源改为也禁用 lark-streaming（即 default 长期不加载），再谈 paseo——这将使两 profile 在插件行为上无差异，与「唯一差异」目标冲突，不推荐。
- 需要 xavier 告知：今天 19:53 的禁用是否本人/预期操作。

### Q2 skills/SOUL 用「整目录/文件符号链接共享」还是「paseo 独立一份」？

- **(A，推荐)** 符号链接共享：零漂移、最省、自动对齐；paseo 不能独立增删技能。
- (B) paseo 独立 seed/复制：可独立演进，但需自行防漂移、且更接近"复制配置"，维护成本高。

### Q3 paseo 的 memory provider：共享同一 hindsight bank，还是初始关闭记忆？

- 任务边界要求 memories **数据层全新、不迁移**；但配置对齐又要求 `memory.provider: hindsight`（同一本地服务、同一 bank `hermes`）→ 实际会与历史记忆内容互通。
- 选项：
  - **(A)** 保留 hindsight 同一 bank：配置完全对齐，但 paseo 能读到既有记忆内容（严格说是"共享"而非"全新"）。
  - **(B，推荐与边界一致)** 配置层仍声明 hindsight，但为 paseo 建**独立 bank（如 `paseo`）**：同一服务、数据隔离、全新起步。代价：config 出现 bank 差异（属数据隔离需要），需在清单中标注。
  - (C) paseo 初始 `memory_enabled: false`：配置层产生差异，不符合"完全对齐"，不推荐。
- 请 xavier 裁定「配置对齐」与「记忆数据全新」孰先；推荐 B（独立 bank，配置结构一致、数据隔离）。

### Q4 落地批次与重启窗口

- 是否同意 D3 的「两次 test（先 profile、后 command）→ 空闲窗口重启 paseo → master/switch」时序？
- 请指定可重启 paseo 的空闲时间段。

---

## 9. 证据索引（汇总）

**官方文档**
- Profiles（多 profile 总览）：https://hermes-agent.nousresearch.com/docs/user-guide/profiles
- Profile Commands Reference：https://hermes-agent.nousresearch.com/docs/reference/profile-commands
- Profile Distributions：https://hermes-agent.nousresearch.com/docs/user-guide/profile-distributions
- Multi-profile Gateways：https://hermes-agent.nousresearch.com/docs/user-guide/multi-profile-gateways

**本机源码（$SRC = /nix/store/y3vh9qfksn89vy9d84km9d22jfckzyy0-hermes-agent-source-patched）**
- profile 目录/校验：`hermes_cli/profiles.py:40`、`:271-298`、`:310-387`、`:1031-1180`、`:1224-1274`、`:2358-2374`
- profile 覆盖与优先级：`hermes_cli/main.py:571-693`
- 插件 enable/disable 与加载：`hermes_cli/plugins.py:472-515`、`:3660-3700`、`:3767-3889`、`:3940-4045`
- 配置占位展开：`hermes_cli/config.py:2613-2627`
- skills 发现路径：`agent/skill_utils.py:582-590`；`hermes_constants.py:213-256`、`:1305-1322`
- 上游 NixOS 模块（无 profiles 选项；config/.env/plugins 落位）：`nix/nixosModules.nix:55-58`、`:482-483`、`:686-688`、`:711-867`
- config 深合脚本：`nix/configMergeScript.nix:21-30`
- wrapper 注入 bundled 资源：`nix/hermes-agent.nix:188-191`

**Paseo（本机 store：/nix/store/8aqadp0l6rdg1dcx5n865c73xaf8zkxm-paseo-0.8.0-beta.1）**
- agentId 注入：`lib/paseo/packages/server/dist/server/server/agent/agent-manager.js:3558-3570`
- 当前渲染配置：`/nix/store/2wyp0wyhl0ra111h7j71f0f4mjp6rlh-paseo-config.json:1-44`

**本仓库（$REPO）**
- `flake.nix:10,33-45`；`hosts/wsl/default.nix:89-96`；`hosts/wsl/hermes.nix:6-13`
- `modules/hermes/agent.nix:13-16,20-305,311-313`；`modules/hermes/hermes-plugins.nix:26-44`
- `modules/hermes/services.nix:17-23`；`modules/paseo.nix:60-68`
- 实测命令：`hermes acp -p default --check` → `Hermes ACP check OK`（exit 0）
