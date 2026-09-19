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
        Title="Folder Tunnel" Height="560" Width="620" WindowStartupLocation="CenterScreen"
        Background="#12141C" ResizeMode="CanMinimize">
  <StackPanel Margin="20">
    <TextBlock Text="FOLDER TUNNEL" Foreground="White" FontSize="20" FontWeight="Bold"/>
    <TextBlock Text="Share folder ke internet tanpa install apa-apa" Foreground="#9AA0AE" FontSize="12" Margin="0,2,0,16"/>
    <TextBlock Text="Folder yang di-share:" Foreground="#E6E6E6"/>
    <DockPanel Margin="0,4,0,12">
      <Button Name="BtnBrowse" Content="Pilih folder..." Width="110" Height="30" DockPanel.Dock="Right" Margin="8,0,0,0"/>
      <TextBox Name="TxtFolder" Height="30" VerticalContentAlignment="Center" Background="#1B1E29" Foreground="#E6E6E6" BorderBrush="#2A2D3A" Padding="6,0" IsReadOnly="True"/>
    </DockPanel>
    <TextBlock Text="Password (opsional, kosong = bebas akses):" Foreground="#E6E6E6"/>
    <PasswordBox Name="PwPass" Height="30" Background="#1B1E29" Foreground="#E6E6E6" BorderBrush="#2A2D3A" Padding="6,0" Margin="0,4,0,12"/>
    <CheckBox Name="ChkUpload" Content="Izin upload file dari browser" Foreground="#E6E6E6" IsChecked="True" Margin="0,0,0,4"/>
    <CheckBox Name="ChkDelete" Content="Izin hapus file dari browser" Foreground="#E6E6E6" Margin="0,0,0,12"/>
    <WrapPanel Margin="0,0,0,12">
      <Button Name="BtnInternet" Content="Share ke INTERNET" Width="150" Height="36" Background="#2F6FD6" Foreground="White" FontWeight="Bold" Margin="0,0,8,0"/>
      <Button Name="BtnLocal" Content="Server lokal saja" Width="130" Height="36" Margin="0,0,8,0"/>
      <Button Name="BtnStop" Content="Stop semua" Width="100" Height="36" Margin="0,0,8,0"/>
      <Button Name="BtnOpen" Content="Buka browser" Width="110" Height="36" IsEnabled="False"/>
    </WrapPanel>
    <Border Background="#1B1E29" BorderBrush="#2F6FD6" BorderThickness="1" CornerRadius="4" Padding="10" Margin="0,0,0,12">
      <StackPanel>
        <TextBlock Text="URL PUBLIK" Foreground="#9AA0AE" FontSize="11"/>
        <TextBlock Name="LblUrl" Text="belum aktif" Foreground="#7AB7FF" FontSize="14" FontWeight="Bold" TextWrapping="Wrap" Margin="0,2,0,0"/>
      </StackPanel>
    </Border>
    <TextBlock Text="LOG" Foreground="#9AA0AE" FontSize="11"/>
    <TextBox Name="TxtLog" Height="150" IsReadOnly="True" Background="#0D0F15" Foreground="#9FE6A0" FontFamily="Consolas" FontSize="11" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled" TextWrapping="Wrap" Margin="0,4,0,0"/>
  </StackPanel>
</Window>
"@

$reader = New-Object System.Xml.XmlNodeReader $xamlDoc
$win = [System.Windows.Markup.XamlReader]::Load($reader)
foreach ($n in "BtnBrowse","TxtFolder","PwPass","ChkUpload","ChkDelete","BtnInternet","BtnLocal","BtnStop","BtnOpen","LblUrl","TxtLog") {
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
  Log "Mengunduh cloudflared (portable ~15MB, sekali saja)..."
  $script:BtnInternet.IsEnabled = $false
  $script:dlHash = @{ ok = $false; error = $null }
  $sb = {
    param($dst, $hash)
    try {
      $ProgressPreference = "SilentlyContinue"
      $tmp = "$dst.download"
      Invoke-WebRequest "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-windows-amd64.exe" -OutFile $tmp -UseBasicParsing
      if (Test-Path $dst) { Remove-Item $dst -Force }
      Move-Item $tmp $dst -Force
      $hash.ok = $true
    } catch { $hash.error = $_.Exception.Message }
  }
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
      $script:dlTicks = ($script:dlTicks + 1) % 6
      if ($script:dlTicks -eq 0) { Log "Masih mengunduh cloudflared... (butuh internet, ±30 dtk)" }
    }
    if ($script:dlHandle -and $script:dlHandle.IsCompleted) {
      $null = $script:dlPs.EndInvoke($script:dlHandle)
      $script:BtnInternet.IsEnabled = $true
      $script:dlPs = $null
      $script:dlHandle = $null
      if ($script:dlHash.error) {
        Log "GAGAL download cloudflared: $($script:dlHash.error)"
      } else {
        Log "cloudflared siap dipakai."
        if ($script:pendingInternet) { $script:pendingInternet = $false; Start-Tunnel }
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

if (-not (Test-Path -LiteralPath $cloudflared)) { Start-Download } else { Log "cloudflared siap." }

Log "Folder Tunnel siap. Pilih folder, lalu klik 'Share ke INTERNET'."
[void]$win.ShowDialog()