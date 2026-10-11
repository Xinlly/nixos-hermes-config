#!/run/current-system/sw/bin/bash
# Detached activator for Paseo + SiliconFlow STT.
# Runs outside any agent cgroup; survives `systemctl restart paseo`.
# Launched once via electerm (sudo); evidence -> /tmp/paseo-asr-activate-20261001.log
set -u
# systemd-run transient units get a minimal PATH; pin the system profile explicitly.
export PATH=/run/current-system/sw/bin:/run/current-system/sw/sbin:/run/wrappers/bin
LOG=/tmp/paseo-asr-activate-20261001.log
WAV=/var/lib/hermes/workspace/temp/voice-probe/zh.wav
SECRET=/var/lib/hermes/.paseo/secret.env
exec >"$LOG" 2>&1
echo "=== activate start $(date -Is) ==="

echo "--- [0] pre-check secret (no value) ---"
stat -c 'secret mode=%a owner=%U:%G size=%s' "$SECRET"
awk -F= '{print $1"=<len:"length($2)"> placeholder:"($2 ~ /PASTE_YOUR/)}' "$SECRET"
KEY=$(sed -n 's/^OPENAI_STT_API_KEY=//p' "$SECRET" | head -1)
echo "key loaded: len=${#KEY}"

echo "--- [1] start user@998 (known rebuild blocker) ---"
systemctl start user@998
systemctl is-active user@998

echo "--- [2] nixos-rebuild test (no boot write) ---"
nixos-rebuild --flake /etc/nixos#nixos test
echo "rebuild_test_rc=$?"

echo "--- [3] restart paseo (env only read at process start) ---"
systemctl restart paseo
sleep 3
echo "paseo active: $(systemctl is-active paseo)"

echo "--- [4] unit-level evidence ---"
echo "EnvironmentFiles:"; systemctl show paseo -p EnvironmentFiles
echo "non-secret env in unit:"
systemctl show paseo -p Environment | tr ' ' '\n' | grep -E 'OPENAI_STT_BASE_URL|STT_MODEL|STT_PROVIDER' || true

echo "--- [5] process /proc environ (key redacted) ---"
PID=$(systemctl show paseo -p MainPID --value)
echo "MainPID=$PID"
tr '\0' '\n' < /proc/$PID/environ | grep -E 'OPENAI_STT_BASE_URL|STT_MODEL|STT_PROVIDER' || true
tr '\0' '\n' < /proc/$PID/environ | sed -E 's/(OPENAI_STT_API_KEY=).*/\1<REDACTED>/' | grep OPENAI_STT_API_KEY || true

echo "--- [6] end-to-end ASR via SiliconFlow (direct, no proxy) ---"
unset HTTP_PROXY HTTPS_PROXY ALL_PROXY http_proxy https_proxy all_proxy
curl --noproxy '*' -sS --max-time 60 \
  -X POST https://api.siliconflow.cn/v1/audio/transcriptions \
  -H "Authorization: Bearer $KEY" \
  -F file=@"$WAV" \
  -F model=FunAudioLLM/SenseVoiceSmall
echo
echo "=== activate done $(date -Is) ==="
