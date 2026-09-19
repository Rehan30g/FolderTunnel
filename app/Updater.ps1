param(
  [int]$AppPid = 0
)

$ErrorActionPreference = "Stop"
$appDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$rootDir = Split-Path -Parent $appDir
$dataDir = Join-Path $rootDir "data"
$logsDir = Join-Path $dataDir "logs"
foreach ($dir in $dataDir, $logsDir) { if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null } }
$versionFile = Join-Path $appDir "version.json"
$stateFile = Join-Path $dataDir "update-state.json"
$logFile = Join-Path $logsDir "update.log"
$repo = "Rehan30g/WinTunnel"
$apiUrl = "https://api.github.com/repos/$repo/releases/latest"
$headers = @{ "User-Agent" = "WinTunnel-Updater"; "Accept" = "application/vnd.github+json" }

function Write-UpdateLog([string]$message) {
  try { Add-Content -LiteralPath $logFile -Value ("[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $message) -Encoding UTF8 } catch {}
}

function Read-JsonFile([string]$path) {
  if (-not (Test-Path -LiteralPath $path)) { return $null }
  try { return Get-Content -LiteralPath $path -Raw | ConvertFrom-Json } catch { return $null }
}

function Save-State([string]$tag, [string]$result) {
  try {
    @{ dismissedTag = $tag; dismissedAt = (Get-Date).ToUniversalTime().ToString("o"); result = $result } |
      ConvertTo-Json | Set-Content -LiteralPath $stateFile -Encoding UTF8
  } catch {}
}

function Get-ChangeSummary($remote) {
  $messages = @()
  $body = [string]$remote.body
  if ($body) {
    foreach ($raw in ($body -split "`r?`n")) {
      $line = $raw.Trim()
      if (-not $line -or $line.StartsWith("#")) { continue }
      $line = $line.TrimStart("-", "*", " ")
      if ($line.Length -gt 100) { $line = $line.Substring(0, 97) + "..." }
      if ($line) { $messages += $line }
      if ($messages.Count -ge 4) { break }
    }
  }
  if ($messages.Count -eq 0) {
    $line = [string]$remote.name
    if (-not $line) { $line = "Versi $([string]$remote.tag_name)" }
    if ($line) { $messages += $line }
  }
  return (($messages | ForEach-Object { "- $_" }) -join [Environment]::NewLine)
}

function Stop-WinTunnelProcesses {
  try {
    $escapedDir = [regex]::Escape($rootDir)
    Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
      ($_.ProcessId -ne $PID) -and (
        ($_.CommandLine -and $_.CommandLine -match $escapedDir -and $_.CommandLine -match "(GUI|server|tunnel)\.ps1") -or
        ($_.ExecutablePath -and $_.ExecutablePath -ieq (Join-Path $dataDir "cloudflared.exe"))
      )
    } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
  } catch {}
  if ($AppPid -gt 0) { Stop-Process -Id $AppPid -Force -ErrorAction SilentlyContinue }
  Start-Sleep -Milliseconds 700
}

function Install-Update($remote) {
  $tempBase = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
  $tempRoot = Join-Path $tempBase ("WinTunnelUpdate-" + [guid]::NewGuid().ToString("N"))
  $zipFile = Join-Path $tempRoot "update.zip"
  $extractDir = Join-Path $tempRoot "extract"
  $backupDir = Join-Path $dataDir ".update-backup"
  $files = @("app\WinTunnel.ps1", "app\server.ps1", "app\tunnel.ps1", "app\WinTunnel.vbs", "app\Updater.ps1", "app\web\index.html", "app\web\login.html", "app\web\styles.css", "app\web\app.js", "start.bat", "README.md", ".gitignore")
  $updated = $false
  $backupReady = $false

  try {
    New-Item -ItemType Directory -Path $tempRoot, $extractDir -Force | Out-Null
    Invoke-WebRequest -Uri ([string]$remote.zipball_url) -Headers $headers -OutFile $zipFile -UseBasicParsing -TimeoutSec 60
    if ((Get-Item -LiteralPath $zipFile).Length -lt 1000) { throw "Arsip update tidak lengkap." }
    Expand-Archive -LiteralPath $zipFile -DestinationPath $extractDir -Force
    $source = Get-ChildItem -LiteralPath $extractDir -Directory | Select-Object -First 1
    if (-not $source -or -not (Test-Path -LiteralPath (Join-Path $source.FullName "app\WinTunnel.ps1")) -or -not (Test-Path -LiteralPath (Join-Path $source.FullName "app\server.ps1"))) {
      throw "Isi update tidak valid."
    }

    Stop-WinTunnelProcesses

    $resolvedRoot = [System.IO.Path]::GetFullPath($rootDir)
    $resolvedBackup = [System.IO.Path]::GetFullPath($backupDir)
    if (-not $resolvedBackup.StartsWith($resolvedRoot + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)) {
      throw "Lokasi backup tidak aman."
    }
    if (Test-Path -LiteralPath $resolvedBackup) { Remove-Item -LiteralPath $resolvedBackup -Recurse -Force }
    New-Item -ItemType Directory -Path $resolvedBackup -Force | Out-Null

    foreach ($name in $files) {
      $current = Join-Path $rootDir $name
      $backupTarget = Join-Path $resolvedBackup $name
      $backupParent = Split-Path -Parent $backupTarget
      if (-not (Test-Path -LiteralPath $backupParent)) { New-Item -ItemType Directory -Path $backupParent -Force | Out-Null }
      if (Test-Path -LiteralPath $current) { Copy-Item -LiteralPath $current -Destination $backupTarget -Force }
    }
    $backupReady = $true

    foreach ($name in $files) {
      $incoming = Join-Path $source.FullName $name
      $destination = Join-Path $rootDir $name
      $destinationParent = Split-Path -Parent $destination
      if (-not (Test-Path -LiteralPath $destinationParent)) { New-Item -ItemType Directory -Path $destinationParent -Force | Out-Null }
      if (Test-Path -LiteralPath $incoming) { Copy-Item -LiteralPath $incoming -Destination $destination -Force }
    }

    @{ version = ([string]$remote.tag_name).TrimStart("v"); tag = [string]$remote.tag_name; updatedAt = ([datetime]$remote.published_at).ToUniversalTime().ToString("o") } |
      ConvertTo-Json | Set-Content -LiteralPath $versionFile -Encoding UTF8
    Save-State ([string]$remote.tag_name) "installed"
    $updated = $true
    Write-UpdateLog "Update terpasang: $($remote.tag_name)"
  } catch {
    Write-UpdateLog "Update gagal: $($_.Exception.Message)"
    if ($backupReady -and (Test-Path -LiteralPath $backupDir)) {
      foreach ($name in $files) {
        $backup = Join-Path $backupDir $name
        $destination = Join-Path $rootDir $name
        if (Test-Path -LiteralPath $backup) { Copy-Item -LiteralPath $backup -Destination $destination -Force -ErrorAction SilentlyContinue }
      }
    }
    throw
  } finally {
    if (Test-Path -LiteralPath $tempRoot) {
      $resolvedTemp = [System.IO.Path]::GetFullPath($tempRoot)
      if ($resolvedTemp.StartsWith($tempBase, [System.StringComparison]::OrdinalIgnoreCase)) {
        Remove-Item -LiteralPath $resolvedTemp -Recurse -Force -ErrorAction SilentlyContinue
      }
    }
    if ($updated) {
      Start-Process -FilePath "wscript.exe" -ArgumentList ('"' + (Join-Path $appDir "WinTunnel.vbs") + '"') -WorkingDirectory $rootDir | Out-Null
    }
  }
}

$mutex = New-Object System.Threading.Mutex($false, "Local\WinTunnelUpdateChecker")
$hasLock = $false
try {
  $hasLock = $mutex.WaitOne(0, $false)
  if (-not $hasLock) { exit 0 }

  $local = Read-JsonFile $versionFile
  $remote = Invoke-RestMethod -Uri $apiUrl -Headers $headers -TimeoutSec 15
  $remoteTag = [string]$remote.tag_name
  $localTag = if ($local -and $local.tag) { [string]$local.tag } else { "" }
  if (-not $remoteTag -or $remoteTag -eq $localTag) { exit 0 }

  $state = Read-JsonFile $stateFile
  if ($state -and $state.dismissedTag -eq $remoteTag -and $state.result -eq "later") {
    try {
      $dismissed = [datetime]$state.dismissedAt
      if (((Get-Date).ToUniversalTime() - $dismissed.ToUniversalTime()).TotalHours -lt 24) { exit 0 }
    } catch {}
  }

  Add-Type -AssemblyName PresentationFramework
  $summary = Get-ChangeSummary $remote
  $dateText = ([datetime]$remote.published_at).ToLocalTime().ToString("dd MMM yyyy, HH:mm")
  $prompt = "Pembaruan WinTunnel tersedia.`n`nYang baru:`n$summary`n`nDiterbitkan: $dateText`n`nUpdate sekarang? Aplikasi akan ditutup sebentar lalu dibuka kembali."
  $choice = [System.Windows.MessageBox]::Show($prompt, "Pembaruan WinTunnel", [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Information)
  if ($choice -ne [System.Windows.MessageBoxResult]::Yes) {
    Save-State $remoteTag "later"
    exit 0
  }

  try {
    Install-Update $remote
    [System.Windows.MessageBox]::Show("Pembaruan berhasil dipasang. WinTunnel akan dibuka kembali.", "Pembaruan selesai", "OK", "Information") | Out-Null
  } catch {
    [System.Windows.MessageBox]::Show("Pembaruan gagal dipasang.`n`n$($_.Exception.Message)`n`nFile lama telah dipertahankan.", "Pembaruan gagal", "OK", "Error") | Out-Null
  }
} catch {
  Write-UpdateLog "Pemeriksaan gagal: $($_.Exception.Message)"
} finally {
  if ($hasLock) { try { $mutex.ReleaseMutex() } catch {} }
  $mutex.Dispose()
}
