# `cdr tune`: Windows settings that hold space on the system drive. Needs an administrator window.
# Run without options to see the current state and be asked about each one.

function Get-HibernateEnabled {
  $v = Get-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\Power' -Name HibernateEnabled -ErrorAction SilentlyContinue
  [bool]($v -and $v.HibernateEnabled)
}

function Show-TuneStatus {
  Write-Title 'Current settings'
  $s = Get-SystemFiles
  $pend = Get-PendingRestart $s
  $h = if (Get-HibernateEnabled) { 'on' } else { 'off' }
  $wait = if ($pend.Hiberfil) { ', removed at the next restart' } else { '' }
  Write-Host ('  Hibernation: {0} (hiberfil.sys {1}{2})' -f $h, (Format-Size $s.Hiberfil), $wait)
  if ($pend.PagefileBytes) { Write-Host ('  pagefile.sys on {0} is {1} now; it shrinks at the next restart.' -f $script:SysDrive, (Format-Size $s.Pagefile)) }
  $cs = Get-CimInstance Win32_ComputerSystem
  if ($cs.AutomaticManagedPagefile) { Write-Host ('  Pagefile: managed by Windows on {0} ({1})' -f $script:SysDrive, (Format-Size $s.Pagefile)) }
  else {
    foreach ($p in @(Get-CimInstance Win32_PageFileSetting)) {
      $size = if ($p.InitialSize -eq 0 -and $p.MaximumSize -eq 0) { 'managed by Windows' } else { '{0}-{1} MB' -f $p.InitialSize, $p.MaximumSize }
      Write-Host ('  Pagefile: {0}  {1}' -f $p.Name, $size)
    }
  }
  Write-Host '  System Restore storage:'
  & vssadmin.exe list shadowstorage /for=$($script:SysDrive) 2>$null | Where-Object { $_ -match '\d' -and $_ -match ':' } | Select-Object -Last 3 | ForEach-Object { Write-Host ('    ' + $_.Trim()) }
}

function Set-Hibernate([string]$State) {
  & powercfg.exe /h $State.ToLower()
  if ($LASTEXITCODE -eq 0) { Write-Ok ('Hibernation {0}.' -f $State.ToLower()); Write-Log "tune hibernate $State" }
  else { Write-Bad 'powercfg failed.' }
  if ($State -eq 'Off') { Write-Host '  hiberfil.sys is removed now or at the next restart. Sleep still works; Fast Startup is off.' }
}

# Keep a small pagefile on the system drive (enough for crash dumps) and let Windows size one on another drive.
function Move-Pagefile([string]$Drive) {
  $d = $Drive.Substring(0, 1).ToUpper() + ':'
  if ($d -eq $script:SysDrive) { Write-Bad 'Pick another drive than the system drive.'; return }
  if (-not (@(Get-OtherDrives) | Where-Object Drive -eq $d)) { Write-Bad "$d is not a fixed local drive."; return }
  $cs = Get-CimInstance Win32_ComputerSystem
  Set-CimInstance -InputObject $cs -Property @{ AutomaticManagedPagefile = $false }
  $sysName = $script:SysDrive + '\pagefile.sys'
  $c = Get-CimInstance Win32_PageFileSetting | Where-Object { $_.Name -ieq $sysName }
  if (-not $c) { $c = New-CimInstance -ClassName Win32_PageFileSetting -Property @{ Name = $sysName } }
  Set-CimInstance -InputObject $c -Property @{ InitialSize = [uint32]2048; MaximumSize = [uint32]4096 }
  $otherName = $d + '\pagefile.sys'
  if (-not (Get-CimInstance Win32_PageFileSetting | Where-Object { $_.Name -ieq $otherName })) {
    New-CimInstance -ClassName Win32_PageFileSetting -Property @{ Name = $otherName; InitialSize = [uint32]0; MaximumSize = [uint32]0 } | Out-Null
  }
  Write-Ok ('Pagefile: 2-4 GB on {0}, managed by Windows on {1}. Restart Windows to apply.' -f $script:SysDrive, $d)
  Write-Log "tune pagefile -> $d"
}

function Reset-Pagefile {
  Get-CimInstance Win32_PageFileSetting | Remove-CimInstance
  Set-CimInstance -InputObject (Get-CimInstance Win32_ComputerSystem) -Property @{ AutomaticManagedPagefile = $true }
  Write-Ok 'Pagefile is managed by Windows again. Restart Windows to apply.'
  Write-Log 'tune pagefile auto'
}

function Invoke-ComponentCleanup {
  Write-Host 'Cleaning superseded Windows components (WinSxS). This can take 5-20 minutes...'
  & Dism.exe /Online /Cleanup-Image /StartComponentCleanup
  Write-Log "tune component cleanup exit $LASTEXITCODE"
}

function Set-RestoreLimit([int]$Percent) {
  & vssadmin.exe resize shadowstorage /For=$($script:SysDrive) /On=$($script:SysDrive) /MaxSize=$Percent%
  Write-Log "tune restore limit $Percent%"
}

function Invoke-Tune([string]$Hibernate, [string]$PagefileTo, [switch]$PagefileAuto, [switch]$ComponentCleanup, [int]$RestorePercent, [switch]$Yes) {
  if (-not (Test-Admin)) {
    $a = @('tune')
    if ($Hibernate) { $a += @('-Hibernate', $Hibernate) }
    if ($PagefileTo) { $a += @('-PagefileTo', $PagefileTo) }
    if ($PagefileAuto) { $a += '-PagefileAuto' }
    if ($ComponentCleanup) { $a += '-ComponentCleanup' }
    if ($RestorePercent) { $a += @('-RestorePercent', [string]$RestorePercent) }
    if ($Yes) { $a += '-Yes' }
    Write-Warn 'These settings need administrator rights. Asking Windows for them...'
    Start-Elevated $a
    return
  }
  $any = $Hibernate -or $PagefileTo -or $PagefileAuto -or $ComponentCleanup -or $RestorePercent
  if ($any) {
    if ($Hibernate) { Set-Hibernate $Hibernate }
    if ($PagefileTo) { Move-Pagefile $PagefileTo }
    if ($PagefileAuto) { Reset-Pagefile }
    if ($ComponentCleanup) { Invoke-ComponentCleanup }
    if ($RestorePercent) { Set-RestoreLimit $RestorePercent }
    return
  }

  Show-TuneStatus
  Write-Host ''
  if ((Get-HibernateEnabled) -and (Read-YesNo 'Turn hibernation off? (frees hiberfil.sys; Sleep keeps working)')) { Set-Hibernate 'Off' }
  $others = @(Get-OtherDrives)
  if ($others.Count) {
    $best = $others | Sort-Object Free -Descending | Select-Object -First 1
    $ans = Read-Host ('Move most of the pagefile to another drive? Type a drive letter (e.g. {0}) or Enter to skip' -f $best.Drive.TrimEnd(':'))
    if ($ans -match '^[A-Za-z]') { Move-Pagefile $ans }
  }
  if (Read-YesNo 'Clean up old Windows component versions (WinSxS)? Safe, takes 5-20 min') { Invoke-ComponentCleanup }
  $pct = Read-Host 'Cap System Restore storage at what % of the drive? (e.g. 5; Enter to keep)'
  if ($pct -match '^\d+$' -and [int]$pct -ge 1 -and [int]$pct -le 50) { Set-RestoreLimit ([int]$pct) }
  Write-Ok 'Done. Restart Windows to finish anything marked "restart".'
}
