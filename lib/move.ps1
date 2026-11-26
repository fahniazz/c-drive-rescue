# `cdr move` / `cdr undo`: move a big folder to another drive and leave a junction (a folder shortcut that
# programs cannot tell apart from the real folder) at the old path. Order: copy -> verify -> rename original
# -> junction -> delete original. Any failure before the last step leaves the original untouched.

$script:ShellKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders'
$script:ShellKeyLegacy = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Shell Folders'

function Get-Moves {
  if (-not (Test-Path -LiteralPath $script:MovesFile)) { return @() }
  $raw = Get-Content -LiteralPath $script:MovesFile -Raw | ConvertFrom-Json
  @($raw | ForEach-Object { $_ })   # 5.1 returns a JSON array as one object; this unrolls it
}

function Save-Moves($List) {
  ConvertTo-Json -InputObject @($List) -Depth 5 | Set-Content -LiteralPath $script:MovesFile -Encoding UTF8
}

function Test-Under([string]$Path, [string]$Parent) {
  $p = $Path.TrimEnd('\').ToLowerInvariant(); $q = $Parent.TrimEnd('\').ToLowerInvariant()
  ($p -eq $q) -or $p.StartsWith($q + '\')
}

# Why a folder must not be moved, or $null when it may.
function Get-MoveBlocker([string]$Path) {
  $item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
  if (-not $item -or -not $item.PSIsContainer) { return 'not a folder' }
  if (Test-Link $item) { return 'already a link (moved before?)' }
  $p = $item.FullName.TrimEnd('\')
  if (-not (Test-Under $p ($script:SysDrive + '\'))) { return ('not on {0}' -f $script:SysDrive) }
  $u = $env:USERPROFILE
  $exact = @(($script:SysDrive + '\'), "$($script:SysDrive)\Users", $env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:ProgramData,
             $u, "$u\AppData", "$u\AppData\Local", "$u\AppData\Roaming", "$u\AppData\LocalLow")
  foreach ($e in $exact) { if ($e -and $p.ToLowerInvariant() -eq $e.TrimEnd('\').ToLowerInvariant()) { return 'system folder' } }
  $profileRoot = Split-Path $u -Parent
  if ((Split-Path $p -Parent).ToLowerInvariant() -eq $profileRoot.ToLowerInvariant()) { return 'a whole user profile' }
  $under = @($env:SystemRoot, "$env:ProgramFiles\WindowsApps", "$env:ProgramFiles\Common Files", "$env:ProgramData\Microsoft",
             "$u\AppData\Local\Microsoft", "$u\AppData\Roaming\Microsoft", "$u\AppData\Local\Packages", "$u\AppData\Local\Temp",
             "$($script:SysDrive)\Recovery", "$($script:SysDrive)\System Volume Information", "$($script:SysDrive)\`$Recycle.Bin")
  foreach ($x in $under) { if ($x -and (Test-Under $p $x)) { return 'used by Windows itself' } }
  foreach ($od in @($env:OneDrive, $env:OneDriveConsumer, $env:OneDriveCommercial)) {
    if ($od -and (Test-Under $p $od)) { return 'inside OneDrive (use OneDrive settings instead)' }
  }
  $null
}

# Registry names of known folders (Documents, Music...) that point at this path, with their raw values.
function Get-ShellFolderNames([string]$Path) {
  $key = Get-Item -LiteralPath $script:ShellKey -ErrorAction SilentlyContinue
  if (-not $key) { return @() }
  foreach ($name in $key.GetValueNames()) {
    $raw = [string]$key.GetValue($name, $null, 'DoNotExpandEnvironmentNames')
    $expanded = [Environment]::ExpandEnvironmentVariables($raw).TrimEnd('\')
    if ($expanded -ieq $Path.TrimEnd('\')) { [pscustomobject]@{ Name = $name; Raw = $raw } }
  }
}

function Set-ShellFolder([string]$Name, [string]$Value) {
  Set-ItemProperty -LiteralPath $script:ShellKey -Name $Name -Value $Value -Type ExpandString
  if (Test-Path -LiteralPath $script:ShellKeyLegacy) {
    if ($null -ne (Get-ItemProperty -LiteralPath $script:ShellKeyLegacy -Name $Name -ErrorAction SilentlyContinue)) {
      Set-ItemProperty -LiteralPath $script:ShellKeyLegacy -Name $Name -Value ([Environment]::ExpandEnvironmentVariables($Value))
    }
  }
}

# Copy a folder tree with robocopy; links are copied as links. Returns $true when the copy matches the source.
function Copy-Verified([string]$From, [string]$To) {
  & robocopy.exe $From $To /E /COPY:DAT /DCOPY:DAT /SJ /SL /R:1 /W:1 /MT:16 /NFL /NDL /NP /NJH /NJS | Out-Null
  if ($LASTEXITCODE -ge 8) { Write-Bad ("robocopy failed (exit code {0})" -f $LASTEXITCODE); return $false }
  $a = Get-RoboStats $From; $b = Get-RoboStats $To
  if ($a.Files -ne $b.Files -or $a.Bytes -ne $b.Bytes) {
    Write-Bad ('Copy does not match: {0} files {1} vs {2} files {3}. A program may still be writing to it.' -f $a.Files, (Format-Size $a.Bytes), $b.Files, (Format-Size $b.Bytes))
    return $false
  }
  $true
}

function Resolve-MoveTarget([string]$Source, [string]$To) {
  if ($To -match '^[A-Za-z]:?\\?$') { $root = $To.Substring(0, 1).ToUpper() + ':\Moved-from-' + $script:SysDrive.TrimEnd(':') }
  else { $root = [IO.Path]::GetFullPath($To) }
  Join-Path $root $Source.Substring(3)   # keep the path below C:\ so two folders named "Cache" never collide
}

function Invoke-Move([string]$Path, [string]$To, [switch]$Yes) {
  if (-not $Path -or -not $To) { Write-Bad 'Usage: cdr move "<folder>" -To D'; return }
  $item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
  if (-not $item) { Write-Bad "Not found: $Path"; return }
  $src = $item.FullName.TrimEnd('\')
  $why = Get-MoveBlocker $src
  if ($why) { Write-Bad ("Cannot move {0}: {1}." -f $src, $why); return }
  $dst = Resolve-MoveTarget $src $To
  $dstRoot = [IO.Path]::GetPathRoot($dst)
  if ($dstRoot -ieq [IO.Path]::GetPathRoot($src)) { Write-Bad 'The new place must be on another drive.'; return }
  if (-not (Test-Path -LiteralPath $dstRoot)) { Write-Bad "Drive $dstRoot not found."; return }
  if ((Test-Path -LiteralPath $dst) -and @(Get-ChildItem -LiteralPath $dst -Force).Count) { Write-Bad "$dst already exists and is not empty."; return }

  $stats = Get-RoboStats $src
  $free = (Get-DriveFree $dstRoot.TrimEnd('\')).Free
  if ($free -lt $stats.Bytes + 1GB) { Write-Bad ('Not enough space on {0}: need {1}, have {2}.' -f $dstRoot, (Format-Size ($stats.Bytes + 1GB)), (Format-Size $free)); return }
  $shell = @(Get-ShellFolderNames $src)

  Write-Title 'Move a folder'
  Write-Host ("  From: {0}" -f $src)
  Write-Host ("  To:   {0}" -f $dst)
  Write-Host ("  Size: {0} in {1} files" -f (Format-Size $stats.Bytes), $stats.Files)
  Write-Host '  The old path keeps working: a junction there points to the new place.'
  if ((Test-Under $src $env:ProgramFiles) -or (${env:ProgramFiles(x86)} -and (Test-Under $src ${env:ProgramFiles(x86)}))) {
    Write-Warn ('  Programs usually keep working, but if this one breaks, run: cdr undo "{0}"' -f $src)
  }
  Write-Warn '  Close the program that uses this folder first (and any Explorer window showing it).'
  if (-not $Yes -and -not (Read-YesNo 'Start?' $false)) { Write-Host 'Cancelled.'; return }

  Write-Host 'Copying (this can take a while)...'
  if (-not (Copy-Verified $src $dst)) { Remove-Entry (New-Object IO.DirectoryInfo($dst)); Write-Bad 'Nothing was changed.'; return }
  try { (Get-Item -LiteralPath $dst -Force).Attributes = $item.Attributes } catch { }   # keeps ReadOnly for desktop.ini folders

  $old = $src + '.cdr-old'
  $mode = 'junction'
  try { Rename-Item -LiteralPath $src -NewName (Split-Path $old -Leaf) -ErrorAction Stop }
  catch {
    if (-not $shell.Count) {
      Remove-Entry (New-Object IO.DirectoryInfo($dst))
      Write-Bad 'The folder is in use. Close the program using it (or restart Windows) and try again. Nothing was changed.'
      return
    }
    # A Windows known folder (Music, Documents...) that Explorer holds open: point Windows at the copy instead.
    $mode = 'redirect'
  }

  if ($mode -eq 'junction') {
    try { New-Item -ItemType Junction -Path $src -Value $dst -ErrorAction Stop | Out-Null }
    catch {
      Rename-Item -LiteralPath $old -NewName (Split-Path $src -Leaf)
      Remove-Entry (New-Object IO.DirectoryInfo($dst))
      Write-Bad "Could not create the junction: $_. Nothing was changed."
      return
    }
    Remove-Entry (New-Object IO.DirectoryInfo($old))
  } else {
    foreach ($s in $shell) { Set-ShellFolder $s.Name $dst }
    foreach ($c in (New-Object IO.DirectoryInfo($src)).GetFileSystemInfos()) { if ($c.Name -ine 'desktop.ini') { Remove-Entry $c } }
    Write-Warn ('Windows now uses {0} for this folder. Sign out and back in so every program picks it up.' -f $dst)
  }

  $list = @(Get-Moves) + [pscustomobject]@{ Source = $src; Target = $dst; Mode = $mode; Bytes = $stats.Bytes; Date = (Get-Date -Format s); Shell = @($shell) }
  Save-Moves $list
  Write-Log ('move {0} -> {1} ({2}, {3} bytes)' -f $src, $dst, $mode, $stats.Bytes)
  Write-Ok ('Moved. {0} freed on {1}.' -f (Format-Size $stats.Bytes), $script:SysDrive)
  Show-Drive
}

function Show-Moves {
  $moves = @(Get-Moves)
  if (-not $moves.Count) { Write-Host 'No folders moved with this tool yet.'; return }
  Write-Title 'Folders moved with this tool'
  foreach ($m in $moves) { Write-Host ('  {0,9}  {1}  ->  {2}  ({3}, {4})' -f (Format-Size $m.Bytes), $m.Source, $m.Target, $m.Mode, $m.Date) }
}

function Invoke-Undo([string]$Path, [switch]$Yes) {
  if (-not $Path) { Show-Moves; Write-Host ''; Write-Host 'Usage: cdr undo "<original folder path>"'; return }
  $full = [IO.Path]::GetFullPath($Path).TrimEnd('\')
  $moves = @(Get-Moves)
  $m = $moves | Where-Object { $_.Source -ieq $full -or $_.Target -ieq $full } | Select-Object -First 1
  if (-not $m) { Write-Bad "No move recorded for $full. Run 'cdr undo' to list them."; return }
  $src = $m.Source; $dst = $m.Target
  if (-not (Test-Path -LiteralPath $dst)) { Write-Bad "The moved copy $dst is missing."; return }
  $stats = Get-RoboStats $dst
  $free = (Get-DriveFree).Free
  if ($free -lt $stats.Bytes + 1GB) { Write-Bad ('Not enough space on {0} to bring it back: need {1}, have {2}.' -f $script:SysDrive, (Format-Size ($stats.Bytes + 1GB)), (Format-Size $free)); return }
  Write-Title 'Bring a folder back'
  Write-Host ("  {0}  ->  {1}  ({2})" -f $dst, $src, (Format-Size $stats.Bytes))
  if (-not $Yes -and -not (Read-YesNo 'Start?' $false)) { Write-Host 'Cancelled.'; return }

  if ($m.Mode -eq 'redirect') {
    if (-not (Copy-Verified $dst $src)) { Write-Bad 'Copy back failed; the moved copy is untouched.'; return }
    foreach ($s in @($m.Shell)) { Set-ShellFolder $s.Name $s.Raw }
  } else {
    $back = $src + '.cdr-back'
    if (-not (Copy-Verified $dst $back)) { Remove-Entry (New-Object IO.DirectoryInfo($back)); Write-Bad 'Copy back failed; nothing was changed.'; return }
    $link = Get-Item -LiteralPath $src -Force -ErrorAction SilentlyContinue
    if ($link -and (Test-Link $link)) { [IO.Directory]::Delete($src, $false) }
    elseif ($link) { Remove-Entry (New-Object IO.DirectoryInfo($back)); Write-Bad "$src is no longer a junction; left everything as it is."; return }
    Rename-Item -LiteralPath $back -NewName (Split-Path $src -Leaf)
  }
  Remove-Entry (New-Object IO.DirectoryInfo($dst))
  Save-Moves @($moves | Where-Object { $_.Source -ine $src })
  Write-Log ('undo {0} <- {1}' -f $src, $dst)
  Write-Ok "Back in $src."
  if ($m.Mode -eq 'redirect') { Write-Warn 'Sign out and back in so every program uses the old place again.' }
}
