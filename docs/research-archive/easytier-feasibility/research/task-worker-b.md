# Worker B 任务书：EasyTier 部署成本、NixOS 打包、许可证与成熟度生态

## 背景（你无本会话上下文，先读这些）
- 我们在 NixOS 环境用 Tailscale 组网，现调研 EasyTier 可行性：需要 NixOS 上的部署方式、与 Tailscale 共存、许可证与成熟度。
- EasyTier 源码已克隆（只读）：
  `/var/lib/hermes/.paseo/worktrees/0tnh6fc8/research-easytier-feasibility/research/easytier-src`
  commit ff3921ce6842f9660d629eafac499498026c6784（2026-09-24 上游 main）。
- 根目录有 `flake.nix`（经初步查看只是开发环境 flake-utils shell，非 NixOS 模块——你需确认这一判断并查全文件）。
- 本仓库就是我们的 NixOS 配置仓库（flake + hosts/ + modules/），可从中了解我们的约定：参考 hosts/raiyun2/（现有 Tailscale DERP 部署形态），但**禁止修改任何文件**。

## 必须回答的问题（每条结论必须给证据：file:line / 完整 URL + 原文引句）
1. NixOS/Nixpkgs 打包现状：nixpkgs 中是否已有 easytier 包或 NixOS 模块？用 web_search + Playwright 真实打开 search.nixos.org（packages/options 两个搜索）与 GitHub nixpkgs 相关 PR/issue 实证；若有，版本、维护状态、服务名。社区（GitHub issue/discussions、第三方 NixOS module）现状也要查。
2. 部署形态：二进制/包/Docker 有哪些（查上游 README、docs、release 资产、easytier/Dockerfile 之类）；服务端与客户端是否同一个二进制（easytier-cli？easytier-core？从 easytier/src main 与 Cargo.toml 实证）；配置方式（CLI flags / TOML 文件，列出与"纯 TCP 公共中继节点"相关的最小参数集，参数名以源码/--help 文档实证，不得编造）。
3. NixOS 最小落地方案的工作量评估：若 nixpkgs 无包，自建打包要包哪些 crate/二进制、Rust 打包在 nixpkgs 的常规做法（rustPlatform.buildRustPackage）、systemd 服务需要什么能力（CAP_NET_ADMIN/tun）；给出"需要新建哪些文件"的清单级评估（只写评估，不实施）。
4. 与 Tailscale 共存：EasyTier 默认虚拟网段、TUN 设备名、是否占用 100.64.0.0 网段、是否会与 tailscale0 路由冲突（从源码 config 默认值实证）；同时运行的注意事项（subnet 路由、DNS、出口节点）。
5. 许可证：根目录 LICENSE 实际是什么协议（LGPL-3.0/Apache-2.0/其他？读原文），各 crate 是否一致，商业/内部使用限制与传染性评估。
6. 成熟度与生态：star 数、发版节奏（最近 release 列表与日期）、open issue 数量级、是否有公司/商业实体支持、是否在积极维护——全部从 GitHub 页面实读（Playwright 打开 github.com/EasyTier/Easytier 及 releases 页），不许只凭印象。
7. 性能：仓库/官方文档中有无 benchmark 数据（吞吐/延迟、对比 WireGuard/Tailscale），如实引述出处与数字；没有就标"未找到"。

## 取证规则
- 本地结论用 search_files/read_file，标 `相对路径:行号`。
- 网页必须用 Playwright MCP（browser_navigate → browser_snapshot/browser_evaluate 实读 innerText）真实打开；每来源记录 完整URL + 原文引句；打不开就写"未能打开"并换源，禁止引用搜索摘要。
- 若 Playwright 在你的环境不可用，立即停止并回报 PLAYWRIGHT_UNAVAILABLE，不许静默降级。
- 推断标 [UNCERTAIN]，禁止编造。

## 边界（红线）
- 只读；唯一允许写入目录：`/var/lib/hermes/.paseo/worktrees/0tnh6fc8/research-easytier-feasibility/research/out/`（先 mkdir -p）。
- 禁止：cargo/nix 构建、拉 nixpkgs 二进制试装、重启任何服务、改 Tailscale/雨云配置、写 worktree 外路径。
- 工具调用预算 ≤28 次；边查边写，每答完一题即追加落盘。

## 输出契约
- 报告：/var/lib/hermes/.paseo/worktrees/0tnh6fc8/research-easytier-feasibility/research/out/worker-b-deployment.md
- 结构：逐题回答（证据齐全）→ 来源清单表（编号|URL|Playwright是否实开|一句原文引述）→ NixOS 落地工作量评级（小/中/大，附理由）→ 未验证项。
- 写完自行 read_file 验证落盘；最终回报给报告路径 + 3-5 句结论摘要。
