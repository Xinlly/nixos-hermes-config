#!/usr/bin/env python3
"""VBAN 测试脚本 — 验证 Windows Voicemeeter → WSL2 音频链路。

用法:
  1. Voicemeeter → VBAN → Outgoing → IP: $(ip addr show eth0 | grep inet) 端口: 6980
  2. python vban-receiver.py          # 监听并打印统计
  3. python vban-receiver.py test     # 监听并写入 WAV 文件用 ffplay 试听
"""

import socket
import struct
import sys
import time
import wave
from pathlib import Path

VBAN_MAGIC = b"VBAN"
HEADER_SIZE = 28
SUPPORTED_SR = [6000, 12000, 24000, 48000, 96000, 192000, 384000,
                8000, 16000, 32000, 64000, 128000, 256000, 512000,
                11025, 22050, 44100, 88200, 176400, 352800, 705600]
SUPPORTED_FORMATS = {0: 8, 1: 16, 2: 24, 3: 32}


def parse_packet(data):
    if len(data) < HEADER_SIZE or data[:4] != VBAN_MAGIC:
        return None
    h = data[4:28]
    bit_idx = h[0] & 0x07
    sr_idx = (h[0] >> 3) & 0x1F
    channels = (h[1] >> 5) + 1  # VBAN: bits 5-7 = channels-1, bits 0-4 = bits_per_sample
    return {
        "stream": h[2:18].decode("utf-8", "replace").rstrip("\x00"),
        "sr": SUPPORTED_SR[sr_idx] if sr_idx < len(SUPPORTED_SR) else 44100,
        "ch": channels,
        "bits": SUPPORTED_FORMATS.get(bit_idx, 16),
        "pcm": data[HEADER_SIZE:],
    }


def listen(port=6980, save_wav=False):
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    sock.bind(("0.0.0.0", port))
    sock.settimeout(1.0)

    print(f"Listening UDP :{port} ...", flush=True)

    pkt_count = 0
    wav = None
    wav_params = None
    last_report = time.time()
    buffer = bytearray()

    try:
        while True:
            try:
                data, addr = sock.recvfrom(65536)
            except socket.timeout:
                continue

            pkt = parse_packet(data)
            if not pkt:
                continue

            pkt_count += 1

            if save_wav:
                params = (pkt["ch"], pkt["bits"] // 8, pkt["sr"])
                if params != wav_params:
                    if wav:
                        wav.close()
                    wav = wave.open("/tmp/vban_test.wav", "wb")
                    wav.setnchannels(params[0])
                    wav.setsampwidth(params[1])
                    wav.setframerate(params[2])
                    wav_params = params
                    print(f"WAV: {params[2]}Hz {params[0]}ch {params[1]*8}bit", flush=True)
                wav.writeframes(pkt["pcm"])

            buffer.extend(pkt["pcm"])
            if len(buffer) > pkt["sr"] * 10:  # Keep 10s ring buffer
                buffer = buffer[-pkt["sr"] * 10:]

            now = time.time()
            if now - last_report >= 5:
                print(f"[{pkt_count:6d}] {pkt['sr']}Hz {pkt['ch']}ch {pkt['bits']}bit "
                      f"'{pkt['stream']}' from {addr[0]}:{addr[1]}", flush=True)
                last_report = now

    except KeyboardInterrupt:
        print(f"\nStopped. {pkt_count} packets received.", flush=True)
    finally:
        sock.close()
        if wav:
            wav.close()


if __name__ == "__main__":
    save = len(sys.argv) > 1 and sys.argv[1] == "test"
    port = int(sys.argv[1]) if len(sys.argv) > 1 and sys.argv[1].isdigit() else 6980
    listen(port, save_wav=save)
