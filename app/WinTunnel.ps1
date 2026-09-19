$ErrorActionPreference = "Stop"
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$rootDir = Split-Path -Parent $here
$dataDir = Join-Path $rootDir "data"
$logsDir = Join-Path $dataDir "logs"
foreach ($dir in $dataDir, $logsDir) { if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null } }
$settingsFile = Join-Path $dataDir "settings.json"
$cloudflared = Join-Path $dataDir "cloudflared.exe"
$internetShortcut = Join-Path $rootDir "WinTunnel Internet.url"

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
        Title="WinTunnel" Height="690" Width="680" MinHeight="620" MinWidth="620"
        WindowStartupLocation="CenterScreen" Background="#F6F8FC" ResizeMode="CanResizeWithGrip">
  <Window.Resources>
    <Style TargetType="Button">
      <Setter Property="FontFamily" Value="Segoe UI"/><Setter Property="FontSize" Value="13"/>
      <Setter Property="Padding" Value="14,7"/><Setter Property="Cursor" Value="Hand"/>
    </Style>
    <Style TargetType="TextBox"><Setter Property="FontFamily" Value="Segoe UI"/></Style>
    <Style TargetType="CheckBox"><Setter Property="FontFamily" Value="Segoe UI"/><Setter Property="FontSize" Value="13"/></Style>
  </Window.Resources>
  <Grid Margin="24">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
    </Grid.RowDefinitions>

    <DockPanel Grid.Row="0" Margin="0,0,0,18">
      <Border Name="StatusBadge" DockPanel.Dock="Right" Background="#E5E7EB" CornerRadius="12" Padding="10,5" VerticalAlignment="Center">
        <StackPanel Orientation="Horizontal"><Ellipse Name="StatusDot" Width="8" Height="8" Fill="#6B7280" Margin="0,0,7,0"/><TextBlock Name="LblState" Text="Siap" Foreground="#374151" FontWeight="SemiBold"/></StackPanel>
      </Border>
      <StackPanel>
        <TextBlock Text="WinTunnel" Foreground="#111827" FontSize="25" FontWeight="Bold"/>
        <TextBlock Text="Bagikan folder dengan satu klik &#x2014; tanpa jendela terminal." Foreground="#6B7280" FontSize="13" Margin="0,3,0,0"/>
      </StackPanel>
    </DockPanel>

    <Border Grid.Row="1" Background="White" BorderBrush="#E5E7EB" BorderThickness="1" CornerRadius="10" Padding="16" Margin="0,0,0,12">
      <StackPanel>
        <TextBlock Text="1. Pilih folder" Foreground="#111827" FontSize="15" FontWeight="SemiBold"/>
        <DockPanel Margin="0,9,0,0">
          <Button Name="BtnBrowse" Content="Pilih folder" Width="112" Height="34" DockPanel.Dock="Right" Margin="9,0,0,0" Background="#F9FAFB" BorderBrush="#D1D5DB"/>
          <TextBox Name="TxtFolder" Height="34" VerticalContentAlignment="Center" Background="#F9FAFB" Foreground="#111827" BorderBrush="#D1D5DB" Padding="9,0" IsReadOnly="True" ToolTip="Folder yang akan dibagikan"/>
        </DockPanel>
      </StackPanel>
    </Border>

    <Border Grid.Row="2" Background="White" BorderBrush="#E5E7EB" BorderThickness="1" CornerRadius="10" Padding="16" Margin="0,0,0,12">
      <Grid>
        <Grid.ColumnDefinitions><ColumnDefinition Width="1.2*"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
        <StackPanel Grid.Column="0" Margin="0,0,18,0">
          <TextBlock Text="2. Atur akses" Foreground="#111827" FontSize="15" FontWeight="SemiBold"/>
          <TextBlock Text="Password (disarankan untuk internet)" Foreground="#4B5563" FontSize="12" Margin="0,8,0,4"/>
          <PasswordBox Name="PwPass" Height="32" Background="#F9FAFB" Foreground="#111827" BorderBrush="#D1D5DB" Padding="8,0"/>
        </StackPanel>
        <StackPanel Grid.Column="1" VerticalAlignment="Bottom">
          <CheckBox Name="ChkUpload" Content="Pengunjung boleh upload" Foreground="#374151" IsChecked="True" Margin="0,0,0,8"/>
          <CheckBox Name="ChkDelete" Content="Pengunjung boleh menghapus" Foreground="#374151"/>
        </StackPanel>
      </Grid>
    </Border>

    <StackPanel Grid.Row="3" Margin="0,0,0,12">
      <TextBlock Text="3. Mulai berbagi" Foreground="#111827" FontSize="15" FontWeight="SemiBold" Margin="0,0,0,8"/>
      <WrapPanel>
        <Button Name="BtnInternet" Content="Bagikan ke internet" MinWidth="164" Height="40" Background="#2563EB" Foreground="White" BorderBrush="#2563EB" FontWeight="SemiBold" Margin="0,0,8,8"/>
        <Button Name="BtnLocal" Content="Hanya di komputer ini" MinWidth="162" Height="40" Background="White" BorderBrush="#D1D5DB" Margin="0,0,8,8"/>
        <Button Name="BtnStop" Content="Hentikan" MinWidth="100" Height="40" Background="#FFF7F7" Foreground="#B42318" BorderBrush="#FECACA" Margin="0,0,8,8"/>
        <Button Name="BtnOpen" Content="Buka" MinWidth="88" Height="40" Background="White" BorderBrush="#D1D5DB" IsEnabled="False" Margin="0,0,8,8"/>
        <Button Name="BtnCopy" Content="Salin link" MinWidth="100" Height="40" Background="White" BorderBrush="#D1D5DB" IsEnabled="False" Margin="0,0,0,8"/>
      </WrapPanel>
    </StackPanel>

    <Border Name="PnlDl" Grid.Row="4" Visibility="Collapsed" Background="#EFF6FF" BorderBrush="#BFDBFE" BorderThickness="1" CornerRadius="8" Padding="12" Margin="0,0,0,12">
      <StackPanel>
        <DockPanel Margin="0,0,0,7">
          <Button Name="BtnSkip" Content="Batalkan" Width="88" Height="27" Padding="8,2" DockPanel.Dock="Right" Margin="8,0,0,0" FontSize="11"/>
          <TextBlock Name="LblDl" Text="Menyiapkan komponen internet..." Foreground="#1E3A8A" FontSize="12" FontWeight="SemiBold" VerticalAlignment="Center" TextWrapping="Wrap"/>
        </DockPanel>
        <ProgressBar Name="PbDl" Height="10" Minimum="0" Maximum="100"/>
      </StackPanel>
    </Border>

    <Border Grid.Row="5" Background="White" BorderBrush="#DCE3EE" BorderThickness="1" CornerRadius="10" Padding="14" Margin="0,0,0,12">
      <Grid>
        <Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
        <Border Width="36" Height="36" CornerRadius="18" Background="#EFF6FF" Margin="0,0,12,0"><TextBlock Text="&#x2197;" FontSize="20" Foreground="#2563EB" HorizontalAlignment="Center" VerticalAlignment="Center"/></Border>
        <StackPanel Grid.Column="1">
          <TextBlock Name="LblHint" Text="Pilih folder, lalu tentukan cara membagikannya." Foreground="#4B5563" FontSize="12"/>
          <TextBlock Name="LblUrl" Text="Belum aktif" Foreground="#1D4ED8" FontSize="15" FontWeight="Bold" TextWrapping="Wrap" Margin="0,3,0,0"/>
        </StackPanel>
      </Grid>
    </Border>

    <Expander Grid.Row="6" Header="Detail aktivitas" Foreground="#6B7280" FontSize="12" IsExpanded="False">
      <TextBox Name="TxtLog" MinHeight="100" IsReadOnly="True" Background="White" Foreground="#1F2937" FontFamily="Consolas" FontSize="11" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled" TextWrapping="Wrap" Margin="0,7,0,0" BorderBrush="#E5E7EB"/>
    </Expander>
  </Grid>
</Window>
"@

$reader = New-Object System.Xml.XmlNodeReader $xamlDoc
$win = [System.Windows.Markup.XamlReader]::Load($reader)
foreach ($n in "BtnBrowse","TxtFolder","PwPass","ChkUpload","ChkDelete","BtnInternet","BtnLocal","BtnStop","BtnOpen","BtnCopy","LblUrl","LblHint","TxtLog","PnlDl","PbDl","LblDl","BtnSkip","StatusBadge","StatusDot","LblState") {
  Set-Variable -Name $n -Value $win.FindName($n) -Scope Script
}

$script:Port = 8080
$script:waitingUrl = $false
$script:urlTries = 0
$script:pendingInternet = $false
$script:dlPs = $null
$script:dlHandle = $null
$script:serverCheckTicks = -1
$script:dlLastSize = -1L
$script:dlStallTicks = 0
$script:mode = "idle"
$script:candidateUrl = $null
$script:urlCheckPs = $null
$script:urlCheckHandle = $null
$script:urlCheckHash = $null
$script:urlCheckAttempts = 0
$script:urlCheckDelayTicks = 0

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

function Set-State([string]$state, [string]$hint = "") {
  $map = @{
    idle       = @("Siap",        "#6B7280", "#E5E7EB")
    download   = @("Mengunduh",   "#2563EB", "#DBEAFE")
    connecting = @("Menghubungkan","#D97706", "#FEF3C7")
    online     = @("Online",      "#16A34A", "#DCFCE7")
    local      = @("Lokal aktif", "#16A34A", "#DCFCE7")
    error      = @("Perlu tindakan","#DC2626", "#FEE2E2")
    stopped    = @("Berhenti",    "#6B7280", "#E5E7EB")
  }
  $v = $map[$state]; if (-not $v) { $v = $map.idle }
  $script:LblState.Text = $v[0]
  $script:StatusDot.Fill = [System.Windows.Media.BrushConverter]::new().ConvertFromString($v[1])
  $script:StatusBadge.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString($v[2])
  if ($hint) { $script:LblHint.Text = $hint }
  $script:mode = $state
}

function Save-Settings {
  @{ folder = $script:TxtFolder.Text; password = $script:PwPass.Password; upload = [bool]$script:ChkUpload.IsChecked; delete = [bool]$script:ChkDelete.IsChecked; port = $script:Port } |
    ConvertTo-Json | Set-Content -LiteralPath $settingsFile -Encoding UTF8
}

function Save-InternetShortcut([string]$url) {
  if (-not $url -or $url -notlike "https://*trycloudflare.com") { return }
  try { "[InternetShortcut]`r`nURL=$url`r`n" | Set-Content -LiteralPath $internetShortcut -Encoding ASCII }
  catch { Log "Shortcut internet gagal dibuat: $($_.Exception.Message)" }
}

function Start-Updater {
  $checker = Join-Path $here "Updater.ps1"
  if (-not (Test-Path -LiteralPath $checker)) { return }
  try {
    Start-Process powershell -ArgumentList @("-NoProfile", "-STA", "-ExecutionPolicy", "Bypass", "-WindowStyle", "Hidden", "-File", $checker, "-AppPid", "$PID") -WindowStyle Hidden | Out-Null
  } catch { Log "Pemeriksaan update tidak dapat dimulai: $($_.Exception.Message)" }
}

function Test-PidAlive([string]$name) {
  $p = Join-Path $logsDir $name
  if (-not (Test-Path -LiteralPath $p)) { return $false }
  $v = Get-Content -LiteralPath $p -First 1 -ErrorAction SilentlyContinue
  if (-not $v) { return $false }
  $v = ([string]$v).Trim()
  if ($v -match "^\d+$") { return $null -ne (Get-Process -Id ([int]$v) -ErrorAction SilentlyContinue) }
  return $false
}

function Test-CloudflaredValid {
  if (-not (Test-Path -LiteralPath $cloudflared)) { return $false }
  try {
    if ((Get-Item -LiteralPath $cloudflared).Length -lt 10MB) { return $false }
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $cloudflared
    $psi.Arguments = "--version"
    $psi.WorkingDirectory = $here
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $p = [System.Diagnostics.Process]::Start($psi)
    if (-not $p.WaitForExit(6000)) { try { $p.Kill() } catch {}; return $false }
    $out = $p.StandardOutput.ReadToEnd() + $p.StandardError.ReadToEnd()
    return ($p.ExitCode -eq 0 -and $out -match "cloudflared version")
  } catch { return $false }
}

function Start-UrlCheck([string]$url) {
  if ($script:urlCheckPs -or -not $url) { return }
  $script:urlCheckHash = [hashtable]::Synchronized(@{ ok = $false; status = 0; error = $null })
  $sb = {
    param($target, $hash)
    $response = $null
    try {
      [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
      $req = [System.Net.HttpWebRequest]::Create($target)
      $req.AllowAutoRedirect = $true
      $req.Timeout = 8000
      $req.ReadWriteTimeout = 8000
      $req.UserAgent = "WinTunnel/1.1 health-check"
      $response = $req.GetResponse()
      $hash.status = [int]$response.StatusCode
      $hash.ok = ($hash.status -ge 200 -and $hash.status -lt 500)
    } catch [System.Net.WebException] {
      if ($_.Exception.Response) {
        $response = $_.Exception.Response
        $hash.status = [int]$response.StatusCode
        # 401 berarti server WinTunnel sudah dapat dijangkau dan hanya meminta password.
        $hash.ok = ($hash.status -ge 200 -and $hash.status -lt 500)
      } else {
        $hash.error = $_.Exception.Message
      }
    } catch {
      $hash.error = $_.Exception.Message
    } finally {
      if ($response) { try { $response.Close() } catch {} }
    }
  }
  $script:urlCheckPs = [powershell]::Create()
  $null = $script:urlCheckPs.AddScript($sb).AddArgument($url).AddArgument($script:urlCheckHash)
  $script:urlCheckHandle = $script:urlCheckPs.BeginInvoke()
  $script:urlCheckAttempts++
}

function Start-Server {
  $folder = $script:TxtFolder.Text
  $up = if ($script:ChkUpload.IsChecked) { "1" } else { "0" }
  $dl = if ($script:ChkDelete.IsChecked) { "1" } else { "0" }
  foreach ($f in "server.log", "server.err", "server.pid") { Remove-Item (Join-Path $logsDir $f) -Force -ErrorAction SilentlyContinue }
  $argStr = "-NoProfile -ExecutionPolicy Bypass -File `"$here\server.ps1`" -Root `"$folder`" -Port $script:Port -Password `"$($script:PwPass.Password)`" -AllowUpload $up -AllowDelete $dl -RuntimeDir `"$logsDir`""
  Start-Process powershell -ArgumentList $argStr -WindowStyle Hidden -RedirectStandardOutput (Join-Path $logsDir "server.log") -RedirectStandardError (Join-Path $logsDir "server.err") | Out-Null
  $script:serverCheckTicks = 0
  Set-State "connecting" "Menyalakan server folder..."
  $script:LblUrl.Text = "Sedang disiapkan..."
  Log "Server mulai: '$folder' di http://localhost:$script:Port"
}

function Start-Tunnel {
  foreach ($f in "tunnel.err", "tunnel.out", "tunnel.url", "tunnel.pid") {
    Remove-Item (Join-Path $logsDir $f) -Force -ErrorAction SilentlyContinue
  }
  $script:waitingUrl = $true
  $script:urlTries = 0
  $script:candidateUrl = $null
  $script:urlCheckAttempts = 0
  $script:urlCheckDelayTicks = 0
  $script:BtnInternet.IsEnabled = $false
  Set-State "connecting" "Server siap. Sedang membuat link internet yang aman..."
  $script:LblUrl.Text = "Membuat link publik..."
  Log "Membuat URL publik (trycloudflare), mohon tunggu..."
  Start-Process powershell -ArgumentList @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", (Join-Path $here "tunnel.ps1"), "-Port", "$script:Port", "-RuntimeDir", $logsDir, "-CloudflaredPath", $cloudflared) -WindowStyle Hidden | Out-Null
}

function Start-Download {
  Log "Mengunduh komponen internet cloudflared (sekali saja)..."
  if ((Test-Path -LiteralPath $cloudflared) -and -not (Test-CloudflaredValid)) {
    $bad = "$cloudflared.invalid"
    Remove-Item -LiteralPath $bad -Force -ErrorAction SilentlyContinue
    Move-Item -LiteralPath $cloudflared -Destination $bad -Force -ErrorAction SilentlyContinue
    Log "File cloudflared lama rusak/tidak lengkap; disisihkan dan diunduh ulang."
  }
  Remove-Item "$cloudflared.download" -Force -ErrorAction SilentlyContinue
  Remove-Item "$cloudflared.download.err" -Force -ErrorAction SilentlyContinue
  $script:BtnInternet.IsEnabled = $false
  $script:PnlDl.Visibility = "Visible"
  $script:BtnSkip.Visibility = "Visible"
  $script:PbDl.Value = 0
  $script:PbDl.IsIndeterminate = $true
  $script:BtnSkip.Content = "Batalkan"
  $script:LblDl.Text = "Menghubungkan ke server unduhan..."
  Set-State "download" "Menyiapkan komponen internet. Aplikasi tetap dapat digunakan setelah selesai."
  $script:LblUrl.Text = "Mengunduh komponen internet..."
  $script:dlHash = [hashtable]::Synchronized(@{ ok = $false; error = $null; total = 0L; received = 0L })
  $sb = {
    param($dst, $hash)
    $url = "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-windows-amd64.exe"
    $tmp = "$dst.download"
    $response = $null; $input = $null; $output = $null
    try {
      [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
      $req = [System.Net.HttpWebRequest]::Create($url)
      $req.AllowAutoRedirect = $true; $req.Timeout = 30000; $req.ReadWriteTimeout = 60000
      $req.UserAgent = "WinTunnel/1.1"
      $response = $req.GetResponse()
      $hash.total = [long]$response.ContentLength
      $input = $response.GetResponseStream()
      $output = [System.IO.File]::Create($tmp)
      $buf = New-Object byte[] 262144
      while (($n = $input.Read($buf, 0, $buf.Length)) -gt 0) {
        $output.Write($buf, 0, $n)
        $hash.received = [long]$hash.received + $n
      }
      $output.Flush(); $output.Close(); $output = $null
      $input.Close(); $input = $null; $response.Close(); $response = $null
      $fi = Get-Item -LiteralPath $tmp
      if ($fi.Length -lt 10MB) { throw "file unduhan terlalu kecil ($($fi.Length) byte)" }
      $fs = [System.IO.File]::OpenRead($tmp)
      try { if ($fs.ReadByte() -ne 0x4D -or $fs.ReadByte() -ne 0x5A) { throw "file unduhan bukan aplikasi Windows yang valid" } } finally { $fs.Close() }
      if (Test-Path $dst) { Remove-Item $dst -Force }
      Move-Item $tmp $dst -Force
      $hash.ok = $true
    } catch {
      $hash.error = $_.Exception.Message
    } finally {
      if ($output) { try { $output.Close() } catch {} }
      if ($input) { try { $input.Close() } catch {} }
      if ($response) { try { $response.Close() } catch {} }
      if (-not $hash.ok -and (Test-Path $tmp)) { Remove-Item $tmp -Force -ErrorAction SilentlyContinue }
    }
  }
  $script:dlStart = Get-Date
  $script:dlWarned = $false
  $script:dlLastSize = -1L
  $script:dlStallTicks = 0
  $script:dlPs = [powershell]::Create()
  $null = $script:dlPs.AddScript($sb).AddArgument($cloudflared).AddArgument($script:dlHash)
  $script:dlHandle = $script:dlPs.BeginInvoke()
}

function Stop-All([switch]$Quiet) {
  if ($script:urlCheckPs) {
    try { $script:urlCheckPs.Stop() } catch {}
    try { $script:urlCheckPs.Dispose() } catch {}
    $script:urlCheckPs = $null
    $script:urlCheckHandle = $null
  }
  $script:candidateUrl = $null
  foreach ($pf in "tunnel.pid", "server.pid") {
    $p = Join-Path $logsDir $pf
    if (Test-Path -LiteralPath $p) {
      $v = ([string](Get-Content -LiteralPath $p -First 1 -ErrorAction SilentlyContinue)).Trim()
      if ($v -match "^\d+$") { try { Stop-Process -Id ([int]$v) -Force -ErrorAction SilentlyContinue } catch {} }
      Remove-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue
    }
  }
  # Bersihkan hanya proses lama milik WinTunnel ini, bukan PowerShell/cloudflared lain.
  try {
    $escapedHere = [regex]::Escape($here)
    Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
      ($_.ProcessId -ne $PID) -and $_.CommandLine -and
      (($_.CommandLine -match $escapedHere -and $_.CommandLine -match "(server|tunnel)\.ps1") -or
       ($_.ExecutablePath -and $_.ExecutablePath -ieq $cloudflared))
    } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
  } catch {}
  Remove-Item (Join-Path $logsDir "tunnel.url") -Force -ErrorAction SilentlyContinue
  $script:LblUrl.Text = "Belum aktif"
  $script:LblHint.Text = "Pilih folder, lalu tentukan cara membagikannya."
  $script:BtnOpen.IsEnabled = $false
  $script:BtnCopy.IsEnabled = $false
  $script:waitingUrl = $false
  if (-not $script:dlPs) { $script:BtnInternet.IsEnabled = $true }
  Set-State "stopped" "Semua koneksi sudah dihentikan."
  if (-not $Quiet) { Log "Semua server & tunnel dihentikan." }
}

function Stop-Download([switch]$Quiet) {
  if ($script:dlPs) {
    try { $script:dlPs.Stop() } catch {}
    try { $script:dlPs.Dispose() } catch {}
    $script:dlPs = $null
    $script:dlHandle = $null
    Remove-Item "$cloudflared.download" -Force -ErrorAction SilentlyContinue
    Remove-Item "$cloudflared.download.err" -Force -ErrorAction SilentlyContinue
  }
  $script:pendingInternet = $false
  Stop-All -Quiet
  $script:PnlDl.Visibility = "Collapsed"
  $script:PbDl.Value = 0
  $script:PbDl.IsIndeterminate = $false
  $script:BtnInternet.IsEnabled = $true
  Set-State "stopped" "Unduhan dibatalkan. Mode lokal tetap dapat digunakan."
  $script:LblUrl.Text = "Unduhan dibatalkan"
  if (-not $Quiet) { Log "Download dibatalkan. Klik 'Bagikan ke internet' untuk mencoba lagi." }
}

$BtnSkip.Add_Click({
  if ($script:dlPs) { Stop-Download } else { $script:PnlDl.Visibility = "Collapsed" }
})

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
  if (-not (Test-Path -LiteralPath $script:TxtFolder.Text)) { [System.Windows.MessageBox]::Show("Pilih folder yang ingin dibagikan terlebih dahulu.", "WinTunnel", "OK", "Warning") | Out-Null; return }
  Save-Settings
  Stop-All -Quiet
  Start-Server
  if ($script:dlPs) {
    $script:pendingInternet = $true
    Log "Menunggu download cloudflared selesai..."
  } elseif (Test-CloudflaredValid) {
    Start-Tunnel
  } else {
    $script:pendingInternet = $true
    Start-Download
  }
})

$BtnLocal.Add_Click({
  if (-not (Test-Path -LiteralPath $script:TxtFolder.Text)) { [System.Windows.MessageBox]::Show("Pilih folder yang ingin dibagikan terlebih dahulu.", "WinTunnel", "OK", "Warning") | Out-Null; return }
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

$BtnCopy.Add_Click({
  $u = $script:LblUrl.Text
  if ($u -like "http*") {
    [System.Windows.Clipboard]::SetText($u)
    $script:LblHint.Text = "Link sudah disalin."
    Log "Link disalin ke clipboard."
  }
})

$win.Add_Closing({
  $running = (Test-PidAlive "server.pid") -or (Test-PidAlive "tunnel.pid")
  if ($running) {
    $r = [System.Windows.MessageBox]::Show("Tutup aplikasi dan hentikan server + tunnel?", "WinTunnel", [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Question)
    if ($r -ne [System.Windows.MessageBoxResult]::Yes) { $this.DialogResult = $false; $_.Cancel = $true; return }
    Stop-All -Quiet
  }
})

$script:timer = New-Object System.Windows.Threading.DispatcherTimer
$script:timer.Interval = [TimeSpan]::FromMilliseconds(800)
$script:timer.Add_Tick({
  try {
    if ($script:dlPs) {
      $r = [long]$script:dlHash.received
      $t = [long]$script:dlHash.total
      $el = [int]((Get-Date) - $script:dlStart).TotalSeconds
      if ($r -gt 0) {
        $script:dlWarned = $false
        if ($t -gt 0) {
          $pct = [math]::Min(100, [int](100 * $r / $t))
          $script:PbDl.IsIndeterminate = $false
          $script:PbDl.Value = $pct
          $script:LblDl.Text = ("Mengunduh komponen internet: {0:N1} MB / {1:N1} MB ({2}%)" -f ($r / 1MB), ($t / 1MB), $pct)
        } else {
          $script:PbDl.IsIndeterminate = $true
          $script:LblDl.Text = ("Mengunduh komponen internet: {0:N1} MB diterima" -f ($r / 1MB))
        }
      } else {
        $script:PbDl.IsIndeterminate = $true
        $script:LblDl.Text = "Menghubungkan ke server unduhan... ($el detik)"
        if ($el -ge 45 -and -not $script:dlWarned) {
          $script:dlWarned = $true
          Log "Koneksi unduhan lambat: $el detik belum ada data."
        }
      }
      if ($script:dlHandle -and $script:dlHandle.IsCompleted) {
        try { $null = $script:dlPs.EndInvoke($script:dlHandle) } catch { $script:dlHash.error = $_.Exception.Message }
        try { $script:dlPs.Dispose() } catch {}
        $script:dlPs = $null
        $script:dlHandle = $null
        $script:PbDl.IsIndeterminate = $false
        $script:BtnInternet.IsEnabled = $true
        $valid = $script:dlHash.ok -and (Test-CloudflaredValid)
        if (-not $valid) {
          $why = [string]$script:dlHash.error
          if (-not $why) { $why = "file selesai diunduh tetapi gagal diperiksa" }
          $script:PbDl.Value = 0
          $script:LblDl.Text = "Unduhan gagal: $why"
          $script:BtnSkip.Content = "Tutup"
          $script:pendingInternet = $false
          Stop-All -Quiet
          $script:PnlDl.Visibility = "Visible"
          Set-State "error" "Komponen internet belum siap. Periksa koneksi lalu coba lagi."
          $script:LblUrl.Text = "Unduhan gagal"
          Log "GAGAL download cloudflared: $why"
        } else {
          $script:PbDl.Value = 100
          $script:LblDl.Text = "Unduhan selesai dan sudah diverifikasi."
          $script:BtnSkip.Visibility = "Collapsed"
          Log "cloudflared selesai diunduh dan valid."
          if ($script:pendingInternet) { $script:pendingInternet = $false; Start-Tunnel }
        }
      } else {
        if ($r -eq $script:dlLastSize) { $script:dlStallTicks++ } else { $script:dlStallTicks = 0; $script:dlLastSize = $r }
        if ($script:dlStallTicks -gt 75) {
          try { $script:dlPs.Stop() } catch {}
          try { $script:dlPs.Dispose() } catch {}
          $script:dlPs = $null
          $script:dlHandle = $null
          $script:PbDl.Value = 0
          $script:PbDl.IsIndeterminate = $false
          $script:BtnInternet.IsEnabled = $true
          $script:pendingInternet = $false
          Remove-Item "$cloudflared.download" -Force -ErrorAction SilentlyContinue
          $script:LblDl.Text = "Unduhan berhenti: tidak ada data selama 60 detik."
          $script:BtnSkip.Content = "Tutup"
          Stop-All -Quiet
          $script:PnlDl.Visibility = "Visible"
          Set-State "error" "Koneksi terhenti. Klik 'Bagikan ke internet' untuk mencoba lagi."
          $script:LblUrl.Text = "Unduhan terhenti"
          Log "Download macet (60+ detik tanpa data) dan dihentikan."
        }
      }
    }
    if ($script:waitingUrl) {
      $script:urlTries++
      $txt = ""
      foreach ($f in "tunnel.err", "tunnel.out") {
        $fp = Join-Path $logsDir $f
        if (Test-Path -LiteralPath $fp) { $txt += [string](Get-Content -LiteralPath $fp -Raw -ErrorAction SilentlyContinue) }
      }
      if (-not $script:candidateUrl -and $txt -match "https://[a-zA-Z0-9-]+\.trycloudflare\.com") {
        $script:candidateUrl = $Matches[0]
        $script:LblUrl.Text = "Memverifikasi link publik..."
        Set-State "connecting" "URL sudah dibuat. Menunggu DNS dan koneksi Cloudflare benar-benar siap..."
        Log "URL dibuat; menunggu tunnel terdaftar dan dapat diakses..."
      }

      if ($script:urlCheckPs -and $script:urlCheckHandle -and $script:urlCheckHandle.IsCompleted) {
        try { $null = $script:urlCheckPs.EndInvoke($script:urlCheckHandle) } catch { $script:urlCheckHash.error = $_.Exception.Message }
        try { $script:urlCheckPs.Dispose() } catch {}
        $script:urlCheckPs = $null
        $script:urlCheckHandle = $null
        if ($script:urlCheckHash.ok -and (Test-PidAlive "tunnel.pid")) {
          $u = $script:candidateUrl
          $script:waitingUrl = $false
          $script:LblUrl.Text = $u
          $script:BtnOpen.IsEnabled = $true
          $script:BtnCopy.IsEnabled = $true
          $script:BtnInternet.IsEnabled = $true
          $script:PnlDl.Visibility = "Collapsed"
          Set-State "online" "Link sudah diuji dan aktif. Siapa pun yang punya link dapat membuka folder sesuai izin."
          $u | Out-File (Join-Path $logsDir "tunnel.url") -Encoding ascii
          Save-InternetShortcut $u
          Log "ONLINE TERVERIFIKASI (HTTP $($script:urlCheckHash.status)): $u"
        } else {
          $script:urlCheckDelayTicks = 3
          if ($script:urlCheckAttempts -eq 1 -or ($script:urlCheckAttempts % 5) -eq 0) {
            $detail = if ($script:urlCheckHash.status) { "HTTP $($script:urlCheckHash.status)" } else { [string]$script:urlCheckHash.error }
            Log "Link belum siap ($detail), pemeriksaan akan diulang..."
          }
        }
      }

      if ($script:waitingUrl -and $script:candidateUrl -and $txt -match "Registered tunnel connection" -and -not $script:urlCheckPs) {
        if ($script:urlCheckDelayTicks -gt 0) { $script:urlCheckDelayTicks-- } else { Start-UrlCheck $script:candidateUrl }
      }

      if ($script:waitingUrl -and $script:urlTries -gt 225) {
        $script:waitingUrl = $false
        $script:BtnInternet.IsEnabled = $true
        $ef = Join-Path $logsDir "tunnel.err"
        $tail = ""
        if (Test-Path $ef) { $tail = ((Get-Content $ef -Tail 3 -ErrorAction SilentlyContinue) -join " ") }
        Stop-All -Quiet
        Set-State "error" "Link internet gagal dibuat. Detail teknis tersedia di aktivitas."
        $script:LblUrl.Text = "Gagal membuat link publik"
        Log "GAGAL memverifikasi link (timeout 3 menit). $tail"
      }
    }
    if ($script:serverCheckTicks -ge 0) {
      $script:serverCheckTicks++
      if ($script:serverCheckTicks -eq 6) {
        if (-not (Test-PidAlive "server.pid")) {
          $ef = Join-Path $logsDir "server.err"
          $lf = Join-Path $logsDir "server.log"
          $msg = ""
          if (Test-Path $lf) { $msg = ((Get-Content $lf -Tail 2 -ErrorAction SilentlyContinue) -join " | ") }
          if (Test-Path $ef) { $msg += " " + ((Get-Content $ef -Tail 3 -ErrorAction SilentlyContinue) -join " | ") }
          Set-State "error" "Server folder gagal dimulai. Coba hentikan lalu mulai kembali."
          $script:LblUrl.Text = "Server gagal dimulai"
          Log "Server GAGAL jalan. $msg"
        } elseif (-not $script:pendingInternet -and -not $script:waitingUrl -and $script:mode -ne "online") {
          $localUrl = "http://localhost:$script:Port"
          $script:LblUrl.Text = $localUrl
          $script:BtnOpen.IsEnabled = $true
          $script:BtnCopy.IsEnabled = $true
          Set-State "local" "Server lokal aktif dan hanya dapat dibuka dari komputer ini."
          Log "Server lokal siap: $localUrl"
        }
        $script:serverCheckTicks = -1
      }
    }
  } catch {
    if (-not $script:lastTimerError -or $script:lastTimerError -ne $_.Exception.Message) {
      $script:lastTimerError = $_.Exception.Message
      Log "Kesalahan pemantauan: $($script:lastTimerError)"
    }
  }
})

Set-State "idle" "Pilih folder, lalu tentukan cara membagikannya."
Log "WinTunnel siap. Pilih folder, lalu klik 'Bagikan ke internet'."
if (Test-CloudflaredValid) { Log "Komponen internet siap." } elseif (Test-Path -LiteralPath $cloudflared) { Log "Komponen internet lama rusak/tidak lengkap; aplikasi akan mengunduh ulang saat dibutuhkan." }
$script:timer.Start()
Start-Updater
[void]$win.ShowDialog()
