# Shared helpers: paths, logging, sizes, and deletion that never follows links.
# Works in Windows PowerShell 5.1 and PowerShell 7. Keep this file ASCII only (5.1 reads BOM-less files as ANSI).

$script:CdrHome = if ($env:CDR_HOME) { $env:CDR_HOME } else { Join-Path $env:LOCALAPPDATA 'c-drive-rescue' }
$script:LogFile = Join-Path $script:CdrHome 'cdr.log'
$script:MovesFile = Join-Path $script:CdrHome 'moves.json'
$script:SysDrive = $env:SystemDrive          # usually C:
$script:RoboNull = Join-Path $env:TEMP 'cdr-robocopy-dry-run'   # /L never creates it
New-Item -ItemType Directory -Force -Path $script:CdrHome | Out-Null

function Write-Log([string]$Message) {
  $line = '{0}  {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
  try { Add-Content -LiteralPath $script:LogFile -Value $line -Encoding UTF8 } catch { }
}

function Write-Title([string]$Text) { Write-Host ''; Write-Host $Text -ForegroundColor Cyan; Write-Host ('-' * $Text.Length) -ForegroundColor DarkCyan }
function Write-Ok([string]$Text) { Write-Host $Text -ForegroundColor Green }
function Write-Warn([string]$Text) { Write-Host $Text -ForegroundColor Yellow }
function Write-Bad([string]$Text) { Write-Host $Text -ForegroundColor Red }

function Test-Admin {
  $p = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
  $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Format-Size([double]$Bytes) {
  if ($Bytes -ge 1GB) { return ('{0:N1} GB' -f ($Bytes / 1GB)) }
  if ($Bytes -ge 1MB) { return ('{0:N0} MB' -f ($Bytes / 1MB)) }
  if ($Bytes -gt 0) { return ('{0:N0} KB' -f [math]::Max(1, $Bytes / 1KB)) }
  '0'
}

function Get-DriveFree([string]$Drive = $script:SysDrive) {
  $d = Get-CimInstance Win32_LogicalDisk -Filter ("DeviceID='{0}'" -f $Drive.TrimEnd('\'))
  [pscustomobject]@{ Drive = $Drive; Free = [long]$d.FreeSpace; Size = [long]$d.Size }
}

function Show-Drive([string]$Drive = $script:SysDrive) {
  $d = Get-DriveFree $Drive
  $pct = if ($d.Size) { [math]::Round(100 * $d.Free / $d.Size) } else { 0 }
  $color = if ($pct -lt 10) { 'Red' } elseif ($pct -lt 20) { 'Yellow' } else { 'Green' }
  Write-Host ('Drive {0}  {1} free of {2} ({3}% free)' -f $Drive, (Format-Size $d.Free), (Format-Size $d.Size), $pct) -ForegroundColor $color
}

# Fixed local drives other than the system drive, with free space (candidates to move things to).
function Get-OtherDrives {
  Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' |
    Where-Object { $_.DeviceID -ne $script:SysDrive } |
    ForEach-Object { [pscustomobject]@{ Drive = $_.DeviceID; Free = [long]$_.FreeSpace; Size = [long]$_.Size } }
}

function Test-Link($Item) { [bool]($Item.Attributes -band [IO.FileAttributes]::ReparsePoint) }

# Robocopy in list-only mode (/L) counts a folder far faster than PowerShell can walk it. /XJ skips junctions,
# so linked folders are neither followed nor counted twice. Returns files and bytes; works on localized Windows
# because only the numeric summary rows are read (Dirs, Files, Bytes in that order).
function Get-RoboStats([string]$Path) {
  $p = $Path.TrimEnd('\'); if ($p.EndsWith(':')) { $p += '\.' }
  $lines = & robocopy.exe $p $script:RoboNull /L /E /XJ /R:0 /W:0 /NFL /NDL /NJH /NP /BYTES /MT:16 2>$null
  $rows = @($lines | Where-Object { $_ -match '^\s*[^:\d]+:\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s*$' } |
    ForEach-Object { [long]($_ -replace '^\s*[^:\d]+:\s+(\d+).*$', '$1') })
  if ($rows.Count -lt 3) { return [pscustomobject]@{ Files = 0; Bytes = [long]0 } }
  [pscustomobject]@{ Files = $rows[1]; Bytes = $rows[2] }
}

# Size of a file or folder (folder = everything inside it, links not followed).
function Get-PathSize([string]$Path) {
  $item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
  if (-not $item) { return [long]0 }
  if (-not $item.PSIsContainer) { return [long]$item.Length }
  if (Test-Link $item) { return [long]0 }
  (Get-RoboStats $Path).Bytes
}

# One pass over a folder: total bytes and the newest write time anywhere inside (links not followed).
function Get-TreeInfo([string]$Path) {
  $bytes = [long]0; $newest = [datetime]::MinValue
  $stack = New-Object System.Collections.Stack
  $stack.Push((New-Object IO.DirectoryInfo($Path)))
  while ($stack.Count -gt 0) {
    $d = $stack.Pop()
    try { $items = $d.GetFileSystemInfos() } catch { continue }
    foreach ($i in $items) {
      if ($i.LastWriteTime -gt $newest) { $newest = $i.LastWriteTime }
      if (Test-Link $i) { continue }
      if ($i -is [IO.DirectoryInfo]) { $stack.Push($i) } else { $bytes += $i.Length }
    }
  }
  [pscustomobject]@{ Bytes = $bytes; Newest = $newest }
}

# Delete one file or folder. A link (junction or symlink) is unlinked; what it points to is never touched.
# Folders: .NET deletes them natively and does not follow links inside; if something is read-only or locked it
# gives up, so a slower walk then clears read-only flags and deletes whatever is not in use.
function Remove-Entry([IO.FileSystemInfo]$Item) {
  try {
    if (Test-Link $Item) {
      if ($Item -is [IO.DirectoryInfo]) { [IO.Directory]::Delete($Item.FullName, $false) } else { [IO.File]::Delete($Item.FullName) }
      return
    }
    if ($Item -is [IO.DirectoryInfo]) {
      try { [IO.Directory]::Delete($Item.FullName, $true); return } catch { }
      Remove-TreeWalk $Item
      return
    }
    if ($Item.Attributes -band [IO.FileAttributes]::ReadOnly) { $Item.Attributes = $Item.Attributes -band (-bnot [IO.FileAttributes]::ReadOnly) }
    $Item.Delete()
  } catch { }  # in use: leave it
}

function Remove-TreeWalk([IO.DirectoryInfo]$Dir) {
  try { $items = $Dir.GetFileSystemInfos() } catch { return }
  foreach ($i in $items) { Remove-Entry $i }
  try {
    if ($Dir.Attributes -band [IO.FileAttributes]::ReadOnly) { $Dir.Attributes = $Dir.Attributes -band (-bnot [IO.FileAttributes]::ReadOnly) }
    $Dir.Delete()
  } catch { }
}

# Empty a folder (the folder itself stays). With -OlderThanDays, a top-level entry is only deleted when nothing
# inside it was written in that many days: a recent file means some program may still be using it.
# In age mode it returns the bytes of the entries it picked (with -DryRun it only counts them).
# Without an age, callers measure the folder before and after instead.
function Clear-Folder([string]$Path, [int]$OlderThanDays = 0, [switch]$DryRun) {
  $dir = New-Object IO.DirectoryInfo($Path)
  if (-not $dir.Exists) { return [long]0 }
  try { $items = $dir.GetFileSystemInfos() } catch { return [long]0 }
  $cutoff = (Get-Date).AddDays(-$OlderThanDays)
  $bytes = [long]0
  foreach ($i in $items) {
    if ($OlderThanDays -gt 0) {
      if (Test-Link $i) { continue }   # leave links alone in age mode
      if ($i -is [IO.DirectoryInfo]) {
        $info = Get-TreeInfo $i.FullName
        if ($info.Newest -gt $cutoff -or $i.LastWriteTime -gt $cutoff) { continue }
        $size = $info.Bytes
      } else {
        if ($i.LastWriteTime -gt $cutoff) { continue }
        $size = $i.Length
      }
      $bytes += $size
    }
    if (-not $DryRun) { Remove-Entry $i }
  }
  $bytes
}

# Quote a value for a Start-Process argument list (5.1 does not quote for you).
function ConvertTo-Arg([string]$Value) { if ($Value -match '[\s"]') { '"' + ($Value -replace '"', '\"') + '"' } else { $Value } }

# Re-run this tool as administrator in a new window (UAC prompt), with the given arguments.
function Start-Elevated([string[]]$Arguments) {
  $exe = (Get-Process -Id $PID).Path
  $list = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-NoExit', '-File', (ConvertTo-Arg $script:Entry)) + @($Arguments | ForEach-Object { ConvertTo-Arg $_ })
  try { Start-Process -FilePath $exe -Verb RunAs -ArgumentList $list | Out-Null; Write-Ok 'Opened an administrator window. Continue there.' }
  catch { Write-Bad 'Administrator rights were not granted.' }
}

function Read-YesNo([string]$Question, [bool]$Default = $false) {
  $hint = if ($Default) { '[Y/n]' } else { '[y/N]' }
  $a = Read-Host "$Question $hint"
  if ([string]::IsNullOrWhiteSpace($a)) { return $Default }
  $a.Trim().ToLower().StartsWith('y')
}
