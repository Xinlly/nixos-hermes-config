# 音频输入方案

## 架构

```
Voicemeeter Banana (Windows)
  → VBAN UDP (48000Hz/2ch/16bit)
    → WSL2 :6980
      → vban-receiver.service → /tmp/vban_audio.fifo
        → pulseaudio pipe-source (vban_mic)
```

## 两个方案

### 主方案：portaudio 原生 PulseAudio 后端

`modules/hermes/runtime.nix` 中的 `portaudio` derivation：
- cmake + libpulseaudio.dev → 编译时链接 libpulse-simple
- 关 ALSA/JACK/OSS，只保留 PulseAudio
- PortAudio 原生看到 vban_mic → Hermes 用 sd.InputStream 走真实设备

验证：
```bash
ldd libportaudio.so | grep pulse  # 应有 libpulse-simple
```

### 备选方案：sitecustomize.py ⑥ 劫持

如果主方案不通，⑥ 劫持代码仍在 sitecustomize.py：
- 替换 sd.InputStream → _FakeStream
- _FakeStream._run() 从 FIFO 读 PCM，喂 Hermes 回调
- RMS < 200 静音过滤

主方案通了即可删除 ⑥。

## VBAN 参数

- VBAN 端口：6980
- WSL2 IP：`ip addr show eth0` 获取
- Voicemeeter → VBAN → Outgoing Stream → IP + 端口
- 采样：48000Hz / 2ch / 16bit

## 模型

- small 模型已下载 (464MB, /var/lib/hermes/.cache/huggingface/)
- base 模型太小，中文识别差

## 相关文件

- `modules/hermes/runtime.nix`：portaudio derivation + shim (sitecustomize.py)
- `modules/hermes/agent.nix`：extraPackages (audio + browser)
- `modules/hermes/vban-receiver.nix`：vban-receiver.service + pipe-source
- `modules/hermes/services.nix`：systemd LD_LIBRARY_PATH (libpulse)
- `hosts/wsl/hermes.nix`：Hermes 子模块聚合入口
- `hosts/wsl/default.nix`：WSL2 变体入口
- `hosts/wsl/users.nix`：sudo env_keep 代理变量
- `flake.nix`：flakes 入口（nixosConfigurations.nixos）
- `scripts/vban-receiver.py`：独立测试脚本（不参与部署）
