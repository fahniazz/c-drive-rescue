<#
.SYNOPSIS
  C Drive Rescue: find what fills your Windows system drive and free it safely.

.DESCRIPTION
  scan    Read-only report: caches, system files, biggest folders, and what to do. Deletes nothing.
  clean   Empty caches that programs rebuild by themselves. Shows sizes first, you pick.
  move    Move a big folder to another drive; the old path keeps working (junction).
  undo    Bring a moved folder back. Without a path, lists what was moved.
  tune    Hibernation, pagefile, WinSxS cleanup, System Restore cap (administrator).
  menu    Simple numbered menu (default when started with no command).

.EXAMPLE
  .\cdr.ps1 scan
  .\cdr.ps1 clean -Only Browser,GPU
  .\cdr.ps1 move "$env:APPDATA\ModrinthApp" -To D
  .\cdr.ps1 tune -Hibernate Off
#>
[CmdletBinding()]
param(
  [Parameter(Position = 0)][ValidateSet('menu', 'scan', 'clean', 'move', 'undo', 'tune', 'help')][string]$Command = 'menu',
  [Parameter(Position = 1)][string]$Path,
  [string]$To,
  [string[]]$Only,
  [string[]]$Skip,
  [switch]$Yes,
  [switch]$Deep,
  [switch]$Admin,
  [ValidateSet('On', 'Off')][string]$Hibernate,
  [string]$PagefileTo,
  [switch]$PagefileAuto,
  [switch]$ComponentCleanup,
  [ValidateRange(0, 50)][int]$RestorePercent = 0
)

$ErrorActionPreference = 'Continue'
$script:Root = $PSScriptRoot
$script:Entry = $PSCommandPath
$script:Version = '0.1.1'
foreach ($f in 'core', 'clean', 'scan', 'move', 'tune', 'menu') { . (Join-Path $PSScriptRoot "lib\$f.ps1") }

# -Only/-Skip also accept "a,b" as one string (that is what the elevated window receives)
$Only = @($Only | ForEach-Object { $_ -split ',' } | Where-Object { $_ })
$Skip = @($Skip | ForEach-Object { $_ -split ',' } | Where-Object { $_ })

switch ($Command) {
  'scan' { Invoke-Scan -Deep:$Deep }
  'clean' { Invoke-Clean -Only $Only -Skip $Skip -Yes:$Yes -Admin:$Admin }
  'move' { Invoke-Move -Path $Path -To $To -Yes:$Yes }
  'undo' { Invoke-Undo -Path $Path -Yes:$Yes }
  'tune' { Invoke-Tune -Hibernate $Hibernate -PagefileTo $PagefileTo -PagefileAuto:$PagefileAuto -ComponentCleanup:$ComponentCleanup -RestorePercent $RestorePercent -Yes:$Yes }
  'help' { Get-Help $PSCommandPath -Detailed }
  default { Invoke-Menu }
}
