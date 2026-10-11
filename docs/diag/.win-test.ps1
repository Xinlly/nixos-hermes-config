[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
function T($ip,$port){
  $c = New-Object System.Net.Sockets.TcpClient
  $iar = $c.BeginConnect($ip,$port,$null,$null)
  $ok = $iar.AsyncWaitHandle.WaitOne(2500,$false)
  if ($ok -and $c.Connected) { $c.EndConnect($iar); "Windows -> ${ip}:${port} OPEN"; $c.Close() }
  else { "Windows -> ${ip}:${port} TIMEOUT/CLOSED"; try{$c.Close()}catch{} }
}
T '10.144.144.3' 3389
T '10.144.144.3' 2222
T '10.144.144.3' 6767
T '10.144.144.3' 8888
T '10.144.144.3' 9999
T '192.168.0.205' 2222
T '192.168.0.205' 6767
T '127.0.0.1' 2222
