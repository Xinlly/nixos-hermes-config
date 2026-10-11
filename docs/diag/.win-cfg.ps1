[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = 'Continue'
Write-Output '=== easytier-gui config locations ==='
$dirs = @(
  "$env:APPDATA\com.kkrainbow.easytier",
  "$env:LOCALAPPDATA\com.kkrainbow.easytier",
  "$env:USERPROFILE\.config\easytier",
  "$env:USERPROFILE\.easytier"
)
foreach ($d in $dirs) {
  if (Test-Path $d) {
    Write-Output "DIR: $d"
    Get-ChildItem -Recurse $d -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '\.(toml|json|conf|cfg|yaml)$' -or $_.Name -match 'config' } | ForEach-Object {
      Write-Output "--- FILE: $($_.FullName)"
      Get-Content $_.FullName | ForEach-Object { if ($_ -match 'secret|password') { '<REDACTED>' } else { $_ } }
    }
  }
}
