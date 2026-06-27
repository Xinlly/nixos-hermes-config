# overlay.nix — nixpkgs overlay
# 强制 portaudio 编译 PulseAudio 后端（WSL2 无 ALSA 硬件，唯一可用音频路径）
#
# 要点:
#   - libpulseaudio.dev 提供 pkg-config 所需的 .pc 文件（非 libpulseaudio 普通输出）
#   - cmakeFlags 强制只开 PulseAudio，关 ALSA/JACK/OSS 避免无设备噪声
final: prev: {
  portaudio = prev.portaudio.overrideAttrs (old: {
    buildInputs = (old.buildInputs or []) ++ [ final.libpulseaudio.dev ];
    nativeBuildInputs = (old.nativeBuildInputs or []) ++ [ final.pkg-config ];
    cmakeFlags = (old.cmakeFlags or []) ++ [
      "-DPA_USE_PULSEAUDIO=ON"
      "-DPA_USE_ALSA=OFF"
      "-DPA_USE_JACK=OFF"
      "-DPA_USE_OSS=OFF"
    ];
  });
}
