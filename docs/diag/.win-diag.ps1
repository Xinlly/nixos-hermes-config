[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = 'Continue'

Write-Output '=== EasyTier dir ==='
if (Test-Path C:\EasyTier) { Get-ChildItem -Recurse C:\EasyTier -File | Select-Object -ExpandProperty FullName } else { 'NO C:\EasyTier' }

Write-Output ''
Write-Output '=== start-node.ps1 (secret line redacted) ==='
if (Test-Path C:\EasyTier\start-node.ps1) {
  Get-Content C:\EasyTier\start-node.ps1 | ForEach-Object { if ($_ -match 'secret') { '<REDACTED secret line>' } else { $_ } }
}

Write-Output ''
Write-Output '=== easytier-core process cmdline ==='
$procs = Get-CimInstance Win32_Process -Filter "Name='easytier-core.exe'"
if ($procs) { $procs | ForEach-Object { "PID=$($_.ProcessId) CMD=$($($_.CommandLine) -replace '(--network-secret\s+)\S+','$1<REDACTED>')" } } else { 'NO easytier-core.exe' }

Write-Output ''
Write-Output '=== IPv4 addresses ==='
Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -notlike '169.254*' } | Sort-Object InterfaceAlias | Format-Table InterfaceAlias,IPAddress,PrefixLength -AutoSize | Out-String

Write-Output '=== route 10.144.144.0/24 ==='
Get-NetRoute -DestinationPrefix '10.144.144.0/24' -ErrorAction SilentlyContinue | Format-Table InterfaceAlias,NextHop,RouteMetric,ifMetric -AutoSize | Out-String

Write-Output '=== connection profiles ==='
Get-NetConnectionProfile | Format-Table InterfaceAlias,NetworkCategory,IPv4Connectivity -AutoSize | Out-String

Write-Output '=== Windows firewall profiles ==='
Get-NetFirewallProfile | Format-Table Name,Enabled,DefaultInboundAction,DefaultOutboundAction -AutoSize | Out-String

Write-Output '=== Hyper-V firewall VM settings (mirrored mode) ==='
try { Get-NetFirewallHyperVVMSetting | Format-List Name,Enabled,DefaultInboundAction,DefaultOutboundAction,LoopbackEnabled,LoopbackRouteMode } catch { "ERR: $_" }

Write-Output '=== Hyper-V firewall creators ==='
try { Get-NetFirewallHyperVVMCreator | Format-List } catch { "ERR: $_" }

Write-Output '=== easytier-cli peer ==='
$cli = Get-ChildItem C:\EasyTier -Recurse -Filter easytier-cli.exe -ErrorAction SilentlyContinue | Select-Object -First 1
if ($cli) { & $cli.FullName peer 2>&1 | Out-String } else { 'NO easytier-cli.exe' }

Write-Output '=== easytier-cli route ==='
if ($cli) { & $cli.FullName route 2>&1 | Out-String }
