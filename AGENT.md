# AGENT.md — nixos-hermes-config

## 项目概况

NixOS Flake 配置仓库，以声明式方式管理多台机器（WSL 工作站 + 雨云 VPS）及上面的 Hermes Agent / Paseo / Hindsight 等服务。

- 远端：`https://github.com/Xinlly/nixos-hermes-config`
- 工作目录：`/var/lib/hermes/workspace/projects/our/nixos/`
- 许可证：仓库当前**无 LICENSE 文件**（未声明，勿臆造）
- nixpkgs：跟踪 `nixos-unstable`；系统版本形如 `26.11.20260616.567a49d`

## 目录结构

```
nixos/
├── flake.nix                 # Flake 入口：inputs + nixosConfigurations 各主机
├── flake.lock
├── common/                   # 跨主机共享
│   ├── base.nix              # experimental-features / nix-ld / 时区 / 基础包
│   └── proxy.nix
├── hosts/                    # 各主机变体
│   ├── wsl/                  # WSL2 工作站（default.nix / hermes.nix / users.nix）
│   ├── raiyun/               # 雨云 VPS（default.nix / disk-config.nix / derper.nix）
│   └── raiyun2/              # 雨云高速线新机（default.nix / disk-config.nix）
├── modules/
│   ├── hermes/               # Hermes Agent 相关（见组件归属）
│   ├── paseo.nix
│   └── tailscale.nix
├── patches/hermes-agent/     # 对 Hermes Agent 源码的本地 backport（overlay 注入）
├── scripts/vban-receiver.py
├── AUDIO.md                  # 音频方案备忘
└── AGENT.md                  # 本文件
```

## 主机与变体（flake.nix `nixosConfigurations`）

| Attr | 机器 | 引导 | 说明 |
|---|---|---|---|
| `nixos` | WSL2 工作站 | NixOS-WSL | 全功能：Hermes + Paseo + 音频 + 浏览器 |
| `raiyun` | 雨云 VPS（公网地址/端口不入库） | BIOS+GPT(EF02)，disko | 最小 NixOS + Tailscale/DERP + mihomo |
| `raiyun2` | 新机雨云高速线（公网地址/端口不入库） | BIOS+GPT(EF02)，disko | **已装 NixOS 26.11**：最小 NixOS + SSH（无 derper/mihomo），过程见下 |

新增主机 = 在 `hosts/<name>/` 加目录 + flake.nix 注册一个 `nixosConfigurations.<name>`。

## 部署工作流与硬闸门

只改 workspace 源文件，**严禁直接手改 `/etc/nixos`**（除授权轮内的标准同步）。

1. 改 `hosts/ common/ modules/ flake.nix` 等源文件 → commit → push。
2. 授权后 `rsync -av --exclude='.git' workspace/ /etc/nixos/`（**无 `--delete`**）。
3. 同步后 `diff -rq --exclude='.git'` 必须零差异。
4. 授权后重建：
   - `nixos-rebuild test`：仅当前运行生效，**不改 boot 默认代**，重启回旧版。
   - `nixos-rebuild switch`：持久化为 boot 默认（需明确授权）。

未获逐轮授权前禁止：rsync 到 /etc、任何 rebuild/switch、重启 Paseo daemon / agent、`wsl --shutdown`、改默认发行版 / `.wslconfig`。

代理（本地 35353）：重建前在目标 tty 执行 `set-proxy` + `set-nix-proxy`，并核验 nix-daemon 进程 environ 带代理。详见 `nixos-hermes-safe-ops` skill。

### /etc 现存 .git 的处理（现状，非理想态）

`/etc/nixos` 历史上带 `.git`（skill 原则0 认为不应有）。rsync 排除 `.git` 会让新文件对旧 HEAD 成为未跟踪/已修改，导致 `git merge --ff-only` 被拒。
已认可做法：确认工作树 `diff -rq` 零差异后，用**非破坏性 `sudo git -C /etc/nixos reset --mixed <目标SHA>`** 只移动分支指针、刷新索引，不触碰工作树文件。不要用 `reset --hard`（毁工作树）或 `pull`（被禁）。

## Git 提交署名

- 推送认证恒为 Xinlly token（`~/.hermes/.env` 的 `GITHUB_TOKEN`），GitHub pusher = Xinlly。
- AI 代实现的提交：作者名 **Dora**，邮箱用用户的 GitHub ID 邮箱 **52117993+Xinlly@users.noreply.github.com**（用户 2026-09-25 定，与 33de9c4 一致），用当轮 `GIT_AUTHOR_*` / `GIT_COMMITTER_*` 生效，不改全局/仓库 config。
- 用户本人写的代码：Xinlly。用户在 VS/Zed 自行提交仍署名 Xinlly。
- 仅当用户明确说「这是我的」才用 Xinlly 身份；不要把 `dora@users.noreply.github.com`（旧式会归属真实账号）与 `dora@noreply.local` 混淆。

## 委派规则（Paseo 治理）

- **Paseo 项目内禁用 Hermes `delegate_task`**，所有子代理一律走 Paseo `create_agent`（脚本/恢复可用 Paseo CLI）。原因：delegate 子代理对 Paseo 不可见、完成通知不走 Paseo 通道，可能唤不醒托管父代理。
- 父子归属只存在 label `paseo.parent-agent-id`（**没有顶层 `parentAgentId` 字段**）；读归属去 labels 读，不要因顶层字段为 null 误判断链。
- 调研 / 联网 / 大段源码勘察：派**一次性 research agent**（create_agent，带 role/project label），主会话不堵塞，完即归档；不自行在主会话做。
- 临时安装/fix 类：一次性 agent、完即回收；**只有长生命周期 feat 线才配常驻 Planner**，无长期线不养 Planner（KISS）。

## 关键组件归属

| 组件 | 归属 | 配置位置 |
|---|---|---|
| Hermes Agent | Hermes/NixOS | `modules/hermes/agent.nix`（gateway systemd 服务、ReadWritePaths） |
| Hermes 运行时/wrapper | Hermes/NixOS | `modules/hermes/runtime.nix`（sitecustomize shim、patched source） |
| Hermes 插件 | Hermes | `modules/hermes/hermes-plugins.nix`、`services.nix` |
| Paseo daemon | Paseo/NixOS | `modules/paseo.nix`（`paseo.service`，端口 6767） |
| Hindsight | Hindsight（容器） | `modules/hermes/hindsight.nix`：podman，`--network=host`，LLM=MiniMax-M3、embedding=local |
| mihomo | 工具（nixpkgs 二进制，配置手动上传） | `hosts/raiyun/default.nix` |
| Tailscale / DERP | 工具 | `modules/tailscale.nix`、`hosts/raiyun/derper.nix` |

- Hindsight：抽取 LLM 与 embedding 解耦；换 LLM 只改 env 三变量 + `hindsight/.env` key，19k facts 的嵌入不受影响。容器 env 仅**创建时**读取，改配置需重建容器（restart 不重读 env-file）。
- backport：`patches/hermes-agent/0001-acp-fix-none-final-response.patch` 经 overlay 只 patch **source root**；python 依赖集合不变时 sealed env hash 也不变，故判断是否拿到修复要看 source root / PYTHONPATH 中的 sitecustomize，不能只看 env hash。

## 红线与坑点

- `config.yaml` 等运行时文件由 Nix 生成，直接编辑会被 rebuild 覆盖；长期修复改 Nix 源。
- 密钥只入 `*.env`（不进 git、不写命令行/进程列表/输出）；askpass 脚本用后即删。
- 跨服务日志取证：只走该服务 `journalctl -u <unit>` / 独立日志，或严格时间窗 + 精确词并排除请求体，**禁止整库宽 grep**（避免读到别的项目 agent 数据）。
- 日志须带级别/模块；临时 debug 日志验收前清理。

## raiyun2 装机记录（2026-09-25，nixos-anywhere + disko + kexec）

**目标**：最小 NixOS + SSH，不含 derper/mihomo；新机无数据，无需备份。

**与 raiyun 的配置差异**（落在 `hosts/raiyun2/`）：
1. `networking.hostName = "raiyun2"`，flake attr=`raiyun2`。
2. disko 设备 `/dev/sda`（新机 SCSI `sd` 总线；raiyun 是 virtio `/dev/vda`）。
3. 静态内网 IP / 接口见 `hosts/raiyun2/default.nix`（virtio_net，按 Driver 匹配；公网经雨云 NAT）。
4. `qemu-guest.nix` 保留；GRUB BIOS/i386-pc 写 /dev/sda。

**执行步骤**：
1. Electerm 打开书签 `raiyun2_highspeed`（id `ZI9nvtp`），时间戳探针确认可执行、**无双执行**。当时为 Debian 12 / kernel 6.1.38 / 2 vCPU / 2GB / 30G sda / BIOS。
2. 部署 SSH 公钥到 `/root/.ssh/authorized_keys`（600），修复本地私钥权限为 600，本地私钥免密登录验证通过（kexec 前置，见 safe-ops）。
3. 本地 `nix build` toplevel 与 diskoScript，`nix build` nixos-anywhere（1.13.0）。
4. 本地经代理 35353 下载 kexec tarball（439MB），gzip 校验，`--kexec` 传本地路径（避免目标机直连 GitHub）。
5. `nixos-anywhere -s <disko可执行脚本> <toplevel> --kexec <本地tar> -i <key> -p <外部SSH口> --post-kexec-ssh-port <外部SSH口>`。
6. 自动完成：kexec → disko 擦盘分区 → 安装 NixOS + GRUB → 重启。日志 `/tmp/r2-install.log` 结尾 `### Done! ###`，进程 exit 0。
7. 重启后清旧 host key，SSH 免密登录验证：NixOS 26.11 / kernel 6.18.35 / hostname raiyun2 / sda2 挂 / / sshd active+enabled / firewall active / 出网+DNS 正常。

**本次新坑（已同步到 `nixos-anywhere-deploy` skill）**：
- `nix eval` 算出的 store 路径**不代表产物已落盘**——必须真正 `nix build` 后再传给 nixos-anywhere，否则报 `must be existing store-paths`。
- `-s` 的第一个参数要传 disko 的**可执行脚本**（`<disko>/bin/disko`），不是包目录。
- NAT 机型：nixos-anywhere 在 kexec 后默认把端口改回 **22**，外部若是 NAT 非 22 映射，必须显式 `--post-kexec-ssh-port <外部口>`，否则 kexec 后失联。
- 重装后新机 host key **必然变化**，`known_hosts` 旧条目会触发 IDENTIFICATION CHANGED，`ssh-keygen -R '[host]:port'` 后重新接受（自己装的机属预期，非中间人）。
