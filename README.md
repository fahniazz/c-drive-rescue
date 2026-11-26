# C Drive Rescue

**Your C: drive is full. This finds out why and frees it without touching your own files.**

[Bahasa Indonesia](README.id.md)

A small PowerShell tool for Windows 10 and 11. There is nothing to install. It works the way a careful
person would do it by hand: it measures first, shows you the numbers, and lets you choose. It only deletes
caches that programs rebuild on their own. It moves big folders instead of deleting them, and it can undo
every move.

It started when a video tool quietly left 36 GB of temp copies on C:. A manual cleanup freed more than
100 GB on that PC: from 46 GB free to 164 GB free.

## Quick start

1. Click **Code > Download ZIP**. Right-click the zip, choose **Properties**, tick **Unblock**, then extract it.
2. Double-click **`Start.cmd`**.
3. Choose **1 Scan**. It deletes nothing and tells you what takes space and what to do about it.

```text
  1  Scan: show what takes space (deletes nothing)
  2  Clean caches (you see sizes and choose first)
  3  Clean Windows caches too (asks for administrator)
  4  Move a big folder to another drive
  5  Hibernation / pagefile / WinSxS / restore points (administrator)
  6  Bring a moved folder back
  7  Open the log
```

## Commands

From a PowerShell window in the extracted folder:

```powershell
powershell -ExecutionPolicy Bypass -File .\cdr.ps1 scan
```

In the rest of this page, `cdr` is short for that whole command.

| Command | What it does |
|---|---|
| `scan [-Deep]` | Read-only report: cleanable caches, hiberfil/pagefile, the 20 biggest folders in your profile, and numbered suggestions. `-Deep` also measures top-level folders on C:. |
| `clean [-Only a,b] [-Skip a,b] [-Admin] [-Yes]` | Measures every cache in [`targets.psd1`](targets.psd1), shows a numbered table, and deletes what you pick (`A` for all, or `1,3,5-7`). `-Only`/`-Skip` take ids or groups (`Windows`, `GPU`, `Browser`, `App`, `Dev`). `-Admin` reopens it as administrator for the Windows caches. |
| `move "<folder>" -To D [-Yes]` | Moves a folder to another drive and leaves a junction at the old path, so programs still find it. |
| `undo ["<folder>"] [-Yes]` | Brings a moved folder back. With no path it lists everything that was moved. |
| `tune` | Asks about each Windows setting below and shows its current state. Needs administrator rights. |
| `tune -Hibernate Off` | Deletes `hiberfil.sys`, which is often 40% of your RAM. Sleep keeps working; Hibernate and Fast Startup turn off. |
| `tune -PagefileTo D` | Keeps a 2-4 GB pagefile on C: (enough for crash dumps) and lets Windows size one on D:. Applies after a restart. `-PagefileAuto` undoes it. |
| `tune -ComponentCleanup` | Runs `DISM /StartComponentCleanup`, the supported way to shrink WinSxS. |
| `tune -RestorePercent 5` | Caps System Restore storage at 5% of the drive. |

## Safety rules

- **Measure first.** `scan` never deletes anything, and `clean` shows sizes and waits for your choice.
- **Caches only.** Every entry in `targets.psd1` is a folder its program refills by itself, such as shader caches, browser caches (not history, passwords or logins), package caches and Windows Update downloads.
- **Only what is inside.** The cache folder itself stays. `temp` keeps anything touched in the last 24 hours, and any folder holding a recent file is kept whole.
- **Links are never followed.** A junction or symlink inside a cache is removed as a link; what it points to is not touched. The tests check this.
- **Open apps are skipped.** If Chrome, Discord, Steam and so on are running, their caches show `Close chrome` and are left alone.
- **Moves are verified.** The tool copies the folder, then compares file count and bytes. It renames the original, creates the junction, and only then deletes the original. If any step fails, the original is put back.
- **Off-limits for moves:** `C:\Windows`, `Program Files\WindowsApps`, `ProgramData\Microsoft`, `AppData\Local\Microsoft`, `AppData\Local\Packages`, your profile root, Temp, and anything in OneDrive.
- **Never touched:** `WinSxS` and `C:\Windows\Installer` by hand, and your documents, projects, game saves and drafts.
- **Everything is logged** to `%LOCALAPPDATA%\c-drive-rescue\cdr.log`.

## What `clean` knows about

| Group | Caches |
|---|---|
| Windows | Temp (older than 1 day), Recycle Bin, crash dumps, Windows Temp, error reports and memory dumps, downloaded Windows Update files, Delivery Optimization |
| GPU | NVIDIA, AMD, Intel and DirectX shader caches |
| Browser | Chrome, Edge, Brave (Cache, Code Cache, GPUCache), Firefox (cache2) |
| App | Discord, Spotify, VS Code, Steam, Epic, Roblox, CapCut, TikTok LIVE Studio, Adobe media cache, and the Chromium cache folders of any other Electron app |
| Dev | npm, Yarn, pip, uv, NuGet, Gradle, Go, Cargo, Electron |

Missing a cache you know is safe to clear? Add an entry to `targets.psd1` and open a pull request.

## How `move` works

```text
C:\Users\you\AppData\Roaming\BigLauncher   (junction)  ->  D:\Moved-from-C\Users\you\AppData\Roaming\BigLauncher
```

A junction is a folder shortcut that Windows and programs cannot tell apart from the real folder. The launcher
still opens `C:\...\BigLauncher`, but the bytes live on D:. The path below `C:\` is kept, so two folders
called `Cache` never collide.

Close the program that uses the folder first. If Windows still has the folder open, nothing is changed and
you are told so. For known folders like Music and Documents, the tool points Windows at the new place
instead, and asks you to sign out and back in.

## FAQ

**Is turning hibernation off safe?** Yes. You lose Hibernate and Fast Startup; Sleep and shutdown work as
before. `tune -Hibernate On` brings it back.

**Is a small pagefile on C: safe?** The rest of the pagefile moves to another drive, so total virtual memory
stays the same. Keep the other drive plugged in, since an external drive is not a good place for it.

**Why not just delete `WinSxS` or `C:\Windows\Installer`?** Doing that by hand breaks updates and uninstallers.
`tune -ComponentCleanup` is the safe way to shrink WinSxS.

**A program broke after a move.** Run `cdr undo "<folder>"` and it is back as it was.

## Tests

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tests\smoke.ps1
pwsh -NoProfile -File tests\smoke.ps1
```

The tests work on throwaway folders only. They cover links, age filtering, sizes, the target list, move
guards, and a real move and undo through a second drive when one exists.

## License

MIT
