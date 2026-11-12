# Worker C 报告：EasyTier 官方文档 Windows 安装与配置实读取证

> 取证时间：2026-09-27。取证方式：Paseo Playwright MCP（browser_new_tab / browser_navigate / browser_evaluate 取 document.body.innerText）真实打开页面，下列引述均为页面正文原文照抄。
> 任务书：research/task-worker-c.md。仅做只读网页实读，未下载、未安装、未运行任何 EasyTier。

## 一、来源清单表

| 编号 | URL | Playwright 是否实开 | 原文引述一句 |
|---|---|---|---|
| 1 | https://www.easytier.cn/ （打开后实际落地 https://www.easytier.cn/index.html） | 是（browserId e9a913ce-59a0-4be2-8fc8-0520fbec6531） | "✨ 一个简单、安全、去中心化的异地组网方案" |
| 2 | https://www.easytier.cn/guide/download.html | 是 | "命令行程序的压缩包中包含四个可执行程序：easytier-core：EasyTier 的核心程序" |
| 3 | https://www.easytier.cn/guide/installation.html | 是（首次 navigate 超时，重试后成功并读到正文） | "下载后为 ZIP 压缩包，解压后既可直接使用。" |
| 4 | https://www.easytier.cn/guide/network/quick-networking.html | 是 | "当没有公网 IP 时，可使用共享节点快速组网……P2P 失败时由共享节点中转数据。" |
| 5 | https://www.easytier.cn/guide/network/config-file.html | 是 | "支持使用 -c 参数指定配置文件路径。" |
| 6 | https://www.easytier.cn/guide/faq.html | 是 | "Q：一定需要WEB控制台吗？ A： EasyTier 是去中心化的，所以其没有也不需要一个类似 ZeroTier、Tailscale 的中心控制面板来管理所有设备。" |

硬约束要求 ≥4 页，本报告实开 6 页（官网首页 + Windows 相关下载/安装中文页 2 页 + CLI 参数页 + TOML 配置页 + FAQ 页）。

## 二、逐页要点

### 第 1 页：官网首页
- URL：https://www.easytier.cn/ → 实际落地 https://www.easytier.cn/index.html
- title："EasyTier - 简单、安全、去中心化的异地组网方案"
- 文档/下载入口（真实跳转 URL，从页面 `<a href>` 取得）：
  - "快速开始" → https://www.easytier.cn/guide/introduction.html
  - "下载" → https://www.easytier.cn/guide/download.html
  - "Web 控制台" → https://www.easytier.cn/web.html
  - "配置助手" → https://easytier.cn/assistant/
  - "变更日志" → https://github.com/EasyTier/EasyTier/releases
- 平台与协议原文：
  - "跨平台 支持 Win / MacOS / Linux / FreeBSD / Android 兼容 X86 / ARM / MIPS 架构"
  - "高性能 全链路零拷贝 支持 TCP / UDP / WS / WSS / WG / QUIC / FakeTCP 等协议"

### 第 2 页：下载页（Windows 下载实证）
- URL：https://www.easytier.cn/guide/download.html（页内标注"最后更新于: 2026/9/6 18:26:21"）
- 当前版本："稳定版(v2.6.4)"，与任务书钉死的 release v2.6.4 一致。
- 压缩包构成原文：
  > "命令行程序的压缩包中包含四个可执行程序：
  > easytier-core：EasyTier 的核心程序
  > easytier-cli：EasyTier 管理程序，启动 easytier-core 后，可以使用 easytier-cli 查看虚拟网信息
  > easytier-web: 用于自建 EasyTier 的 Web 控制台后端，一般情况下无需自建，使用官方提供的 Web 控制台即可
  > easytier-web-embed: 与 easytier-web 功能相同，但内置了 Web 前端。"
- Windows 行原文（下载表格）：
  > "Windows x86_64 exe zip Windows 7 需要是 SP1 及以上, 并且需要安装 KB3063858、KB4474419 这两个补丁，并关闭 QUIC 输入。"
  > "Windows arm64 exe zip"
- Windows x86_64 真实下载链接（页面 href 原文）：
  - GUI：https://github.com/EasyTier/EasyTier/releases/download/v2.6.4/easytier-gui_2.6.4_x64-setup.exe
  - CLI zip：https://github.com/EasyTier/EasyTier/releases/download/v2.6.4/easytier-windows-x86_64-v2.6.4.zip
- 页内提供 GitHub 加速通道原文："Github 加速 直连 https://ghfast.top/ https://v6.gh-proxy.org/ https://hk.gh-proxy.org/ https://cdn.gh-proxy.org/ https://edgeone.gh-proxy.org/"（江苏移动出口拉 GitHub 资源时可走加速）。
- 总入口原文："您可以直接前往 GitHub Release 页面 查看所有版本的下载链接"（→ https://github.com/EasyTier/EasyTier/releases）。

### 第 3 页：安装 CLI（Windows 安装步骤）
- URL：https://www.easytier.cn/guide/installation.html
- Windows 安装方式原文：
  > "手动下载命令行程序
  > 访问 ⬇️下载页面 下载适用于您操作系统和硬件架构的 EasyTier 命令行程序。下载后为 ZIP 压缩包，解压后既可直接使用。"
- 页内有 "Linux / MacOS / FreeBSD / Windows" 切换标签；解压后验证命令原文：`./easytier-core --version`
- 同页 Docker 方式原文（与第 4 类补充页相关）：
  > "docker pull easytier/easytier:latest
  > docker run -d --privileged --network host easytier/easytier:latest
  > # 国内用户可以使用 DaoCloud 镜像
  > docker pull m.daocloud.io/docker.io/easytier/easytier:latest"
- 同页另有：Docker Compose 安装（配置放 ./conf/easytier.toml，"修改 ./conf/easytier.toml 后，执行 docker compose restart easytier 重新加载配置"）、一键脚本（"一键安装脚本（仅 Linux）"，Windows 不适用）、源码安装 `cargo install --git https://github.com/EasyTier/EasyTier.git easytier`（"源码安装需要 Rust 环境，并且安装 LLVM"）。
- 对我们场景的含义：Windows 宿主机上官方安装路径 = 下载 zip → 解压 → 管理员权限直接跑 exe，无安装器、无系统依赖步骤（wintun.dll 等已在包内，见任务书钉死事实）。
- 侧栏还存在官方服务化页面链接（本次未逐页打开）："安装为 Windows 服务" → https://www.easytier.cn/guide/network/install-as-a-windows-service.html；"一键安装服务" → https://www.easytier.cn/guide/network/oneclick-install-as-service.html。

### 第 4 页：快速组网（CLI 参数实读）
- URL：https://www.easytier.cn/guide/network/quick-networking.html
- 场景前提原文："当没有公网 IP 时，可使用共享节点快速组网，共享节点的搭建请参考搭建共享节点。节点间会自动尝试 NAT 穿透并建立 P2P 连接，P2P 失败时由共享节点中转数据。"
- 节点 A/B 运行命令原文（页内有 "Linux / Windows" 标签，命令一致；标注 "# 管理员权限运行"）：
  ```
  ./easytier-core -d --network-name abc --network-secret abc -p tcp://<共享节点 IP或域名>:1010
  ```
- 参数解释原文（逐字照抄）：
  - "-d 自动分配虚拟 IP，默认分配 10.126.126.0/24 网段，可使用 -i 10.11.11.0/24 指定其他虚拟 IP。"
  - "--network-name 指定虚拟网络名称（支持中文）。注意：若与其他用户网络名冲突，可能导致组网失败。"
  - "--network-secret 指定虚拟网络的密码，用于保护网络安全。"
  - "-p 指定节点地址，"（原文此处句子在 tab 切换处截断；下文示例补全为 `-p tcp://...`）
  - "-l 指定监听端口。"
- 多共享节点原文："为提升可用性，可同时连接多个共享节点，只需指定多个 -p 参数：`-p tcp://1.1.1.1:11010 -p udp://1.1.1.2:11011` 建议所有节点指定相同的共享节点列表。"
- 多实例原文："EasyTier 支持同一设备运行多个进程，每个进程加入不同虚拟网。……启动多个实例时需指定不同监听端口"，示例：
  ```
  ./easytier-core --network-name net1 -p tcp://<共享节点 IP或域名>:1010 -l 11010
  ./easytier-core --network-name net2 -p tcp://<共享节点 IP或域名>:1010 -l 21010
  ```
- 状态查看命令原文：`easytier-cli peer`（节点信息）、`easytier-cli route`（路由）、`easytier-cli node`（本节点）。
- 连通性测试原文：`ping 10.126.126.1` / `ping 10.126.126.1`；"如无法 ping 通，可能是防火墙阻止入站流量。请关闭防火墙或添加放行规则。"
- 对我们场景的关键支撑：官方示例即用 `-p tcp://<共享节点 IP或域名>:1010` 纯 TCP 接入共享节点，与"雨云机仅 TCP 入站"的约束相容；监听侧用 `-l <端口>` 暴露 TCP 监听。

### 第 5 页：配置文件（TOML）
- URL：https://www.easytier.cn/guide/network/config-file.html
- 原文要点（逐字照抄）：
  - "支持使用 -c 参数指定配置文件路径。" 示例：`easytier-core -c ./config.yaml`
  - "注意：配置文件中的参数可以被命令行覆盖，比如配置文件中指定了 --hostname abc，但在命令行中使用 --hostname xyz，则会使用命令行中的主机名参数 xyz。"
  - "使用参数运行可以获得对应参数的配置文件。配置文件会打印在命令行中，可以手动复制对应配置保存为toml文件即可。"
  - "在不使用参数的情况下直接运行 easytier-core 可以获得最小配置文件。"
  - "多配置文件启动……可以通过 -c 参数指定多个配置文件，EasyTier 会在一个进程中加载多个配置文件并启动多个虚拟网络。" 示例：`easytier-core -c ./config1.yaml -c ./config2.yaml`
  - 配置助手：https://easytier.cn/assistant/ ，"按需生成配置文件，然后通过 -c 参数加载：`easytier-core -c ./config.toml`"
- 注意：官方示例中文件扩展名 yaml/toml 混用（见第三节不一致点）。
- listeners/relay 等 TOML 字段名本页未逐一列出；官方获取完整字段的办法是"使用参数运行可以获得对应参数的配置文件"（即跑 `easytier-core <CLI 参数>` 打印对应 TOML）。本次未实开 configurations.html / host-public-server.html，不引用其内容。

### 第 6 页：常见问题 FAQ
- URL：https://www.easytier.cn/guide/faq.html
- 实开状态：成功打开并读取正文（title="常见问题 | EasyTier - 简单、安全、去中心化的异地组网方案"，页内标注"最后更新于: 2026/9/6 18:26:21"）。
- 与 Windows 部署直接相关的原文条目：
  > "Q：Windows 7 无法创建网络，程序崩溃或者报错无法创建虚拟网？
  > A： Windows 7 需为 SP1 及以上版本，并安装以下补丁：KB3063858 KB4474419"
- 与监听/端口冲突（雨云共享节点侧相关）原文：
  > "Q：启动后报错 Address already in use？
  > A： 可能是端口冲突。请检查 11010 端口或启动参数指定的端口（如 -l tcp:12345）是否被其他程序占用。"
  > "Q：如何启动多个实例？ A：……只要设置监听器 (listener) 的端口没有与其他已启动的实例冲突即可。如果设置了 rpc，也需要保证端口不冲突。"
- 与 Web 控制台/去中心化相关原文：
  > "Q：一定需要WEB控制台吗？ A： EasyTier 是去中心化的，所以其没有也不需要一个类似 ZeroTier、Tailscale 的中心控制面板来管理所有设备。"
  > "网络名称 + 网络密码 完全相同才能成功建立网络，传递有效信息。"
- 另有 TunError 条目（Linux/Docker 为主，"如果在 Docker 中运行，请确保开启特权模式"）、Linux 帮助中文化（`export LANG=zh_CN`）。
- 补充页任务（Docker / 公共节点 / FAQ 任一）已由本页 + 第 3 页 Docker 段落共同满足。

## 三、官方文档与源码事实（任务书钉死）对照

1. **CLI zip 构成 — 一致**：下载页说"压缩包中包含四个可执行程序"（core/cli/web/web-embed），与钉死事实"zip 内含 easytier-core.exe、easytier-cli.exe、easytier-web.exe、easytier-web-embed.exe"一致。文档未提 wintun.dll、WinDivert64.sys、Packet.dll，但钉死事实确认这些驱动/ DLL 也在包内——属于文档未列全，非矛盾。
2. **纯 TCP 组网路径 — 文档与源码相容且互相支撑**：文档快速组网示例即 `-p tcp://...`；钉死源码事实为"TCP/WS/WSS 建连全程不经 UDP（connectivity/protocol/mod.rs:25）""中继逐包转发、默认开"。文档表述"P2P 失败时由共享节点中转数据"与源码"中继默认开"一致；文档没有写明 TCP 中继不依赖 UDP，但源码事实补足了这一点，二者不冲突。
3. **配置文件扩展名/格式 — 文档自身不严谨**：config-file 页示例写 `easytier-core -c ./config.yaml`，但同页又说"保存为toml文件"、配置助手加载的是 `./config.toml`；钉死事实中配置解析模块为 config/toml.rs，即内容格式是 TOML。[UNCERTAIN] 是否同时支持 YAML 解析，本次未实读源码、未实测，不能断言；可确认的是文档在扩展名上 yaml/toml 混用。
4. **服务运行方式 — 文档有专页但本次未实读**：侧栏存在"安装为 Windows 服务"（install-as-a-windows-service.html）等页面，符合任务背景关注，但不在硬约束 4 页清单内，本报告不引用其内容，仅记录入口 URL。

## 四、未能打开 / 未读取的页面

- 无"未能打开"页面：第 3 页 installation.html 首次 browser_navigate 返回 browser_timeout（15000ms 超时），立即重试成功并读到完整正文，已如实记录。
- 已发现入口但本次未打开（不引用其内容）：
  - https://www.easytier.cn/guide/network/install-as-a-windows-service.html （安装为 Windows 服务）
  - https://www.easytier.cn/guide/network/oneclick-install-as-service.html （一键安装服务）
  - https://www.easytier.cn/guide/network/configurations.html （其他配置）
  - https://www.easytier.cn/guide/network/host-public-server.html （搭建共享节点）
  - https://www.easytier.cn/guide/network/discovery-url.html （发现地址）

## 五、给 Windows + 雨云（仅 TCP 入站）实测的直接可用信息（均出自上面实读原文）

1. Windows 宿主机：下载 `easytier-windows-x86_64-v2.6.4.zip` → 解压 → 管理员权限运行（官方原文"解压后既可直接使用""# 管理员权限运行"）。
2. 雨云共享节点侧：`easytier-core` 用 `-l <端口>` 指定 TCP 监听端口；客户端侧用 `-p tcp://<雨云IP>:<端口>` 接入（官方快速组网示例形态）。
3. 两端同网络标识：`--network-name <名称>` + `--network-secret <密码>`；虚拟 IP 用 `-d` 自动分配（默认 10.126.126.0/24）或 `-i <CIDR>` 指定。
4. 配置文件化：`easytier-core -c ./config.toml`；可先用带参运行打印出对应 TOML 再落盘，或用官方配置助手 https://easytier.cn/assistant/ 生成。
5. GitHub 拉取慢时官方页列出加速前缀（ghfast.top 等）。
