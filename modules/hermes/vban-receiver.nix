# modules/vban-receiver.nix — VBAN UDP 音频接收器，桥接 Voicemeeter → WSL2 PulseAudio
#
# 音频链路:
#   Voicemeeter Banana (Windows) → VBAN UDP → WSL2 :6980
#     → vban-receiver.service (Python, 写 FIFO)
#       → pulseaudio pipe-source (vban_mic)
#         → Hermes STT (faster-whisper)
#
# Voicemeeter 侧设置:
#   1. VBAN 按钮 → Outgoing Stream → + 加一条流
#   2. IP = WSL2 的 eth0 地址（ip addr show eth0），端口 6980
#   3. Bus = Mix 或要监听的音频总线
#   4. 参数建议: 44100Hz / 1ch / 16bit
{ config, pkgs, lib, ... }:

let
  cfg = config.services.vbanReceiver;

  # Python 脚本: 监听 VBAN UDP，解析协议头，写 PCM 到 named pipe
  # 用 writeScriptBin 打包进 Nix store，避免外部文件依赖
  vbanScript = pkgs.writeScriptBin "vban-receiver" ''
    #!${pkgs.python312}/bin/python3
    import socket, struct, os, sys, time
    from pathlib import Path

    VBAN_MAGIC = b"VBAN"
    FIFO_PATH = "${cfg.fifoPath}"
    HEADER_SIZE = 28
    SUPPORTED_SR = [6000, 12000, 24000, 48000, 96000, 192000, 384000,
                    8000, 16000, 32000, 64000, 128000, 256000, 512000,
                    11025, 22050, 44100, 88200, 176400, 352800, 705600]
    SUPPORTED_FORMATS = {0: 8, 1: 16, 2: 24, 3: 32}

    class VBANPacket:
        def __init__(self, data: bytes):
            if len(data) < HEADER_SIZE or data[:4] != VBAN_MAGIC:
                raise ValueError("Not a VBAN packet")
            header = data[4:28]
            format_sr = header[0]
            format_nbs_nbc = header[1]
            self.stream_name = header[2:18].decode("utf-8", errors="replace").rstrip("\x00")
            self.frame_counter = struct.unpack(">I", header[18:22])[0]
            bit_idx = format_sr & 0x07
            self.bits_per_sample = SUPPORTED_FORMATS.get(bit_idx, 16)
            sr_idx = (format_sr >> 3) & 0x1F
            self.sample_rate = SUPPORTED_SR[sr_idx] if sr_idx < len(SUPPORTED_SR) else 44100
            self.channels = (format_nbs_nbc >> 5) + 1  # VBAN: bits 5-7 = channels-1
            self.pcm_data = data[HEADER_SIZE:]

    def main(port: int):
        fifo = Path(FIFO_PATH)
        if fifo.exists():
            fifo.unlink()
        os.mkfifo(str(fifo))

        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        sock.bind(("0.0.0.0", port))
        sock.settimeout(1.0)

        print(f"[VBAN] Listening UDP :{port} -> {FIFO_PATH}", file=sys.stderr, flush=True)
        pkt_count = 0
        last_report = time.time()

        while True:
            try:
                data, _ = sock.recvfrom(65536)
                pkt = VBANPacket(data)
                pkt_count += 1
                # PIPE_BUF (4096) 保证原子写
                try:
                    fd = os.open(FIFO_PATH, os.O_WRONLY | os.O_NONBLOCK)
                    os.write(fd, pkt.pcm_data)
                    os.close(fd)
                except (OSError, BrokenPipeError):
                    pass
                now = time.time()
                if now - last_report >= 10:
                    print(f"[VBAN] {pkt_count} pkts, "
                          f"{pkt.sample_rate}Hz/{pkt.channels}ch/{pkt.bits_per_sample}bit",
                          file=sys.stderr, flush=True)
                    last_report = now
            except socket.timeout: continue
            except ValueError: continue
            except KeyboardInterrupt: break
        sock.close()
        fifo.unlink()

    if __name__ == "__main__":
        port = int(sys.argv[1]) if len(sys.argv) > 1 else ${toString cfg.port}
        main(port)
  '';

  # 辅助脚本: 在 WSLg PulseServer 上加载 pipe-source 模块创建虚拟麦克风
  vbanSetup = pkgs.writeShellScriptBin "vban-setup" ''
    ${pkgs.pulseaudio}/bin/pactl --server=${cfg.pulseServer} load-module module-pipe-source \
      file=${cfg.fifoPath} \
      source_name=vban_mic \
      source_properties=device.description=Voicemeeter_VBAN \
      format=s16le \
      rate=48000 \
      channels=2 2>/dev/null || true
    ${pkgs.pulseaudio}/bin/pactl --server=${cfg.pulseServer} list sources short 2>/dev/null \
      | grep vban_mic && echo "VBAN mic ready" || echo "WARNING: vban_mic not found"
  '';

in {
  options.services.vbanReceiver = {
    enable = lib.mkEnableOption "VBAN UDP audio receiver for Voicemeeter";
    port = lib.mkOption {
      type = lib.types.int;
      default = 6980;
      description = "UDP port for VBAN stream";
    };
    pulseServer = lib.mkOption {
      type = lib.types.str;
      default = "unix:/mnt/wslg/PulseServer";
      description = "PulseAudio server address (WSLg socket)";
    };
    fifoPath = lib.mkOption {
      type = lib.types.str;
      default = "/tmp/vban_audio.fifo";
      description = "Named pipe for PCM audio";
    };
  };

  config = lib.mkIf cfg.enable {
    # pactl 需要 pulseaudio 包
    environment.systemPackages = [ pkgs.pulseaudio ];

    systemd.services.vban-receiver = {
      description = "VBAN UDP Audio Receiver";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];
      serviceConfig = {
        User = "hermes";
        Group = "hermes";
        ExecStart = "${vbanScript}/bin/vban-receiver ${toString cfg.port}";
        ExecStartPre = "${vbanSetup}/bin/vban-setup";
        Restart = "always";
        RestartSec = "5s";
        RuntimeDirectory = "vban";
        RuntimeDirectoryMode = "0755";
      };
    };
  };
}
