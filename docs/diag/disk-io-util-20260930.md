# 磁盘 I/O 利用率打满（%util 100%）只读诊断报告

- 报告时间：2026-09-30（UTC+8）
- 执行环境：WSL2 NixOS 虚拟机，hostname=`nixos`，kernel `6.18.33.1-microsoft-standard-WSL2`，身份 uid=998 `hermes`
- 诊断人：Dora（research，本任务全程自己执行，未派生任何子 agent）
- 纪律：全程只读取证；未删除/回收/GC/改配置/激活持久服务。所有修复均为**待批准建议**。
- **症状澄清（xavier 09-30 纠正）：所报"100%"指磁盘读写 I/O 利用率（%util / I/O wait 打满），不是存储空间占用。** 存储空间（72G/1007G=8%）始终正常。
- 取证时点：重启后约 15 分钟（开机启动 I/O 风暴尚未完全退去的窗口期）。

---

## 1. 结论先行：最可能根因排序

| 排序 | 根因假设 | 置信度 | 与"随 uptime 累积、重启释放"的吻合 |
|---|---|---|---|
| 1 | **WSL2 冷缓存 + 开机服务群启动的海量回读风暴**（NixOS 大量小 store 文件、常驻 agent/容器/PG 同时拉起，page cache 空） | 中高（对"重启后即观测到的高 I/O"）；**对"长时间运行后才 100%"偏低** | 部分吻合：解释每次重启后的 I/O 高峰，但不解释 uptime 很久后才 100% |
| 2 | **随 uptime 累积的内存压力 → 页缓存回收/直接回收颠簸（thrashing）**，某进程内存缓慢增长挤占 cache，反复换入换出 sdc；无 guest swap，压力全部表现为磁盘读 I/O | 高（对"长时间运行后 100%、重启即好"这一核心现象） | **高度吻合**：累积型、重启清零；PSI memory full 开机期已有累计 534s |
| 3 | **Podman overlay / Hindsight-PG 写放大**（WAL、autovacuum、overlay 多层 CoW、容器日志）随消息量增长 | 中 | 累积型吻合；但单纯重启不释放已落盘数据，除非风暴来自 cache/WAL 循环 |
| 4 | **Windows 宿主侧 VHDX 动态扩容 + Defender/索引实时扫描 VHDX 与回写**，guest 内表现为 sdc %util 100% | 中低（本次未取宿主侧实据，见未验证项） | 可随 uptime 写入量累积；重启 WSL 释放 VHDX 活跃写入窗口 |
| 5 | **崩溃—重启循环**（某服务反复 crash 产生 core / 重放 / 回读） | 低（本次 ps 未见 D 态、未见明显 crash 循环；未取 coredumpctl，因权限与收尾指令） | 累积型吻合，但缺证据 |

> 核心判断：**重启后 15 分钟窗口抓到的是"开机读风暴"（根因 1），这很可能不是 xavier 看到的"长时间运行后 100%"本体**。对"长期运行后打满、重启释放"解释力最强的是**根因 2（内存压力导致的 I/O 颠簸）**，但现场已清，必须用 §5 的只读采样器在下次复现时抓现行才能定论。当前结论置信度受取证窗口限制，已逐项标注。

---

## 2. 现状基线证据（命令 + 数值，均为本次实跑输出）

### 2.1 文件系统：空间与 inode 均正常（再次确认问题不是容量）

`df -h`（节选）：

```
Filesystem  Size  Used Avail Use% Mounted on
/dev/sdc    1007G   72G  885G   8% /
drivers      301G  172G  129G  58% /usr/lib/wsl/drivers
C:\          301G  172G  129G  58% /mnt/c
D:\          654G  223G  432G  35% /mnt/d
```

`df -i /`：

```
Filesystem     Inodes   IUsed    IFree IUse% Mounted on
/dev/sdc    67108864 2142113 64966751    4% /
```

→ 容量 8%、inode 4%，**排除空间/inode 耗尽**。

### 2.2 块设备：sdc 是 WSL2 ext4 虚拟磁盘

`lsblk`：

```
NAME   SIZE TYPE MOUNTPOINT       FSTYPE ROTA
sda  356.9M disk                  ext4      1
sdb  159.5M disk                  ext4      1
sdc      1T disk /mnt/wslg/distro ext4      1
```

→ `/dev/sdc` 为 WSL2 发行版虚拟磁盘（背后是 Windows 上的 ext4 VHDX）。`ROTA=1` 是虚拟化上报，不代表物理机械盘；真实 I/O 成本受宿主磁盘类型与 VHDX 动态盘机制影响（见根因 4）。

### 2.3 Load average：重启前 15 分钟负载高达 ~45

`uptime`（开机 15 分钟时）：

```
06:10:21 up 0:15, 1 user, load average: 1.00, 7.12, 45.33
```

→ load1=1.00、load5=7.12、load15=45.33。15 分钟均值 45 远超 19GiB 内存机型的合理值，且与开机窗口重叠，**说明重启前/开机阶段存在大量阻塞任务（很可能阻塞在 I/O）**。

### 2.4 PSI：开机期 I/O 与内存压力显著

`cat /proc/pressure/io`：

```
some avg10=0.00 avg60=0.01 avg300=2.17 total=1149151589
full avg10=0.00 avg60=0.01 avg300=1.61 total=932572844
```

`cat /proc/pressure/memory`：

```
some avg10=0.00 avg60=0.00 avg300=0.98 total=539490144
full avg10=0.00 avg60=0.00 avg300=0.98 total=534257284
```

→ IO stall 累计约 1149s（microsec 总量级），memory full stall 累计约 534s；avg300 仍有 2.17/1.61。**开机约 900s 内有 ~932s 至少一个任务因 I/O 完全停顿，并有 ~534s 全系统因内存回收停顿**——I/O 与内存回收压力同时存在，支撑根因 1 与根因 2。

### 2.5 diskstats：开机 15 分钟读约 150GB，设备近乎持续繁忙

`grep ' sdc ' /proc/diskstats`（开机约 15 分钟）：

```
8 32 sdc 3694359 427510 315454404 852582282 1182648 646549 46782648 7090679 0 1737840 859843544 43028 7305 57911840 7635 72587 162946
```

字段解读（按 /proc/diskstats 规范）：

- 读完成 3,694,359 次；读扇区 315,454,404 → **读约 150.4 GiB**（315,454,404 × 512B）。
- 读 I/O 累计耗时 852,582,282 ms ≈ **852.6s**（开机仅约 900s）→ 设备读路径近乎被占满。
- 写完成 1,182,648 次；写扇区 46,782,648 → 写约 22.3 GiB。
- field13 `time doing I/O` = 1,737,840（单位 10ms 刻度，累计约 1738s 的设备繁忙，可超过墙上时间，因多请求并行/队列）。
- field14 加权 I/O 时间 859,843,544 ms ≈ 859.8s。

→ **以读为主（读/写 ≈ 6.7:1），且设备在开机 900s 内有约 852s 在读**——典型"冷缓存全量回读"，不是"某进程疯狂写日志"。这把开机高峰明确指向根因 1。

### 2.6 内存与 swap：guest 内无 swap

`free -h`：

```
              total used free  shared buff/cache available
Mem:           19Gi  10Gi 5.8Gi   255Mi      4.0Gi     9.2Gi
Swap:            0B   0B
```

`swapon --show`：（空）；`cat /proc/sys/vm/swappiness` = `60`。

→ WSL2 guest 内**无 swap 设备**。后果：内存压力无法换出到 swap 缓解，**只能靠回收 page cache 并在缺页时从 sdc 重新读盘**——这正是根因 2 在本机的特有放大机制（无 swap 颠簸 ≈ cache 与可执行映像之间的反复回读）。

### 2.7 实时 vmstat：平静后几乎无 I/O

`vmstat 1 3`：

```
 r b ... si so   bi   bo ... wa
 1 0 ...  0  0 1402  204 ...  1
 0 0 ...  0  0    0    0 ...  0
 0 0 ...  0  0    0    0 ...  0
```

→ 风暴退去后 bi/bo 归零、wa=0，I/O 系统恢复正常。说明 100% 是**阶段性/累积性**现象，而非设备恒定饱和。

### 2.8 挂载（区分重启消失项）

`df -h` 中运行态均为 WSL 注入的 tmpfs/9p 类挂载，重启即重建：`/dev`(1000M)、`/run`(4.9G)、`/run/lock`、`/run/shm`、`/run/wrappers`、`/run/user/*`、`/mnt/wsl*`、`/init`；持久数据仅 `/dev/sdc`（/）与宿主 9p 盘 `/mnt/c`、`/mnt/d`、drivers。
→ **"重启即消失"的是 tmpfs 与冷 page cache；sdc 上已落盘字节不消失。** 因此若现象每次重启都清零，根因更偏向"内存/cache 状态"而非"磁盘上持续增长的文件"。

---

## 3. 逐项 I/O 嫌疑判定（证据 + 累积/释放性质）

### 3.1 开机冷缓存 + 服务群启动的海量回读 —— 有强证据（当前窗口主因）

- 证据：§2.5 15 分钟读 150GiB、读耗时 852s/900s；§2.4 IO PSI；§2.3 load15=45。
- 现场常驻服务多（`ps` 实测）：`hindsight-api`、`postgres`（Hindsight 库，多个 idle 连接）、`mihomo`、`Paseo Daemon`、多个 `hermes acp/gateway`、多个 node（Paseo CLI）。NixOS 程序由海量小 store 文件组成，冷 cache 下并发回读极易把虚拟盘读饱和。
- 累积性：**不随 uptime 单调增长**，每次开机集中爆发后退去（§2.7）。
- 释放性：重启 cache 清空反而是**触发**它的原因，不是释放。
- 判定：能解释"刚重启那段时间磁盘 100%"，**不能单独解释"长时间运行后才 100%"**。

### 3.2 内存压力 / 直接回收颠簸 —— 对核心现象解释力最高（需采样证实）

- 证据：memory PSI `full total≈534s`（开机 900s 内）；guest 无 swap（§2.6）；多常驻 agent/node 进程并存，长期运行存在缓慢内存增长的现实条件。
- 机制：可用内存被占 → 内核回收 page cache → 代码/数据缺页 → 从 sdc 回读 → 进一步占内存与 I/O → %util 升高、load 升高。重启清空全部内存状态，立刻恢复——**与"长期累积、重启清零"完全吻合**。
- 累积性：随 uptime 单调恶化（若存在泄漏/缓存无界）。
- 释放性：重启或重启相关服务（释放其内存）即缓解。
- 判定：**根因排序第 2 但对主诉解释力第 1**；当前缺"长 uptime 现场"的内存/I/O 联动曲线，需 §5 抓现行。

### 3.3 Podman overlay / 容器写放大 —— 有间接证据，未取体积数值

- 证据：podman 5.8.2 存在（`/run/current-system/sw/bin/podman`）；`hindsight-api` 容器与多 postgres 后端连接在跑。本次受收尾指令未执行 `podman system df` / overlay du / 容器日志大小，**[UNCERTAIN] 其实际体积与写速率**。
- 机制：overlay 多层 CoW + 容器 stdout 日志无界增长 + 镜像/层堆积，可造成持续写 I/O。
- 累积性：随 uptime 与消息量增长。
- 释放性：已落盘的层/日志**不会因单纯重启消失**；只有日志/WAL 循环或 cache 型写入才会重启缓解。
- 判定：中置信度，需采样与 `podman system df` 基线补证。

### 3.4 PostgreSQL WAL / autovacuum / Hindsight 写入 —— 有服务存在，未取 PG 内部指标

- 证据：`postgres: hindsight hindsight 127.0.0.1 ... idle` 多连接（ps 实测）；属 Hindsight 后端。未取 `pg_wal` 大小、autovacuum 状态、DB 体积（收尾指令停止探查），**[UNCERTAIN]**。
- 机制：Hindsight 持续 retain → WAL 生成、checkpoint、autovacuum 写放大；若写峰集中可打满磁盘写 I/O。
- 累积性：随写入量增长。
- 释放性：WAL 在 checkpoint/保留期后回收（周期性，不依赖重启）；数据文件不随重启缩小。
- 判定：中置信度。若采样显示写为主（而非读为主）则优先级上调；当前 §2.5 显示开机以**读**为主，故开机峰非 PG 写入所致。

### 3.5 Windows 宿主侧：VHDX 动态增长 + Defender/索引扫描 —— 未取宿主证据

- 证据：sdc 为 WSL2 VHDX（§2.2）；宿主 C: 58%、D: 35%（空间充足）。**未在 Windows 侧采样磁盘活跃时间、Defender、VHDX 物理位置**，**[UNCERTAIN]**。
- 机制：动态 VHDX 扩容、宿主实时防护/搜索索引扫描 VHDX，会让 guest 看到的 sdc %util=100%，而 guest 内找不到对应"大写入进程"。
- 累积性：随 guest 写入导致 VHDX 扩张而触发。
- 释放性：关闭 WSL 后宿主侧活跃写入停止。
- 判定：中低置信度，需在宿主用 `typeperf "\PhysicalDisk(*)\% Idle Time"`/资源监视器与 guest 时间对齐核实。

### 3.6 崩溃—重启循环 / coredump 堆积 —— 本次未见证据

- 证据：采样时 `ps` 中**无 D 态任务**；未见服务反复拉起的明显迹象。未运行 `coredumpctl list`、未查 `/var/lib/systemd/coredump`（权限 + 收尾指令），**[UNCERTAIN] 历史 core**。
- 累积性：若崩溃循环存在则随 uptime 堆积 core 与重放 I/O。
- 释放性：core 落盘不随重启自动消失（除非 tmpfs）。
- 判定：低置信度，列此备查。

---

## 4. Windows 宿主侧取证（2026-09-30 实跑，只读）

用户确认 100% 在 **Windows 任务管理器**看到、且明确由 WSL 引起。经 PowerShell 5.1 只读采集（脚本存 workspace/temp/win-disk-diag/）：

- **WSL 根盘 VHDX**：`D:\wslDistroStorage\NixOS\ext4.vhdx`，当前 **105.43GB**（由注册表 `HKCU\Software\Microsoft\Windows\CurrentVersion\Lxss` 的 BasePath 定位）。
- **宿主 D 盘没满**：物理盘实例 `0 c: d:`（C/D 同盘），D 盘已用 222GB / 剩 **431GB** → 排除“VHDX 所在卷空间耗尽”。
- **诊断时磁盘空闲**：`% Disk Time≈1.1%`、`% Idle≈99.2%`、队列 0。
- **Defender 实时保护开启**；排除项需管理员查看，普通权限**无法确认 VHDX 是否已被排除** `[UNCERTAIN]`。
- **进程归属确认**：WSL2 在宿主侧的内存/I-O 进程为 **`vmmemWSL`**（计数器实例小写 `vmmemwsl`），相关还有 `wslservice/wsl/wslhost`。
- 进程级 40s 采样期间磁盘空闲，`vmmemWSL` 与 `MsMpEng` 读写均≈0，**抓不到高 I/O 现场**（须故障时抓）。
- `Diagnostics-Performance/Operational` 近 24h 无事件。

**Windows 侧判定**：WSL 的磁盘读写经 `vmmemWSL` 全部落在 D 盘那个 ext4 VHDX；D 盘没满、当前空闲，故“任务管理器 100%”是**某时段 VHDX 的读写 / 被扫描打满**，非容量问题。guest 内 ext4 挂载带 `discard`，大量写入删除会对 VHDX 产生 TRIM；叠加 Defender 实时扫描 VHDX，会在宿主侧放大为 100%。这两个宿主侧放大项需与 WSL 内采样同时观测才能定量。

---

## 4b. 真实现场已抓到（2026-09-30 14:39–14:54，决定根因）

xavier 报告 I/O 又满，当场只读取证，**根因不是磁盘退化也不是空间，而是“工具子进程大量堆积不回收”导致的进程/回读爆炸**。

实测：
- **负载**：`load average 223.69 / 160.92 / 112.26`（14:39），到 14:54 降到 69。
- **PSI**（14:39）：io some avg60=79.4 / avg300=85.8，io full avg300=80.6；memory full avg300=40.8 → 绝大多数任务在等 I/O 与回收。
- **diskstats 6 秒窗口**：读完成从 15,720,972 → 16,176,592（**+455,620 次读 ≈ 7.6 万读 IOPS**），读扇区 +2964 万（约 +14GB 累计计数）；而各进程 `/proc/<pid>/io` 的 read_bytes 增量加总仅几十 MB → 是**海量小写/元数据与页缓存回读**，不是单进程顺序大读。
- **进程数异常（同一时刻）**：`python3.12=121`、`node=87`、`hermes=33`、`npm exec @playwright…=30`、`postgres=27`、`npm exec @upstash…=27`、`cua-driver.exe=26`、`npx=6`；线程总数 2483。正常应各仅数个 → 大量 agent 的工具子进程（MCP node 包装、python、cua-driver、postgres）被拉起后**未随任务结束而回收**，长期堆积。
- **顶层归属（ps 全量上溯）**：这些工具进程的顶层祖先 **286 个归到 `Paseo Daemon (pid 328)`**，另 conmon 22、hermes(311) 10。即堆积的工具进程主要由 Paseo 各 agent 的工具调用派生、daemon/agent 侧未做子进程回收。
- 抽样 node 进程父级：`npm exec @playwright`、`python3.12`、`npm exec @upstash`，启动时间分布在 13:35–14:38（跨约 1 小时持续累积），非单次任务。

**判定（高置信度）**：长时间运行后磁盘 I/O 打满 = **Paseo agent 工具子进程（MCP/浏览器/数据库/driver 包装）不断派生却不回收**，进程与句柄累积、页缓存回读/元数据 I/O 与调度队列爆炸；重启清空全部进程故立即恢复。这比早先“冷缓存回读 / swap 颠簸 / VHDX-Defender”等假设更直接解释“随 uptime 累积、重启即好”，且有进程计数与父子链实据。那些项（TRIM、Defender、无 swap）仍可能是放大器，但不是主因。

待办（需批准，不在本只读任务执行）：①定位 Paseo/Hermes 侧工具进程生命周期与回收逻辑（为何 npm exec node / python / cua-driver 不随 turn 结束退出），给 file:line；②先做应急回收（确认属残留后批量清理这些堆积工具进程），再做根因修复；③复核当前在跑 agent 是否存在失控重复派工具调用。

---

## 5. 未验证项（诚实标注）

1. journal：uid=998 无权读系统 journal（`journalctl --disk-usage` 返回 insufficient permissions）；仅测得 `/var/log` = 2.3G（其中 `/var/log/journal` 2.3G）。未做按单元统计、未翻上一轮 boot 历史。需 sudo(electerm) 或加入 adm/systemd-journal 组。
2. 未取 `du -xh -d1 /`（A2 空间下钻）——问题已澄清为 I/O，且收尾指令要求立即成稿；该项对 I/O 定位价值低。
3. 未取 nix roots/generations 体积、podman system df、PG pg_wal/autovacuum、coredump、应用 SQLite 增长——均为空间/写入视角，留待抓现行阶段按需要再取。
4. 未取 Windows 宿主侧磁盘/Defender/VHDX 指标（根因 4 缺关键实据）。
5. 当前所有数值仅为"重启后 15 分钟窗口"单点，**无长 uptime 现场样本**，故对根因 2 不能据本次数据下定论。

---

## 5. "抓现行"只读采样方案（现场已清，靠持续观测）

目标：下次再出现 %util 100% 时，能同时拿到 PSI、diskstats 增量、按进程 I/O、D 态、top CPU、内存余量，从而判定是"读颠簸（根因 2）"还是"写放大（根因 3/4）"以及具体进程。

- 写入极小：每样本约 300~800 字节 TSV，默认落 `/tmp/disk-io-sampler/samples.tsv`（tmpfs，重启清空，不留大文件）；如需跨重启保留，将 `STATE_DIR` 指到持久目录（须先批准）。
- 只读来源：`/proc/pressure/*`、`/proc/diskstats`、`/proc/<pid>/io`、`/proc/meminfo`、`ps`。不装依赖、不删任何东西。
- 拟放置位置（待批准，本次写 scripts 被 ACP 审批拒绝，未落盘）：
  - 脚本：`/var/lib/hermes/workspace/projects/our/nixos/scripts/disk-io-sampler.sh`
  - 建议节奏：60s 一次（手动或 timer）；风暴期可临时 `STATE_DIR=/tmp/disk-io-sampler bash <脚本>` 手动连跑。
- 不自行激活 timer；timer 方案见 §5.2，批准后再由声明式/electerm 落地。

### 5.1 采样脚本完整内容（逐字，批准后按上述路径落盘）

```bash
#!/usr/bin/env bash
# disk-io-sampler.sh — 磁盘 I/O 利用率只读采样器（WSL2/NixOS 通用）
# 只读系统状态；不删除、不改配置、不装依赖、不产生大文件。
set -u

STATE_DIR="${STATE_DIR:-/tmp/disk-io-sampler}"
LOG="${LOG:-$STATE_DIR/samples.tsv}"
DEV="${DEV:-sdc}"
WATCH="${WATCH:-postgres hindsight-api mihomo hermes Paseo node}"

mkdir -p "$STATE_DIR"
SNAP="$STATE_DIR/diskstats.prev"

now_epoch="$(date +%s)"
now_iso="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
up_s="$(awk '{printf "%d", $1}' /proc/uptime)"
load="$(awk '{print $1","$2","$3}' /proc/loadavg)"

psi_io="$(awk '/some/{s=$2" "$5} /full/{f=$2" "$5} END{print s" "f}' /proc/pressure/io \
  | sed 's/avg60=//g; s/total=//g')"
psi_mem="$(awk '/some/{s=$2" "$5} /full/{f=$2" "$5} END{print s" "f}' /proc/pressure/memory \
  | sed 's/avg60=//g; s/total=//g')"

mem_avail="$(awk '/MemAvailable:/{print $2}' /proc/meminfo)"
mem_free="$(awk '/MemFree:/{print $2}' /proc/meminfo)"

cur="$(awk -v d="$DEV" '$3==d{print $4,$6,$8,$10,$13,$14}' /proc/diskstats)"
prev="$(cat "$SNAP" 2>/dev/null || true)"
echo "$cur" > "$SNAP"
if [ -n "$prev" ]; then
  set -- $cur; r1=$1; rs1=$2; w1=$3; ws1=$4; busy1=$5; wbusy1=$6
  set -- $prev; r0=$1; rs0=$2; w0=$3; ws0=$4; busy0=$5; wbusy0=$6
  dt=$((now_epoch - ${LAST_TS:-$now_epoch})); [ "$dt" -le 0 ] && dt=1
  d_r=$(( (r1-r0)/dt )); d_rs=$(( (rs1-rs0)/dt ))
  d_w=$(( (w1-w0)/dt )); d_ws=$(( (ws1-ws0)/dt ))
  d_busy=$((busy1-busy0)); d_wbusy=$((wbusy1-wbusy0))
else
  d_r=0; d_rs=0; d_w=0; d_ws=0; d_busy=0; d_wbusy=0
fi
echo "$now_epoch" > "$STATE_DIR/last.ts"

pio=""
for pat in $WATCH; do
  rc=0; wc=0; rb=0; wb=0; n=0
  for p in /proc/[0-9]*; do
    comm="$(cat "$p/comm" 2>/dev/null || true)"
    case "$comm" in *"$pat"*) ;; *) continue;; esac
    vals="$(awk '/^(rchar|wchar|read_bytes|write_bytes):/{print $2}' "$p/io" 2>/dev/null | tr '\n' ' ')"
    [ -z "$vals" ] && continue
    set -- $vals
    rc=$((rc+${1:-0})); wc=$((wc+${2:-0})); rb=$((rb+${3:-0})); wb=$((wb+${4:-0})); n=$((n+1))
  done
  pio="${pio}${pat}:n=${n},rb=${rb},wb=${wb},rc=${rc},wc=${wc};"
done

dstate="$(ps -eo state=,pid=,comm= 2>/dev/null | awk '$1=="D"{printf "%s/%s;",$2,$3}')"
[ -z "$dstate" ] && dstate="-"
topcpu="$(ps -eo pcpu=,comm= --sort=-pcpu 2>/dev/null | head -8 \
  | awk '{gsub(/ /,"",$1); printf "%s:%s%%;",$2,$1}')"

if [ ! -s "$LOG" ]; then
  printf 'epoch\tiso\tuptime_s\tload1_5_15\tio_some_avg60\tio_some_total\tio_full_avg60\tio_full_total\tmem_some_avg60\tmem_full_avg60\tmem_free_kb\tmem_avail_kb\tsdc_read_iops\tsdc_read_sectors_s\tsdc_write_iops\tsdc_write_sectors_s\tsdc_busy_ms_delta\tsdc_weighted_ms_delta\tproc_io_agg\td_state\ttop_cpu\n' >> "$LOG"
fi
set -- $psi_io; io_sa=$1; io_st=$2; io_fa=$3; io_ft=$4
set -- $psi_mem; m_sa=$1; m_st=$2; m_fa=$3; m_ft=$4
printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
  "$now_epoch" "$now_iso" "$up_s" "$load" \
  "$io_sa" "$io_st" "$io_fa" "$io_ft" "$m_sa" "$m_fa" \
  "$mem_free" "$mem_avail" \
  "$d_r" "$d_rs" "$d_w" "$d_ws" "$d_busy" "$d_wbusy" \
  "$pio" "$dstate" "$topcpu" >> "$LOG"
```

判读方法：复现时看 `io_full_avg60` 是否飙高；`sdc_read_sectors_s` 高 = 读颠簸（→根因 2），`sdc_write_sectors_s` 高 = 写放大（→根因 3/4）；`proc_io_agg` 里 rb/wb 最大者即肇事进程组；`mem_avail_kb` 是否同步走低、`mem_full_avg60` 是否升高以确认内存联动。

### 5.2 可选 systemd timer（不激活；批准后以声明式配置实现）

拟用 NixOS 声明式（放入对应 host 配置），每 60s 运行一次、纯追加 tmpfs 日志；`OnBootSec` 可设。service 仅 `ExecStart = ${pkgs.bash}/bin/bash /var/lib/.../disk-io-sampler.sh`，`Type=oneshot`，timer `OnUnitActiveSec=60s`。**本次未写任何 .service/.timer、未激活。**

---

## 6. 待批准修复建议（按根因；分级：可立即做 / 需 sudo(electerm) / 需改声明式配置）

> 以下均未执行。原则：先用 §5 采样确认根因，再动手；与 I/O 无直接关系的"空间清理"不优先。

### 6.1 针对根因 1（开机读风暴）
- 可立即做（无需 sudo）：错峰手动启动非关键服务观察；确认无多余重复 agent/node 常驻（本次见多个 hermes acp 与 Paseo node 并存）[OWNER 核查项]。
- 需改声明式配置：精简开机自启服务/减少并发拉起；必要时对重服务设启动顺序与限流。

### 6.2 针对根因 2（内存压力 / cache 回收颠簸，主诉首选）
- 可立即做（无需 sudo）：下次长 uptime 时先用采样器确认 `mem_avail` 与读 I/O 联动；定位内存持续增长的进程（/proc/<pid>/status VmRSS）。
- 需改声明式配置：为 WSL2 配置/增大 swap（`.wslconfig` 或 NixOS swap 文件），把"无 swap 直接回读"改为可换出；给内存大户设内存上限/定期重启策略；修复确认后的内存泄漏。
- 需 sudo(electerm)：临时为高内存服务做受控重启以缓解（仅在批准后）。

### 6.3 针对根因 3（podman overlay / 容器日志写放大）
- 可立即做（无需 sudo，只读先评估）：`podman system df`、`podman ps`、查容器日志驱动配置。
- 需 sudo(electerm)：配置容器日志轮转/大小上限（`--log-opt max-size/max-file` 或 containers.conf）；清理悬挂卷/层（**属删除操作，CRITICAL，须单独批准并先盘点**）。
- 需改声明式配置：在 NixOS podman/容器声明中固化日志轮转与 log-driver。

### 6.4 针对根因 4（PG WAL / autovacuum / Hindsight）
- 可立即做（只读）：经本地连接查 `pg_wal` 大小、`pg_stat_activity`、autovacuum 与保留配置（不输出连接串/口令）。
- 需改声明式配置/服务配置：调整 WAL 保留、checkpoint、autovacuum 参数与 Hindsight 写入批量化；评估备份策略。
- 需 sudo(electerm)：重启/维护 PG 容器（批准后）。

### 6.5 针对根因 5（Windows 宿主 VHDX / Defender）
- 需在 Windows 侧（xavier 管理员执行，命令原文报批）：将 WSL VHDX 所在目录加入 Defender 排除项、确认宿主磁盘类型、用 typeperf/资源监视器对齐 guest I/O；评估 VHDX 扩容策略。**不改 guest 声明。**

### 6.6 针对根因 6（崩溃循环 / coredump）
- 需 sudo(electerm)：`coredumpctl list`、查 `/var/lib/systemd/coredump` 与崩溃单元；启用 journald 存储限额（`SystemMaxUse` 等）以防日志写放大——**限 journald 为写放大型防护，需声明式配置固化**。

---

## 7. 命令与环境索引（便于复跑核盘）

- 环境/块设备：`uname -a`、`uptime`、`lsblk -o NAME,SIZE,TYPE,MOUNTPOINT,FSTYPE,ROTA`
- 空间/inode：`df -h`、`df -i /`
- 内存/swap：`free -h`、`swapon --show`、`cat /proc/sys/vm/swappiness`
- 压力：`cat /proc/pressure/{io,memory,cpu}`
- 设备 I/O：`grep ' sdc ' /proc/diskstats`、`vmstat 1 3`
- 进程：`ps -eo pid,ppid,stat,comm,args --sort=-pcpu`
- 日志（受限）：`journalctl --disk-usage`（uid998 无权）、`du -xh -d1 /var/log`
- 容器：`podman version`（system df 未取）

> 本报告不含任何 secret/连接串/凭据。所有数值来自 2026-09-30 重启后约 15 分钟窗口的真实命令输出；未取到的项已在 §4 明确标注 [UNCERTAIN] 及原因。
