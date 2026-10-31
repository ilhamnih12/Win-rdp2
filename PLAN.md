# Prompt dan rencana: sesi pengembangan Windows untuk porting aplikasi

## Revisi sebelum implementasi: Google Antigravity menggantikan Codex

Pengguna membatalkan Codex dan memilih Google Antigravity dengan opsi gratis. Hapus instalasi npm Codex, action setup-node yang tidak lagi diperlukan untuk agent, serta petunjuk login Codex. Pertahankan RDP privat, akun non-admin, durasi, clone source, dan ekspor hasil.

Verifikasi paket Windows melalui manifest `Google.Antigravity` pada repository Microsoft winget-pkgs. Pin versi, URL installer HTTPS resmi Google, SHA256, dan commit manifest; jangan mengarang URL. Manifest 2.28.2 menyebut installer NSIS **scope user**, sehingga jangan memasangnya sebagai runneradmin. Unduh dan verifikasi SHA256 serta Authenticode publisher Google LLC saat setup. Sediakan shortcut desktop yang menjalankan helper instalasi **di sesi devrdp**, kemudian membuka Antigravity. Helper menggunakan lokasi `C:\Dev\Antigravity` dan memeriksa hasil instalasi. Tidak menonaktifkan sandbox atau memaksa flag no-sandbox.

Login akun Google dilakukan sendiri melalui UI/browser dalam sesi RDP. Jangan menyimpan password, token Google, atau profil aplikasi dalam artifact. Tidak menambah secret Google atau API key. Akses gratis/kuota, ketersediaan negara/akun, dan dukungan Windows Server/VM/RDP belum diverifikasi lewat aplikasi nyata; tuliskan batasan ini dan jangan menjanjikan paket gratis tanpa syarat. Jika UI hanya menawarkan paket berbayar/trial kartu kredit, berhenti, bukan mengaktifkan billing.

Perbarui README, petunjuk desktop, job summary, penamaan firewall/hostname yang sebelumnya memakai Codex, dan tes agar tidak ada instalasi/login Codex tersisa. Catat sumber manifest dan keterbatasan pengujian Windows di VALIDATION.md. Bagian di bawah adalah rencana dasar yang kini disesuaikan dengan revisi ini.

## Kebutuhan terbaru

Pengguna hanya memiliki HP low-end, tidak menggunakan Termux, tidak memiliki server atau kartu kredit, dan memerlukan sesi Windows sekitar 2–3 jam untuk menjalankan Google Antigravity guna mem-port aplikasi open source. Ini adalah kebutuhan pengembangan, bukan permintaan komputer pribadi 24/7.

Rencana self-hosted sebelumnya dibatalkan karena membutuhkan komputer yang tidak dimiliki pengguna. Implementasi berikut memakai job Windows hosted **untuk pekerjaan pengembangan repository**, dengan akses RDP privat sebagai sarana interaksi. Kesesuaian penggunaan tetap mengikuti ketentuan GitHub; durasi di bawah timeout tidak dengan sendirinya menjamin izin penggunaan. Jangan gunakan untuk desktop umum, mengakali kuota, mining, atau menjalankan ulang sesi secara otomatis.

## Prompt implementasi detail

Buat workflow GitHub Actions manual untuk sesi pengembangan Windows maksimal 180 menit. Sediakan input repository GitHub publik yang ingin di-port, branch/tag/commit opsional, deskripsi tugas porting, dan durasi. Clone sumber tanpa kredensial GitHub ke C:\Dev\source. Siapkan installer Google Antigravity terverifikasi, helper instalasi per-user, dan petunjuk kerja di desktop akun RDP lokal non-admin.

Hubungkan Windows ke tailnet pengguna menggunakan Tailscale dan secret TS_AUTHKEY. Gunakan instalasi MSI resmi yang tanda tangan Authenticode-nya divalidasi. Pengguna menginstal Tailscale di HP dan masuk ke tailnet yang sama; ini tidak membutuhkan Termux. RDP memakai TCP 3389 pada IP privat Tailscale, bukan tunnel TCP publik. Tailscale dapat memakai relay bila koneksi langsung tidak memungkinkan; jangan menjamin transport underlay atau koneksi 100% berhasil di semua jaringan.

Gunakan secret RDP_PASSWORD, wajib memenuhi kompleksitas, jangan mencetak password/token atau memasukkannya ke artifact. Buat akun lokal khusus anggota Remote Desktop Users, bukan Administrators. Tetap aktifkan NLA; batasi aturan firewall RDP ke interface Tailscale dan subnet tailnet, nonaktifkan aturan RDP bawaan yang lebih luas. Pengguna tetap perlu membatasi kebijakan akses tailnet ke perangkatnya.

Gunakan permissions contents: read, actions dipin ke commit, tanpa trigger pull_request/push, tanpa checkout menggunakan kredensial persisten. Jangan jalankan kode proyek sumber otomatis dengan secret terpasang. Hapus auth key dari environment setelah autentikasi dan dari environment langkah selanjutnya. Terapkan concurrency tanpa membatalkan sesi yang aktif. Sesi berakhir otomatis sesuai durasi; pembatalan manual juga tersedia. Bersihkan RDP, akun, dan sesi Tailscale pada langkah always(), dengan catatan cleanup tidak dijamin pada hard kill runner.

Sediakan upload artifact opt-in hanya dari C:\Dev\exports\*.bundle pada akhir sesi. Pengguna meninjau perubahan, melakukan commit lokal secara eksplisit, lalu membuat git bundle untuk menyimpan pekerjaan; jangan otomatis git add atau mengunggah workspace/profil Windows karena mungkin berisi rahasia. Jelaskan bundle hanya berisi commit, bukan perubahan yang belum di-commit, dan dapat memuat seluruh riwayat repository. Ingatkan pengguna agar menyimpan pekerjaan sebelum timeout/cancel, karena artifact bukan pengganti backup dan hard cancellation dapat melewati langkah upload. Tombol akhiri sesi melalui file penanda memungkinkan upload sebelum durasi habis.

Jelaskan secara jujur bahwa runner/kuota, paket Personal Tailscale, dan akses model adalah tiga hal berbeda. Workflow tidak menyertakan kredit API, tidak membeli layanan, tidak menjamin kelayakan akun/kuota Antigravity gratis. Pengguna login Google sendiri di sesi RDP menggunakan metode resmi yang tersedia untuk akunnya. Jika akun tidak memiliki akses/kuota Antigravity, workflow tidak mengatasinya.

## Urutan pekerjaan

1. Perbarui dokumen ini terlebih dahulu sesuai tujuan porting yang diklarifikasi pengguna.
2. Implementasikan workflow dan skrip setup, hold, export, cleanup.
3. Tulis README Bahasa Indonesia untuk setup dari browser HP, secrets, koneksi, Antigravity, menyimpan pekerjaan, dan batas biaya/keamanan.
4. Jalankan validasi YAML, actionlint, serta pemeriksaan sintaks PowerShell jika tooling tersedia. Tidak memicu workflow berbayar atau mencoba login atas nama pengguna.
5. Laporkan keterbatasan pengujian: sandbox Linux bukan host Windows, dan pengujian RDP end-to-end perlu tailnet/password milik pengguna.
