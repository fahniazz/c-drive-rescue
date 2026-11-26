# `cdr scan`: read-only report of where the space went and what to do about it. Deletes nothing.

function Get-SystemFiles {
  $root = New-Object IO.DirectoryInfo($script:SysDrive + '\')
  $sys = @{}
  try { foreach ($f in $root.GetFiles('*.sys')) { $sys[$f.Name.ToLower()] = $f.Length } } catch { }
  $old = Join-Path ($script:SysDrive + '\') 'Windows.old'
  [pscustomobject]@{
    Hiberfil   = [long]$sys['hiberfil.sys']
    Pagefile   = [long]$sys['pagefile.sys']
    Swapfile   = [long]$sys['swapfile.sys']
    WindowsOld = if (Test-Path -LiteralPath $old) { (Get-RoboStats $old).Bytes } else { [long]0 }
  }
}

# Folders worth looking at: everything in the profile, and every app folder in AppData. Links are skipped.
function Get-BigFolders([switch]$Deep, [long]$MinBytes = 300MB) {
  $profileDir = $env:USERPROFILE
  $parents = @($profileDir, "$profileDir\AppData\Local", "$profileDir\AppData\Roaming", "$profileDir\AppData\LocalLow")
  $skip = @("$profileDir\AppData".ToLower())
  if ($Deep) {
    $parents += ($script:SysDrive + '\')
    $skip += @('windows', 'users', '$recycle.bin', 'system volume information', 'recovery', 'config.msi') | ForEach-Object { ($script:SysDrive + '\' + $_).ToLower() }
  }
  $dirs = foreach ($parent in $parents) {
    $d = New-Object IO.DirectoryInfo($parent)
    try { $d.GetDirectories() } catch { }
  }
  $dirs = @($dirs | Where-Object { -not (Test-Link $_) -and ($skip -notcontains $_.FullName.ToLower()) })
  $n = 0
  $out = foreach ($d in $dirs) {
    $n++
    Write-Progress -Activity 'Measuring folders' -Status $d.FullName -PercentComplete (100 * $n / [math]::Max(1, $dirs.Count))
    $b = (Get-RoboStats $d.FullName).Bytes
    if ($b -ge $MinBytes) { [pscustomobject]@{ Path = $d.FullName; Bytes = $b } }
  }
  Write-Progress -Activity 'Measuring folders' -Completed
  @($out | Sort-Object Bytes -Descending)
}

function Invoke-Scan([switch]$Deep) {
  Write-Title 'Drives'
  Show-Drive
  $others = @(Get-OtherDrives)
  foreach ($o in $others) { Show-Drive $o.Drive }
  $best = $others | Sort-Object Free -Descending | Select-Object -First 1   # where moved things should go

  Write-Title 'Caches that cdr clean can empty'
  $rows = @(Measure-Targets)
  $shown = @($rows | Where-Object { $_.Bytes -ge 10MB -or $_.Status -eq 'Needs admin' })
  if ($shown.Count) { Show-TargetTable $shown } else { Write-Ok 'All caches are already small.' }
  $cacheBytes = ($rows | Where-Object Status -eq 'Ready' | Measure-Object Bytes -Sum).Sum

  Write-Title 'Windows system files'
  $s = Get-SystemFiles
  $fmt = '  {0,-34} {1,9}  {2}'
  Write-Host ($fmt -f 'hiberfil.sys (hibernation)', (Format-Size $s.Hiberfil), $(if ($s.Hiberfil) { 'cdr tune -Hibernate Off frees it (admin)' } else { 'off' }))
  Write-Host ($fmt -f 'pagefile.sys (virtual memory)', (Format-Size $s.Pagefile), $(if ($s.Pagefile -gt 4GB -and $best) { ('cdr tune -PagefileTo {0} (admin) moves most of it' -f $best.Drive.TrimEnd(':')) } else { '' }))
  if ($s.Swapfile) { Write-Host ($fmt -f 'swapfile.sys', (Format-Size $s.Swapfile), 'small, leave it') }
  if ($s.WindowsOld) { Write-Host ($fmt -f 'Windows.old (previous Windows)', (Format-Size $s.WindowsOld), 'remove with Disk Cleanup > Clean up system files > Previous Windows installation(s)') }
  Write-Host ($fmt -f 'WinSxS, Installer', '', 'never delete by hand; cdr tune -ComponentCleanup trims WinSxS safely') -ForegroundColor DarkGray

  Write-Title 'Biggest folders in your profile'
  $big = @(Get-BigFolders -Deep:$Deep | Select-Object -First 20)
  foreach ($b in $big) {
    $why = Get-MoveBlocker $b.Path
    $hint = if ($why) { '' } else { 'movable' }
    Write-Host ('  {0,9}  {1}  ' -f (Format-Size $b.Bytes), $b.Path) -NoNewline
    Write-Host $hint -ForegroundColor DarkGreen
  }
  if (-not $big.Count) { Write-Host '  nothing over 300 MB' }

  Write-Title 'Suggestions'
  $tips = New-Object System.Collections.ArrayList
  if ($cacheBytes -ge 500MB) { [void]$tips.Add(('Run  cdr clean  to free about {0} of caches now.' -f (Format-Size $cacheBytes))) }
  if ($s.Hiberfil -ge 1GB) { [void]$tips.Add(('Run  cdr tune -Hibernate Off  as admin to free {0} (you lose Hibernate and Fast Startup; Sleep still works).' -f (Format-Size $s.Hiberfil))) }
  if ($s.Pagefile -ge 8GB -and $best) { [void]$tips.Add(('Run  cdr tune -PagefileTo {0}  as admin: keeps a small 2-4 GB pagefile on {1}, the rest moves (takes effect after restart).' -f $best.Drive.TrimEnd(':'), $script:SysDrive)) }
  $movable = @($big | Where-Object { -not (Get-MoveBlocker $_.Path) -and $_.Bytes -ge 2GB })
  if ($movable.Count -and $best) {
    foreach ($m in ($movable | Select-Object -First 3)) {
      [void]$tips.Add(('Move  "{0}"  ({1}) to {2}  cdr move "{0}" -To {3}' -f $m.Path, (Format-Size $m.Bytes), $best.Drive, $best.Drive.TrimEnd(':')))
    }
  }
  $dl = $big | Where-Object { $_.Path -eq (Join-Path $env:USERPROFILE 'Downloads') }
  if ($dl -and $dl.Bytes -ge 2GB) { [void]$tips.Add(('Your Downloads folder holds {0}. Old installers and videos there are often forgotten.' -f (Format-Size $dl.Bytes))) }
  if (-not $tips.Count) { [void]$tips.Add('Nothing big stands out. Try  cdr scan -Deep  to include Program Files and other top-level folders.') }
  $i = 0; foreach ($t in $tips) { $i++; Write-Host ('  {0}. {1}' -f $i, $t) }
  Write-Log ('scan: caches {0}, hiberfil {1}, pagefile {2}' -f $cacheBytes, $s.Hiberfil, $s.Pagefile)
}
