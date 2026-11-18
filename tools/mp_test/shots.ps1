param([string]$Run = "run", [int]$MaxSeconds = 420)
# mp-test: while a multiplayer test runs, waits for "[MPT] ... SHOT <name>" lines in the test server's log and saves a
# picture of every test CLIENT window (PrintWindow: only those windows' own content is read, nothing else on screen)
# as tools\mp_test\shots\<Run>_<name>_<PlayerN>.png. Nothing is clicked, focused or moved. Ends at ENDTEST.
$out = Join-Path $PSScriptRoot "shots"
New-Item -ItemType Directory -Force $out | Out-Null
Add-Type -AssemblyName System.Drawing
Add-Type @"
using System;
using System.Text;
using System.Collections.Generic;
using System.Runtime.InteropServices;
public class MptWin {
  public delegate bool EnumProc(IntPtr hWnd, IntPtr lParam);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr lParam);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint pid);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetWindowText(IntPtr hWnd, StringBuilder sb, int max);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern IntPtr GetWindow(IntPtr hWnd, uint cmd);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT r);
  [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr hWnd, IntPtr hdc, uint flags);
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  public static IntPtr MainWindow(uint wanted) {
    IntPtr found = IntPtr.Zero; int best = 0;
    EnumWindows((h, l) => {
      uint pid; GetWindowThreadProcessId(h, out pid);
      if (pid == wanted && IsWindowVisible(h) && GetWindow(h, 4) == IntPtr.Zero) {
        var sb = new StringBuilder(300); GetWindowText(h, sb, 300);
        RECT r; GetWindowRect(h, out r);
        int area = (r.Right - r.Left) * (r.Bottom - r.Top);
        if (sb.ToString().Contains("Roblox Studio") && area > best) { best = area; found = h; }
      }
      return true;
    }, IntPtr.Zero);
    return found;
  }
  public static uint ForegroundPid() { uint pid; GetWindowThreadProcessId(GetForegroundWindow(), out pid); return pid; }
}
"@
[MptWin]::SetProcessDPIAware() | Out-Null
$logDir = "$env:LOCALAPPDATA\Roblox\logs"
$t0 = Get-Date
$names = @{}   # pid -> player name
$done = @{}
$serverLog = $null
function Get-Clients {
  $all = Get-CimInstance Win32_Process | Where-Object { $_.Name -eq "RobloxStudioBeta.exe" -or $_.Name -eq "RobloxCrashHandler.exe" }
  $clients = @($all | Where-Object { $_.Name -eq "RobloxStudioBeta.exe" -and $_.CommandLine -match "-task StartClient" })
  foreach ($c in $clients) {
    $cpid = [uint32]$c.ProcessId
    if (-not $names.ContainsKey($cpid)) {
      $h = $all | Where-Object { $_.Name -eq "RobloxCrashHandler.exe" -and $_.CommandLine -match "--studioPid $cpid\b" } | Select-Object -First 1
      if ($h -and $h.CommandLine -match "attachment_([^=\s]+_Studio_[0-9A-Fa-f]+_last\.log)=") {
        $m = Select-String -Path (Join-Path $logDir $Matches[1]) -Pattern "\[MPT\]\[C:([A-Za-z0-9_]+)\]" -List -ErrorAction SilentlyContinue
        if ($m) { $names[$cpid] = $m.Matches[0].Groups[1].Value }
      }
    }
  }
  return $clients
}
function Save-Shot([string]$name) {
  $clients = Get-Clients
  $fg = [MptWin]::ForegroundPid()
  foreach ($c in $clients) {
    $cpid = [uint32]$c.ProcessId
    $hwnd = [MptWin]::MainWindow($cpid)
    if ($hwnd -eq [IntPtr]::Zero) { continue }
    $r = New-Object MptWin+RECT
    [MptWin]::GetWindowRect($hwnd, [ref]$r) | Out-Null
    $w = $r.Right - $r.Left; $h = $r.Bottom - $r.Top
    if ($w -lt 50 -or $h -lt 50) { continue }
    $bmp = New-Object System.Drawing.Bitmap $w, $h
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $hdc = $g.GetHdc()
    [MptWin]::PrintWindow($hwnd, $hdc, 2) | Out-Null
    $g.ReleaseHdc($hdc); $g.Dispose()
    $who = if ($names.ContainsKey($cpid)) { $names[$cpid] } else { "pid$cpid" }
    $file = Join-Path $out ("{0}_{1}_{2}.png" -f $Run, $name, $who)
    $bmp.Save($file, [System.Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
    "{0:HH:mm:ss.fff} saved {1} ({2}x{3}, minimized={4}, foreground={5})" -f (Get-Date), (Split-Path $file -Leaf), $w, $h, [MptWin]::IsIconic($hwnd), ($fg -eq $cpid)
  }
}
while (((Get-Date) - $t0).TotalSeconds -lt $MaxSeconds) {
  if (-not $serverLog) {
    $cand = Get-ChildItem $logDir -File -Filter "*_Studio_*_last.log" | Where-Object { $_.LastWriteTime -gt $t0.AddSeconds(-20) } | Sort-Object LastWriteTime -Descending
    foreach ($f in $cand) {
      if (Select-String -Path $f.FullName -Pattern "\[MPT\] 0001 " -List -ErrorAction SilentlyContinue) { $serverLog = $f.FullName; "server log: $($f.Name)"; break }
    }
    if (-not $serverLog) { Start-Sleep -Milliseconds 500; continue }
  }
  $hits = Select-String -Path $serverLog -Pattern "\[MPT\] (\d{4}) [\d\.]+ (SHOT (\S+)|ENDTEST)" -ErrorAction SilentlyContinue
  $end = $false
  foreach ($hit in $hits) {
    $id = $hit.Matches[0].Groups[1].Value
    if ($done.ContainsKey($id)) { continue }
    $done[$id] = $true
    if ($hit.Matches[0].Groups[2].Value -eq "ENDTEST") { $end = $true } else { Save-Shot $hit.Matches[0].Groups[3].Value }
  }
  if ($end) { "ENDTEST seen"; break }
  Start-Sleep -Milliseconds 120
}
"watcher done after {0:N0} s" -f ((Get-Date) - $t0).TotalSeconds
