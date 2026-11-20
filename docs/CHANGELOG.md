# Changelog — GoldenEra

**GoldenEra v1 · 𝙴𝚟𝚘𝚛𝚎𝚣 • 6.6.118**
Redmi Note 13 5G (**gold**) · Google GKI `android15-6.6-2026-01_r34` (`e56cf6b09cca`) · 4 KB pages

Every entry is a GitHub Actions run. The build never happens on a PC; the image/zip
you flash is packed from your own stock `boot.img`.

---

## TL;DR — where things stand

| | |
|---|---|
| Kernel | 6.6.118, GKI android15-6.6, 4 KB pages, CFI_CLANG, LTO_NONE |
| Root | KernelSU `64833c00` + SUSFS `f98f0822` (in-tree) |
| `uname -r` | `6.6.118-android15-8-maybe-dirty-4k-GoldenEra-v1` |
| ABI | **9444/9444 exported symbol CRCs identical to stock build 15511674** |
| Hardware | the `-4k-golden` builds **boot on the phone** (confirmed from `uname -r`) |
| Vendor modules | untouched — the stock MTK/Xiaomi prebuilts keep running |

---

## How GoldenEra differs from stock

Everything is built from `android15-6.6-2026-01_r34` — the **same** source the stock
kernel comes from. The differences are config and packaging only.

### 1. Identical to stock (verified, not assumed)

| Item | Stock | GoldenEra | How it is verified |
|---|---|---|---|
| Source commit | `e56cf6b09cca` | same | `git describe` check before the build |
| Kernel version | 6.6.118 | same | config read back from the Image |
| Page size | 4 KB | same | `CONFIG_ARM64_4K_PAGES=y` |
| Toolchain model | LTO_NONE + CFI_CLANG | same | gate |
| Module ABI | `MODVERSIONS=y` + `TRIM_UNUSED_KSYMS=y` + same whitelist | same | gate |
| `HZ` / `NR_CPUS` / `PREEMPT_DYNAMIC` | 250 / 32 / off | same | config diff |
| **Every exported symbol's CRC** | 9444 symbols | **9444/9444 identical** | KMI gate vs the stock `kernel_aarch64_Module.symvers` (build 15511674) |
| Vendor modules (vendor_dlkm, vendor_boot, system_dlkm) | stock | **stock** | we do not rebuild them |
| `vendor_boot` (dtb, vendor ramdisk) | stock | **untouched** | boot.img repack assertion |
| boot.img header / cmdline / ramdisk / tail | — | **byte-identical**, only `kernel_size` changed | CI assertion |

### 2. What changed (config delta)

Config diff (r26 build vs the config inside your stock `boot.img`): **12 stock-only
lines, 44 ours-only** out of 7.7k.

| Option | Stock | GoldenEra | Why |
|---|---|---|---|
| `CONFIG_DEFAULT_TCP_CONG` | `"cubic"` (+`CUBIC=y`) | `"bbr"` (+`DEFAULT_BBR=y`) | congestion control |
| `CONFIG_MODULE_SIG_PROTECT` | `y` | **off** | so Google-signed `system_dlkm` modules load (we sign with our own key) |
| `CONFIG_THERMAL_WRITABLE_TRIPS` | `y` | **off** | DO-NOT-INCLUDE (no thermal bypass) |
| `CONFIG_UCLAMP_BUCKETS_COUNT` | `20` | `20` | was 5 → **bootloop**; now the stock value (ABI) |
| `CONFIG_LOCALVERSION` | `"-4k"` | `"-4k-GoldenEra-v1"` | identity only; with CRCs present the release string is not compared |

### 3. What was added

| Group | What |
|---|---|
| Scheduling / perf | schedutil default governor, EAS energy model, uclamp (+ task group), cpusets, cgroup sched |
| Memory | PSI, memcg, MGLRU (`LRU_GEN_ENABLED`), zram algorithms: lz4 / lz4hc / lzo / 842 / zstd |
| Storage | ext4, F2FS (+compression), EROFS (+zip), FBE inline crypto, UFS crypto, mq-deadline |
| Network | BBR + fq default, fq_codel, **CAKE**, WireGuard, **CIFS**, **IP_SET / NETFILTER_XT_SET** |
| Extras | exFAT, NTFS3, tmpfs xattr, gamepad HID (Xbox / PS / Switch), pstore + ramoops + console |
| Root | KernelSU + SUSFS (sus_mount, sus_kstat, sus_path, sus_map, spoof_uname, open_redirect, hide_symbols) |

### 4. Deliberately **not** done

| Request | Why not |
|---|---|
| **GPU overclock** | DO-NOT-INCLUDE contract, and the mali driver / OPP tables live in `mali_kbase_mt6833_r49.ko` (a vendor module) — not reachable from the Image |
| **Charging current / fast-charge tweaks** | `mtk_charger_framework.ko`, `hq_charger_sysfs.ko` are vendor modules; only the runtime `charge-limit 80` node exists |
| **Thermal bypass / writable trips** | banned (policy gate) |
| **Touch response tuning** | the touch driver is a vendor module |
| **fsync removal / SELinux permissive / performance governor default** | banned (machine-enforced policy gate) |
| **CASS scheduler** | not an upstream patchset; core-scheduler changes with CFI and the vendor FPSGO/GED in the mix are a real risk |

---

## Release history

| Run | Tag | What | Result |
|---|---|---|---|
| r6–r11 | `gold-r6…r11` | GKI baseline + custom build pipeline, KMI/policy gates, Drive docs | build ✅ |
| r13 | `gold-r13` | first **recovery-flashable AnyKernel3 zip** (pinned `41f04bd`) | zip ✅ |
| r14 | `gold-r14` | KernelSU + SUSFS, `UCLAMP_BUCKETS_COUNT=5` | **bootloop** ❌ |
| r17 | `gold-r17` | features only (no root), `UCLAMP_BUCKETS_COUNT=20` | **booted** ✅ |
| r22 | `gold-r22` | full: KSU + SUSFS + tweaks, uclamp 20 | build ✅ |
| r23 | `gold-r23` | parity (no root, no tweaks) — baseline proof | build ✅ |
| r25 | `gold-r25` | **GoldenEra** branding, `-4k-golden` suffix | build ✅ |
| r26 | `gold-r26` | **KMI CRC gate on** (stock symvers 15511674) | build ✅ 9444/9444 |
| r27 | `gold-r27` | + CAKE / CIFS / IP_SET (v1.1) | **booted** ✅ |
| r28 | — | SukiSU-Ultra `v3.0.0` flavor (artifact only) | build ran |
| r29 | — | `uname -r` → `-4k-GoldenEra-v1`, final naming | build ✅ 9444/9444 |
| r30 | — | SukiSU retry | ❌ policy gate aborted (empty patch manifest + `pipefail`) — fixed |
| r31 | — | **vanilla** (no root, tweaks on) | build ✅ |
| r32 | — | **BakaSU** `v4.2.0-rc3` + tweaks, publishing | build ran |
| r33 | — | SukiSU retry | ❌ KMI gate: fork-added KMI entries counted as missing — fixed |

---

## The bootloop, end to end

1. r14 flashed (`Done`) and the phone bootlooped — the kernel never reached userspace.
2. Packaging ruled out: header/ramdisk/tail byte-asserted, kernel payload sha256 matched.
3. Source ruled out: the exact GKI tag that stock runs.
4. Vermagic release string ruled out: with `MODVERSIONS=y` it is not compared.
5. The stock config was recovered (`bootimg.py config`, `IKCFG_ST`) → a 12 / 44-line
   delta → the only ABI-relevant difference was **`UCLAMP_BUCKETS_COUNT=5`**
   (stock: 20) → set to 20.
6. Bisection: r17 (features only) **booted** → pipeline fine; adding root + SUSFS
   (r22 → r27) **booted** as well.
7. Since then the CRC gate is permanent: every build compares 9444 symbol CRCs against
   stock, which is exactly what was missing when r14 was built.

## Release policy: latest = final

Exactly **one** release exists at any moment and it is always the newest build: the
publish step creates the new release, uploads the assets, and deletes every older
`gold-r*` release (with its tag). Older builds stay reachable as Actions artifacts.

## Gates every build passes

| Gate | What it checks |
|---|---|
| Pinned source | `common` HEAD == `e56cf6b09cca` (stock's) |
| Config read-back | config recovered from the built Image (4K, CFI, LTO_NONE, MODVERSIONS, `MODULE_SIG_PROTECT=off`) |
| **KMI CRC parity** | 9444 symbols must match the stock build 15511674, or the build **fails** |
| Policy gate | DO-NOT-INCLUDE contract: thermal / OPP / DVFS / governor / display / fsync / SELinux permissive |
| Packaging | boot.img header byte-identical (only `kernel_size`), zip structure + permissions |

## Credits

- **Star-caorui** — rebuilt gold's vendor modules from source and compared them with
  stock byte by byte (`verify/results.md`, 360 modules). That work is where the stock
  GKI build **15511674** `kernel_aarch64_Module.symvers` comes from, which powers our
  KMI CRC gate.
- **WildKernels/GKI_KernelSU_SUSFS** — reference for the SukiSU/SUSFS pairing.

## Naming format

- Release title / NOTES / docs: **`GoldenEra v1 · 𝙴𝚟𝚘𝚛𝚎𝚣 • 6.6.118`**
- `uname -r`: `6.6.118-android15-8-maybe-dirty-4k-GoldenEra-v1`
- `uname -r` cannot contain a space or `·`: the release string is a filesystem token
  (`/lib/modules/<release>`) and part of module vermagic. Allowed: `A-Za-z0-9 . - _`.
