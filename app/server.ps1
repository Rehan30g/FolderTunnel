param(
  [Parameter(Mandatory=$true)][string]$Root,
  [int]$Port = 8080,
  [string]$Password = "",
  [int]$AllowUpload = 0,
  [int]$AllowDelete = 0,
  [string]$RuntimeDir = $PSScriptRoot
)

$ErrorActionPreference = "Stop"
$Root = [System.IO.Path]::GetFullPath($Root)
if (-not (Test-Path -LiteralPath $Root)) { Write-Host "Folder tidak ditemukan: $Root"; Start-Sleep 5; exit 1 }
$RuntimeDir = [System.IO.Path]::GetFullPath($RuntimeDir)
if (-not (Test-Path -LiteralPath $RuntimeDir)) { New-Item -ItemType Directory -Path $RuntimeDir -Force | Out-Null }
$pidFile = Join-Path $RuntimeDir "server.pid"

$key = $null
if ($Password -ne "") {
  $sha = [System.Security.Cryptography.SHA256]::Create()
  $key = ([System.BitConverter]::ToString($sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($Password)))).Replace("-","").ToLowerInvariant()
  $sha.Dispose()
}

function Esc([string]$s) { return [System.Net.WebUtility]::HtmlEncode([string]$s) }

$mime = @{
  ".html"="text/html; charset=utf-8"; ".htm"="text/html; charset=utf-8"; ".css"="text/css"; ".js"="text/javascript"; ".json"="application/json";
  ".png"="image/png"; ".jpg"="image/jpeg"; ".jpeg"="image/jpeg"; ".gif"="image/gif"; ".svg"="image/svg+xml"; ".ico"="image/x-icon";
  ".pdf"="application/pdf"; ".txt"="text/plain; charset=utf-8"; ".zip"="application/zip"; ".rar"="application/octet-stream";
  ".mp3"="audio/mpeg"; ".wav"="audio/wav"; ".mp4"="video/mp4"; ".webm"="video/webm"; ".mkv"="video/x-matroska"
}

$webDir = Join-Path $PSScriptRoot "web"
foreach ($required in "index.html", "login.html", "styles.css", "app.js") {
  if (-not (Test-Path -LiteralPath (Join-Path $webDir $required))) { throw "File web tidak ditemukan: $required" }
}

function Get-Template([string]$name) {
  return Get-Content -LiteralPath (Join-Path $webDir $name) -Raw -Encoding UTF8
}

function Send-Html($ctx, [string]$html, [int]$code = 200) {
  $b = [System.Text.Encoding]::UTF8.GetBytes($html)
  $ctx.Response.StatusCode = $code
  $ctx.Response.ContentType = "text/html; charset=utf-8"
  $ctx.Response.ContentLength64 = $b.Length
  $ctx.Response.OutputStream.Write($b, 0, $b.Length)
  $ctx.Response.OutputStream.Close()
}

function Send-Asset($ctx, [string]$name, [string]$contentType) {
  $path = Join-Path $webDir $name
  if (-not (Test-Path -LiteralPath $path)) { Send-Error $ctx 404 "Tidak ditemukan"; return }
  $b = [System.IO.File]::ReadAllBytes($path)
  $ctx.Response.StatusCode = 200
  $ctx.Response.ContentType = $contentType
  $ctx.Response.ContentLength64 = $b.Length
  $ctx.Response.OutputStream.Write($b, 0, $b.Length)
  $ctx.Response.OutputStream.Close()
}

function Send-Error($ctx, [int]$code, [string]$msg) {
  $ctx.Response.StatusCode = $code
  $ctx.Response.ContentType = "text/plain; charset=utf-8"
  $b = [System.Text.Encoding]::UTF8.GetBytes($msg)
  $ctx.Response.ContentLength64 = $b.Length
  $ctx.Response.OutputStream.Write($b, 0, $b.Length)
  $ctx.Response.OutputStream.Close()
}

function Get-SafePath([string]$rel) {
  if ($null -eq $rel) { $rel = "" }
  $rel = $rel.Trim().TrimStart("/").TrimEnd("/")
  if ($rel -eq "") { return $Root }
  $full = [System.IO.Path]::GetFullPath((Join-Path $Root ($rel.Replace("/", "\"))))
  if (-not ($full + "\").StartsWith($Root + "\", [System.StringComparison]::OrdinalIgnoreCase)) { return $null }
  return $full
}

function Test-Auth($ctx) {
  if ($null -eq $key) { return $true }
  $c = $ctx.Request.Cookies["ftk"]
  if ($c -ne $null -and $c.Value -eq $key) { return $true }
  if ($ctx.Request.QueryString["key"] -eq $key) {
    $ck = New-Object System.Net.Cookie("ftk", $key, "/", $ctx.Request.Url.Host)
    $ctx.Response.Cookies.Add($ck)
    return $true
  }
  return $false
}

function Show-Listing($ctx, [string]$rel) {
  $full = Get-SafePath $rel
  $relNorm = $rel.Replace("\", "/").Trim("/")
  $crumb = "<a href='/'>Folder utama</a>"
  if ($relNorm) {
    $acc = ""
    foreach ($seg in $relNorm.Split("/")) {
      if ($seg -eq "") { continue }
      if ($acc) { $acc = $acc + "/" + $seg } else { $acc = $seg }
      $crumb += "<span class='sep'>/</span><a href='?p=$([System.Uri]::EscapeDataString($acc))'>$(Esc $seg)</a>"
    }
  }
  $rows = ""
  $items = @(Get-ChildItem -LiteralPath $full -Force | Sort-Object @{Expression={$_.PSIsContainer};Descending=$true}, Name)
  foreach ($it in $items) {
    $r = if ($relNorm) { $relNorm + "/" + $it.Name } else { $it.Name }
    $er = [System.Uri]::EscapeDataString($r)
    $changed = $it.LastWriteTime.ToString("yyyy-MM-dd HH:mm")
    if ($it.PSIsContainer) {
      $rows += "<tr><td class='name'><a href='?p=$er'>$(Esc $it.Name)</a></td><td><span class='type'>Folder</span></td><td class='meta size'>&mdash;</td><td class='meta hide-mobile'>$changed</td><td class='actions'><a class='action' href='?p=$er'>Buka</a></td></tr>"
    } else {
      $sz = if ($it.Length -ge 1MB) { "{0:N1} MB" -f ($it.Length / 1MB) } elseif ($it.Length -ge 1KB) { "{0:N1} KB" -f ($it.Length / 1KB) } else { "$($it.Length) B" }
      $actions = "<a class='action' href='?dl=$er'>Unduh</a>"
      if ($AllowDelete -eq 1) {
        $actions += "<a class='action danger' href='?del=$er' onclick=`"return confirm('Hapus file ini?')`">Hapus</a>"
      }
      $extLabel = if ($it.Extension) { $it.Extension.TrimStart(".").ToUpperInvariant() } else { "File" }
      $rows += "<tr><td class='name'><a href='?dl=$er'>$(Esc $it.Name)</a></td><td><span class='type'>$(Esc $extLabel)</span></td><td class='meta size'>$sz</td><td class='meta hide-mobile'>$changed</td><td class='actions'>$actions</td></tr>"
    }
  }
  if ($rows -eq "") { $rows = "<tr><td colspan='5' class='empty'>Folder ini masih kosong.</td></tr>" }
  $up = ""
  if ($AllowUpload -eq 1) {
    $enc = [System.Uri]::EscapeDataString($relNorm)
    $up = "<section class='upload' data-upload-path='$enc'><p class='upload-title'>Upload file</p><div class='upload-row'><input type='file' id='fileInput'><button class='btn' id='uploadButton' type='button'>Upload ke folder ini</button></div><div class='progress' id='uploadProgress'><span id='uploadBar'></span></div><div class='upload-status' id='uploadStatus'>Pilih satu file untuk diupload.</div></section>"
  }
  $countText = if ($items.Count -eq 1) { "1 item" } else { "$($items.Count) item" }
  $html = Get-Template "index.html"
  $html = $html.Replace("{{ITEM_COUNT}}", $countText).Replace("{{BREADCRUMB}}", $crumb).Replace("{{UPLOAD_SECTION}}", $up).Replace("{{ROWS}}", $rows)
  Send-Html $ctx $html 200
}

function Serve-File($ctx, $it) {
  $ext = $it.Extension.ToLowerInvariant()
  $ct = "application/octet-stream"
  if ($mime.ContainsKey($ext)) { $ct = $mime[$ext] }
  $ctx.Response.ContentType = $ct
  $ctx.Response.ContentLength64 = $it.Length
  if (-not $mime.ContainsKey($ext)) {
    $ctx.Response.Headers["Content-Disposition"] = "attachment; filename*=UTF-8''" + [System.Uri]::EscapeDataString($it.Name)
  }
  $fs = $it.OpenRead()
  $buf = New-Object byte[] 262144
  try {
    while ($true) {
      $n = $fs.Read($buf, 0, $buf.Length)
      if ($n -le 0) { break }
      $ctx.Response.OutputStream.Write($buf, 0, $n)
    }
  } finally { $fs.Close(); $ctx.Response.OutputStream.Close() }
}

$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://localhost:$Port/")
try { $listener.Start() } catch { Write-Host "GAGAL: $($_.Exception.Message)"; Start-Sleep 5; exit 1 }
$PID | Out-File -FilePath $pidFile -Encoding ascii

Write-Host "=== WINTUNNEL SERVER ==="
Write-Host "Folder  : $Root"
Write-Host "Lokal   : http://localhost:$Port/"
if ($key) { Write-Host "Password: AKTIF" } else { Write-Host "Password: TIDAK ADA (siapa pun dengan URL bisa akses!)" }
if ($AllowUpload -eq 1) { Write-Host "Upload  : AKTIF" } else { Write-Host "Upload  : mati" }
if ($AllowDelete -eq 1) { Write-Host "Hapus   : AKTIF" } else { Write-Host "Hapus   : mati" }
Write-Host "(Jangan tutup jendela ini selama tunnel dipakai)"
Write-Host ""

try {
  while ($listener.IsListening) {
    $ctx = $listener.GetContext()
    try {
      $req = $ctx.Request
      $q = $req.QueryString
      $path = $req.Url.AbsolutePath

      if ($path -eq "/assets/styles.css") { Send-Asset $ctx "styles.css" "text/css; charset=utf-8"; continue }
      if ($path -eq "/assets/app.js") { Send-Asset $ctx "app.js" "text/javascript; charset=utf-8"; continue }

      if ($path -eq "/login") {
        if ($null -eq $key) {
          $ctx.Response.StatusCode = 302
          $ctx.Response.RedirectLocation = "/"
          $ctx.Response.OutputStream.Close()
          continue
        }
        if ($req.HttpMethod -eq "POST") {
          $sr = New-Object System.IO.StreamReader($req.InputStream, [System.Text.Encoding]::UTF8)
          $body = $sr.ReadToEnd(); $sr.Close()
          $pw = ""
          $ix = $body.IndexOf("=")
          if ($ix -ge 0) { $pw = [System.Net.WebUtility]::UrlDecode($body.Substring($ix + 1)) }
          if ($pw -eq $Password) {
            $ck = New-Object System.Net.Cookie("ftk", $key, "/", $req.Url.Host)
            $ctx.Response.Cookies.Add($ck)
            $ctx.Response.StatusCode = 302
            $ctx.Response.RedirectLocation = "/"
            $ctx.Response.OutputStream.Close()
          } else {
            $html = (Get-Template "login.html").Replace("{{MESSAGE_CLASS}}", "error").Replace("{{MESSAGE}}", "Password salah. Silakan coba kembali.")
            Send-Html $ctx $html 401
          }
        } else {
          $html = (Get-Template "login.html").Replace("{{MESSAGE_CLASS}}", "").Replace("{{MESSAGE}}", "Folder ini dilindungi password.")
          Send-Html $ctx $html 401
        }
        continue
      }

      if (-not (Test-Auth $ctx)) {
        $ctx.Response.StatusCode = 302
        $ctx.Response.RedirectLocation = "/login"
        $ctx.Response.OutputStream.Close()
        continue
      }

      $dl = $q["dl"]
      if ($null -ne $dl) {
        $full = Get-SafePath $dl
        if ($null -eq $full) { Send-Error $ctx 403 "Akses ditolak"; continue }
        if (-not (Test-Path -LiteralPath $full)) { Send-Error $ctx 404 "Tidak ditemukan"; continue }
        $it = Get-Item -LiteralPath $full -Force
        if ($it.PSIsContainer) {
          $ctx.Response.StatusCode = 302
          $ctx.Response.RedirectLocation = "/?p=" + [System.Uri]::EscapeDataString($dl.Trim("/").Replace("\", "/"))
          $ctx.Response.OutputStream.Close()
          continue
        }
        Serve-File $ctx $it
        continue
      }

      $del = $q["del"]
      if ($null -ne $del) {
        if ($AllowDelete -ne 1) { Send-Error $ctx 403 "Hapus tidak diizinkan"; continue }
        $full = Get-SafePath $del
        if ($null -eq $full) { Send-Error $ctx 403 "Akses ditolak"; continue }
        if (Test-Path -LiteralPath $full) { Remove-Item -LiteralPath $full -Recurse -Force }
        $relTrim = $del.Trim("/").Replace("\", "/")
        $pr = ""
        $ix2 = $relTrim.LastIndexOf("/")
        if ($ix2 -gt 0) { $pr = $relTrim.Substring(0, $ix2) }
        $ctx.Response.StatusCode = 302
        if ($pr) { $ctx.Response.RedirectLocation = "/?p=" + [System.Uri]::EscapeDataString($pr) } else { $ctx.Response.RedirectLocation = "/" }
        $ctx.Response.OutputStream.Close()
        continue
      }

      if ($path -eq "/upload") {
        if ($AllowUpload -ne 1) { Send-Error $ctx 403 "Upload tidak diizinkan"; continue }
        $name = [System.IO.Path]::GetFileName([System.Net.WebUtility]::UrlDecode($q["name"]))
        $dir = Get-SafePath $q["p"]
        if ($null -eq $dir -or $name -eq "") { Send-Error $ctx 400 "Nama file tidak valid"; continue }
        $target = [System.IO.Path]::GetFullPath((Join-Path $dir $name))
        if (-not ($target + "\").StartsWith($Root + "\", [System.StringComparison]::OrdinalIgnoreCase)) { Send-Error $ctx 403 "Akses ditolak"; continue }
        try {
          $fs = [System.IO.File]::Create($target)
          $req.InputStream.CopyTo($fs)
          $fs.Close()
          Send-Error $ctx 200 "Upload selesai."
        } catch {
          Send-Error $ctx 500 ("Gagal simpan: " + $_.Exception.Message)
        }
        continue
      }

      $rel = $q["p"]
      if ($null -eq $rel) { $rel = "" }
      $rel = $rel.TrimStart("/").TrimEnd("/")
      $full = Get-SafePath $rel
      if ($null -eq $full) { Send-Error $ctx 403 "Akses ditolak"; continue }
      if (-not (Test-Path -LiteralPath $full)) { Send-Error $ctx 404 "Tidak ditemukan"; continue }
      $it = Get-Item -LiteralPath $full -Force
      if (-not $it.PSIsContainer) { Serve-File $ctx $it; continue }
      Show-Listing $ctx $rel
    } catch {
      try {
        $ctx.Response.StatusCode = 500
        $msg = [System.Text.Encoding]::UTF8.GetBytes("Error: $($_.Exception.Message)")
        $ctx.Response.OutputStream.Write($msg, 0, $msg.Length)
        $ctx.Response.OutputStream.Close()
      } catch {}
    }
  }
} finally {
  try { $listener.Stop() } catch {}
  Remove-Item $pidFile -ErrorAction SilentlyContinue
}
