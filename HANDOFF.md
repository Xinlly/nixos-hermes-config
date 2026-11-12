# HANDOFF — nixos-hermes-config 项目交接（2026-11-12，阶段 D 后终态）

> 本文件只写进度、未完成项、指针与待办，便于全新 agent 接手；静态知识（目录结构、分支策略、署名、红线）见 `AGENT.md`，不重复。本文不含任何真实公网 IP 或密钥值，敏感值一律用占位符或指针表示。

## 1. 当前进度（已完成）

- **manager-profile + xavier-mesh 特性线**：`feat/manager-profile` 四个提交已并入 `develop` 并推送。运行态经 `nixos-rebuild test` 验证通过（test 态，见第 2 节未完成项）。
- **Git 历史敏感信息重写（公网 IP 清除）已完成 A→B→C→D**：
  - 阶段 A：在隔离 mirror 用 `git filter-repo --replace-text` 重写历史，4 个曾入库的真实公网 IP 替换为占位符（`RAIYUN2_PUBLIC_IP` / `RAIYUN_PUBLIC_IP` / `RAIYUN_EGRESS_NAT_IP` / `HK_SERVER_PUBLIC_IP`），公共 DNS 与内核版本串等保护项逐字保留。
  - 阶段 B：显式 `--force-with-lease` 强推 4 个远端分支（方案一），9 标签未变；4 个本地研究分支未推公开仓。fresh clone 验证 4 个 IP 全历史零命中。
  - 阶段 C：主仓 `develop` 已 `reset --hard` 对齐重写后的新历史，研究资料脱敏入库（commit `94443a2`，普通 fast-forward push）。
  - 阶段 D：worktree 与本地分支收敛完成（见第 5 节终态）。
- **灾备研究资料归档**：原 `.paseo/worktrees` 中有丢失风险的调查笔记/脚本（25 个文本文件）已复制进 `docs/research-archive/`（三个来源子目录），其中 7 个含真实 IP 的文件已脱敏（占位符 `RAIYUN2_PUBLIC_IP` 出现 45 次、`WAN_EGRESS_IP` 出现 10 次），原始未脱敏件存 `.sensitive/raw-pii/`（git 忽略，7 件）。

## 2. 未完成项（接手优先看这里）

1. **运行态仍是 test，未 switch（最高优先隐患）**：
   - `/run/current-system` 指向新 toplevel（含 easytier-wsl、hermes-manager provider 等），但 `/run/booted-system` 与系统 profile 仍是旧 generation。
   - 含义：**机器一旦重启会回退到没有 `easytier-wsl.service` 的旧系统**。此前已有一次强制重启前科。
   - 待办：择窗口经授权执行 `nixos-rebuild switch`（或 `boot`）固化；未获 xavier 明确授权前禁止 switch/boot、禁止手动 restart easytier-wsl/paseo/hermes-agent。
2. **develop → master 正式分发冻结**：本地与远端 `master=f4e68b7` 已对齐重写后历史（不再含敏），但是否把当前 `develop=94443a2`（含研究归档提交）正式合并/推送到 master，属独立授权动作，未授权前不碰 master、不做合并。
3. **reflog 仍含旧含敏 SHA（有意保留）**：未做 `git reflog expire` / `git gc`，reflog 仍可检出旧 SHA（`064f6cc` 5 条、`ccc8354` 2 条）。回滚靠冷备 tar 兜底；待整个 NixOS 项目确认不需回滚后，再另行授权清理。
4. **`.playwright-mcp/` 浏览器缓存（git 已忽略）内仍有 3 个 yml 含真实 IP**，不入库；是否物理清理待授权。
5. **Paseo 孤儿 agent `de24d0e0`（research worker，closed）已知保留、不处理**：xavier 2026-11-12 明示不处理，保持 closed 无害现状（活动列表仍可见、archive API 报 not found 的级联漏网）；不要尝试归档，也不要手工改 daemon JSON。

## 3. 关键分支与远端指针

- 远端：`https://github.com/Xinlly/nixos-hermes-config.git`（public）。推送走进程级代理 `HTTPS_PROXY/HTTP_PROXY=http://127.0.0.1:35353`，禁止写进 git config；token 不读不印。
- 收敛后本地仅 4 个分支（以实际 `git rev-parse` 为准）：
  - `develop=94443a2`（当前检出，含研究归档；跟踪 origin/develop）
  - `feat/manager-profile=9305bf1`（已对齐 origin，重写后历史，pickaxe 零命中）
  - `master=f4e68b7`（已对齐 origin/master，重写后历史，pickaxe 零命中）
  - `fix/hermes-acp-none-final-response=abea457`（历史无 IP，保留；远端存在）
- 公开仓只有 4 个分支、9 个标签（标签 SHA 全未变），无研究分支。原 4 个仅本地研究分支（`chore/agentmd-orchestration`、`fix/raiyun2-derp-stun-901`、`research/easytier-feasibility`、`research/networking-alt-solutions`，均同指 `dc339e1`、为 develop 祖先、远端无）已用小写 `git branch -d` 安全删除。
- 占位符口径（历史重写 + 归档统一；真实值不写入任何 Git 文件，仅本机 `.sensitive/` 保留）：
  - `RAIYUN2_PUBLIC_IP`：raiyun2 云机公网地址（曾入库，已在历史与归档中脱敏）
  - `RAIYUN_PUBLIC_IP`：raiyun 公网入口（曾入库，已在历史中脱敏）
  - `RAIYUN_EGRESS_NAT_IP`：raiyun 出口 NAT 地址（曾入库，已在历史中脱敏）
  - `HK_SERVER_PUBLIC_IP`：香港服务器公网地址（曾入库，已在历史中脱敏）
  - `WAN_EGRESS_IP`：本地宽带出口地址（从未进 Git，仅在归档资料脱敏时引入）
  - 占位符与真实值的对应关系是本机运维知识，需要真实值时到 `.sensitive/raw-pii/` 原件核对，不要回填进仓库。
- 保护项（任何替换都不得误伤）：公共 DNS `223.5.5.5`、`119.29.29.29`；内核版本串 `6.18.33.1-microsoft-standard-WSL2`（其中 `6.18.33.1` 不是 IP）。

## 4. `.sensitive/` 原始件指针（只存路径/用途/来源，无真实值）

目录 `.sensitive/`（已写入 `.gitignore`，永不入库；目录 2700 setgid、文件 600，访问主体等价 700/600）；原始未脱敏件在 `.sensitive/raw-pii/`（7 个文件，权限 600），相对路径与来源一一对应：

| 指针路径（.sensitive/raw-pii 下） | 用途 | 原工作副本（已删除） |
|---|---|---|
| easytier-feasibility/DEPLOY-PLAN.md | EasyTier 部署预案（含真实端点） | research-easytier-feasibility |
| easytier-feasibility/REPORT.md | EasyTier 可行性报告 | research-easytier-feasibility |
| fix-raiyun2-derp-stun-901/evidence.md | DERP/STUN 901 排查证据（NAT 端口映射） | fix-raiyun2-derp-stun-901 |
| fix-raiyun2-derp-stun-901/TASK.md | 901 排查任务书 | fix-raiyun2-derp-stun-901 |
| networking-alt-solutions/research/task-worker-a.md | 组网备选调研任务 A | research-networking-alt-solutions |
| networking-alt-solutions/research/task-worker-b.md | 组网备选调研任务 B | research-networking-alt-solutions |
| networking-alt-solutions/research/task-worker-c.md | 组网备选调研任务 C | research-networking-alt-solutions |

脱敏后的对应文件在 `docs/research-archive/` 同相对路径，可公开入库（25 个 tracked 文件）。真实 IP/密钥值不在本文件、不在 Git，仅存于本机 `.sensitive/`。

## 5. worktree 收敛终态（阶段 D 已完成）

`git worktree list` 实测**只剩 1 项**：主仓 `…/our/nixos`（develop=`94443a2`，协调者 primary）。

下列 5 个工作副本已全部用正规 `git worktree remove` 删除（无 `rm -rf`），物理目录不存在、`worktree prune --dry-run` 无残留登记；其未跟踪成果均已在阶段 C 入 `docs/research-archive/`，无丢失：

1. `.paseo/worktrees/0tnh6fc8/feat-manager-profile`（干净，普通 remove）。
2. `…/fix-raiyun2-derp-stun-901`（含未跟踪 TASK/evidence/scripts，已归档；普通 remove 被拒后 `--force`）。
3. `…/research-easytier-feasibility`（含约 80M 可重建源码/构建物与一处被 develop 超集取代的 default.nix 旧版改动；`--force`）。
4. `…/research-networking-alt-solutions`（REPORT/research 已归档；`--force`）。
5. `…/our/raiyun2-new-derp-domain`（原 detached HEAD `caf2d31`，未提交的 derper.nix 是被 develop 实质取代的更老 socat 试验版、真实 IP 命中 0，diff 存 `rewrite/evidence/40-detached-derper-diff.txt`；`--force`）。

Paseo 登记层：daemon 在物理目录被删时自动把对应工作区置 `archivedAt`，NixOS 项目活动工作区现仅剩 primary，无孤儿登记；空容器 `~/.paseo/worktrees/0tnh6fc8/` 已由管理者 `rmdir` 移除。

## 6. 红线与坑（接手必守）

- 未授权不 switch/boot、不 restart 服务、不 nixos-rebuild、不 force push、不碰 master（develop→master 分发待授权）、不 `reflog expire/gc`。
- 任何新内容入库前必须复扫 5 个真实 IP 与密钥模式零命中；`.sensitive/` 与 `.playwright-mcp/` 已 gitignore，不得 `git add -f`。
- 本仓提交署名用临时 env：`GIT_AUTHOR_NAME="Dora"`、`GIT_AUTHOR_EMAIL="52117993+Xinlly@users.noreply.github.com"`（含对应 COMMITTER 变量），不改 git config；显式逐文件 `git add`，禁止 `add -A`/`add .`。
- 历史重写全流程证据与回滚备份在：`/var/lib/hermes/workspace/work/paseo-dr-20261112/rewrite/`（含 pre-rewrite 整仓 tar.gz 备份 `backup/nixos-pre-rewrite-20261112-111342.tar.gz`、STAGE-A/B/C/D 报告、evidence/）。
- 灾备盘点原始报告：`CLOSEOUT-20261111.md`（本仓根，已入库）。
- 已知局限：GitHub 对悬空对象有服务端 GC 延迟，历史 fork/缓存不可追回，要物理 purge 需另开 GitHub Support（未授权）；公网 IP 无法像密钥那样吊销。
