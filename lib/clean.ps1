# `cdr clean`: measure every cache in targets.psd1, show what would be freed, delete only what the user picks.

function Get-Targets {
  $data = Import-PowerShellDataFile -Path (Join-Path $script:Root 'targets.psd1')
  $data.Targets
}

function Get-RecycleBinPath {
  $sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
  Join-Path ($script:SysDrive + '\') ('$Recycle.Bin\' + $sid)
}

# Expand %VARS% and wildcards; return the existing paths. Paths in $Claimed were taken by an earlier target.
function Resolve-TargetPaths($Target, [hashtable]$Claimed) {
  if ($Target.Special -eq 'RecycleBin') { $list = @(Get-RecycleBinPath) }
  else {
    $list = foreach ($p in @($Target.Paths)) {
      $e = [Environment]::ExpandEnvironmentVariables($p)
      if ($e -match '[*?]') { Get-Item -Path $e -Force -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName } }
      elseif ([IO.Directory]::Exists($e) -or [IO.File]::Exists($e)) { $e }
    }
  }
  foreach ($p in @($list)) {
    if (-not $p) { continue }
    $key = $p.TrimEnd('\').ToLowerInvariant()
    if ($Claimed.ContainsKey($key)) { continue }
    $Claimed[$key] = $true
    # never let a wildcard reach outside the system drive or into a link
    $item = Get-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue
    if ($item -and -not (Test-Link $item)) { $p }
  }
}

# Measure all targets. Returns rows: Index, Target, Paths, Bytes, Status (Ready | NeedsAdmin | Close app | Empty).
function Measure-Targets([string[]]$Only, [string[]]$Skip) {
  $admin = Test-Admin
  $claimed = @{}
  $rows = New-Object System.Collections.ArrayList
  $all = @(Get-Targets)
  $n = 0
  foreach ($t in $all) {
    $n++
    if ($Only -and ($Only -notcontains $t.Id) -and ($Only -notcontains $t.Group)) { continue }
    if ($Skip -and (($Skip -contains $t.Id) -or ($Skip -contains $t.Group))) { continue }
    Write-Progress -Activity 'Measuring caches' -Status $t.Name -PercentComplete (100 * $n / $all.Count)
    $status = 'Ready'; $bytes = [long]0
    if ($t.Admin -and -not $admin) {
      # without admin rights these folders often cannot even be looked at; list them so the user knows
      [void]$rows.Add([pscustomobject]@{ Index = 0; Target = $t; Paths = @(); Bytes = $bytes; Status = 'Needs admin' })
      continue
    }
    $paths = @(Resolve-TargetPaths $t $claimed)
    if ($paths.Count -eq 0) { continue }
    $running = @()
    if ($t.Close) { $running = @(Get-Process -Name $t.Close -ErrorAction SilentlyContinue | Select-Object -ExpandProperty ProcessName -Unique) }
    if ($running.Count -gt 0) { $status = 'Close ' + ($running -join ', ') }
    foreach ($p in $paths) {
      if ($t.OlderThanDays) { $bytes += Clear-Folder $p -OlderThanDays $t.OlderThanDays -DryRun }
      else { $bytes += Get-PathSize $p }
    }
    if ($bytes -eq 0 -and $status -eq 'Ready') { $status = 'Empty' }
    [void]$rows.Add([pscustomobject]@{ Index = 0; Target = $t; Paths = $paths; Bytes = $bytes; Status = $status })
  }
  Write-Progress -Activity 'Measuring caches' -Completed
  $i = 0
  foreach ($r in $rows) { $i++; $r.Index = $i }
  $rows
}

function Show-TargetTable($Rows) {
  $fmt = '{0,3}  {1,-8} {2,-48} {3,9}  {4}'
  Write-Host ($fmt -f '#', 'Group', 'What', 'Size', 'Status') -ForegroundColor DarkGray
  foreach ($r in $Rows) {
    $color = switch -Wildcard ($r.Status) { 'Ready' { 'White' } 'Empty' { 'DarkGray' } default { 'Yellow' } }
    $size = if ($r.Status -eq 'Needs admin') { '?' } else { Format-Size $r.Bytes }
    $name = $r.Target.Name; if ($name.Length -gt 48) { $name = $name.Substring(0, 45) + '...' }
    Write-Host ($fmt -f $r.Index, $r.Target.Group, $name, $size, $r.Status) -ForegroundColor $color
  }
  $ready = @($Rows | Where-Object Status -eq 'Ready')
  $sum = ($ready | Measure-Object Bytes -Sum).Sum
  Write-Host ''
  Write-Ok ('Ready to free now: {0} in {1} items' -f (Format-Size $sum), $ready.Count)
  $blocked = @($Rows | Where-Object { $_.Status -like 'Close *' })
  if ($blocked.Count) { Write-Warn ('{0} items wait for an app to be closed (see Status).' -f $blocked.Count) }
  if (@($Rows | Where-Object Status -eq 'Needs admin').Count) { Write-Warn 'Some Windows items need an administrator window: cdr clean -Admin' }
}

# Delete one measured row. Returns bytes freed (measured before and after, so in-use files are not counted).
function Invoke-TargetClean($Row) {
  $t = $Row.Target
  $before = [long]0; foreach ($p in $Row.Paths) { $before += Get-PathSize $p }
  switch ($t.Special) {
    'RecycleBin' {
      try { Clear-RecycleBin -DriveLetter $script:SysDrive.TrimEnd(':') -Force -ErrorAction Stop }
      catch { foreach ($p in $Row.Paths) { [void](Clear-Folder $p) } }
    }
    'WindowsUpdate' {
      $svc = @('wuauserv', 'bits')
      try {
        Stop-Service -Name $svc -Force -ErrorAction SilentlyContinue
        foreach ($p in $Row.Paths) { [void](Clear-Folder $p) }
      } finally { Start-Service -Name $svc -ErrorAction SilentlyContinue -WarningAction SilentlyContinue }
    }
    'DeliveryOptimization' {
      if (Get-Command Delete-DeliveryOptimizationCache -ErrorAction SilentlyContinue) { Delete-DeliveryOptimizationCache -Force -ErrorAction SilentlyContinue }
      else { foreach ($p in $Row.Paths) { [void](Clear-Folder $p) } }
    }
    default {
      foreach ($p in $Row.Paths) {
        $item = Get-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue
        if (-not $item) { continue }
        if ($item.PSIsContainer) { [void](Clear-Folder $p -OlderThanDays ([int]$t.OlderThanDays)) }
        else { Remove-Entry $item }
      }
    }
  }
  $after = [long]0; foreach ($p in $Row.Paths) { $after += Get-PathSize $p }
  $freed = [math]::Max([long]0, $before - $after)
  Write-Log ('clean {0}: freed {1} ({2})' -f $t.Id, $freed, ($Row.Paths -join '; '))
  $freed
}

# Parse "1,3,5-7" into indexes.
function ConvertFrom-Selection([string]$Text) {
  foreach ($part in ($Text -split '[,\s]+' | Where-Object { $_ })) {
    if ($part -match '^(\d+)-(\d+)$') { [int]$Matches[1]..[int]$Matches[2] }
    elseif ($part -match '^\d+$') { [int]$part }
  }
}

function Invoke-Clean([string[]]$Only, [string[]]$Skip, [switch]$Yes, [switch]$Admin) {
  if ($Admin -and -not (Test-Admin)) {
    $a = @('clean'); if ($Only) { $a += '-Only'; $a += ($Only -join ',') }; if ($Skip) { $a += '-Skip'; $a += ($Skip -join ',') }
    Start-Elevated $a; return
  }
  Write-Title 'Caches that can be cleaned'
  Show-Drive
  $rows = @(Measure-Targets -Only $Only -Skip $Skip)
  if ($rows.Count -eq 0) { Write-Ok 'Nothing found to clean.'; return }
  Show-TargetTable $rows
  $ready = @($rows | Where-Object Status -eq 'Ready')
  if ($ready.Count -eq 0) { return }

  if ($Yes) { $pick = $ready }
  else {
    Write-Host ''
    $answer = Read-Host 'Delete them? [A] all Ready items, numbers like 1,3,5-7, or Enter to cancel'
    if ([string]::IsNullOrWhiteSpace($answer)) { Write-Host 'Cancelled, nothing deleted.'; return }
    if ($answer.Trim().ToLower() -in @('a', 'all', 'y', 'yes')) { $pick = $ready }
    else {
      $idx = @(ConvertFrom-Selection $answer)
      $pick = @($rows | Where-Object { $idx -contains $_.Index })
      $notReady = @($pick | Where-Object Status -ne 'Ready')
      foreach ($r in $notReady) { Write-Warn ('Skipping #{0} {1}: {2}' -f $r.Index, $r.Target.Name, $r.Status) }
      $pick = @($pick | Where-Object Status -eq 'Ready')
    }
  }
  $freeBefore = (Get-DriveFree).Free
  $total = [long]0
  foreach ($r in $pick) {
    Write-Host ('Cleaning {0}... ' -f $r.Target.Name) -NoNewline
    $f = Invoke-TargetClean $r
    $total += $f
    Write-Ok (Format-Size $f)
  }
  $gain = (Get-DriveFree).Free - $freeBefore
  Write-Host ''
  Write-Ok ('Done. Freed {0} (drive {1} gained {2}).' -f (Format-Size $total), $script:SysDrive, (Format-Size ([math]::Max(0, $gain))))
  Write-Log ('clean total: {0} bytes, drive gain {1}' -f $total, $gain)
  Show-Drive
}
