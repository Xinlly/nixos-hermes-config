# 为 Paseo daemon 注入云端 ASR（SiliconFlow）环境变量 — NixOS 正确写法

- 日期：2026-10-01
- 性质：**只读取证 + 待批准方案**（本次未改任何配置、未 rebuild、未重启、未写密钥）
- 目标机：本机 WSL NixOS（主机名 `nixos`，flake 属性 `nixosConfigurations.nixos`），Paseo daemon 以 `hermes`(uid 998) 身份运行
- 上游 Paseo：`github:getpaseo/paseo` @ `da8c1b5c94e752b01d451645e5fa52aba2c1b2f0`（0.8.0-beta.1），本机源码 `/nix/store/x77wjz3hjb3p4gznr8l931hk1c9zi0ql-source`

---

## 0. 结论（TL;DR）

1. Paseo daemon 的 systemd 单元名 = **`paseo.service`**，由上游 nixos 模块 `nix/module.nix` 生成；当前**没有** `EnvironmentFile` / `LoadCredential`，也**没有**任何文件系统/命名空间加固（无 `ProtectSystem`/`ProtectHome`/`ReadWritePaths`）。
2. 密钥的正确落地方式：在本地 `modules/paseo.nix` 给单元加 **`serviceConfig.EnvironmentFile = [ "/var/lib/hermes/.paseo/secret.env" ]`**，密钥文件本身放在 dataDir 内、`chmod 600`、属主 `hermes:hermes`，**由人工另行创建，不进 `/etc/nixos` 源码、不进 `/nix/store`、不进 git**。
3. 非密钥变量（baseURL / model / provider 选择）放进声明式 `services.paseo.environment`（类型 `attrsOf str`），随单元可重建、可审计；只有 `OPENAI_STT_API_KEY` 放 EnvironmentFile。
4. 激活：改完需 `nixos-rebuild switch`（写 boot）或先 `test`；因环境变量只在进程启动时读取，**必须 restart `paseo.service`**（`reload` 对环境变量无效）。restart 会中断 daemon 上正在运行的 agent turn。

---

## 1. 定位 daemon 单元（file:line 实据）

### 1.1 本地声明式入口
- `/etc/nixos/modules/paseo.nix`（72 行）设置 `services.paseo`：
  - `enable = true`（:13）
  - `user = "hermes"` / `group = "hermes"`（:17-18）
  - `dataDir = "/var/lib/hermes/.paseo"`（:19）
  - `listenAddress = "0.0.0.0"`（:23）
  - `inheritUserEnvironment = true`（:26）
  - `settings`（:35-70）渲染为 `config.json`，其中 `daemon.mcp.injectIntoAgents = true`（:43）
  - **该文件当前未设置任何 `environment`、`EnvironmentFile`、`LoadCredential`。**

### 1.2 上游模块如何生成单元
上游 nixos 模块 = `/nix/store/x77wjz3hjb3p4gznr8l931hk1c9zi0ql-source/nix/module.nix`（293 行）：

- 选项 `services.paseo.environment`，`type = lib.types.attrsOf lib.types.str`，`default = {}`，描述 "Extra environment variables for the Paseo daemon."（**module.nix:157-166**）
- 单元定义 `systemd.services.paseo`（**module.nix:223**），其 `environment` 在末尾用 `// cfg.environment` 合并用户自定义变量（**module.nix:268**）。
- `serviceConfig`（**module.nix:270-285**）只设了：`Type=simple`、`User`、`Group`、`ExecStart`、`Restart=on-failure`、`RestartSec=5`、`KillSignal=SIGTERM`、`TimeoutStopSec=15`。
  - **没有** `EnvironmentFile`、`LoadCredential`、`ProtectSystem`、`ProtectHome`、`ProtectKernelTunables`、`PrivateTmp`、`ReadWritePaths`、`BindReadOnlyPaths` 等任何加固项。
- 单元的 `preStart`（**module.nix:228-230**）：`install -m 0600 <渲染的 paseo-config.json> ${cfg.dataDir}/config.json` —— 这就是每次开机 `~/.paseo/config.json` 被覆盖的原因，故密钥不能写进 config.json。
- dataDir 由 systemd-tmpfiles 保证存在：`"d ${cfg.dataDir} 0700 ${cfg.user} ${cfg.group} - -"`（**module.nix:219-221**），即 `/var/lib/hermes/.paseo` 权限 `0700 hermes:hermes`。

### 1.3 运行态单元实测（本次只读）
`systemctl cat paseo` 输出（单元为符号链接到当前代 store）：
- `User=hermes` / `Group=hermes`
- 现有 `Environment=` 仅：`LOCALE_ARCHIVE`、`PASEO_HOME=/var/lib/hermes/.paseo`、`PASEO_LISTEN=0.0.0.0:6767`、`PATH=...`、`TZDIR`
- `ExecStartPre=.../paseo-pre-start`；`ExecStart=.../paseo-0.8.0-beta.1/bin/paseo-server`
- **无 EnvironmentFile / LoadCredential / 加固指令**；`systemctl is-active paseo` = `active`

---

## 2. STT 读取的环境变量（源码核实，含一处重要修正）

> 任务描述给的变量名，与源码逐一核对结果如下。**STT 专用键确实存在**；但要注意该版本还内置了到 `OPENAI_API_KEY` 的回退。

证据：`packages/server/src/server/speech/providers/openai/config.ts`

- STT API Key 解析顺序（**config.ts:130-135**）：
  `persisted.providers.openai.stt.apiKey` → **`env.OPENAI_STT_API_KEY`** → `persisted.providers.openai.apiKey` → **`env.OPENAI_API_KEY`**
- STT BaseURL 解析顺序（**config.ts:136-141**）：
  `persisted...stt.baseUrl` → **`env.OPENAI_STT_BASE_URL`** → `persisted...baseUrl` → **`env.OPENAI_BASE_URL`**
- STT 模型（**config.ts:94-98**）：**`env.STT_MODEL`** 优先，其次 voice/dictation 在 config.json 里的模型。
- 空字符串/纯空白不会遮蔽后续回退（**config.ts:73-77**）。
- Provider 选择（`packages/server/src/server/speech/speech-config-resolver.ts`）：
  - 听写(dictation)：**`env.PASEO_DICTATION_STT_PROVIDER`** 优先（:75-79）
  - 语音对话(voice)：**`env.PASEO_VOICE_STT_PROVIDER`** 优先（:94-98）
  - 二者都取环境变量、其次 config.json。

由此，SiliconFlow 走 OpenAI 兼容协议所需的最小集合：

| 变量 | 值 | 是否敏感 |
|---|---|---|
| `OPENAI_STT_API_KEY` | SiliconFlow 密钥（占位 `PASTE_REAL_KEY`） | **是** |
| `OPENAI_STT_BASE_URL` | `https://api.siliconflow.cn/v1` | 否 |
| `STT_MODEL` | `FunAudioLLM/SenseVoiceSmall` | 否 |
| `PASEO_DICTATION_STT_PROVIDER` | `openai`（听写模式） | 否 |
| `PASEO_VOICE_STT_PROVIDER` | `openai`（语音对话模式，需要时） | 否 |

[UNCERTAIN] 任务描述未提到，但同一 OpenAI 语音链路还提供 TTS；本次只配 STT，不设置 `OPENAI_TTS_*` / `TTS_*`，避免影响 TTS 现状。

---

## 3. 密钥注入方式：方案对比

### 方案 A（推荐）：`EnvironmentFile=` 指向 dataDir 内的独立密钥文件

- 在 nix 里**只引用路径**，文件内容人工创建 → 密钥不进 `/etc/nixos`、不进 `/nix/store`、不进 git。
- 放 dataDir 内 `/var/lib/hermes/.paseo/secret.env` 的理由：
  1. 该目录已由 tmpfiles 保证存在且为 `0700 hermes:hermes`（module.nix:219-221），无需新建目录；
  2. 单元以 `User=hermes` 运行，是该目录属主，可直接读；
  3. 当前单元无 `ProtectSystem`/`ProtectHome`/`ReadWritePaths`，任何路径都可读；即便将来加了 `ProtectSystem=strict`，dataDir 属状态目录、加 `ReadWritePaths`/`BindPaths` 也最自然。
- EnvironmentFile 用列表形式且路径前不加 `-`：文件缺失会让单元启动失败（fail-fast，避免静默以错误凭证运行）。若希望缺失时仍能启动，可加 `-` 前缀，但**不推荐**（会掩盖配置遗漏）。

### 方案 B（备选）：`LoadCredential=` + `SetCredentialEncrypt`

- systemd 凭据目录（`CREDENTIALS_DIRECTORY`）在单元命名空间内挂载，进程从该路径读密钥；配合 `systemd-creds encrypt` 可把密文落在磁盘（`LoadCredentialEncrypted`）。
- 在本环境的评估：
  - 可行，但要求 paseo-server 的配置改为从凭据文件读取（或加 wrapper/`ExecStartPre` 把凭据导出为环境变量）。上游模块与 paseo-server **当前只认环境变量**，没有"从凭据文件读 key"的入口，需额外胶水。
  - 优点是静态密文、与单元生命周期绑定更严格；缺点是配置明显更复杂，且要引入上游不感知的 wrapper，违背 KISS。
- 结论：当前上游以环境变量为唯一注入面，**方案 A 更简单、可直接落地**；方案 B 适合将来对密钥静态落盘有硬性合规要求时再评估。

### 为什么不用 `services.paseo.environment` 直接写密钥
该选项内容会进入单元定义 → `/nix/store`（全局可读），任何能读 store 的用户都能拿到密钥。**禁止**把明文密钥写进 `cfg.environment` 或任何 nix 文件。

---

## 4. 推荐方案完整 nix 片段（只含路径引用，无明文）

在 `/etc/nixos/modules/paseo.nix` 的 `services.paseo = { ... }` 内追加（即现有 `relay = {...};` 与 `settings = {...}` 同级）：

```nix
    # 非敏感 STT 配置：走声明式环境变量（attrsOf str），可重建可审计
    environment = {
      OPENAI_STT_BASE_URL = "https://api.siliconflow.cn/v1";
      STT_MODEL = "FunAudioLLM/SenseVoiceSmall";
      PASEO_DICTATION_STT_PROVIDER = "openai";
      # 需要语音对话模式时再打开：
      PASEO_VOICE_STT_PROVIDER = "openai";
    };

    # 密钥只引用路径；文件由人工创建，不进 nix/git/store
    systemd.services.paseo.serviceConfig.EnvironmentFile =
      [ "/var/lib/hermes/.paseo/secret.env" ];
```

说明：
- `services.paseo.environment` 会在上游 module.nix:268 合并进单元 environment。
- `EnvironmentFile` 在 nixos 模块之外、于本地配置里直接设置 `systemd.services.paseo.serviceConfig`，与上游不冲突（上游未定义该键）。
- 密钥文件只需提供 `OPENAI_STT_API_KEY` 一行；baseURL/model/provider 已由声明式 environment 提供（同一变量 EnvironmentFile 也可，但非密钥没必要）。

---

## 5. 密钥文件创建步骤（人工执行，命令中不含真实值）

EnvironmentFile 是 systemd 原生 KEY=VALUE 解析（非 shell），无需 export、不要在等号两侧加空格。

建议由有权限的账户（经 electerm，用 sudo 落 hermes 属主文件）执行：

```sh
# 1) 写入密钥（把 PASTE_REAL_KEY 换成真实 SiliconFlow key；建议用交互式编辑器避免进 shell 历史）
sudo install -d -o hermes -g hermes -m 700 /var/lib/hermes/.paseo
sudo tee /var/lib/hermes/.paseo/secret.env >/dev/null <<'EOF'
OPENAI_STT_API_KEY=PASTE_REAL_KEY
EOF
sudo chown hermes:hermes /var/lib/hermes/.paseo/secret.env
sudo chmod 600 /var/lib/hermes/.paseo/secret.env

# 2) 校验（不打印值）：只看权限/属主/键名与长度
sudo stat -c 'mode=%a owner=%U:%G size=%s' /var/lib/hermes/.paseo/secret.env
sudo awk -F= '{print $1"=<len:"length($2)">"}' /var/lib/hermes/.paseo/secret.env
```

预期：`mode=600 owner=hermes:hermes`，键名 `OPENAI_STT_API_KEY=<len:N>`（N 为真实 key 长度）。

> 更安全的录入方式：`sudo -u hermes nano /var/lib/hermes/.paseo/secret.env` 手工粘贴，避免密钥进入 here-doc/命令历史；本任务未执行任何创建动作。

---

## 6. 激活方式、影响与验证

### 6.1 激活（二选一，均需 sudo；本任务均未执行）
- 先试激活（不写 boot）：
  ```sh
  sudo nixos-rebuild --flake /etc/nixos#nixos test
  ```
- 确认无误后持久化：
  ```sh
  sudo nixos-rebuild --flake /etc/nixos#nixos switch
  ```
- **环境变量仅在进程启动读取，必须 restart 单元**（`paseo reload` / daemon 热加载不会重建进程环境）：
  ```sh
  sudo systemctl restart paseo
  systemctl is-active paseo          # 期望 active
  ```

> 注意：当前 `nixos-rebuild test` 在本机存在一个**独立的已知阻塞**——`user@998.service`(hermes 用户管理器) 当前 inactive，导致 "reloading user units for hermes" 失败、退出码 4。这与本 ASR 方案无关；做 rebuild 前需先 `sudo systemctl start user@998`（另案待批准）。

### 6.2 验证 daemon 真读到了（只读）
```sh
# 单元最终生效的环境（确认非密钥三项 + EnvironmentFile 行；不打印 key 值）
systemctl show paseo -p Environment
systemctl show paseo -p EnvironmentFiles

# 进程视角确认变量存在（值打码）
PID=$(systemctl show paseo -p MainPID --value)
sudo tr '\0' '\n' < /proc/$PID/environ | grep -E 'OPENAI_STT_BASE_URL|STT_MODEL|STT_PROVIDER'
sudo tr '\0' '\n' < /proc/$PID/environ | sed -E 's/(OPENAI_STT_API_KEY=).*/\1<REDACTED>/' | grep OPENAI_STT_API_KEY
```
端到端确认：在 Paseo 客户端用听写/语音对话录入一句中文，确认返回中文转写，即 SiliconFlow(SenseVoiceSmall) 链路打通。SenseVoiceSmall 原生支持中文，可直接验证此前"英文-only"是否因未配置云端 STT 而回退到本地英文模型。

### 6.3 对在跑 agent 的影响
- `restart paseo` 会终止 daemon 进程；当前正在进行的 agent turn / 未完成工具调用会被打断，已落盘状态不丢，但需重发任务。建议在无关键任务时操作。
- 不影响 config.json、agent 注册与 worktree。

---

## 7. 精确回滚步骤

1. 移除 nix 中本次新增块（`services.paseo.environment` 与 `EnvironmentFile` 两行），重跑：
   ```sh
   sudo nixos-rebuild --flake /etc/nixos#nixos switch
   sudo systemctl restart paseo
   ```
   daemon 即回到未注入状态（STT 回退到其默认/本地提供方）。
2. 可选删除密钥文件：
   ```sh
   sudo rm -f /var/lib/hermes/.paseo/secret.env
   ```
   （删除前确认无其它单元引用该路径。）
3. 因为密钥从未进入 nix/store/git，回滚不涉及 store 历史清理；若密钥曾被泄露到日志，应在 SiliconFlow 控制台轮换该 key。

---

## 8. 未证实项 / 边界

- [UNCERTAIN] 本报告仅静态核实配置键与读取逻辑，**未实际创建密钥、未 restart、未做中文转写端到端实测**；端到端需在批准并执行第 5-6 步后验证。
- [UNCERTAIN] SiliconFlow 的 `https://api.siliconflow.cn/v1` 对 OpenAI `/audio/transcriptions` 的兼容细节（多 part 字段、响应 JSON 形态）未在本次实测；SenseVoiceSmall 的中文能力为模型公开规格，实际以第 6.2 节实测为准。
- 本机出网：SiliconFlow 为国内服务，应**直连不走代理**（本机默认对被墙国外站才走 35353）；paseo-server 是否继承 proxy 环境变量需在激活时确认，避免把国内请求误走代理。
- 本方案只覆盖 STT，不改变 TTS 与 relay 配置。
