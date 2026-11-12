# 任务书：重建 raiyun2 53478 UDP NAT（让 DERP region 901 STUN 可达）

- 日期：2026-09-27
- Planner：57d5322d（planner·raiyun2-derp-901）
- Workspace：wks_33df3c489d111c29 / branch `fix/raiyun2-derp-stun-901`
- Baseline SHA（origin/develop，冻结）：dc339e19f2cc572494791b29800677eb
- 控制台：https://app.rainyun.com/apps/rcs/395070/detail?view=nat（雨云，已登录）

## 背景（根因已钉死，勿重查）
- 雨云公网 UDP 53478 → 内网 3478 的 DNAT 对外部源不生效：控制台显示规则存在，但外部 STUN 包到不了 derper（服务器 /tmp/trace4.log 实证：内网节点 STUN 19/19 到达，公网源 0 次）。
- derper 服务端健康，TCP/TLS 58010 可建立。**不动 derper、不动 58010、不 switch、不重启服务。**

## planner 只读侦察结果（2026-09-27）
现有映射共 6 条，目标规则：
`协议=udp | 标签=derp stun | 内网地址=3478 | 公网=RAIYUN2_PUBLIC_IP:53478`
即该规则**当前已是纯 UDP**。重建目的不是改协议，而是强制雨云后端重新下发转发表项、清除“显示存在但实际不转发”的僵尸态。

## Worker 动作（仅做这些）
1. 用 playwright `browser_tabs` list 找到雨云 NAT 标签页（标题“管理云服务器 | 雨云”），select 它。
2. 删除 `udp / derp stun / 3478 / RAIYUN2_PUBLIC_IP:53478` 这一行：点该行“删除此映射”，按弹窗确认。**不得动其余 5 条（16467/52081/52080/52443/58010）。**
3. 点“新建规则”，重建为完全相同的纯 UDP DNAT：
   - 协议：UDP（仅 UDP，不要 tcp_udp）
   - 标签：`derp stun`
   - 内网地址/端口：`3478`
   - 公网端口：`53478`
   - 提交/确认。
4. 读回端口映射列表，确认新行存在且字段为 `udp | derp stun | 3478 | RAIYUN2_PUBLIC_IP:53478`。
5. 每一步保存原始证据（删除前列表、确认动作后、新建表单、读回列表），用 `browser_evaluate(() => document.body.innerText)` 取文本。

## 红线 / 阻塞
- 只操作这一条 UDP 规则；其余规则、58010、derper 一律不碰。
- 若登录态失效、出现验证码/二次验证/付费确认、或删除/重建按钮不可点：**停止，不要硬试**，按固定格式回报：
  `阻塞：缺<凭据/动作>；请执行：<命令>；完成验收：<标准>`
- Worker 不 commit、不 push、不改仓库文件（本任务无代码改动）。

## 验收（由 planner 真机执行，worker 只负责控制台动作 + 读回）
- 外部 STUN 能从 RAIYUN2_PUBLIC_IP:53478 收到回包；
- `tailscale netcheck` 中 region 901 出现非空延迟（唯一金标准）。
