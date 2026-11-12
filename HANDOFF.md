# HANDOFF — nixos-hermes-config 项目交接（2026-11-12）

> 本文件只写进度、未完成项、指针与待办，便于全新 agent 接手；静态知识（目录结构、分支策略、署名、红线）见 `AGENT.md`，不重复。本文不含任何真实公网 IP 或密钥值，敏感值一律用占位符或指针表示。

## 1. 当前进度（已完成）

- **manager-profile + xavier-mesh 特性线**：`feat/manager-profile` 四个提交已并入 `develop` 并推送。运行态经 `nixos-rebuild test` 验证通过（test 态，见第 2 节未完成项）。
- **Git 历史敏感信息重写（公网 IP 清除）已完成 A→B→C**：
  - 阶段 A：在隔离 mirror 用 `git filter-repo --replace-text` 重写历史，4 个曾入库的真实公网 IP 替换为占位符（`RAIYUN2_PUBLIC_IP` / `RAIYUN_PUBLIC_IP` / `RAIYUN_EGRESS_NAT_IP` / `HK_SERVER_PUBLIC_IP`），公共 DNS 与内核版本串等保护项逐字保留。
  - 阶段 B：显式 `--force-with-lease` 强推 4 个远端分支（方案一），9 标签未变；4 个本地研究分支未推公开仓。fresh clone 验证 4 个 IP 全历史零命中。
  - 阶段 C：主仓 `develop` 已 `reset --hard` 对齐重写后的 `origin/develop`（当前 HEAD 见 `git rev-parse develop`）。
- **灾备研究资料归档**：`.paseo/worktrees` 中有丢失风险的调查笔记/脚本（25 个文本文件）复制进 `docs/research-archive/`（三个来源子目录），其中 7 个含真实 IP 的文件已脱敏（占位符 `RAIYUN2_PUBLIC_IP` 45 处、`WAN_EGRESS_IP` 10 处），原始未脱敏件存 `.sensitive/raw-pii/`（git 忽略）。

## 2. 未完成项（接手优先看这里）

1. **运行态仍是 test，未 switch（最高优先隐患）**：
   - `/run/current-system` 指向新 toplevel（含 easytier-wsl、hermes-manager provider 等），但 `/run/booted-system` 与系统 profile 仍是旧 generation。
   - 含义：**机器一旦重启会回退到没有 `easytier-wsl.service` 的旧系统**。今天已有一次强制重启前科。
   - 待办：择窗口经授权执行 `nixos-rebuild switch`（或 `boot`）固化；未获 xavier 明确授权前禁止 switch/boot、禁止手动 restart easytier-wsl/paseo/hermes-agent。
2. **本地 `master` 与 `feat/manager-profile` 分支仍指向重写前的旧历史**（含真实 IP 的旧对象），本次只对齐了 `develop`。对齐这两个本地分支属独立授权动作，未授权前禁止 `branch -f/reset/checkout` 它们，也禁止 `reflog expire/gc`。
3. **`.paseo/worktrees` 下危险区工作副本待回收**（见第 5 节），回收需单独授权，当前一律保留不删。
4. `.playwright-mcp/` 浏览器缓存（git 已忽略）内仍有 3 个 yml 含真实 IP，不入库；是否物理清理待授权。

## 3. 关键分支与远端指针

- 远端：`https://github.com/Xinlly/nixos-hermes-config.git`（public）。推送走进程级代理 `HTTPS_PROXY/HTTP_PROXY=http://127.0.0.1:35353`，禁止写进 git config；token 不读不印。
- 重写后远端（以实际 `git ls-remote` 为准）：`develop`/`feat/manager-profile` 同一新 SHA、`master` 独立新 SHA、`fix/hermes-acp-none-final-response` 未变；9 个标签 SHA 全未变；公开仓只有 4 个分支，无研究分支。
- 占位符口径（历史重写 + 归档统一；真实值不写入任何 Git 文件，仅本机 `.sensitive/` 与原始 worktree 保留）：
  - `RAIYUN2_PUBLIC_IP`：raiyun2 云机公网地址（曾入库，已在历史与归档中脱敏）
  - `RAIYUN_PUBLIC_IP`：raiyun 公网入口（曾入库，已在历史中脱敏）
  - `RAIYUN_EGRESS_NAT_IP`：raiyun 出口 NAT 地址（曾入库，已在历史中脱敏）
  - `HK_SERVER_PUBLIC_IP`：香港服务器公网地址（曾入库，已在历史中脱敏）
  - `WAN_EGRESS_IP`：本地宽带出口地址（从未进 Git，仅在归档资料脱敏时引入）
  - 占位符与真实值的对应关系是本机运维知识，需要真实值时到 `.sensitive/raw-pii/` 原件核对，不要回填进仓库。
- 保护项（任何替换都不得误伤）：公共 DNS `223.5.5.5`、`119.29.29.29`；内核版本串 `6.18.33.1-microsoft-standard-WSL2`（其中 `6.18.33.1` 不是 IP）。

## 4. `.sensitive/` 原始件指针（只存路径/用途/来源，无真实值）

目录 `.sensitive/`（权限 700，已写入 `.gitignore`，永不入库）；原始未脱敏件在 `.sensitive/raw-pii/`（文件 600），相对路径与来源一一对应：

| 指针路径（.sensitive/raw-pii 下） | 用途 | 来源工作副本 |
|---|---|---|
| easytier-feasibility/DEPLOY-PLAN.md | EasyTier 部署预案（含真实端点） | research-easytier-feasibility |
| easytier-feasibility/REPORT.md | EasyTier 可行性报告 | research-easytier-feasibility |
| fix-raiyun2-derp-stun-901/evidence.md | DERP/STUN 901 排查证据（NAT 端口映射） | fix-raiyun2-derp-stun-901 |
| fix-raiyun2-derp-stun-901/TASK.md | 901 排查任务书 | fix-raiyun2-derp-stun-901 |
| networking-alt-solutions/research/task-worker-a.md | 组网备选调研任务 A | research-networking-alt-solutions |
| networking-alt-solutions/research/task-worker-b.md | 组网备选调研任务 B | research-networking-alt-solutions |
| networking-alt-solutions/research/task-worker-c.md | 组网备选调研任务 C | research-networking-alt-solutions |

脱敏后的对应文件在 `docs/research-archive/` 同相对路径，可公开入库。真实 IP/密钥值不在本文件、不在 Git，仅存于本机 `.sensitive/` 与原始 worktree。

## 5. worktree 待回收清单（回收前必须逐项授权，当前保留）

`git worktree list` 实测 6 项：

1. 主仓 `…/our/nixos`（develop，协调者 primary，**保留**）。
2. `.paseo/worktrees/0tnh6fc8/feat-manager-profile`（feat/manager-profile，已并入 develop 并推送；本地分支旧历史，待第 2.2 项对齐后回收）。
3. `…/fix-raiyun2-derp-stun-901`（研究分支，含未跟踪 TASK/evidence/scripts，成果已归档）。
4. `…/research-easytier-feasibility`（研究分支，含约 80M 可重建源码/构建物，成果已归档）。
5. `…/research-networking-alt-solutions`（研究分支，REPORT/research 已归档）。
6. `…/our/raiyun2-new-derp-domain`（**detached HEAD `caf2d31`**）：其提交是 develop 祖先，但工作树有一份未提交的 `hosts/raiyun2/derper.nix`，是更老的试验版（用 `cn.xinlly.top` 域名、无 HSTS/NO_PROXY），develop 已有更新更完整的版本，实质被取代但**非逐字相同**；该文件真实 IP 命中为 0。回收前需单独列出确认，不得直接删。

## 6. 红线与坑（接手必守）

- 未授权不 switch/boot、不 restart 服务、不 nixos-rebuild、不 archive/删 worktree、不 force push、不碰 master、不 `reflog expire/gc`。
- 任何新内容入库前必须复扫 5 个真实 IP 与密钥模式零命中；`.sensitive/` 与 `.playwright-mcp/` 已 gitignore，不得 `git add -f`。
- 本仓提交署名用临时 env：`GIT_AUTHOR_NAME="Dora"`、`GIT_AUTHOR_EMAIL="52117993+Xinlly@users.noreply.github.com"`（含对应 COMMITTER 变量），不改 git config；显式逐文件 `git add`，禁止 `add -A`/`add .`。
- 历史重写全流程证据与回滚备份在：`/var/lib/hermes/workspace/work/paseo-dr-20261112/rewrite/`（含 pre-rewrite 整仓 tar.gz 备份、STAGE-A/B/C 报告、evidence/）。
- 灾备盘点原始报告：`CLOSEOUT-20261111.md`（本仓根，已随本次入库）。
