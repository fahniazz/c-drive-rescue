# C Drive Rescue

**Drive C: penuh? Tool ini mencari tahu penyebabnya dan melegakannya tanpa menyentuh file kamu.**

[English](README.md)

Tool PowerShell kecil untuk Windows 10 dan 11, tanpa instalasi. Cara kerjanya sama seperti kalau kamu
membersihkan dengan hati-hati secara manual: ukur dulu, tampilkan angkanya, lalu kamu yang memilih. Yang
dihapus hanya cache, yang nanti dibuat ulang sendiri oleh programnya. Folder besar dipindah, bukan dihapus,
dan setiap pemindahan bisa dibatalkan.

Tool ini lahir waktu sebuah tool video diam-diam meninggalkan 36 GB salinan sementara di C:. Setelah
dibereskan manual dengan cara yang sama, ruang kosong di PC itu naik dari 46 GB menjadi 164 GB.

## Cara pakai (paling gampang)

1. Klik **Code > Download ZIP**. Klik kanan file zip-nya, pilih **Properties**, centang **Unblock**, lalu extract.
2. Klik dua kali **`Start.cmd`**.
3. Pilih **1 Scan**. Tidak ada yang dihapus; kamu hanya diberi tahu apa yang memakan ruang dan apa yang bisa dilakukan.

| Menu | Fungsi |
|---|---|
| 1 Scan | Laporan saja: cache, file sistem, 20 folder terbesar, dan saran bernomor |
| 2 Clean | Membersihkan cache. Ukurannya ditampilkan dulu, lalu ketik `A` untuk semua atau nomor seperti `1,3,5-7` |
| 3 Clean + Windows | Sama, ditambah cache Windows (Windows Update, Windows Temp). Akan minta izin administrator |
| 4 Move | Memindahkan folder besar ke drive lain. Path lamanya tetap bisa dipakai |
| 5 Tune | Hibernate, pagefile, WinSxS, dan System Restore (administrator) |
| 6 Undo | Mengembalikan folder yang pernah dipindah |

## Lewat command line

```powershell
powershell -ExecutionPolicy Bypass -File .\cdr.ps1 scan
powershell -ExecutionPolicy Bypass -File .\cdr.ps1 clean -Only Browser,GPU
powershell -ExecutionPolicy Bypass -File .\cdr.ps1 move "$env:APPDATA\ModrinthApp" -To D
powershell -ExecutionPolicy Bypass -File .\cdr.ps1 undo
powershell -ExecutionPolicy Bypass -File .\cdr.ps1 tune -Hibernate Off
```

## Aturan keamanan

- **Selalu ukur dulu.** `scan` tidak pernah menghapus apa pun. `clean` menunggu pilihanmu.
- **Hanya cache.** Isi [`targets.psd1`](targets.psd1) adalah folder yang diisi ulang sendiri oleh programnya. Untuk browser, yang dihapus hanya cache. History, password, dan login tidak tersentuh.
- **Hanya isinya.** Folder cache-nya sendiri tetap ada. Untuk Temp, apa pun yang disentuh dalam 24 jam terakhir dibiarkan.
- **Link tidak pernah diikuti.** Junction atau symlink di dalam cache hanya dilepas, isi tujuannya aman. Ini diuji di `tests\smoke.ps1`.
- **Aplikasi yang sedang terbuka dilewati.** Kalau Chrome, Discord, Steam, dan lainnya sedang jalan, statusnya `Close chrome` dan cache-nya tidak disentuh.
- **Pemindahan dicek.** Urutannya: salin, bandingkan jumlah file dan byte, ganti nama folder asli, buat junction, baru hapus yang lama. Kalau ada langkah yang gagal, semuanya dikembalikan.
- **Tidak boleh dipindah:** `C:\Windows`, `WindowsApps`, `ProgramData\Microsoft`, `AppData\Local\Microsoft`, `AppData\Local\Packages`, folder profil, Temp, dan OneDrive.
- **Semua tercatat** di `%LOCALAPPDATA%\c-drive-rescue\cdr.log`.

## Tanya jawab

**Mematikan hibernate aman?** Aman. Yang hilang hanya Hibernate dan Fast Startup. Sleep dan shutdown
tetap normal. Untuk menyalakannya lagi: `tune -Hibernate On`.

**Pagefile kecil di C: aman?** Sisanya pindah ke drive lain, jadi total memori virtual tetap sama. Jangan
pakai drive eksternal untuk ini.

**Kenapa WinSxS atau `C:\Windows\Installer` tidak dihapus saja?** Menghapusnya manual bisa merusak update
dan uninstaller. Cara yang aman untuk WinSxS adalah `tune -ComponentCleanup`.

**Ada program error setelah dipindah?** Jalankan `undo "<folder>"`, semuanya kembali seperti semula.

## Lisensi

MIT
