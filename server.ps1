param(
  [Parameter(Mandatory=$true)][string]$Root,
  [int]$Port = 8080,
  [string]$Password = "",
  [int]$AllowUpload = 0,
  [int]$AllowDelete = 0
)

$ErrorActionPreference = "Stop"
$Root = [System.IO.Path]::GetFullPath($Root)
if (-not (Test-Path -LiteralPath $Root)) { Write-Host "Folder tidak ditemukan: $Root"; Start-Sleep 5; exit 1 }

$PID | Out-File -FilePath (Join-Path $PSScriptRoot "server.pid") -Encoding ascii

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

$style = @'
<style>
body{font-family:'Segoe UI',Arial,sans-serif;background:#12141c;color:#e6e6e6;margin:0;padding:24px}
h1{font-size:20px;margin:0 0 10px}
a{color:#7ab7ff;text-decoration:none}
a:hover{text-decoration:underline}
table{border-collapse:collapse;width:100%;max-width:900px;margin-top:10px}
td,th{padding:7px 10px;border-bottom:1px solid #2a2d3a;text-align:left;white-space:nowrap}
th{color:#9aa0ae;font-size:12px;text-transform:uppercase}
td.sz{color:#9aa0ae;text-align:right}
.btn{background:#2f6fd6;color:#fff;border:0;padding:8px 14px;border-radius:6px;cursor:pointer;margin-top:8px}
input[type=file]{margin-top:8px;color:#e6e6e6}
input[type=password]{padding:8px;border-radius:6px;border:1px solid #444;background:#1b1e29;color:#fff}
.crumb{margin:14px 0;font-size:14px}
.note{margin-top:24px;color:#666;font-size:12px}
</style>
'@

function Send-Page($ctx, [string]$title, [string]$body, [int]$code = 200) {
  $html = "<!doctype html><html><head><meta charset='utf-8'><meta name='viewport' content='width=device-width,initial-scale=1'><title>$(Esc $title)</title>" + $style + "</head><body>" + $body + "</body></html>"
  $b = [System.Text.Encoding]::UTF8.GetBytes($html)
  $ctx.Response.StatusCode = $code
  $ctx.Response.ContentType = "text/html; charset=utf-8"
  $ctx.Response.ContentLength64 = $b.Length
  $ctx.Response.OutputStream.Write($b, 0, $b.Length)
  $ctx.Response.OutputStream.Close()
}

function Send-Error($ctx, [int]$code, [string]$msg) {
  $ctx.Response.StatusCode = $code
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
  $crumb = "<a href='/'>&#128193; [root]</a>"
  if ($relNorm) {
    $acc = ""
    foreach ($seg in $relNorm.Split("/")) {
      if ($seg -eq "") { continue }
      if ($acc) { $acc = $acc + "/" + $seg } else { $acc = $seg }
      $crumb += " / <a href='?p=$([System.Uri]::EscapeDataString($acc))'>$(Esc $seg)</a>"
    }
  }
  $rows = ""
  $items = @(Get-ChildItem -LiteralPath $full -Force | Sort-Object @{Expression={!$_.PSIsContainer};Descending=$true}, Name)
  foreach ($it in $items) {
    $r = if ($relNorm) { $relNorm + "/" + $it.Name } else { $it.Name }
    $er = [System.Uri]::EscapeDataString($r)
    if ($it.PSIsContainer) {
      $rows += "<tr><td><a href='?p=$er'>&#128193; $(Esc $it.Name)</a></td><td class='sz'>folder</td><td></td></tr>"
    } else {
      $sz = if ($it.Length -ge 1MB) { "{0:N1} MB" -f ($it.Length / 1MB) } elseif ($it.Length -ge 1KB) { "{0:N1} KB" -f ($it.Length / 1KB) } else { "$($it.Length) B" }
      $del = ""
      if ($AllowDelete -eq 1) {
        $del = "<td><a href='?del=$er' onclick=`"return confirm('Hapus $($it.Name)?')`" style='color:#ff7b7b'>[hapus]</a></td>"
      }
      $rows += "<tr><td><a href='?dl=$er'>$(Esc $it.Name)</a></td><td class='sz'>$sz</td>$del</tr>"
    }
  }
  if ($rows -eq "") { $rows = "<tr><td colspan='3' style='color:#888'>(folder kosong)</td></tr>" }
  $up = ""
  if ($AllowUpload -eq 1) {
    $enc = [System.Uri]::EscapeDataString($relNorm)
    $up = "<p><input type='file' id='f'><button class='btn' onclick='up()'>Upload ke sini</button></p><script>function up(){var f=document.getElementById('f').files[0];if(!f)return;fetch('upload?p=$enc&name='+encodeURIComponent(f.name),{method:'PUT',body:f}).then(function(r){if(r.ok){location.reload()}else{r.text().then(function(t){alert(t)})}})}</script>"
  }
  $body = "<h1>&#128230; Folder Tunnel</h1><div class='crumb'>$crumb</div>$up<table><tr><th>Nama</th><th>Ukuran</th><th></th></tr>$rows</table><p class='note'>Folder Tunnel &mdash; folder: $(Esc $Root)</p>"
  Send-Page $ctx "Folder Tunnel" $body 200
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

Write-Host "=== FOLDER TUNNEL - SERVER ==="
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
            Send-Page $ctx "Login" ("<h1>&#128274; Folder Tunnel</h1><p style='color:#ff7b7b'>Password salah.</p><form method='post' action='/login'><input type='password' name='pw' autofocus> <button class='btn'>Masuk</button></form>") 401
          }
        } else {
          Send-Page $ctx "Login" ("<h1>&#128274; Folder Tunnel</h1><p>Folder ini dilindungi password.</p><form method='post' action='/login'><input type='password' name='pw' autofocus> <button class='btn'>Masuk</button></form>") 401
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
          Send-Page $ctx "OK" ("<h1>Berhasil</h1><p>File '$(Esc $name)' terupload. <a href='javascript:history.back()'>Kembali</a></p>") 200
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
  Remove-Item (Join-Path $PSScriptRoot "server.pid") -ErrorAction SilentlyContinue
}