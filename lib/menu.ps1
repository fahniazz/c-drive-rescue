# Numbered menu for people who would rather not type commands (Start.cmd opens this).

function Invoke-Menu {
  while ($true) {
    Clear-Host
    Write-Host ('C Drive Rescue {0}' -f $script:Version) -ForegroundColor Cyan
    Show-Drive
    Write-Host ''
    Write-Host '  1  Scan: show what takes space (deletes nothing)'
    Write-Host '  2  Clean caches (you see sizes and choose first)'
    Write-Host '  3  Clean Windows caches too (asks for administrator)'
    Write-Host '  4  Move a big folder to another drive'
    Write-Host '  5  Hibernation / pagefile / WinSxS / restore points (administrator)'
    Write-Host '  6  Bring a moved folder back'
    Write-Host '  7  Open the log'
    Write-Host '  0  Exit'
    Write-Host ''
    $c = Read-Host 'Choose'
    switch ($c) {
      '1' { Invoke-Scan }
      '2' { Invoke-Clean }
      '3' { Invoke-Clean -Admin }
      '4' {
        Show-Drive; foreach ($o in Get-OtherDrives) { Show-Drive $o.Drive }
        $p = Read-Host 'Folder to move (paste the full path; tip: Scan lists big ones)'
        $p = $p.Trim().Trim('"')
        if ($p) {
          $to = Read-Host 'Move it to which drive letter (e.g. D)'
          if ($to) { Invoke-Move -Path $p -To $to.Trim() }
        }
      }
      '5' { Invoke-Tune }
      '6' {
        Show-Moves
        $p = Read-Host 'Original path to bring back (Enter to skip)'
        if ($p) { Invoke-Undo -Path $p.Trim().Trim('"') }
      }
      '7' { if (Test-Path -LiteralPath $script:LogFile) { Start-Process notepad.exe $script:LogFile } else { Write-Host 'No log yet.' } }
      '0' { return }
      default { continue }
    }
    Write-Host ''
    [void](Read-Host 'Press Enter to go back to the menu')
  }
}
