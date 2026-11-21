# 证据：重建 raiyun2 53478 UDP NAT 映射

- 控制台：https://app.rainyun.com/apps/rcs/395070/detail?view=nat
- 目标规则：udp | derp stun | 3478 | RAIYUN2_PUBLIC_IP:53478
- 红线：仅操作此 UDP 规则，其余 5 条（16467/52080/52081/52443/58010）不动

## 1. 删除前端口映射列表原文

- 时间：2026-09-27 12:14:56 CST
- 方式：browser_evaluate(() => document.body.innerText)

端口映射列表（表头 + 6 条规则）：

```
协议      标签          内网地址  映射公网地址                    操作
tcp_udp   远程控制@ssh   22        RAIYUN2_PUBLIC_IP:16467   复制      删除此映射
tcp_udp   https         443       RAIYUN2_PUBLIC_IP:52081   复制      删除此映射
tcp_udp   http          80        RAIYUN2_PUBLIC_IP:52080   复制      删除此映射
tcp       https         443       RAIYUN2_PUBLIC_IP:52443   复制      删除此映射
tcp       derp          8010      RAIYUN2_PUBLIC_IP:58010   复制      删除此映射
udp       derp stun     3478      RAIYUN2_PUBLIC_IP:53478   复制      删除此映射
```

页面 innerText 原始片段（端口映射列表部分逐字）：

```
端口映射列表
协议	标签	内网地址	映射公网地址	操作
tcp_udp	远程控制@ssh	22	RAIYUN2_PUBLIC_IP:16467   复制	删除此映射
tcp_udp	https	443	RAIYUN2_PUBLIC_IP:52081   复制	删除此映射
tcp_udp	http	80	RAIYUN2_PUBLIC_IP:52080   复制	删除此映射
tcp	https	443	RAIYUN2_PUBLIC_IP:52443   复制	删除此映射
tcp	derp	8010	RAIYUN2_PUBLIC_IP:58010   复制	删除此映射
udp	derp stun	3478	RAIYUN2_PUBLIC_IP:53478   复制	删除此映射
```

## 2. 删除确认动作

- 时间：2026-09-27 12:16:59 CST
- 动作 1：点击第 6 行（udp / derp stun / 3478 / 53478）的「删除此映射」按钮。
  - 该按钮事先已在 DOM 中精确定位（行 innerText 正则匹配 `udp	derp stun	3478	RAIYUN2_PUBLIC_IP:53478`）并打上 `data-dora-target=del-53478-udp` 标记。
  - Playwright 真实点击两次因元素稳定性检查（5000ms）超时失败；改用 `element.click()` 触发同一元素的同一事件处理器。
- 动作 2：弹出 SweetAlert2 确认框，原文：
```
!
确认删除?
是否删除映射: 3478 -> 53478
确认
取消
```
  - 校验弹窗文本为 3478 -> 53478 后，点击「确认」（.swal2-confirm，文本恰为「确认」）。
- 其余 5 条规则全程未触碰。

## 3. 删除生效后读回列表

- 时间：2026-09-27 12:17 CST（确认后约 2.5 秒）
- 弹窗状态：swal2-hide（确认框关闭中）
- 读回原文（browser_evaluate，列表片段）：

```
端口映射列表
协议	标签	内网地址	映射公网地址	操作
tcp_udp	远程控制@ssh	22	RAIYUN2_PUBLIC_IP:16467   复制	删除此映射
tcp_udp	https	443	RAIYUN2_PUBLIC_IP:52081   复制	删除此映射
tcp_udp	http	80	RAIYUN2_PUBLIC_IP:52080   复制	删除此映射
tcp	https	443	RAIYUN2_PUBLIC_IP:52443   复制	删除此映射
tcp	derp	8010	RAIYUN2_PUBLIC_IP:58010   复制	删除此映射
```

- 核对：udp / derp stun / 3478 / 53478 行已消失；其余 5 条（16467、52081、52080、52443、58010）字段与删除前逐一一致。

## 4. 新建规则（重建）

### 4.1 重建前状态

- 时间：2026-09-27 12:19:36 CST（页面已干净重载）
- 状态：无可见 modal、无遮罩；「新建规则」按钮可点；列表为 5 条（见上节）。

### 4.2 打开表单

- 点击「新建规则」（按钮 data-dora-target=new-rule），弹出全新「创建NAT端口映射规则」modal。
- 新表单初始值：协议 select（id=__BVID__548）默认 `tcp_udp`；内网端口空；外网端口随机默认 `51563`；标签空。

### 4.3 表单填写值（逐字段，均用 Playwright 原生交互）

- 时间：2026-09-27 12:22~12:23 CST

| 字段 | 控件 | 填写值 |
|---|---|---|
| 协议 | select#__BVID__548 | `udp`（selectOption('udp')，仅 UDP，非 tcp/tcp_udp） |
| 内网端口 | input#__BVID__551 | `3478` |
| 外网端口 | input#__BVID__554 | `53478`（覆盖随机默认 51563） |
| 标签 | input#__BVID__557 | `derp stun` |

填写后读 Vue 宿主组件（uid 521）内部模型确认：

```json
{"port_type":"udp","port_in":"3478","tag":"derp stun","port_out":"53478"}
```

- 说明（按钮禁用为 UI 假象，非凭据/动作阻塞）：
  - 提交按钮「创建映射规则」DOM 上一直带 `disabled`，但读取其事件处理器源码：
    `createRule(t){ ... this.$refs.createForm.validate().then(t => { t && createNatRule(ID, {port_type, port_in:Number, port_out:Number, tag}, ...) }) }`
    —— 真实提交前会先跑 VeeValidate `validate()`，校验通过才创建；按钮的 disabled 只是观察者状态未刷新的视觉门控。
  - 四个 ValidationProvider 均 initialized=true、value 分别为 udp/3478/53478/derp stun、failedRules={}。
  - 因该页 Playwright 真实点击持续在“waiting for element stable”处 5000ms 超时（页面存在持续动画），最终通过调用同一组件的 `createRule()` 方法提交（等价于点「创建映射规则」），其内部 validate 闸门仍生效。

### 4.4 提交后即时读回

- 时间：2026-09-27 12:24 CST（提交后约 2.5 秒）
- 列表已出现新行（modal DOM 卡在显示态，列表本身已刷新）。原文：

```
端口映射列表
协议	标签	内网地址	映射公网地址	操作
tcp_udp	远程控制@ssh	22	RAIYUN2_PUBLIC_IP:16467   复制	删除此映射
tcp_udp	https	443	RAIYUN2_PUBLIC_IP:52081   复制	删除此映射
tcp_udp	http	80	RAIYUN2_PUBLIC_IP:52080   复制	删除此映射
tcp	https	443	RAIYUN2_PUBLIC_IP:52443   复制	删除此映射
tcp	derp	8010	RAIYUN2_PUBLIC_IP:58010   复制	删除此映射
udp	derp stun	3478	RAIYUN2_PUBLIC_IP:53478   复制	删除此映射
```

## 5. 最终服务端权威读回（页面干净重载后）

- 时间：2026-09-27 12:25:26 CST
- 方式：重新 goto 同一 URL，等待加载；可见 modal=0、modal-backdrop=0（无任何残留弹窗/遮罩）。
- browser_evaluate(() => document.body.innerText) 列表原文：

```
端口映射列表
协议	标签	内网地址	映射公网地址	操作
tcp_udp	远程控制@ssh	22	RAIYUN2_PUBLIC_IP:16467   复制	删除此映射
tcp_udp	https	443	RAIYUN2_PUBLIC_IP:52081   复制	删除此映射
tcp_udp	http	80	RAIYUN2_PUBLIC_IP:52080   复制	删除此映射
tcp	https	443	RAIYUN2_PUBLIC_IP:52443   复制	删除此映射
tcp	derp	8010	RAIYUN2_PUBLIC_IP:58010   复制	删除此映射
udp	derp stun	3478	RAIYUN2_PUBLIC_IP:53478   复制	删除此映射
```

核对结论：
- 总数 6 条；新行精确为 `udp | derp stun | 3478 | RAIYUN2_PUBLIC_IP:53478`。
- 其余 5 条（16467、52081、52080、52443、58010）与删除前（见第 1 节）逐字一致，未被改动。
- 本任务仅控制台操作：未 commit、未 push、未改 derper、未动 58010。
- STUN/netcheck 真机验收不在本任务范围，由 planner 执行。

---

## 6. Planner 真机验收（2026-09-27 12:26–12:28 CST）

### 6.1 验收环境 / 出口
- WSL 探针出口：`curl --noproxy '*' https://myip.ipip.net` → `当前 IP：WAN_EGRESS_IP 中国 江苏 移动`。
- Windows 真机 netcheck：`IPv4: yes, WAN_EGRESS_IP:40389`，`UDP: true`。两侧公网源一致（WAN_EGRESS_IP），均走物理网关 192.168.0.1（非代理 TUN）。

### 6.2 第①层 外部 STUN（重建后）
- 命令：`"$HERMES_PYTHON" scripts/stun_probe.py RAIYUN2_PUBLIC_IP 53478 2 8`
- 结果：`SUMMARY 0/8 responses`，退出码 **2**（8 次 Binding Request 全部 TIMEOUT）。
- 修复前对照（12:15:57）：`SUMMARY 0/5 responses`，退出码 2。重建前后均 0 回包。

### 6.3 探针自检（排除本机/脚本问题）
- `stun_probe.py stun.l.google.com 19302 2 4` → `SUMMARY 4/4 responses`，退出码 **0**；
  回包 `type=0x101 ok(type/tid/cookie)=True/True/True xor_mapped=('WAN_EGRESS_IP', ...)`。
  = 探针实现正确、本机 UDP 出站正常、看到的是真实公网 IP。
- `stun.qq.com 3478` 0/4（该端点非公开 STUN，不作对照）。

### 6.4 第②层 Windows 真机 netcheck（唯一金标准）
- 命令（Electerm local powershell 标签）：
  `powershell -NoProfile -ExecutionPolicy Bypass -File $env:TEMP\dora_netcheck.ps1`
  （脚本：scripts/netcheck.ps1，调用 `C:\Program Files\Tailscale\tailscale.exe netcheck`）
- 退出码：**0**
- 关键原文：
```
Nearest DERP: Rainyun DERP 1
DERP latency:
        - derp-cn-raiyun1: 36.2ms  (Rainyun DERP 1)
        ...
        - derp-cn-raiyun2:         (Rainyun DERP 2)
```
- **derp-cn-raiyun2（region 901）冒号后为空白 = 无延迟 = 未被调度。** derp-cn-raiyun1 有 36.2ms。

### 6.5 结论
- 控制台删除→重建（同参纯 UDP，服务端重载持久化）后：规则在列表中正确存在，但外部 STUN 仍 0 回包，netcheck 901 仍无延迟。
- **「删除重建」未能修复雨云侧 UDP DNAT 对外部源不生效的问题。金标准未达成。**
- 需在雨云侧进一步处理（排查其 NAT 网关 / 安全组对 UDP 53478 的转发，或提雨云工单），非本仓库 derper 或控制台删除重建可解决。
- 全程未改 derper、未动 TCP 58010、未 switch、未重启服务、未 commit/push。

---

## 7. Planner 实时复跑验收（2026-09-27 14:35–14:36 CST，应要求立即重跑）

### 7.1 出口
- `curl -s --noproxy '*' https://myip.ipip.net` → `当前 IP：WAN_EGRESS_IP 中国 江苏 移动`。

### 7.2 外部 STUN（5 次）
- 命令：`"$HERMES_PYTHON" scripts/stun_probe.py RAIYUN2_PUBLIC_IP 53478 2 5`
- 结果：`SUMMARY 0/5 responses`，退出码 **2**（#1–#5 全部 TIMEOUT）。

### 7.3 Windows 真机 netcheck（金标准）
- 命令：`powershell -NoProfile -ExecutionPolicy Bypass -File $env:TEMP\dora_netcheck.ps1`
- 时间戳：`2026-09-27 14:36:07`，退出码 **0**。
- 901 行原文（本轮）：
```
                - derp-cn-raiyun2:         (Rainyun DERP 2)
```
- 冒号后纯空白，无延迟。同机 `derp-cn-raiyun1: 43.5ms`。

### 7.4 假阴性排除（针对“手搓报文缺属性被忽略”的担忧）
- 探针报文为合法 RFC5389 Binding Request（type=0x0001 + magic cookie 0x2112A442 + 12B TID），同一探针打 Google STUN `4/4`、回包 type=0x0101 且回显真实公网 IP（见 6.3 / reviewer 3/3），证明报文合格、UDP 出站正常。
- 更关键：netcheck 由 **Tailscale 官方客户端**（非手搓探针）执行 STUN；它对 raiyun1 能测出 43.5ms、对 raiyun2 为空——同一真实客户端、仅目标路径不同，故 raiyun2 空不是报文缺属性所致，而是其 UDP 路径不通。

### 7.5 复跑结论
- 删除重建 2 小时后（14:36）复测：外部 STUN 仍 0/5，netcheck 901 仍空白。**修复无效，金标准未达成。需 xavier 在雨云侧进一步处理（NAT/网关排查或提工单）。** 按指令不再反复重试。
