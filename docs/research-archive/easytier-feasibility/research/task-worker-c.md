# Worker C 任务书：EasyTier 官方文档 Windows 安装与配置实读取证

## 背景
我们规划用「Windows 宿主机（江苏移动公网出口）+ 一台新雨云机器（共享 NAT，仅 TCP 入站）」实测 EasyTier。需要官方文档对 Windows 安装步骤、CLI/TOML 配置、服务运行方式的一手说明。你无会话上下文，关键源码结论已钉死（见下），勿重复调研。

## 红线
- 只读；不下载安装、不运行任何 EasyTier、不改本机配置。
- 只做网页实读与落盘；所有产物落 `/var/lib/hermes/.paseo/worktrees/0tnh6fc8/research-easytier-feasibility/research/out/`。
- 工具预算 ≤18 次调用。每读完一页立即把条目追加写入报告（边查边写）。

## 实读硬约束（必须遵守，否则不合格）
1. 必须用 **Paseo Playwright MCP**（browser_new_tab / browser_navigate → browser_snapshot / browser_evaluate 取 document.body.innerText）真实打开每个页面读正文；**禁止用 web_search 摘要充当已读**。
2. 至少真实打开 **4 个页面**：
   - 官网首页 https://www.easytier.cn/ （找到文档/下载入口并记录真实跳转 URL）；
   - Windows 平台安装/下载/使用说明页（从官网或 GitHub README 的文档链接找，至少 1 页中文文档）；
   - 手动组网/CLI 参数或 TOML 配置说明页（easytier-core 的 -i/-p/--listeners/--network-name/--network-secret/relay 相关，至少 1 页）；
   - 再补 1 页（Docker / 公共节点说明 / 常见问题 FAQ 任一）。
3. 每来源记录：完整 URL + Playwright 是否成功打开 + **打开后看到的原文关键句照抄（不改写）** + 与 Windows 部署相关的具体步骤/命令。打不开的页面如实记"未能打开"并换页补足，不得引用其搜索摘要。
4. 若 Playwright MCP 在你环境不可用，立即停止并回报 `PLAYWRIGHT_UNAVAILABLE`，禁止降级为摘要拼凑。

## 已钉死、可直接引用的事实（源码+release 实证，不用重查）
- release v2.6.4 Windows x86_64 zip 内含：easytier-core.exe、easytier-cli.exe、easytier-web.exe、easytier-web-embed.exe、wintun.dll、WinDivert64.sys、Packet.dll（已下载解包核查）。
- TCP/WS/WSS 建连全程不经 UDP（connectivity/protocol/mod.rs:25）；中继逐包转发、默认开（peers/peer_manager.rs:3078-3112、config/toml.rs:42,72）。
- nixos-unstable nixpkgs 含 easytier 2.6.4 包与 services.easytier 模块（ipv4 空=纯转发无 TUN，module.nix:72-81）。

## 输出契约
- 报告写到 `/var/lib/hermes/.paseo/worktrees/0tnh6fc8/research-easytier-feasibility/research/out/worker-c-docs.md`，结构：
  来源清单表（编号|URL|Playwright是否实开|原文引述一句）→ 逐页要点（Windows 安装步骤、配置项、运行命令，均原文引述+URL）→ 官方文档与源码事实不一致处 → 未能打开的页面。
- 落盘后自行 read_file 验证，最终回报：报告路径 + 4 个页面是否全部实开 + 一句话摘要。
