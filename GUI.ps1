$ErrorActionPreference = "Stop"
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$settingsFile = Join-Path $here "settings.json"
$cloudflared = Join-Path $here "cloudflared.exe"

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName System.Windows.Forms

try {
  Add-Type -Namespace FT -Name Win -MemberDefinition @"
[DllImport("user32.dll")] public static extern bool ShowWindow(System.IntPtr hWnd, int nCmdShow);
"@
  $h = (Get-Process -Id $PID).MainWindowHandle
  if ($h -ne [IntPtr]::Zero) { [void][FT.Win]::ShowWindow($h, 0) }
} catch {}

[xml]$xamlDoc = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        Title="Folder Tunnel" Height="580" Width="620" WindowStartupLocation="CenterScreen"
        Background="#F4F5F7" ResizeMode="CanMinimize">
  <StackPanel Margin="20">
    <TextBlock Text="FOLDER TUNNEL" Foreground="#111827" FontSize="20" FontWeight="Bold"/>
    <TextBlock Text="Share folder ke internet tanpa install apa-apa" Foreground="#6B7280" FontSize="12" Margin="0,2,0,16"/>
    <TextBlock Text="Folder yang di-share:" Foreground="#374151"/>
    <DockPanel Margin="0,4,0,12">
      <Button Name="BtnBrowse" Content="Pilih folder..." Width="110" Height="30" DockPanel.Dock="Right" Margin="8,0,0,0"/>
      <TextBox Name="TxtFolder" Height="30" VerticalContentAlignment="Center" Background="White" Foreground="#111827" BorderBrush="#D1D5DB" Padding="6,0" IsReadOnly="True"/>
    </DockPanel>
    <TextBlock Text="Password (opsional, kosong = bebas akses):" Foreground="#374151"/>
    <PasswordBox Name="PwPass" Height="30" Background="White" Foreground="#111827" BorderBrush="#D1D5DB" Padding="6,0" Margin="0,4,0,12"/>
    <CheckBox Name="ChkUpload" Content="Izin upload file dari browser" Foreground="#374151" IsChecked="True" Margin="0,0,0,4"/>
    <CheckBox Name="ChkDelete" Content="Izin hapus file dari browser" Foreground="#374151" Margin="0,0,0,12"/>
    <WrapPanel Margin="0,0,0,12">
      <Button Name="BtnInternet" Content="Share ke INTERNET" Width="150" Height="36" Background="#2563EB" Foreground="White" FontWeight="Bold" Margin="0,0,8,0"/>
      <Button Name="BtnLocal" Content="Server lokal saja" Width="130" Height="36" Background="White" BorderBrush="#D1D5DB" Margin="0,0,8,0"/>
      <Button Name="BtnStop" Content="Stop semua" Width="100" Height="36" Background="White" BorderBrush="#D1D5DB" Margin="0,0,8,0"/>
      <Button Name="BtnOpen" Content="Buka browser" Width="110" Height="36" Background="White" BorderBrush="#D1D5DB" IsEnabled="False"/>
    </WrapPanel>
    <StackPanel Name="PnlDl" Visibility="Collapsed" Margin="0,0,0,12">
      <TextBlock Name="LblDl" Text="Mengunduh cloudflared..." Foreground="#374151" FontSize="11" Margin="0,0,0,3"/>
      <ProgressBar Name="PbDl" Height="14" Minimum="0" Maximum="100"/>
    </StackPanel>
    <Border Background="White" BorderBrush="#2563EB" BorderThickness="1" CornerRadius="4" Padding="10" Margin="0,0,0,12">
      <StackPanel>
        <TextBlock Text="URL PUBLIK" Foreground="#6B7280" FontSize="11"/>
        <TextBlock Name="LblUrl" Text="belum aktif" Foreground="#2563EB" FontSize="14" FontWeight="Bold" TextWrapping="Wrap" Margin="0,2,0,0"/>
      </StackPanel>
    </Border>
    <TextBlock Text="LOG" Foreground="#6B7280" FontSize="11"/>
    <TextBox Name="TxtLog" Height="150" IsReadOnly="True" Background="White" Foreground="#1F2937" FontFamily="Consolas" FontSize="11" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled" TextWrapping="Wrap" Margin="0,4,0,0" BorderBrush="#E5E7EB"/>
  </StackPanel>
</Window>
"@

$reader = New-Object System.Xml.XmlNodeReader $xamlDoc
$win = [System.Windows.Markup.XamlReader]::Load($reader)
foreach ($n in "BtnBrowse","TxtFolder","PwPass","ChkUpload","ChkDelete","BtnInternet","BtnLocal","BtnStop","BtnOpen","LblUrl","TxtLog","PnlDl","PbDl","LblDl") {
  Set-Variable -Name $n -Value $win.FindName($n) -Scope Script
}

$script:Port = 8080
$script:waitingUrl = $false
$script:urlTries = 0
$script:pendingInternet = $false
$script:dlPs = $null
$script:dlHandle = $null
$script:serverCheckTicks = -1

if (Test-Path -LiteralPath $settingsFile) {
  try {
    $s = Get-Content -LiteralPath $settingsFile -Raw | ConvertFrom-Json
    $script:TxtFolder.Text = [string]$s.folder
    $script:PwPass.Password = [string]$s.password
    $script:ChkUpload.IsChecked = [bool]$s.upload
    $script:ChkDelete.IsChecked = [bool]$s.delete
    if ($s.port) { $script:Port = [int]$s.port }
  } catch {}
}

function Log([string]$msg) {
  $script:TxtLog.AppendText("[" + (Get-Date -Format "HH:mm:ss") + "]  " + $msg + [Environment]::NewLine)
  $script:TxtLog.ScrollToEnd()
}

function Save-Settings {
  @{ folder = $script:TxtFolder.Text; password = $script:PwPass.Password; upload = [bool]$script:ChkUpload.IsChecked; delete = [bool]$script:ChkDelete.IsChecked; port = $script:Port } |
    ConvertTo-Json | Set-Content -LiteralPath $settingsFile -Encoding UTF8
}

function Test-PidAlive([string]$name) {
  $p = Join-Path $here $name
  if (-not (Test-Path -LiteralPath $p)) { return $false }
  $v = Get-Content -LiteralPath $p -First 1 -ErrorAction SilentlyContinue
  if (-not $v) { return $false }
  $v = ([string]$v).Trim()
  if ($v -match "^\d+$") { return $null -ne (Get-Process -Id ([int]$v) -ErrorAction SilentlyContinue) }
  return $false
}

function Start-Server {
  $folder = $script:TxtFolder.Text
  $up = if ($script:ChkUpload.IsChecked) { "1" } else { "0" }
  $dl = if ($script:ChkDelete.IsChecked) { "1" } else { "0" }
  foreach ($f in "server.log", "server.err", "server.pid") { Remove-Item (Join-Path $here $f) -Force -ErrorAction SilentlyContinue }
  $argStr = "-NoProfile -ExecutionPolicy Bypass -File `"$here\server.ps1`" -Root `"$folder`" -Port $script:Port -Password `"$($script:PwPass.Password)`" -AllowUpload $up -AllowDelete $dl"
  Start-Process powershell -ArgumentList $argStr -WindowStyle Hidden -RedirectStandardOutput (Join-Path $here "server.log") -RedirectStandardError (Join-Path $here "server.err") | Out-Null
  $script:serverCheckTicks = 0
  Log "Server mulai: '$folder' di http://localhost:$script:Port"
}

function Start-Tunnel {
  $script:waitingUrl = $true
  $script:urlTries = 0
  $script:BtnInternet.IsEnabled = $false
  Log "Membuat URL publik (trycloudflare), mohon tunggu..."
  Start-Process powershell -ArgumentList @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", (Join-Path $here "tunnel.ps1"), "-Port", "$script:Port") -WindowStyle Hidden | Out-Null
}

function Start-Download {
  Log "Mengunduh cloudflared (portable ~55MB, sekali saja)..."
  $script:BtnInternet.IsEnabled = $false
  $script:PnlDl.Visibility = "Visible"
  $script:PbDl.Value = 0
  $script:PbDl.IsIndeterminate = $false
  $script:LblDl.Text = "Menghubungkan..."
  $script:dlHash = [hashtable]::Synchronized(@{ ok = $false; error = $null; total = 0 })
  $sb = {
    param($dst, $hash)
    $url = "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-windows-amd64.exe"
    $tmp = "$dst.download"
    $errs = @()
    try {
      try { [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12 } catch {}
      $curl = Join-Path $env:SystemRoot "System32\curl.exe"
      if (Test-Path $curl) {
        try {
          $head = & $curl -sIL --connect-timeout 15 --max-time 30 $url 2>$null
          $m = ($head | Select-String -Pattern "content-length:\s*(\d+)" -AllMatches).Matches
          if ($m.Count -gt 0) { $hash.total = [long]$m[$m.Count - 1].Groups[1].Value }
        } catch {}
        $null = & $curl -L -sS --retry 2 --retry-delay 2 --connect-timeout 20 --speed-time 30 --speed-limit 2048 --max-time 300 -o $tmp $url 2>"$tmp.err"
        if ($LASTEXITCODE -ne 0) {
          $errs += "curl exit $LASTEXITCODE"
          $ef = "$tmp.err"
          if (Test-Path $ef) { $errs += (((Get-Content $ef -Tail 2 -ErrorAction SilentlyContinue) -join " | ")) }
        }
      }
      if (-not (Test-Path $tmp) -or (Get-Item $tmp -ErrorAction SilentlyContinue).Length -lt 1000000) {
        $errs += "curl tidak lengkap, coba fallback..."
        $ProgressPreference = "SilentlyContinue"
        Invoke-WebRequest $url -OutFile $tmp -UseBasicParsing -TimeoutSec 300
      }
      if (-not (Test-Path $tmp) -or (Get-Item $tmp).Length -lt 1000000) { throw "file unduhan tidak lengkap. $($errs -join ' | ')" }
      if (Test-Path $dst) { Remove-Item $dst -Force }
      Move-Item $tmp $dst -Force
      $hash.ok = $true
    } catch {
      $hash.error = $_.Exception.Message
      if (Test-Path $tmp) { Remove-Item $tmp -Force -ErrorAction SilentlyContinue }
      Remove-Item "$tmp.err" -Force -ErrorAction SilentlyContinue
    }
  }
  $script:dlStart = Get-Date
  $script:dlWarned = $false
  $script:dlPs = [powershell]::Create()
  $null = $script:dlPs.AddScript($sb).AddArgument($cloudflared).AddArgument($script:dlHash)
  $script:dlHandle = $script:dlPs.BeginInvoke()
}

function Stop-All([switch]$Quiet) {
  foreach ($pf in "tunnel.pid", "server.pid") {
    $p = Join-Path $here $pf
    if (Test-Path -LiteralPath $p) {
      $v = ([string](Get-Content -LiteralPath $p -First 1 -ErrorAction SilentlyContinue)).Trim()
      if ($v -match "^\d+$") { try { Stop-Process -Id ([int]$v) -Force -ErrorAction SilentlyContinue } catch {} }
      Remove-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue
    }
  }
  Remove-Item (Join-Path $here "tunnel.url") -Force -ErrorAction SilentlyContinue
  $script:LblUrl.Text = "belum aktif"
  $script:BtnOpen.IsEnabled = $false
  $script:waitingUrl = $false
  if (-not $script:dlPs) { $script:BtnInternet.IsEnabled = $true }
  if (-not $Quiet) { Log "Semua server & tunnel dihentikan." }
}

$BtnBrowse.Add_Click({
  $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
  $dlg.Description = "Pilih folder yang mau di-share ke internet"
  $dlg.ShowNewFolderButton = $false
  if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
    $script:TxtFolder.Text = $dlg.SelectedPath
    Save-Settings
  }
})

$BtnInternet.Add_Click({
  if (-not (Test-Path -LiteralPath $script:TxtFolder.Text)) { [System.Windows.MessageBox]::Show("Pilih folder dulu!", "Folder Tunnel", "OK", "Warning") | Out-Null; return }
  Save-Settings
  Stop-All -Quiet
  Start-Server
  if ($script:dlPs) {
    $script:pendingInternet = $true
    Log "Menunggu download cloudflared selesai..."
  } elseif (Test-Path -LiteralPath $cloudflared) {
    Start-Tunnel
  } else {
    $script:pendingInternet = $true
    Start-Download
  }
})

$BtnLocal.Add_Click({
  if (-not (Test-Path -LiteralPath $script:TxtFolder.Text)) { [System.Windows.MessageBox]::Show("Pilih folder dulu!", "Folder Tunnel", "OK", "Warning") | Out-Null; return }
  Save-Settings
  Stop-All -Quiet
  Start-Server
})

$BtnStop.Add_Click({ Stop-All })

$BtnOpen.Add_Click({
  $u = $script:LblUrl.Text
  if ($u -like "https://*trycloudflare*") { Start-Process $u }
  elseif (Test-PidAlive "server.pid") { Start-Process "http://localhost:$script:Port" }
})

$win.Add_Closing({
  $running = (Test-PidAlive "server.pid") -or (Test-PidAlive "tunnel.pid")
  if ($running) {
    $r = [System.Windows.MessageBox]::Show("Tutup aplikasi dan hentikan server + tunnel?", "Folder Tunnel", [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Question)
    if ($r -ne [System.Windows.MessageBoxResult]::Yes) { $this.DialogResult = $false; $_.Cancel = $true; return }
    Stop-All -Quiet
  }
})

$script:timer = New-Object System.Windows.Threading.DispatcherTimer
$script:timer.Interval = [TimeSpan]::FromMilliseconds(800)
$script:timer.Add_Tick({
  try {
    if ($script:dlPs) {
      $tmp = "$cloudflared.download"
      $r = 0
      if (Test-Path -LiteralPath $tmp) { $r = (Get-Item -LiteralPath $tmp -ErrorAction SilentlyContinue).Length }
      $t = [long]$script:dlHash.total
      $el = [int]((Get-Date) - $script:dlStart).TotalSeconds
      if ($r -gt 0) {
        $script:dlWarned = $false
        if ($t -gt 0) {
          $pct = [math]::Min(100, [int](100 * $r / $t))
          $script:PbDl.IsIndeterminate = $false
          $script:PbDl.Value = $pct
          $script:LblDl.Text = ("Mengunduh cloudflared: {0:N1} MB / {1:N1} MB  ({2}%)  [{3} dtk]" -f ($r / 1MB), ($t / 1MB), $pct, $el)
        } else {
          $script:PbDl.IsIndeterminate = $true
          $script:LblDl.Text = ("Mengunduh cloudflared: {0:N1} MB terunduh  [{1} dtk]" -f ($r / 1MB), $el)
        }
      } else {
        $script:PbDl.IsIndeterminate = $true
        $script:LblDl.Text = "Menghubungkan ke github.com...  [$el dtk]"
        if ($el -ge 45 -and -not $script:dlWarned) {
          $script:dlWarned = $true
          $ef = "$cloudflared.download.err"
          $errTxt = ""
          if (Test-Path $ef) { $errTxt = ((Get-Content $ef -Tail 2 -ErrorAction SilentlyContinue) -join " | ") }
          Log "Koneksi lambat: $el dtk belum ada data. $errTxt"
        }
      }
      if ((Test-Path -LiteralPath $cloudflared) -and ((Get-Item -LiteralPath $cloudflared -ErrorAction SilentlyContinue).Length -gt 1000000)) {
        try { $script:dlPs.Stop() } catch {}
        $script:dlPs = $null
        $script:dlHandle = $null
        $script:PnlDl.Visibility = "Collapsed"
        $script:PbDl.Value = 0
        $script:PbDl.IsIndeterminate = $false
        $script:BtnInternet.IsEnabled = $true
        Log "cloudflared terdeteksi siap di folder aplikasi."
        if ($script:pendingInternet) { $script:pendingInternet = $false; Start-Tunnel }
      } elseif ($script:dlHandle -and $script:dlHandle.IsCompleted) {
        try { $null = $script:dlPs.EndInvoke($script:dlHandle) } catch {}
        $script:dlPs = $null
        $script:dlHandle = $null
        $script:PnlDl.Visibility = "Collapsed"
        $script:PbDl.Value = 0
        $script:PbDl.IsIndeterminate = $false
        $script:BtnInternet.IsEnabled = $true
        if ($script:dlHash.error) {
          Log "GAGAL download cloudflared: $($script:dlHash.error)"
        } else {
          Log "cloudflared siap dipakai."
          if ($script:pendingInternet) { $script:pendingInternet = $false; Start-Tunnel }
        }
      } else {
        if ($r -eq $script:dlLastSize) { $script:dlStallTicks++ } else { $script:dlStallTicks = 0; $script:dlLastSize = $r }
        if ($script:dlStallTicks -gt 75) {
          try { $script:dlPs.Stop() } catch {}
          $script:dlPs = $null
          $script:dlHandle = $null
          $script:PnlDl.Visibility = "Collapsed"
          $script:PbDl.Value = 0
          $script:PbDl.IsIndeterminate = $false
          $script:BtnInternet.IsEnabled = $true
          Remove-Item "$cloudflared.download" -Force -ErrorAction SilentlyContinue
          Log "Download macet (60+ dtk tanpa data) - dihentikan. Klik 'Share ke INTERNET' untuk coba lagi."
        }
      }
    }
    if ($script:waitingUrl) {
      $script:urlTries++
      $txt = ""
      foreach ($f in "tunnel.err", "tunnel.out") {
        $fp = Join-Path $here $f
        if (Test-Path -LiteralPath $fp) { $txt += [string](Get-Content -LiteralPath $fp -Raw -ErrorAction SilentlyContinue) }
      }
      if ($txt -match "https://[a-zA-Z0-9-]+\.trycloudflare\.com") {
        $u = $Matches[0]
        $script:waitingUrl = $false
        $script:LblUrl.Text = $u
        $script:BtnOpen.IsEnabled = $true
        $script:BtnInternet.IsEnabled = $true
        $u | Out-File (Join-Path $here "tunnel.url") -Encoding ascii
        Log "URL PUBLIK: $u"
      } elseif ($script:urlTries -gt 225) {
        $script:waitingUrl = $false
        $script:BtnInternet.IsEnabled = $true
        $ef = Join-Path $here "tunnel.err"
        $tail = ""
        if (Test-Path $ef) { $tail = ((Get-Content $ef -Tail 3 -ErrorAction SilentlyContinue) -join " ") }
        Log "GAGAL dapat URL (timeout 3 menit). $tail"
      }
    }
    if ($script:serverCheckTicks -ge 0) {
      $script:serverCheckTicks++
      if ($script:serverCheckTicks -eq 6) {
        if (-not (Test-PidAlive "server.pid")) {
          $ef = Join-Path $here "server.err"
          $lf = Join-Path $here "server.log"
          $msg = ""
          if (Test-Path $lf) { $msg = ((Get-Content $lf -Tail 2 -ErrorAction SilentlyContinue) -join " | ") }
          if (Test-Path $ef) { $msg += " " + ((Get-Content $ef -Tail 3 -ErrorAction SilentlyContinue) -join " | ") }
          Log "Server GAGAL jalan. $msg"
        }
        $script:serverCheckTicks = -1
      }
    }
  } catch {}
})

Log "Folder Tunnel siap. Pilih folder, lalu klik 'Share ke INTERNET'."
if (-not (Test-Path -LiteralPath $cloudflared)) { Start-Download } else { Log "cloudflared siap." }
[void]$win.ShowDialog()