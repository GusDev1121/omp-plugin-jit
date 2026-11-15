# Benchmark JIT di open.mp — sebelum vs sesudah

Tanggal: 2026-11-16 · Dijalankan oleh: Claude Code (otomatis, tanpa pemain terhubung)

## Ringkasan

- **Kode Pawn murni (CPU-bound) jadi 7–31× lebih cepat**: aritmetika integer 14×, akses array 31×, pemanggilan fungsi 7×.
- **Kode yang didominasi native hanya 1,1–2,6× lebih cepat**: `format`/`strfind` 1,1×, panggilan native ringan 2,6×, math float 2,4×. JIT mempercepat kode Pawn di sekitar native, tapi tidak native-nya sendiri.
- **Startup gamemode ~0,8 detik lebih lambat** dengan JIT, karena ada biaya compile satu kali untuk `GM.amx` (57 MB, ±2,28 juta cell kode).
- **Callback pemuatan data MySQL ~2× lebih cepat** (75 ms → 38 ms dari network start sampai semua data termuat).
- **CPU saat idle (0 pemain) tidak berbeda** (±1,1–1,2% satu core di kedua mode). Beban server kosong didominasi loop internal open.mp, bukan Pawn.

## Lingkungan

| | |
|---|---|
| CPU | AMD Ryzen 7 7840HS (8C/16T) |
| RAM | 15,3 GB |
| OS | Windows 11 Pro 10.0.26300 |
| Server | open.mp 1.5.8.3079 (Windows, 32-bit) |
| Compiler | Pawn 3.10.11 (qawno) |
| JIT | 2.4.1 + perbaikan open.mp di repo ini (Release, MSVC 14.51) |
| YSI | 5.09.0982 |

## 1. Benchmark sintetis (`benchmarks/omp_cpu.pwn`)

Gamemode khusus dijalankan di salinan server terpisah, hanya dengan komponen open.mp bawaan, tanpa plugin lain. Compile: `pawncc -d0 -O1`. Ada 3 run per mode, dijalankan bergantian; yang dipakai adalah median. Checksum setiap tes identik di semua run, jadi JIT menghasilkan hasil perhitungan yang sama dengan interpreter.

| Tes | Tanpa JIT (ms) | Dengan JIT (ms) | Median tanpa → dengan | Speedup |
|---|---|---|---|---|
| `int_arith` — 50 juta iterasi LCG | 953 / 946 / 952 | 70 / 67 / 68 | 952 → 68 | **14,0×** |
| `array_sort` — bubble sort 4000 elemen | 740 / 740 / 743 | 24 / 25 / 24 | 740 → 24 | **30,8×** |
| `func_calls` — `Fib(30)` rekursif | 74 / 73 / 72 | 9 / 10 / 11 | 73 → 10 | **7,3×** |
| `native_calls` — 5 juta `strlen` | 214 / 182 / 179 | 70 / 71 / 70 | 182 → 70 | **2,6×** |
| `float_math` — 10 juta `floatsqroot`/`floatabs`/aritmetika float | 1006 / 1001 / 994 | 413 / 421 / 413 | 1001 → 413 | **2,4×** |
| `string_format` — 300 ribu `format` + `strlen` + `strfind` | 165 / 161 / 160 | 143 / 144 / 138 | 161 → 143 | **1,1×** |

## 2. Gamemode asli (`GM.amx`, YSI + MySQL + Streamer)

Server dijalankan dengan `config.json` user; satu-satunya yang diubah adalah ada atau tidaknya `"jit"` di `legacy_plugins`. Ada 3 run per mode. Waktu dihitung dalam ms sejak proses `omp-server.exe` dijalankan, berdasarkan timestamp baris output. CPU idle diukur selama 60 detik, dimulai 5 detik setelah semua data termuat.

| Mode | Run | Codegen YSI (ms) | MySQL connect | Network start | Semua data termuat | CPU idle (% 1 core) |
|---|---|---|---|---|---|---|
| JIT | 1 | 474 | 1688 | 1705 | 1743 | 1,19 |
| JIT | 2 | 467 | 1660 | 1677 | 1713 | 1,06 |
| JIT | 3 | 462 | 1675 | 1691 | 1729 | 1,22 |
| Tanpa JIT | 1 | 475 | 859 | 876 | 951 | 1,11 |
| Tanpa JIT | 2 | 477 | 838 | 856 | 929 | 1,11 |
| Tanpa JIT | 3 | 472 | 830 | 847 | 922 | 1,27 |

Median:

| Metrik | Tanpa JIT | Dengan JIT | Selisih |
|---|---|---|---|
| Semua data termuat | 929 ms | 1729 ms | +800 ms (biaya compile JIT, satu kali) |
| Network start → semua data termuat (callback MySQL) | 75 ms | 38 ms | **~2× lebih cepat** |
| CPU idle, 0 pemain | 1,11% | 1,19% | tidak signifikan |

Codegen YSI tetap ±470 ms di kedua mode, karena berjalan di interpreter (`OnJITCompile`) sebelum JIT meng-compile. Tidak ada `[jit] Run time error` maupun `Jump to invalid address` di semua run.

## Batasan

- **Tanpa pemain.** Belum ada pengukuran di bawah beban nyata (pemain, sync, command). Di server ramai, keuntungannya bergantung pada seberapa banyak waktu CPU dihabiskan di kode Pawn dibanding di native dan plugin. Untuk mengukurnya, aktifkan `/bench` di gamemode (`System/Benchmark.pwn`) saat server terisi pemain.
- **Satu mesin, 3 run.** Variasi antar-run kecil (lihat kolom per-run), tapi hasil di mesin lain bisa berbeda.
- **Server dihentikan paksa.** Perintah `exit` lewat stdin tidak diproses console open.mp, jadi setiap run gamemode dihentikan paksa dan `OnGameModeExit` tidak dijalankan. Tidak ada pemain terhubung; `config.json` dikembalikan ke aslinya, dicek dengan md5.

## Cara mengulang

```sh
# 1. Sintetis: compile lalu jalankan di folder server terpisah
pawncc benchmarks/omp_cpu.pwn -i<qawno>/include -d0 -O1 -o<server>/gamemodes/bench.amx
#    config.json: "main_scripts": ["bench 1"], "legacy_plugins": ["jit"]  (atau [] tanpa JIT)
node benchmarks/run_omp_server.js <server> "\[BENCH\] done" 500 300000 "BENCH"

# 2. Gamemode asli: ukur startup + CPU idle 60 detik
CPU_WINDOW_MS=60000 node benchmarks/run_omp_server.js <server> "Dynamic Billiard Tables" 5000 120000 "MySQL connection|Legacy Network|Billiard|Done in"
```
