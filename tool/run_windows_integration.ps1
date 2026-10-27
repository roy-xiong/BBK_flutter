$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Force build/validation | Out-Null
$taskProbeStop = Join-Path (Get-Location) 'build/validation/probe.done'
Remove-Item $taskProbeStop -ErrorAction SilentlyContinue
$taskProbe = Start-Job -ArgumentList $taskProbeStop -ScriptBlock {
  param($stopFile)
  Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class WindowProbe {
  [DllImport("user32.dll", SetLastError=true)]
  public static extern IntPtr SendMessageTimeout(IntPtr hwnd, uint msg,
    UIntPtr wp, IntPtr lp, uint flags, uint timeout, out UIntPtr result);
}
'@
  $deadline = (Get-Date).AddMinutes(12)
  $samples = 0
  $failures = 0
  $slowest = 0
  while ((Get-Date) -lt $deadline -and !(Test-Path $stopFile)) {
    $process = Get-Process -Name bbk_flutter -ErrorAction SilentlyContinue |
      Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
    if ($process) {
      $result = [UIntPtr]::Zero
      $watch = [Diagnostics.Stopwatch]::StartNew()
      $reply = [WindowProbe]::SendMessageTimeout($process.MainWindowHandle,
        0, [UIntPtr]::Zero, [IntPtr]::Zero, 2, 1000, [ref]$result)
      $watch.Stop()
      $samples++
      $slowest = [Math]::Max($slowest, $watch.ElapsedMilliseconds)
      if ($reply -eq [IntPtr]::Zero) { $failures++ }
    }
    Start-Sleep -Milliseconds 200
  }
  [PSCustomObject]@{samples=$samples; unresponsive=$failures; maxReplyMs=$slowest}
}
$taskTestExit = 1
try {
  flutter drive --profile -d windows --driver=test_driver/integration_test.dart --target=integration_test/windows_game_test.dart
  $taskTestExit = $LASTEXITCODE
} finally {
  Set-Content $taskProbeStop 'done'
  $taskResult = Receive-Job $taskProbe -Wait -AutoRemoveJob
  $taskResult | ConvertTo-Json | Set-Content -Encoding utf8 build/validation/windows-window-probe.json
}
if ($taskTestExit -ne 0) { throw 'Windows 集成回归未通过' }
if ($taskResult.samples -lt 10 -or $taskResult.unresponsive -ne 0) {
  throw "Win32 窗口响应未通过：$($taskResult | ConvertTo-Json -Compress)"
}
Write-Output ($taskResult | ConvertTo-Json)
