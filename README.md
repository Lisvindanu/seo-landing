# seo-landing

Sebuah situs yang menulis ulang dirinya sendiri setiap hari.

Sekali sehari, cron memanggil Claude untuk menyusun ulang satu komponen Astro — halaman visual abstrak yang sepenuhnya baru. Kalau hasilnya gagal di-build, situs otomatis kembali ke versi terakhir yang diketahui baik. Kalau berhasil, edisi itu dibekukan sebagai arsip permanen dan versi barunya naik ke produksi.

Live di **[seo.project-n.site](https://seo.project-n.site)**. Sudah berjalan selama 61 edisi.

## Kenapa dibangun

Saya ingin tahu apakah sebuah situs produksi bisa dibiarkan menulis ulang dirinya tanpa pengawasan, tanpa akhirnya rusak. Jawabannya bergantung sepenuhnya pada satu hal: apa yang terjadi ketika AI menghasilkan keluaran yang salah. Ini bukan proyek tentang generasi konten — ini tentang pagar pengamannya.

## Bagaimana loop-nya bekerja

```
snapshot  →  Claude menulis ulang  →  build  →  ┬─ berhasil → arsipkan, promosikan, deploy
                                                └─ gagal    → pulihkan versi baik terakhir
```

Yang membuatnya bertahan:

- **Rollback menuju versi baik terakhir, bukan versi sebelumnya.** Kalau keluaran AI rusak, memulihkan "file kemarin" tidak cukup bila kemarin juga sudah rusak. Skrip menyimpan `last-good.astro` terpisah, dan hanya mempromosikannya *setelah* build berhasil.
- **Lock berbasis `flock`.** Cron yang menyala saat proses manual masih berjalan akan keluar diam-diam, bukan saling menimpa.
- **Sinkronisasi sebelum menulis.** `git pull --rebase --autostash` dijalankan lebih dulu, dan hanya bila working tree bersih.
- **Arsip yang gagal ikut dibatalkan.** Bila build gagal setelah edisi diarsipkan, entri arsip dan manifestnya ikut dibuang, sehingga tidak ada edisi hantu.

## Batasan yang dipegang

Situs ini dibangun dengan target performa dan SEO yang ketat, dan batasan itu ikut ditegakkan ke dalam prompt regenerasi:

- **Nol JavaScript eksternal.** Tidak ada framework runtime, tidak ada library pihak ketiga di browser.
- **CSS di-inline seluruhnya** (`inlineStylesheets: 'always'`) — tidak ada render-blocking stylesheet.
- **HTML dikompresi** saat build, sitemap dibuat otomatis.

Setiap edisi harus tetap memenuhi batasan itu, atau tidak akan lolos build.

## Menjalankan secara lokal

```bash
npm install
npm run dev
```

Untuk memicu satu siklus regenerasi (butuh CLI `claude` terpasang dan sudah login):

```bash
./scripts/regen.sh
```

Pasang di cron untuk menjalankannya harian:

```
0 4 * * * /path/ke/seo-landing/scripts/regen.sh >> /path/ke/seo-landing/.regen/cron.log 2>&1
```

Setel `DEPLOY_CMD` ke perintah publikasi kamu (`rsync`, `wrangler pages deploy dist`, dan sejenisnya). Bila tidak diisi, skrip berhenti setelah `dist/` siap.

## Struktur

```
src/
├── components/DailyShowcase.astro   satu-satunya file yang ditulis ulang AI
├── editions/                        61 edisi beku, immutable
├── data/editions.json               manifest arsip
└── pages/                           index, /edisi, /arsip
scripts/
├── regen.sh                         loop regenerasi + rollback
├── regen-prompt.md                  instruksi dan batasan untuk AI
└── archive-edition.mjs              membekukan edisi hari ini
```

## Lisensi

MIT — lihat [LICENSE](LICENSE).
