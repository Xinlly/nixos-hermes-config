# tailscale netcheck on the Windows host (run via Electerm local tab):
#   powershell -ExecutionPolicy Bypass -File netcheck.ps1
$ErrorActionPreference = "Continue"

$candidates = @(
    "$env:ProgramFiles\Tailscale\tailscale.exe",
    "${env:ProgramFiles(x86)}\Tailscale\tailscale.exe",
    "$env:LOCALAPPDATA\Programs\Tailscale\tailscale.exe"
)
$ts = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $ts) {
    $cmd = Get-Command tailscale.exe -ErrorAction SilentlyContinue
    if ($cmd) { $ts = $cmd.Source }
}
if (-not $ts) {
    Write-Output "ERROR: tailscale.exe not found"
    exit 127
}

Write-Output "tailscale = $ts"
Write-Output ("time      = " + (Get-Date -Format "yyyy-MM-dd HH:mm:ss"))
Write-Output "---- netcheck ----"
& $ts netcheck
$code = $LASTEXITCODE
Write-Output "---- exit code: $code ----"
exit $code
