# modules/hermes/services.nix — Hermes systemd 环境 + MiMo TTS 代理服务
#
# systemd Environment 比 .env 更早生效，sitecustomize.py 在 Python 启动时就需要 PYTHONPATH。
# MiMo TTS 走 xiaomiTTS2OpenAITTSAPI 代理，独立 systemd 单元。
{ config, pkgs, lib, ... }:
let
  cfg = config.services.hermesRuntime;

  # MiMo TTS 代理 Python 环境 — 含 fastapi/uvicorn/httpx/pydantic
  ttsPython = pkgs.python3.withPackages (ps: with ps; [ fastapi uvicorn httpx python-dotenv pydantic ]);
in
{
  # ═══════════════════════════════════════════════
  # systemd 环境变量 — Python 启动前必须就位
  # ═══════════════════════════════════════════════
  systemd.services.hermes-agent.serviceConfig.Environment = [
    "PYTHONPATH=${cfg.pythonPath}"
    "HERMES_PATCHED_GATEWAY=${config.services.hermesFeishuCard.patchedGateway}"
    "LD_LIBRARY_PATH=${pkgs.libpulseaudio}/lib"   # PortAudio dlopen libpulse 需要
    "no_proxy=localhost,127.0.0.1,::1"
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
      Restart = "always";
      RestartSec = 5;
    };
  };
}
