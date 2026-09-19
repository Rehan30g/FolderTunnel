param(
  [int]$Port = 8080,
  [string]$RuntimeDir = "",
  [string]$CloudflaredPath = ""
)
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $RuntimeDir) { $RuntimeDir = Join-Path (Split-Path -Parent $here) "logs" }
if (-not $CloudflaredPath) { $CloudflaredPath = Join-Path (Join-Path (Split-Path -Parent $here) "data") "cloudflared.exe" }
$RuntimeDir = [System.IO.Path]::GetFullPath($RuntimeDir)
$exe = [System.IO.Path]::GetFullPath($CloudflaredPath)
if (-not (Test-Path -LiteralPath $RuntimeDir)) { New-Item -ItemType Directory -Path $RuntimeDir -Force | Out-Null }
if (-not (Test-Path -LiteralPath $exe)) { Write-Host "cloudflared.exe tidak ditemukan di folder data"; Start-Sleep 5; exit 1 }

foreach ($f in @("tunnel.err", "tunnel.out", "tunnel.url")) {
  Remove-Item (Join-Path $RuntimeDir $f) -ErrorAction SilentlyContinue
}

$p = Start-Process -FilePath $exe -ArgumentList "tunnel", "--url", "http://localhost:$Port", "--http-host-header", "localhost", "--protocol", "http2", "--no-autoupdate" -WorkingDirectory (Split-Path -Parent $exe) -WindowStyle Hidden -RedirectStandardOutput (Join-Path $RuntimeDir "tunnel.out") -RedirectStandardError (Join-Path $RuntimeDir "tunnel.err") -PassThru
$p.Id | Out-File (Join-Path $RuntimeDir "tunnel.pid") -Encoding ascii

Write-Host "Menunggu URL publik dari trycloudflare..."
$url = $null
for ($i = 0; $i -lt 120; $i++) {
  Start-Sleep -Seconds 1
  $txt = ""
  foreach ($f in @("tunnel.err", "tunnel.out")) {
    $fp = Join-Path $RuntimeDir $f
    if (Test-Path -LiteralPath $fp) { $txt += (Get-Content -LiteralPath $fp -Raw -ErrorAction SilentlyContinue) }
  }
  if ($txt -match "https://[a-zA-Z0-9-]+\.trycloudflare\.com") { $url = $Matches[0]; break }
  if ($p.HasExited) { break }
}

if ($url) {
  $url | Out-File (Join-Path $RuntimeDir "tunnel.url") -Encoding ascii
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
