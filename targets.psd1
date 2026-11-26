# What `cdr clean` may empty. Every entry is a cache or leftover that the owning program rebuilds by itself.
# Only the CONTENTS of each folder are deleted, never the folder. Links inside are unlinked, never followed.
#
#   Id            short name for -Only / -Skip
#   Paths         %ENV% variables and * wildcards allowed; a path that is a file deletes that file
#   OlderThanDays only delete entries untouched for this many days (anything newer may be in use)
#   Close         process names (without .exe) that must not be running, else the entry is skipped
#   Admin         needs an administrator window
#   Special       handled in code: RecycleBin, WindowsUpdate, DeliveryOptimization
#
# Order matters: a path claimed by an earlier entry is not counted again by a later wildcard entry.
# Want to add a cache? Add an entry, run `cdr scan`, and open a pull request with what it frees.
@{
  Targets = @(
    # --- Windows ---------------------------------------------------------------------------------------------
    @{ Id = 'temp'; Group = 'Windows'; Name = 'Your temp folder (older than 1 day)'
       Paths = @('%TEMP%'); OlderThanDays = 1
       Note = 'Programs drop leftovers here and forget them (one video tool left 36 GB). Recent items are kept.' }
    @{ Id = 'recycle-bin'; Group = 'Windows'; Name = 'Recycle Bin on the system drive'; Special = 'RecycleBin'
       Paths = @() ; Note = 'Files you already deleted. Look inside first if you are unsure.' }
    @{ Id = 'crash-dumps'; Group = 'Windows'; Name = 'App crash dumps'
       Paths = @('%LOCALAPPDATA%\CrashDumps') }
    @{ Id = 'windows-temp'; Group = 'Windows'; Name = 'Windows temp folder (older than 1 day)'; Admin = $true
       Paths = @('%SystemRoot%\Temp'); OlderThanDays = 1 }
    @{ Id = 'error-reports'; Group = 'Windows'; Name = 'Windows error reports and memory dumps'; Admin = $true
       Paths = @('%ProgramData%\Microsoft\Windows\WER\ReportArchive', '%ProgramData%\Microsoft\Windows\WER\ReportQueue',
                 '%SystemRoot%\Minidump', '%SystemRoot%\MEMORY.DMP') }
    @{ Id = 'windows-update'; Group = 'Windows'; Name = 'Downloaded Windows Update files'; Admin = $true; Special = 'WindowsUpdate'
       Paths = @('%SystemRoot%\SoftwareDistribution\Download')
       Note = 'Updates that are already installed. The update service is stopped for a moment while this runs.' }
    @{ Id = 'delivery-optimization'; Group = 'Windows'; Name = 'Delivery Optimization cache'; Admin = $true; Special = 'DeliveryOptimization'
       Paths = @('%SystemRoot%\ServiceProfiles\NetworkService\AppData\Local\Microsoft\Windows\DeliveryOptimization\Cache') }

    # --- Graphics drivers: shader caches, rebuilt the next time a game starts (first launch may stutter) -----
    @{ Id = 'nvidia'; Group = 'GPU'; Name = 'NVIDIA shader cache'
       Paths = @('%LOCALAPPDATA%\NVIDIA\DXCache', '%LOCALAPPDATA%\NVIDIA\GLCache', '%LOCALAPPDATA%\NVIDIA Corporation\NV_Cache',
                 '%ProgramData%\NVIDIA Corporation\NV_Cache') }
    @{ Id = 'amd'; Group = 'GPU'; Name = 'AMD shader cache'
       Paths = @('%LOCALAPPDATA%\AMD\DxCache', '%LOCALAPPDATA%\AMD\DxcCache', '%LOCALAPPDATA%\AMD\GLCache', '%LOCALAPPDATA%\AMD\VkCache') }
    @{ Id = 'intel'; Group = 'GPU'; Name = 'Intel shader cache'
       Paths = @('%USERPROFILE%\AppData\LocalLow\Intel\ShaderCache') }
    @{ Id = 'directx'; Group = 'GPU'; Name = 'DirectX shader cache'
       Paths = @('%LOCALAPPDATA%\D3DSCache') }

    # --- Browsers: cached web files only. History, passwords, cookies and logins are NOT touched -------------
    @{ Id = 'chrome'; Group = 'Browser'; Name = 'Google Chrome cache'; Close = @('chrome')
       Paths = @('%LOCALAPPDATA%\Google\Chrome\User Data\*\Cache', '%LOCALAPPDATA%\Google\Chrome\User Data\*\Code Cache',
                 '%LOCALAPPDATA%\Google\Chrome\User Data\*\GPUCache', '%LOCALAPPDATA%\Google\Chrome\User Data\ShaderCache',
                 '%LOCALAPPDATA%\Google\Chrome\User Data\GrShaderCache') }
    @{ Id = 'edge'; Group = 'Browser'; Name = 'Microsoft Edge cache'; Close = @('msedge')
       Paths = @('%LOCALAPPDATA%\Microsoft\Edge\User Data\*\Cache', '%LOCALAPPDATA%\Microsoft\Edge\User Data\*\Code Cache',
                 '%LOCALAPPDATA%\Microsoft\Edge\User Data\*\GPUCache', '%LOCALAPPDATA%\Microsoft\Edge\User Data\ShaderCache',
                 '%LOCALAPPDATA%\Microsoft\Edge\User Data\GrShaderCache')
       Note = 'Edge often keeps running in the background; turn off Startup boost in Edge settings if it is always skipped.' }
    @{ Id = 'brave'; Group = 'Browser'; Name = 'Brave cache'; Close = @('brave')
       Paths = @('%LOCALAPPDATA%\BraveSoftware\Brave-Browser\User Data\*\Cache', '%LOCALAPPDATA%\BraveSoftware\Brave-Browser\User Data\*\Code Cache',
                 '%LOCALAPPDATA%\BraveSoftware\Brave-Browser\User Data\*\GPUCache') }
    @{ Id = 'firefox'; Group = 'Browser'; Name = 'Firefox cache'; Close = @('firefox')
       Paths = @('%LOCALAPPDATA%\Mozilla\Firefox\Profiles\*\cache2') }

    # --- Apps -------------------------------------------------------------------------------------------------
    @{ Id = 'discord'; Group = 'App'; Name = 'Discord cache'; Close = @('Discord')
       Paths = @('%APPDATA%\discord\Cache', '%APPDATA%\discord\Code Cache', '%APPDATA%\discord\GPUCache') }
    @{ Id = 'spotify'; Group = 'App'; Name = 'Spotify song cache'; Close = @('Spotify')
       Paths = @('%LOCALAPPDATA%\Spotify\Data') ; Note = 'Downloaded (offline) songs are kept elsewhere and stay.' }
    @{ Id = 'vscode'; Group = 'App'; Name = 'VS Code cache'; Close = @('Code')
       Paths = @('%APPDATA%\Code\Cache', '%APPDATA%\Code\CachedData', '%APPDATA%\Code\CachedExtensionVSIXs',
                 '%APPDATA%\Code\Code Cache', '%APPDATA%\Code\GPUCache') }
    @{ Id = 'steam'; Group = 'App'; Name = 'Steam web cache'; Close = @('steam', 'steamwebhelper')
       Paths = @('%LOCALAPPDATA%\Steam\htmlcache') }
    @{ Id = 'epic'; Group = 'App'; Name = 'Epic Games Launcher web cache'; Close = @('EpicGamesLauncher')
       Paths = @('%LOCALAPPDATA%\EpicGamesLauncher\Saved\webcache*') }
    @{ Id = 'roblox'; Group = 'App'; Name = 'Roblox asset cache and installers'; Close = @('RobloxPlayerBeta', 'RobloxStudioBeta')
       Paths = @('%LOCALAPPDATA%\Roblox\rbx-storage', '%LOCALAPPDATA%\Roblox\Downloads') }
    @{ Id = 'capcut'; Group = 'App'; Name = 'CapCut cache'; Close = @('CapCut')
       Paths = @('%LOCALAPPDATA%\CapCut\User Data\Cache')
       Note = 'Only the cache. Your CapCut projects and drafts are not touched.' }
    @{ Id = 'tiktok-live'; Group = 'App'; Name = 'TikTok LIVE Studio cache'; Close = @('TikTok LIVE Studio')
       Paths = @('%APPDATA%\TikTok LIVE Studio\Cache', '%APPDATA%\TikTok LIVE Studio\gecko_cache') }
    @{ Id = 'adobe-media-cache'; Group = 'App'; Name = 'Adobe media cache (Premiere, After Effects)'
       Close = @('Adobe Premiere Pro', 'AfterFX', 'Adobe Media Encoder')
       Paths = @('%APPDATA%\Adobe\Common\Media Cache Files', '%APPDATA%\Adobe\Common\Media Cache')
       Note = 'Preview and audio conform files; Adobe rebuilds them when you open a project.' }
    @{ Id = 'chromium-apps'; Group = 'App'; Name = 'Other Electron/Chromium app caches'
       Paths = @('%APPDATA%\*\Cache\Cache_Data', '%APPDATA%\*\Code Cache', '%APPDATA%\*\GPUCache')
       Note = 'Same cache folders inside every Electron app (Teams, Slack, Figma, launchers...). Files in use are skipped.' }

    # --- Developer tools: package caches, downloaded again when a build needs them --------------------------
    @{ Id = 'npm'; Group = 'Dev'; Name = 'npm cache'; Paths = @('%LOCALAPPDATA%\npm-cache\_cacache') }
    @{ Id = 'yarn'; Group = 'Dev'; Name = 'Yarn cache'; Paths = @('%LOCALAPPDATA%\Yarn\Cache') }
    @{ Id = 'pip'; Group = 'Dev'; Name = 'pip cache'; Paths = @('%LOCALAPPDATA%\pip\cache') }
    @{ Id = 'uv'; Group = 'Dev'; Name = 'uv cache'; Close = @('uv'); Paths = @('%LOCALAPPDATA%\uv\cache') }
    @{ Id = 'nuget'; Group = 'Dev'; Name = 'NuGet HTTP cache'; Paths = @('%LOCALAPPDATA%\NuGet\v3-cache', '%LOCALAPPDATA%\NuGet\plugins-cache') }
    @{ Id = 'gradle'; Group = 'Dev'; Name = 'Gradle caches'; Paths = @('%USERPROFILE%\.gradle\caches')
       Note = 'Stop running Gradle daemons first (gradle --stop).' }
    @{ Id = 'go'; Group = 'Dev'; Name = 'Go build cache'; Paths = @('%LOCALAPPDATA%\go-build') }
    @{ Id = 'cargo'; Group = 'Dev'; Name = 'Cargo download cache'; Paths = @('%USERPROFILE%\.cargo\registry\cache') }
    @{ Id = 'electron'; Group = 'Dev'; Name = 'Electron download cache'; Paths = @('%LOCALAPPDATA%\electron\Cache', '%LOCALAPPDATA%\electron-builder\Cache') }
  )
}
