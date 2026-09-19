param([int]$Port = 8080)
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$exe = Join-Path $here "cloudflared.exe"
if (-not (Test-Path -LiteralPath $exe)) { Write-Host "cloudflared.exe tidak ditemukan di $here"; Start-Sleep 5; exit 1 }

foreach ($f in @("tunnel.err", "tunnel.out", "tunnel.url")) {
  Remove-Item (Join-Path $here $f) -ErrorAction SilentlyContinue
}

$p = Start-Process -FilePath $exe -ArgumentList "tunnel", "--url", "http://localhost:$Port", "--no-autoupdate" -WorkingDirectory $here -RedirectStandardOutput (Join-Path $here "tunnel.out") -RedirectStandardError (Join-Path $here "tunnel.err") -PassThru
$p.Id | Out-File (Join-Path $here "tunnel.pid") -Encoding ascii

Write-Host "Menunggu URL publik dari trycloudflare..."
$url = $null
for ($i = 0; $i -lt 45; $i++) {
  Start-Sleep -Seconds 1
  $txt = ""
  foreach ($f in @("tunnel.err", "tunnel.out")) {
    $fp = Join-Path $here $f
    if (Test-Path -LiteralPath $fp) { $txt += (Get-Content -LiteralPath $fp -Raw -ErrorAction SilentlyContinue) }
  }
  if ($txt -match "https://[a-zA-Z0-9-]+\.trycloudflare\.com") { $url = $Matches[0]; break }
  if ($p.HasExited) { break }
}

if ($url) {
  $url | Out-File (Join-Path $here "tunnel.url") -Encoding ascii
  Write-Host ""
  Write-Host "=========================================="
  Write-Host "  URL PUBLIK:"
  Write-Host "  $url"
  Write-Host "=========================================="
  Write-Host "Jendela ini boleh diminimize, JANGAN ditutup."
} else {
  Write-Host "Gagal mendapat URL. Cek file tunnel.err / koneksi internet."
}
Start-Sleep -Seconds 3