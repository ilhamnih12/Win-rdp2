# Validasi implementasi

Tanggal: 31 Oktober 2026.

## Berhasil dijalankan di sandbox Linux

```sh
python -m pip install -r tests/requirements.txt
python -m unittest discover -s tests -v
git diff --check
```

Pada sesi implementasi, dependensi Python dipasang di cache di luar repository dan unittest dijalankan dengan PYTHONPATH yang menunjuk ke cache itu. Perintah di atas adalah cara reproduksi pada lingkungan Python biasa.

**Hasil: 12 test lulus; pemeriksaan whitespace `git diff --check` lulus.**

Cakupan:

- YAML terbaca; hanya trigger manual dan token read-only.
- Actions dipin ke SHA commit; checkout tanpa kredensial persisten.
- Pilihan durasi terbatas dan deadline sesi eksplisit.
- Referensi skrip workflow tersedia.
- Secret hanya diberikan pada langkah setup; auth key lewat file sementara, bukan argument bernilai secret.
- Guardrail statis untuk akun non-admin, NLA, publisher MSI, dan firewall Tailscale.
- Cleanup dan upload best-effort `always()`, hanya file bundle yang sengaja dibuat.
- Tidak ada eksekusi otomatis build/source atau push dari skrip setup.
- Metadata Antigravity dipin; checksum/publisher diperiksa sebelum staging dan instalasi per-user; instalasi npm/login Codex dihapus.
- Keempat file PowerShell lolos pemeriksaan grammar tree-sitter-powershell (bukan parser resmi PowerShell).
- Uji Git nyata pada repository temporer: clone, branch porting, commit file berubah dan baru, buat bundle, verifikasi bundle, clone ulang, dan bandingkan isi. Diuji dari default branch maupun kondisi detached HEAD. File yang tidak di-commit tidak ikut bundle.

## Perbaikan dari hasil pengujian

Rancangan awal menggunakan shallow clone dan bundle ref HEAD. Percobaan pemulihan gagal dengan perintah clone yang direncanakan. Implementasi akhir memakai riwayat lengkap branch terpilih dan ref bernama `porting-work`; uji pemulihan kemudian lulus.

## Belum teruji / keterbatasan

- Tidak ada job GitHub Actions yang dipicu, secrets yang diminta di chat, atau koneksi tailnet yang dibuat selama implementasi.
- Windows PowerShell/pwsh runtime tidak tersedia di sandbox Linux ini. Pemeriksaan grammar tidak membuktikan cmdlet Windows atau service/firewall bekerja pada runner sesungguhnya.
- actionlint belum berhasil dijalankan: unduhan binary release dialihkan ke host release-assets yang tidak dapat diakses dari sandbox. Alternatif installer Python juga membutuhkan unduhan yang sama. Pemeriksaan YAML/unittest bukan pengganti penuh actionlint.
- Installer Tailscale, signature Windows, NLA, koneksi RDP dari HP, instalasi/login/kuota Antigravity, cleanup saat cancel, dan upload artifact belum diuji end-to-end.
- Paket `Google.Antigravity` versi `2.28.2` x64 diperiksa melalui GitHub API pada manifest Microsoft winget-pkgs. URL Google, SHA256, scope user, dan commit manifest dipin di `config/antigravity.json`. Binary installer belum dapat diunduh/dijalankan dari sandbox ini; pemeriksaan SHA256/Authenticode dilakukan saat run di Windows.
- Harga/syarat gratis Google saat ini belum diverifikasi langsung dari situs resmi karena batas akses jaringan sandbox. Tidak ada klaim bahwa semua akun mendapat akses gratis atau bahwa Windows Server/VM/RDP didukung.
- Tidak ada klaim bahwa koneksi pasti berhasil, pemakaian pasti tanpa biaya untuk semua akun, atau akses model diberikan gratis.

## Checklist uji pertama oleh pemilik repository

1. Review workflow di branch ini, lalu gabungkan ke default branch jika disetujui.
2. Siapkan Tailscale Personal yang sesuai syarat, key sementara sekali pakai/ephemeral, secret password kuat, dan ACL/grants privat.
3. Pastikan akun GitHub dapat menggunakan runner standar tanpa mengaktifkan pengeluaran berbayar; pastikan akun Google memenuhi syarat opsi gratis Antigravity sebelum memulai.
4. Jalankan sesi **30 menit** dahulu dengan repository publik kecil dan tugas pengembangan nyata.
5. Periksa job summary, hubungkan Tailscale HP dan RDP, lalu klik **Install or open Antigravity**, pastikan helper memasang aplikasi sebagai devrdp, dan login Google sendiri. Jika harus membayar atau memakai trial kartu kredit, berhenti.
6. Buat perubahan dummy, commit, ekspor bundle, lalu akhiri menggunakan file `C:\Dev\end-session`.
7. Unduh artifact, pulihkan bundle, periksa isi perubahan, pastikan RDP terputus dan node Tailscale dibersihkan.
8. Baru gunakan sesi 120/180 menit untuk porting yang sebenarnya. Review lisensi serta keamanan source sebelum menjalankan kode.
