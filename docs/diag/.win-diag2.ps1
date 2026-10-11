[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = 'Continue'

Write-Output '=== any process matching easy/tier ==='
Get-CimInstance Win32_Process | Where-Object { $_.Name -match 'easy|tier|wintun' -or $_.CommandLine -match 'easytier' } | ForEach-Object { "PID=$($_.ProcessId) NAME=$($_.Name) CMD=$($_.CommandLine)" }

Write-Output ''
Write-Output '=== services matching easy ==='
Get-Service | Where-Object { $_.Name -match 'easy|tier' -or $_.DisplayName -match 'easy|tier' } | Format-Table Name,DisplayName,Status,StartType -AutoSize | Out-String

Write-Output '=== scheduled tasks matching easy ==='
Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object { $_.TaskName -match 'easy|tier' } | Format-Table TaskName,State -AutoSize | Out-String

Write-Output '=== net adapters (et/vgate) ==='
Get-NetAdapter | Where-Object { $_.Name -match 'et_|vgate|Tailscale' -or $_.InterfaceDescription -match 'wintun|EasyTier|Tailscale|vgate' } | Format-Table Name,InterfaceDescription,Status,MacAddress,LinkSpeed -AutoSize | Out-String

Write-Output '=== adapter stats et_8_pvnr (sample 1) ==='
$a = Get-NetAdapter -Name et_8_pvnr -ErrorAction SilentlyContinue
if ($a) { $s = $a.GetStats(); "ReceivedBytes=$($s.BytesReceived) SentBytes=$($s.BytesSent) RecvPackets=$($s.PacketsReceived) SentPackets=$($s.PacketsSent)" }
Start-Sleep -Seconds 3
Write-Output '=== adapter stats et_8_pvnr (sample 2 after 3s) ==='
if ($a) { $s = $a.GetStats(); "ReceivedBytes=$($s.BytesReceived) SentBytes=$($s.BytesSent) RecvPackets=$($s.PacketsReceived) SentPackets=$($s.PacketsSent)" }

Write-Output '=== Hyper-V VM setting ActiveStore (effective) ==='
try { Get-NetFirewallHyperVVMSetting -PolicyStore ActiveStore | Format-List Name,Enabled,DefaultInboundAction,DefaultOutboundAction,LoopbackEnabled,LoopbackRouteMode } catch { "ERR: $_" }

Write-Output '=== Hyper-V firewall rules count and list ==='
try {
  $rules = Get-NetFirewallHyperVRule -PolicyStore ActiveStore -ErrorAction Stop
  "TOTAL RULES: $($rules.Count)"
  $rules | Where-Object { $_.Direction -eq 'Inbound' } | Format-Table DisplayName,Enabled,Action,VMCreatorId -AutoSize | Out-String
} catch { "ERR: $_" }

Write-Output '=== listening ports 15888/11010/2222 owner ==='
$conns = Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue | Where-Object { $_.LocalPort -in 15888,11010,2222,3389 }
foreach ($c in $conns) { $p = Get-Process -Id $c.OwningProcess -ErrorAction SilentlyContinue; "Port=$($c.LocalPort) Addr=$($c.LocalAddress) PID=$($c.OwningProcess) Proc=$($p.ProcessName)" }

Write-Output '=== EasyTier related files timestamps ==='
Get-ChildItem -Recurse C:\EasyTier -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 10 FullName,LastWriteTime,Length | Format-Table -AutoSize | Out-String
