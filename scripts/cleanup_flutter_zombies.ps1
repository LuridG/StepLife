<#
.SYNOPSIS
  清理卡死在 flutter.bat :acquire_lock 死循环里的僵尸进程，并清除过期锁文件。

.DESCRIPTION
  当 flutter 命令无响应、或机器上出现大量高 CPU 的 cmd 进程时，通常是某个
  flutter.bat 包装进程没能获得 bin\cache\flutter.bat.lock，在 batch 层
  :acquire_lock 循环里空转烧 CPU（一个进程一天能烧掉数万 CPU 秒，并会阻塞
  后续所有 flutter 命令）。

  本脚本：
    1) 找出命令行包含 flutter 的 cmd/dart 包装进程（含子进程树）并结束；
    2) 结束后若已无任何 flutter 相关进程存活，删除过期锁文件（下次运行自动重建）；
    3) 打印清理摘要。

.PARAMETER ListOnly
  仅列出将清理的目标，不实际结束进程（安全预览）。

.PARAMETER Force
  即使检测到仍有 flutter 进程存活，也强制删除锁文件（慎用；一般不需要）。

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\scripts\cleanup_flutter_zombies.ps1
  powershell -ExecutionPolicy Bypass -File .\scripts\cleanup_flutter_zombies.ps1 -ListOnly
#>
param(
  [switch]$ListOnly,
  [switch]$Force
)

$ErrorActionPreference = 'Continue'
$cleaned = New-Object System.Collections.Generic.List[object]

function Get-FlutterWrapperProcesses {
  $targets = New-Object System.Collections.Generic.List[object]
  try {
    $procs = Get-CimInstance Win32_Process -ErrorAction Stop
    foreach ($p in $procs) {
      $cmdLine = [string]$p.CommandLine
      if ([string]::IsNullOrWhiteSpace($cmdLine)) { continue }
      if ($p.Name -in @('cmd.exe', 'dart.exe', 'dartvm.exe', 'dartaotruntime.exe') -and
          ($cmdLine -match 'flutter' -or $cmdLine -match 'flutter_tools')) {
        $targets.Add($p)
      }
    }
  } catch {
    # 无 CIM 权限时兜底：按“高 CPU + 启动超过 5 分钟”识别疑似空转的包装进程
    Write-Warning '无法读取进程命令行（CIM 被拒绝），改用 CPU/启动时间兜底判断。'
    $now = Get-Date
    Get-Process -Name cmd, dart, dartvm, dartaotruntime -ErrorAction SilentlyContinue | ForEach-Object {
      $elapsedMin = 0.0
      if ($_.StartTime) { $elapsedMin = ($now - $_.StartTime).TotalMinutes }
      if ($_.CPU -gt 30 -and $elapsedMin -gt 5) {
        $targets.Add([pscustomobject]@{
          ProcessId   = $_.Id
          Name        = $_.ProcessName
          CommandLine = '(兜底识别)'
        })
      }
    }
  }
  return $targets
}

function Get-FlutterRoot {
  try {
    $cmd = Get-Command flutter -ErrorAction Stop
    if ($cmd.Source) {
      $bin = Split-Path $cmd.Source -Parent
      $root = Split-Path $bin -Parent
      return $root
    }
  } catch { }
  return $null
}

$targets = Get-FlutterWrapperProcesses

if ($targets.Count -eq 0) {
  Write-Host '未发现 flutter 僵尸包装进程。' -ForegroundColor Green
} else {
  Write-Host ("发现 {0} 个 flutter 相关进程：" -f $targets.Count) -ForegroundColor Yellow
  foreach ($t in $targets) {
    Write-Host ('  PID {0,-8} {1,-20} {2}' -f $t.ProcessId, $t.Name, $t.CommandLine)
    $cleaned.Add($t)
  }
  if (-not $ListOnly) {
    foreach ($t in $targets) {
      try {
        taskkill /F /T /PID $t.ProcessId 2>&1 | Out-Null
      } catch { }
    }
    Start-Sleep -Seconds 1
    Write-Host ('已结束 {0} 个进程。' -f $targets.Count) -ForegroundColor Green
  }
}

# 锁文件处理：仅当已无 flutter 进程存活（或 -Force）时删除
$flutterRoot = Get-FlutterRoot
if ($flutterRoot) {
  $lockCandidates = @(
    (Join-Path $flutterRoot 'bin\cache\flutter.bat.lock'),
    (Join-Path $flutterRoot 'bin\cache\lockfile')
  )
  # 结束进程后复查是否仍有 flutter 相关包装进程存活（避免把用户自身终端误判为 flutter 进程）
  $remaining = Get-FlutterWrapperProcesses
  $removeLocks = $Force -or ($remaining.Count -eq 0)
  if (-not $removeLocks) {
    Write-Host ('仍有 {0} 个 flutter 相关进程存活，跳过锁文件删除（避免干扰正在运行的命令）。' -f $remaining.Count) -ForegroundColor Yellow
  }
  if ($removeLocks) {
    foreach ($lf in $lockCandidates) {
      if (Test-Path -LiteralPath $lf) {
        if ($ListOnly) {
          Write-Host ('将删除过期锁文件：{0}' -f $lf) -ForegroundColor Yellow
        } else {
          try {
            Remove-Item -LiteralPath $lf -Force -ErrorAction Stop
            Write-Host ('已删除过期锁文件：{0}' -f $lf) -ForegroundColor Green
          } catch {
            Write-Warning ('删除锁文件失败（可能仍被占用）：{0} - {1}' -f $lf, $_.Exception.Message)
          }
        }
      }
    }
  }
} else {
  Write-Host '未定位到 flutter 根目录（不在 PATH 或 FVM 配置异常），跳过锁文件处理。' -ForegroundColor Yellow
}

if ($ListOnly) {
  Write-Host '（-ListOnly 预览模式，未做任何修改）'
} elseif ($cleaned.Count -gt 0) {
  Write-Host ("完成：共清理 {0} 个进程。可重新运行 flutter 命令。" -f $cleaned.Count) -ForegroundColor Green
} else {
  Write-Host '完成：无需清理。' -ForegroundColor Green
}
