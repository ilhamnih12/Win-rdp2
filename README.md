# Windows untuk porting aplikasi dengan Google Antigravity

Workflow manual untuk **sesi pengembangan Windows sementara**, diakses dari HP dengan RDP melalui jaringan privat Tailscale. Cocok untuk membuka source aplikasi open source, menjalankan Google Antigravity, lalu melakukan porting/build/test. Tidak membutuhkan Termux atau komputer milik sendiri.

> **Pilih opsi gratis, jangan aktifkan billing/trial kartu kredit.** Runner mengikuti kuota dan ketentuan GitHub; Tailscale mengikuti syarat paket Personal. Akses gratis Google Antigravity bergantung kelayakan akun/wilayah dan kuota yang tersedia. Installer tidak memberi langganan atau kuota model. Ketentuan gratis terkini belum dapat diverifikasi langsung dari situs Google di sandbox ini; periksa [pricing resmi](https://antigravity.google/pricing) sebelum mulai. Workflow tidak membeli layanan atau mengatasi pembatasan akun.

Prompt detail dan rencana sebelum implementasi: [PLAN.md](PLAN.md).

## Yang disiapkan

- Windows Server 2022 GitHub-hosted, Git, serta installer Google Antigravity **2.28.2 x64** yang diverifikasi SHA256 dan tanda tangan publisher Google LLC.
- Shortcut **Install or open Antigravity** untuk memasang aplikasi pada akun `devrdp` setelah Anda terhubung RDP. Installer bersifat **per-user**; tidak dipasang pada akun runneradmin.
- Metadata versi, URL, hash, dan sumber manifest dipin di [`config/antigravity.json`](config/antigravity.json).
- Clone **repository GitHub publik** yang Anda tentukan ke `C:\Dev\source`.
- Akun RDP `devrdp`, **bukan administrator**, dengan NLA aktif.
- TCP 3389 dibatasi ke antarmuka Tailscale dan rentang IPv4 tailnet; aturan Remote Desktop bawaan yang lebih luas dinonaktifkan.
- Durasi **30 / 60 / 120 / 180 menit setelah setup selesai**, tanpa restart otomatis. Job maksimal 210 menit termasuk instalasi dan cleanup, jadi total menit pemakaian lebih besar daripada durasi sesi.
- Artifact opsional hanya untuk `C:\Dev\exports\*.bundle` yang Anda buat sendiri; tidak otomatis mengunggah source, password, atau profil Google/Antigravity.

Tidak membuka port router, tidak memakai IP RDP publik, dan tidak menggunakan ngrok. Alamat RDP adalah TCP, tetapi koneksi jaringan Tailscale di bawahnya bisa langsung atau melalui relay DERP, bergantung jaringan HP/runner. Tidak ada jaminan koneksi 100% pada semua jaringan.

## Batas gratis yang perlu dipahami dahulu

1. **GitHub Actions:** runner standar pada repository publik umumnya tidak dikenai biaya menit Actions. Repository privat memakai kuota akun; Windows dapat menghabiskan kuota lebih cepat. Periksa halaman billing/usage akun, jangan mengaktifkan pengeluaran berbayar. Jika kuota/hak akses tidak tersedia, workflow mungkin tidak berjalan. Tidak ada trik untuk menghindari pembatasan itu.
2. **Tailscale:** gunakan paket Personal gratis jika penggunaan Anda memenuhi syarat. Tidak perlu memilih paket trial berbayar untuk mengikuti panduan ini. Jika layanan menawarkan syarat yang berbeda pada akun Anda, periksa dahulu dan jangan lanjutkan pembelian.
3. **Google Antigravity:** login Google sendiri melalui UI/browser pada sesi RDP. Gunakan opsi gratis hanya jika tersedia untuk akun Anda; batas model/kuota dapat berlaku. Tidak perlu menambahkan password Google atau API key sebagai secret repository. Jika akun Anda hanya ditawari paket berbayar/trial kartu kredit, **berhenti**, bukan mengaktifkannya. Ketersediaan akses gratis tidak dijamin oleh workflow.
4. **Tujuan penggunaan:** gunakan untuk tugas pengembangan repository yang nyata. Durasi di bawah timeout tidak otomatis berarti semua penggunaan diperbolehkan. Ikuti [ketentuan fitur GitHub](https://docs.github.com/en/site-policy/github-terms/github-terms-for-additional-products-and-features#actions) dan [batas Actions](https://docs.github.com/en/actions/reference/limits). Jangan gunakan sebagai VPS/desktop umum, mengakali kuota, atau membuat loop sesi.

## Setup sekali dari browser HP

### 1. Siapkan Tailscale di HP

1. Instal aplikasi resmi **Tailscale** dari toko aplikasi HP dan buat/login akun.
2. Aktifkan koneksinya. Android biasanya hanya mengizinkan satu VPN aktif; VPN lain dapat berbenturan.
3. Dari browser, buka [Tailscale admin console](https://login.tailscale.com/admin/settings/keys), lalu buat **auth key**:
   - **Reusable: OFF** — satu key untuk satu run.
   - **Ephemeral: ON** — node sementara dapat dibersihkan setelah offline.
   - Gunakan masa berlaku pendek; jika tailnet memerlukan device approval, setujui node sebelum batas setup habis atau gunakan pre-approval yang sesuai kebijakan Anda.
4. Simpan key sebagai secret GitHub, **jangan** di file/chat/log. Setelah satu run memakai key sekali pakai, buat key baru untuk run berikutnya.
5. Batasi ACL/grants tailnet agar **hanya perangkat/identitas Anda** boleh mengakses node development pada TCP 3389. Firewall dalam workflow membatasi jaringan dan interface, bukan memilih satu pengguna tailnet. Pada tailnet dengan anggota lain, aturan default yang terlalu luas tetap berisiko.

### 2. Isi dua repository secrets

Di repository milik Anda: **Settings → Secrets and variables → Actions → New repository secret**.

| Secret | Isi |
| --- | --- |
| `TS_AUTHKEY` | Auth key Tailscale sementara dari langkah di atas |
| `RDP_PASSWORD` | Password acak unik 16–128 karakter: huruf besar, kecil, angka, dan simbol; tidak mengandung `devrdp` |

Tidak perlu token GitHub tambahan, API key agent atau password Google, atau kartu kredit untuk konfigurasi workflow ini. Simpan password di password manager. Jangan gunakan password akun GitHub atau password utama Anda.

> Secrets hanya melindungi dari pembacaan biasa, bukan dari kode workflow yang berbahaya. Jalankan hanya workflow pada branch yang Anda percaya dan batasi siapa yang dapat mengubah repository. Workflow ini tidak dipicu oleh PR atau push.

### 3. Jalankan workflow

File workflow harus sudah ada di **default branch** repository agar tombol manual muncul. Perubahan di branch kerja perlu ditinjau dan digabung terlebih dahulu.

1. **Actions → Windows development session → Run workflow**.
2. Pilih branch implementasi tepercaya, lalu isi:
   - `source_repository`: `pemilik/nama-repo` publik, bukan URL.
   - `source_ref`: opsional branch/tag/commit; kosong memakai default branch.
   - `task`: tujuan konkret, misalnya `Port aplikasi CLI Linux agar build dan test lulus di Windows`.
   - `minutes`: `120` atau `180`, sesuai kebutuhan.
3. Tunggu langkah **Prepare development workspace and private RDP** selesai. Instalasi bisa memakan beberapa menit.
4. Buka **Summary** run atau log setup untuk menemukan IP `100.x.x.x:3389` dan username `NAMA-HOST\devrdp`.

Repository sumber hanya di-clone. Workflow **tidak otomatis menjalankan instruksi/build dari repository sumber**, tidak mengirimkan task ke model, dan tidak membuka PR atas nama Anda.

## Connect dari RDP client / Windows App di HP

1. Pastikan Tailscale HP masih aktif dan berada di tailnet yang sama dengan runner.
2. Di aplikasi Microsoft Remote Desktop atau **Windows App yang mendukung koneksi PC pada platform HP Anda**, pilih **Add PC**.
3. **PC name/address:** IP dari summary, misalnya `100.x.x.x:3389`.
4. **Username:** nilai lengkap dari summary, `NAMA-HOST\devrdp`.
5. **Password:** nilai secret `RDP_PASSWORD` yang Anda simpan sendiri. Jangan memasukkan PIN HP atau password GitHub.
6. Sertifikat RDP bawaan dapat menimbulkan peringatan. Pastikan alamat dan node cocok dengan run serta tailnet Anda sebelum menyetujui; jangan menyetujui host yang tidak dikenal.

Untuk HP low-end, pilih resolusi rendah dan matikan audio, animasi, serta pengalihan perangkat yang tidak diperlukan. Ketersediaan fitur Add PC dan nama aplikasinya bergantung OS/versi client; tidak semua Windows App memiliki fitur yang sama.

## Menjalankan Antigravity dan porting

1. Setelah terhubung RDP, buka `START-HERE.txt` di desktop.
2. Klik dua kali **Install or open Antigravity**. Helper memasang installer user-scope sebagai `devrdp` ke `C:\Dev\Antigravity`, bukan sebagai administrator runner.
3. Installer diverifikasi ulang sebelum dijalankan; setelah selesai, Antigravity dibuka. Instalasi ini memakan sebagian waktu sesi yang Anda pilih.
4. Login Google melalui UI/browser resmi di **Windows remote**, lalu pilih opsi gratis yang tersedia untuk akun Anda. Jangan memasukkan password Google ke GitHub Secrets atau chat.
5. Pilih folder/project/workspace **`C:\Dev\source`** sesuai UI versi aplikasi, lalu masukkan instruksi porting. Isi input `task` workflow tersedia di `START-HERE.txt`; tidak otomatis dikirim ke agent.

Helper bisa dijalankan ulang melalui shortcut yang sama. Jika instalasi gagal, pesan error akan tetap terbuka; source dan RDP tidak langsung ditutup. **Kompatibilitas Antigravity di Windows Server 2022/VM/RDP belum diuji end-to-end.** Tidak ada bypass sandbox, persyaratan akun, kuota, atau persyaratan OS. Jika Google tidak mendukung lingkungan ini, workflow tidak bisa menjamin aplikasinya berjalan.

Unduhan menggunakan URL Google dari [manifest Microsoft winget-pkgs yang dipin](https://github.com/microsoft/winget-pkgs/blob/4d1a890c48e686804d40c5cbcd8edff326dff845/manifests/g/Google/Antigravity/2.28.2/Google.Antigravity.installer.yaml), bukan mirror pihak ketiga. Dokumentasi dan syarat aplikasi: [Antigravity](https://antigravity.google/) / [Docs](https://antigravity.google/docs) / [Terms](https://antigravity.google/terms). Paket bersifat proprietary; lisensi source aplikasi yang Anda port tetap harus diperiksa tersendiri.

Contoh instruksi ke agent:

> Pelajari README, lisensi, dan instruksi build repository ini. Susun rencana porting ke Windows terlebih dahulu. Cari ketergantungan Linux/POSIX dan ganti dengan implementasi lintas platform. Buat perubahan kecil, tambahkan tes, lalu jalankan build/test yang relevan. Jangan membaca kredensial, menonaktifkan keamanan sistem, menginstal layanan remote, atau melakukan push tanpa persetujuan saya.

Task porting bukan jaminan aplikasi bisa dipindahkan otomatis. Driver, API OS, GUI, hardware, dan lisensi dapat membutuhkan perubahan manual. Akun RDP non-admin mungkin tidak bisa memasang tool sistem; GitHub runner sudah memiliki banyak tool build, tetapi proyek tertentu mungkin membutuhkan workflow build khusus.

## Simpan hasil sebelum sesi berakhir

**VM dan login lokal akan hilang setelah job selesai.** Tidak ada autosave source atau kredensial. Jangan tunggu detik terakhir.

Di PowerShell Windows:

```powershell
cd C:\Dev\source
# Simpan HEAD saat ini pada branch ekspor yang bernama tetap.
git switch -C porting-work
git status
git diff
# Periksa juga file baru dan perubahan yang sudah staged:
git diff --cached
# Tambahkan HANYA file yang sudah Anda tinjau, bukan otomatis seluruh folder.
git add path/ke/file-yang-diubah
git -c user.name=Developer -c user.email=developer@example.invalid commit -m 'Port application'
git bundle create C:\Dev\exports\porting.bundle porting-work
# Akhiri lebih awal setelah bundle berhasil dibuat:
New-Item C:\Dev\end-session -ItemType File -Force
```

- Bundle hanya menyimpan **commit**, bukan file yang belum di-commit. File baru harus dipilih dan di-commit dahulu. Bundle dapat memuat riwayat source yang sudah ada.
- Jangan commit `.env`, password, API keys, auth Google/Antigravity, atau data privat. Workflow tidak dapat menjamin isi commit bebas rahasia.
- RDP ditutup, lalu bundle diunggah. Dari browser HP, buka run → **Artifacts → porting-work-…** dan unduh. Artifact disimpan **7 hari**; unduh segera. Jangan membuat release publik berisi bundle tanpa meninjau isinya.
- Source di-clone dengan riwayat lengkap untuk branch terpilih agar bundle dapat dipulihkan. Repository besar dapat memperlama setup dan memperbesar artifact; pilih repository yang relevan dan tidak terlalu besar.
- Tidak ada push otomatis. Workflow tidak memberi token write ke agent. Untuk sekarang unduh artifact, lalu pilih cara mengirim perubahan upstream secara terpisah.
- Tombol **Cancel workflow**, hard timeout, atau runner crash dapat melewatkan upload. File penanda `end-session` adalah cara yang lebih aman untuk mengakhiri normal.

Contoh pemulihan bundle pada lingkungan Git lain:

```sh
git clone -b porting-work porting.bundle recovered-port
```

## Mematikan dan membersihkan

- Buat `C:\Dev\end-session` untuk akhir normal atau tunggu durasi habis.
- Jika ada penyalahgunaan/insiden, gunakan **Cancel workflow**, cabut auth key, dan hapus node di admin console Tailscale; jangan menunggu artifact.
- Langkah cleanup `always()` menolak RDP, menghapus aturan firewall khusus, menonaktifkan akun, menghentikan proses pengguna, dan logout Tailscale. Cleanup best-effort; hard kill tidak menjamin langkah ini berjalan. GitHub membuang VM hosted setelah job.
- Periksa perangkat ephemeral di Tailscale setelah run. Logout/revoke sesi Google/Antigravity dari pengelolaan akun bila diperlukan.

## Troubleshooting

| Masalah | Yang diperiksa |
| --- | --- |
| Auth key tidak valid | Key sekali pakai sudah dipakai? Buat key baru dan perbarui secret. |
| Setup Tailscale timeout | Device approval, jaringan, kebijakan tailnet, status layanan Tailscale. |
| IP ada tapi RDP gagal | VPN Tailscale HP aktif, tailnet sama, ACL/grants mengizinkan TCP 3389, durasi job belum habis. |
| Login Windows ditolak | Gunakan `HOST\devrdp` dari summary dan password secret, bukan akun Microsoft/PIN. |
| Antigravity gagal login/kuota | Periksa kelayakan akun/wilayah dan kuota gratis Google; workflow tidak menyediakan kuota. |
| Installer/Antigravity gagal dibuka | Lihat pesan helper; periksa hash, publisher, persyaratan OS dan dukungan Server/VM/RDP. Jangan mematikan sandbox atau mengabaikan kegagalan verifikasi. |
| Tidak ada artifact | Belum membuat `C:\Dev\exports\*.bundle`, commit belum disimpan, atau run dihentikan paksa. |
| Workflow tidak muncul | File belum ada di default branch, Actions dinonaktifkan, atau hak akses kurang. |
| Job antre/gagal billing | Periksa runner availability, quota, dan kebijakan akun/repository. Jangan mengaktifkan biaya jika hanya ingin gratis. |

## Pengujian implementasi

Workflow tidak otomatis dijalankan selama pembuatan repository ini dan tidak ada secret pengguna yang digunakan. Validasi statis dicatat di [VALIDATION.md](VALIDATION.md). Uji Windows/RDP/Antigravity end-to-end tetap memerlukan run yang sengaja Anda mulai, konfigurasi tailnet, dan akses akun Google Anda sendiri.
