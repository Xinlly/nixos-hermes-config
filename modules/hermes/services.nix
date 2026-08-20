# modules/hermes/services.nix — Hermes systemd 环境 + MiMo TTS 代理服务
#
# systemd Environment 比 .env 更早生效，sitecustomize.py 在 Python 启动时就需要 PYTHONPATH。
# MiMo TTS 走 xiaomiTTS2OpenAITTSAPI 代理，独立 systemd 单元。
{ config, pkgs, lib, ... }:
let
  cfg = config.services.hermesRuntime;

  # MiMo TTS 代理 Python 环境 — 含 fastapi/uvicorn/httpx/pydantic/pydub
  # pydub + ffmpeg 用于 opus 转码（飞书语音消息要求 opus 格式）
  ttsPython = pkgs.python3.withPackages (ps: with ps; [ fastapi uvicorn httpx python-dotenv pydantic pydub ]);
in
{
  # ═══════════════════════════════════════════════
  # systemd 环境变量 — Python 启动前必须就位
  # ═══════════════════════════════════════════════
  systemd.services.hermes-agent.serviceConfig.Environment = [
    "PYTHONPATH=${cfg.pythonPath}"
    "LD_LIBRARY_PATH=${pkgs.libpulseaudio}/lib"   # PortAudio dlopen libpulse 需要
    "no_proxy=localhost,127.0.0.1,::1"
    # computer_use 工具 — 指向宿主机 Windows 上的 cua-driver.exe
    "HERMES_CUA_DRIVER_CMD=/mnt/c/Users/Admin0/AppData/Local/Programs/Cua/cua-driver/bin/cua-driver.exe"
  ];

  # ═══════════════════════════════════════════════
  # MiMo TTS 代理服务 — xiaomiTTS2OpenAITTSAPI
  # ═══════════════════════════════════════════════
  systemd.services.xiaomi-tts-proxy = {
    description = "Xiaomi MiMo TTS → OpenAI Compatible Proxy";
    after = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      User = "hermes";
      Group = "hermes";
      WorkingDirectory = "/var/lib/hermes/workspace/projects/our/xiaomiTTS2OpenAITTSAPI";
      ExecStart = "${ttsPython}/bin/python3 -m uvicorn main:app --host 127.0.0.1 --port 8080";
      EnvironmentFile = "/var/lib/hermes/.hermes/.env.secrets";
      Path = [ "${pkgs.ffmpeg}/bin" ];  # pydub 转码需要 ffmpeg
      Restart = "always";
      RestartSec = 5;
    };
  };
}
