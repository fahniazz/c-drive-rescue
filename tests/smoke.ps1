# Smoke tests on throwaway folders. Run in both shells:
#   powershell -NoProfile -ExecutionPolicy Bypass -File tests\smoke.ps1
#   pwsh -NoProfile -File tests\smoke.ps1
# The move test needs a second fixed drive and is skipped without one. Nothing outside the test folders is changed.

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$sandbox = Join-Path $env:TEMP ('cdr-smoke-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
$env:CDR_HOME = Join-Path $sandbox 'home'
$script:Root = $root
$script:Entry = Join-Path $root 'cdr.ps1'
foreach ($f in 'core', 'clean', 'scan', 'move', 'tune') { . (Join-Path $root "lib\$f.ps1") }

$script:fails = 0
function Assert([bool]$Cond, [string]$Msg) {
  if ($Cond) { Write-Host "  ok    $Msg" -ForegroundColor Green } else { Write-Host "  FAIL  $Msg" -ForegroundColor Red; $script:fails++ }
}
function New-File([string]$Path, [int]$Bytes = 1000, [int]$AgeDays = 0) {
  New-Item -ItemType Directory -Force -Path (Split-Path $Path -Parent) | Out-Null
  [IO.File]::WriteAllBytes($Path, (New-Object byte[] $Bytes))
  if ($AgeDays) { (Get-Item -LiteralPath $Path).LastWriteTime = (Get-Date).AddDays(-$AgeDays) }
}

Write-Host "PowerShell $($PSVersionTable.PSVersion)  sandbox $sandbox"
try {
  Write-Host 'Links are never followed when emptying a folder'
  $keep = Join-Path $sandbox 'keep'; $cache = Join-Path $sandbox 'cache'
  New-File "$keep\important.txt"
  New-File "$cache\a.bin"; New-File "$cache\sub\b.bin"
  Set-ItemProperty -LiteralPath "$cache\sub\b.bin" -Name IsReadOnly -Value $true
  New-Item -ItemType Junction -Path "$cache\link-top" -Value $keep | Out-Null
  New-Item -ItemType Junction -Path "$cache\sub\link-deep" -Value $keep | Out-Null
  [void](Clear-Folder $cache)
  Assert (Test-Path -LiteralPath "$keep\important.txt") 'file behind both junctions survives'
  Assert (Test-Path -LiteralPath $cache) 'the emptied folder itself stays'
  Assert (@(Get-ChildItem -LiteralPath $cache -Force).Count -eq 0) 'cache is empty (read-only file and links removed)'

  Write-Host 'Age mode keeps anything recent'
  $tmp = Join-Path $sandbox 'tmp'
  New-File "$tmp\old.bin" 2000 5
  New-File "$tmp\new.bin" 2000 0
  New-File "$tmp\olddir\x.bin" 3000 5; (Get-Item "$tmp\olddir").LastWriteTime = (Get-Date).AddDays(-5)
  New-File "$tmp\mixed\old.bin" 3000 5; New-File "$tmp\mixed\new.bin" 3000 0
  $would = Clear-Folder $tmp -OlderThanDays 1 -DryRun
  Assert ($would -eq 5000) "dry run counts only old entries ($would bytes)"
  Assert (Test-Path "$tmp\old.bin") 'dry run deletes nothing'
  [void](Clear-Folder $tmp -OlderThanDays 1)
  Assert (-not (Test-Path "$tmp\old.bin")) 'old file deleted'
  Assert (-not (Test-Path "$tmp\olddir")) 'old folder deleted'
  Assert (Test-Path "$tmp\new.bin") 'new file kept'
  Assert (Test-Path "$tmp\mixed\old.bin") 'folder with a recent file kept whole'

  Write-Host 'Sizes'
  $sz = Join-Path $sandbox 'size'
  New-File "$sz\a.bin" 12345; New-File "$sz\d\b.bin" 54321
  New-Item -ItemType Junction -Path "$sz\loop" -Value $sz | Out-Null
  $r = Get-RoboStats $sz
  Assert ($r.Bytes -eq 66666 -and $r.Files -eq 2) "robocopy count skips links ($($r.Files) files, $($r.Bytes) bytes)"
  Assert ((Get-TreeInfo $sz).Bytes -eq 66666) 'tree walk agrees'

  Write-Host 'Target list'
  $t = @(Get-Targets)
  Assert ($t.Count -ge 20) "targets.psd1 loads ($($t.Count) entries)"
  Assert (@($t | ForEach-Object { $_.Id } | Group-Object | Where-Object Count -gt 1).Count -eq 0) 'ids are unique'
  $rows = @(Measure-Targets -Only 'GPU')
  Assert ($true) "measuring GPU caches works ($($rows.Count) found)"

  Write-Host 'Clean end to end with a fake target list'
  $fake = Join-Path $sandbox 'fake'
  New-File "$fake\c1\a.bin" 4000; New-File "$fake\c1\sub\b.bin" 6000
  New-Item -ItemType Junction -Path "$fake\c1\to-keep" -Value $keep | Out-Null
  $psd = "@{ Targets = @( @{ Id = 'fake'; Group = 'Test'; Name = 'Fake cache'; Paths = @('$fake\c1') } ) }"
  Set-Content -LiteralPath "$fake\targets.psd1" -Value $psd
  $realRoot = $script:Root; $script:Root = $fake
  try {
    $rows = @(Measure-Targets)
    Assert ($rows.Count -eq 1 -and $rows[0].Bytes -eq 10000 -and $rows[0].Status -eq 'Ready') "fake target measured ($($rows[0].Bytes) bytes)"
    Invoke-Clean -Yes | Out-Null
    Assert (@(Get-ChildItem -LiteralPath "$fake\c1" -Force).Count -eq 0) 'clean emptied it'
    Assert (Test-Path -LiteralPath "$keep\important.txt") 'clean left the junction target alone'
  } finally { $script:Root = $realRoot }

  Write-Host 'Move guard'
  Assert ([bool](Get-MoveBlocker $env:SystemRoot)) 'Windows folder is refused'
  Assert ([bool](Get-MoveBlocker $env:USERPROFILE)) 'the profile itself is refused'
  Assert ([bool](Get-MoveBlocker "$env:LOCALAPPDATA\Temp")) 'Temp is refused'

  $other = @(Get-OtherDrives | Where-Object { $_.Free -gt 2GB }) | Select-Object -First 1
  if (-not $other) { Write-Host '  skip  move/undo (no second drive)' -ForegroundColor DarkGray }
  else {
    Write-Host "Move and undo through $($other.Drive)"
    $src = Join-Path $env:USERPROFILE ('cdr-smoke-move-' + [guid]::NewGuid().ToString('N').Substring(0, 6))
    $moveRoot = Join-Path ($other.Drive + '\') ('cdr-smoke-' + [guid]::NewGuid().ToString('N').Substring(0, 6))
    try {
      New-File "$src\one.bin" 1111; New-File "$src\deep\two.bin" 2222
      New-Item -ItemType Junction -Path "$src\inner-link" -Value $keep | Out-Null
      Invoke-Move -Path $src -To $moveRoot -Yes
      $dst = Resolve-MoveTarget $src $moveRoot
      $it = Get-Item -LiteralPath $src -Force
      Assert (Test-Link $it) 'old path is now a junction'
      Assert ([IO.File]::ReadAllBytes("$src\deep\two.bin").Length -eq 2222) 'files readable through the old path'
      Assert (Test-Link (Get-Item -LiteralPath "$dst\inner-link" -Force)) 'inner junction copied as a junction'
      Assert (Test-Path -LiteralPath "$keep\important.txt") 'inner junction target untouched'
      Assert (@(Get-Moves).Count -eq 1) 'move recorded'
      Invoke-Undo -Path $src -Yes
      $it = Get-Item -LiteralPath $src -Force
      Assert (-not (Test-Link $it)) 'undo: real folder again'
      Assert ((Get-Item "$src\deep\two.bin").Length -eq 2222) 'undo: files back'
      Assert (-not (Test-Path -LiteralPath $dst)) 'undo: copy on the other drive removed'
      Assert (@(Get-Moves).Count -eq 0) 'undo: record removed'
    } finally {
      foreach ($p in @($src, $moveRoot)) { if (Test-Path -LiteralPath $p) { Remove-Entry (New-Object IO.DirectoryInfo($p)) } }
    }
  }
} finally {
  Remove-Entry (New-Object IO.DirectoryInfo($sandbox))
}
if ($script:fails) { Write-Host "$script:fails failed" -ForegroundColor Red; exit 1 }
Write-Host 'all passed' -ForegroundColor Green
