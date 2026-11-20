# Changelog — GoldenEra

**GoldenEra v1 · 𝙴𝚟𝚘𝚛𝚎𝚣 • 6.6.118**
Redmi Note 13 5G (**gold**) · Google GKI `android15-6.6-2026-01_r34` (`e56cf6b09cca`) · 4 KB pages

Har entry ek GitHub Actions run hai. Build **kabhi** local PC par nahi hota; device
par flash aapke apne stock `boot.img` se banaye gaye image/zip se hota hai.

---

## TL;DR — abhi kya hai

| | |
|---|---|
| Kernel | 6.6.118, GKI android15-6.6, 4 KB, CFI_CLANG, LTO_NONE |
| Root | KernelSU `64833c00` + SUSFS `f98f0822` (in-tree) |
| `uname -r` | `6.6.118-android15-8-maybe-dirty-4k-GoldenEra-v1` (naye builds) / `…-4k-golden` (r25–r27) |
| ABI | **9444/9444 exported symbol CRCs stock build 15511674 ke bilkul barabar** |
| Hardware | `-4k-golden` builds **boot ho chuke hain** (user ne `uname -r` se confirm kiya) |
| Vendor modules | chhue nahi — stock MTK/Xiaomi prebuilts hi chalte hain |

---

## Stock se farq — poori list

Sab kuch `android15-6.6-2026-01_r34` source se banta hai, **wahi** source jisse aapka
stock kernel bana hai. Farq sirf config aur packaging me hai.

### 1. Jo bilkul same hai (verified, guess nahi)

| Cheez | Stock | GoldenEra | Kaise verify hua |
|---|---|---|---|
| Source commit | `e56cf6b09cca` | same | build ke pehle `git describe` check |
| Kernel version | 6.6.118 | same | Image ka config read-back |
| Page size | 4 KB | same | `CONFIG_ARM64_4K_PAGES=y` |
| Toolchain model | LTO_NONE + CFI_CLANG | same | gate |
| Module ABI | `MODVERSIONS=y` + `TRIM_UNUSED_KSYMS=y` + wahi whitelist | same | gate |
| `HZ` / `NR_CPUS` / `PREEMPT_DYNAMIC` | 250 / 32 / off | same | config diff |
| **Har exported symbol ka CRC** | 9444 symbols | **9444/9444 identical** | KMI gate (stock `kernel_aarch64_Module.symvers`, build 15511674) |
| Vendor modules (vendor_dlkm, vendor_boot, system_dlkm) | stock | **stock hi** | hum unhe rebuild nahi karte |
| `vendor_boot` (dtb, vendor ramdisk) | stock | **chhua nahi** | boot.img repack assertion |
| boot.img header / cmdline / ramdisk / tail | — | **byte-identical**, sirf `kernel_size` badla | CI assertion |

### 2. Jo badla (config delta)

Config diff (r26 build vs aapki stock `boot.img` ka config): **12 lines only-stock,
44 lines only-ours** — 7.7k lines me itna hi.

| Option | Stock | GoldenEra | Kyun |
|---|---|---|---|
| `CONFIG_DEFAULT_TCP_CONG` | `"cubic"` (+`CUBIC=y`) | `"bbr"` (+`DEFAULT_BBR=y`) | congestion control |
| `CONFIG_MODULE_SIG_PROTECT` | `y` | **off** | Google-signed `system_dlkm` modules load ho sakein (humari apni signing key hai) |
| `CONFIG_THERMAL_WRITABLE_TRIPS` | `y` | **off** | DO-NOT-INCLUDE (thermal bypass ban) |
| `CONFIG_UCLAMP_BUCKETS_COUNT` | `20` | `20` | pehle 5 tha → **bootloop**; ab stock jaisa (ABI) |
| `CONFIG_LOCALVERSION` | `"-4k"` | `"-4k-GoldenEra-v1"` | sirf pehchaan; CRCs hone par vermagic ka release hissa compare nahi hota |

### 3. Jo add kiya

| Group | Kya |
|---|---|
| Sched / perf | schedutil default governor, EAS energy model, uclamp (+task group), cpusets, cgroup sched |
| Memory | PSI, memcg, MGLRU (`LRU_GEN_ENABLED`), zram algos: lz4 / lz4hc / lzo / 842 / zstd |
| Storage | ext4, F2FS (+compression), EROFS (+zip), FBE inline crypto, UFS crypto, mq-deadline |
| Net | BBR + fq default, fq_codel, **CAKE**, WireGuard, **CIFS**, **IP_SET / NETFILTER_XT_SET** |
| Extras | exFAT, NTFS3, tmpfs xattr, gamepad HID (Xbox / PS / Switch), pstore + ramoops + console |
| Root | KernelSU + SUSFS (sus_mount, sus_kstat, sus_path, sus_map, spoof_uname, open_redirect, hide_symbols) |

### 4. Jo jaan-boojh kar **nahi** kiya

| Request | Kyun nahi |
|---|---|
| **GPU overclock** | DO-NOT-INCLUDE contract + mali driver/OPP tables `mali_kbase_mt6833_r49.ko` (vendor module) me hain — Image se OC possible nahi |
| **Charging current / fast-charge tweak** | `mtk_charger_framework.ko`, `hq_charger_sysfs.ko` vendor modules me; sirf `charge-limit 80` runtime node |
| **Thermal bypass / writable trips** | banned |
| **Touch response tuning** | touch driver vendor module me |
| **fsync removal / SELinux permissive / performance governor default** | banned (policy gate machine-enforced) |
| **CASS scheduler** | koi upstream patchset nahi; core scheduler + CFI + vendor FPSGO/GED ke saath risk |

---

## Release history

| Run | Tag | Kya | Natija |
|---|---|---|---|
| r6–r11 | `gold-r6…r11` | GKI baseline + custom build pipeline, KMI/policy gates, Drive docs | build ✅ |
| r13 | `gold-r13` | pehla **recovery-flashable AnyKernel3 zip** (pinned `41f04bd`) | zip ✅ |
| r14 | `gold-r14` | KernelSU + SUSFS, `UCLAMP_BUCKETS_COUNT=5` | **bootloop** ❌ |
| r17 | `gold-r17` | features only (root nahi), `UCLAMP_BUCKETS_COUNT=20` | **booted** ✅ |
| r22 | `gold-r22` | full: KSU + SUSFS + tweaks, uclamp 20 | build ✅ |
| r23 | `gold-r23` | parity (na root na tweaks) — baseline proof | build ✅ |
| r25 | `gold-r25` | **GoldenEra** branding + `-4k-golden` suffix | build ✅ |
| r26 | `gold-r26` | **KMI CRC gate on** (stock symvers 15511674) | build ✅ 9444/9444 |
| r27 | `gold-r27` | + CAKE / CIFS / IP_SET (v1.1) | **booted** ✅ |
| r28 | — | SukiSU-Ultra `v3.0.0` flavor (artifact only) | build chal raha |
| r29 | — | `uname -r` → `-4k-GoldenEra-v1`, naam final | build chal raha |

---

## Bootloop ka pura record

1. r14 flash hua (`Done`), phone bootloop — kernel userspace tak nahi pahuncha.
2. Packaging rule out: header/ramdisk/tail byte-asserted, kernel payload sha256 match.
3. Source rule out: exact GKI tag jo stock me hai.
4. Vermagic release string rule out: `MODVERSIONS=y` hone par release hissa compare nahi hota.
5. Stock config nikaala (`bootimg.py config`, `IKCFG_ST`) → 12 / 44 line delta →
   **akela ABI-relevant farq `UCLAMP_BUCKETS_COUNT=5`** (stock 20) → 20 kiya.
6. Bisection: r17 (features only) **boot hua** → pipeline sahi; phir root + SUSFS add
   karke r22 → r27 **boot hua**.
7. Uske baad CRC gate permanent: ab har build 9444 symbols ka CRC stock se compare
   karta hai (jo r14 ke waqt nahi hota tha).

## Verification kaise hota hai (har build)

| Gate | Kya check karta hai |
|---|---|
| Pinned source | `common` HEAD == `e56cf6b09cca` (stock ka) |
| Config read-back | Image ke andar se config nikaal ke check (4K, CFI, LTO_NONE, MODVERSIONS, `MODULE_SIG_PROTECT=off`) |
| **KMI CRC parity** | 9444 symbols ka CRC stock build 15511674 ke barabar, warna build **fail** |
| Policy gate | DO-NOT-INCLUDE contract: thermal/OPP/DVFS/governor/display/fsync/SELinux permissive |
| Packaging | boot.img header byte-identical (sirf `kernel_size`), zip structure + permissions |

## Credits

- **Star-caorui** — gold ke vendor modules source se rebuild + stock se byte-level
  comparison (`verify/results.md`, 360 modules). Usi kaam se stock GKI build
  **15511674** ka `kernel_aarch64_Module.symvers` mila, jisse KMI CRC gate chalta hai.
- **WildKernels/GKI_KernelSU_SUSFS** — SukiSU/SUSFS pairing ka reference.

## Naam ka format

- Release title / NOTES / docs: **`GoldenEra v1 · 𝙴𝚟𝚘𝚛𝚎𝚣 • 6.6.118`**
- `uname -r`: `6.6.118-android15-8-maybe-dirty-4k-GoldenEra-v1`
- `uname -r` me space ya `·` **nahi** aa sakte — release string filesystem token hai
  (`/lib/modules/<release>`) aur module vermagic ka hissa; allowed `A-Za-z0-9 . - _`.
