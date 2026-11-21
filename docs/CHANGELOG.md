# Changelog — GoldenEra

**HAVOC · 𝙴𝚟𝚘𝚛𝚎𝚣 • 6.6.118**
Redmi Note 13 5G (**gold**) · Google GKI `android15-6.6-2026-01_r34` (`e56cf6b09cca`) · 4 KB pages

Every build is a GitHub Actions run; nothing is built on a PC, and the `boot.img` you
flash is packed from your own stock image.

---

## Version

- Kernel **6.6.118**, GKI `android15-6.6-2026-01_r34`, 4 KB pages, CFI_CLANG, LTO_NONE
- `uname -r`: `6.6.118-android15-8-maybe-dirty-4k-HAVOC` (release string changed for this build; module matching is by CRC)
- Release title: `HAVOC · 𝙴𝚟𝚘𝚛𝚎𝚣 • 6.6.118`
- ABI: **9444/9444** exported symbol CRCs identical to the stock build (GKI 15511674)
- Vendor modules: untouched stock MTK/Xiaomi prebuilts
- Root: **BakaSU `v4.2.0-rc3` builtin** (`CONFIG_KSU=y`), one kernel, no flavors

---

## Same as stock (verified, not assumed)

- Source commit `e56cf6b09cca` — the exact tag stock runs, checked before every build
- Kernel version 6.6.118, 4 KB pages — read back out of the built Image
- Toolchain model `LTO_NONE` + `CFI_CLANG`
- Module ABI `MODVERSIONS=y` + `TRIM_UNUSED_KSYMS=y` + the same unused-symbol whitelist
- `HZ=250`, `NR_CPUS=32`, `PREEMPT_DYNAMIC` off
- Every exported symbol's CRC — 9444/9444 against the stock symvers
- `vendor_dlkm` / `vendor_boot` / `system_dlkm` — not rebuilt, not replaced
- `boot.img` header, cmdline, ramdisk, tail — byte-identical, only `kernel_size` changes

## Changed

- `CONFIG_DEFAULT_TCP_CONG` `cubic` → `bbr` (+ `DEFAULT_BBR=y`)
- `CONFIG_MODULE_SIG_PROTECT` `y` → off (so Google-signed `system_dlkm` modules load)
- `CONFIG_THERMAL_WRITABLE_TRIPS` `y` → off (DO-NOT-INCLUDE contract)
- `CONFIG_LOCALVERSION` `-4k` → `-4k-HAVOC` (identity only; with CRCs present
  the loader compares vermagic flags, not the release string)
- `CONFIG_UCLAMP_BUCKETS_COUNT` stays **20** — it was 5 in r14 and that bootlooped
- Config delta against stock: 12 stock-only lines, 44 ours-only, out of ~7.7k

## Added

- Scheduling/perf: schedutil default governor, EAS energy model, uclamp (+ task group),
  cpusets, cgroup sched
- Memory: PSI, memcg, MGLRU, zram algorithms lz4 / lz4hc / lzo / 842 / zstd
- Storage: ext4, F2FS (+compression), EROFS (+zip), FBE inline crypto, UFS crypto,
  **mq-deadline**
- Network: BBR + fq default, fq_codel, **CAKE**, WireGuard, **CIFS**,
  **IP_SET / NETFILTER_XT_SET**
- Extras: exFAT, NTFS3, tmpfs xattr, gamepad HID (Xbox / PS / Switch), pstore + ramoops
- Root (KernelSU flavor): **KernelSU `64833c00` + SUSFS `f98f0822`** — sus_mount,
  sus_kstat, sus_path, sus_map, spoof_uname, open_redirect, hide_symbols
- Root: **BakaSU `v4.2.0-rc3`** — builtin, tracepoint hook, no kernel source patches
- Runtime helper `gold-profiles.sh`: `gaming` / `sustained` / `balanced` /
  `charge-limit 80` / `restore`

## Not included (on purpose)

- **GPU overclock** — mali driver + OPP tables live in `mali_kbase_mt6833_r49.ko`
- **Charging current / fast charge** — `mtk_charger_framework.ko`, `hq_charger_sysfs.ko`
  are vendor modules (only the runtime `charge-limit 80` node exists)
- **Thermal bypass / writable trips** — banned, policy gate enforces it
- **Touch response tuning** — touch driver is a vendor module
- **fsync removal / SELinux permissive / performance governor default** — banned
- **CASS scheduler** — not an upstream patchset; risky with CFI + vendor FPSGO/GED

---

## Build history

- r6–r11 — GKI baseline + build pipeline, KMI/policy gates, docs — build ok
- r13 — first recovery-flashable AnyKernel3 zip (pinned `41f04bd`) — zip ok
- r14 — KernelSU + SUSFS, `UCLAMP_BUCKETS_COUNT=5` — **bootloop**
- r17 — features only, uclamp 20 — **booted** (proves the pipeline)
- r22 — KSU + SUSFS + tweaks, uclamp 20 — build ok
- r23 — parity build (no root, no tweaks) — build ok
- r25 — GoldenEra branding, `-4k-golden` suffix — build ok
- r26 — KMI CRC gate enabled (stock symvers 15511674) — 9444/9444
- r27 — CAKE / CIFS / IP_SET added — **booted**
- r28 — SukiSU flavor — failed in Kleaf (`kmi_symbol_list_strict_mode`)
- r29 — `uname -r` → `-4k-GoldenEra-v1` — 9444/9444
- r30 — SukiSU retry — failed: policy gate aborted on an empty patch manifest
- r31 — vanilla build — ok
- r32 — BakaSU `v4.2.0-rc3` — failed: its Kbuild takes the version code from git
  inside the build, which the sandbox cannot do
- r33 — SukiSU retry — failed: KMI gate counted the fork's own KMI-list entries as
  missing
- r34 — **SukiSU ok** — 9444/9444, 4 fork-private symbols exempted
- r35 — **BakaSU ok** — 9444/9444
- r36 — kernelsu + SUSFS publish build — 9444/9444
- r37 / r38 / r39 — BakaSU + vanilla + kernelsu published side by side — all 9444/9444

## The bootloop (r14), end to end

- Flashed fine, then bootlooped — the kernel never reached userspace
- Packaging ruled out: header/ramdisk/tail byte-asserted, payload sha256 matched
- Source ruled out: the exact GKI tag stock runs
- Vermagic release string ruled out: with `MODVERSIONS=y` it is not compared
- Stock config recovered from the stock `boot.img` (`IKCFG_ST`) → 12/44-line delta →
  the only ABI-relevant difference was `UCLAMP_BUCKETS_COUNT=5` (stock 20) → set to 20
- Bisection: r17 (features only) booted, then root + SUSFS booted as well
- Since then the CRC gate is permanent — exactly what was missing in r14

## Gates every build passes

- Pinned source: `common` HEAD == `e56cf6b09cca`
- Config read-back from the built Image: 4K, CFI_CLANG, LTO_NONE, MODVERSIONS,
  `MODULE_SIG_PROTECT=off`, `CONFIG_KSU` for root flavors
- **KMI CRC parity**: all 9444 shared symbols must match stock, and no symbol stock
  exports may disappear — otherwise the build fails (fork-private additions are allowed)
- Policy gate: thermal / OPP / DVFS / governor / display / fsync / SELinux permissive
- Packaging: boot.img header byte-identical, zip structure and permissions checked

## Packaging: what is inside the zip

The recovery zip is the pinned AnyKernel3 tree plus our `Image`, trimmed to what a
boot-only flash actually reads: `.github/`, `LICENSE`, `README.md`, the empty
`patch/`, `ramdisk/` and `modules/` placeholders (we run `do.systemless=0`,
`do.modules=0`) and the two tools `ak3-core.sh` never calls (`fec`, `magiskpolicy`).
`busybox`, `magiskboot`, `httools_static`, `lptools_static` and
`snapshotupdater_static` stay — `write_boot()` and the no-ramdisk `flash_boot()` path
use them. After trimming, the build re-reads `ak3-core.sh`, extracts every tool name it
mentions and fails if any of them is missing from the zip.

The kernel itself is **not** trimmed: WireGuard, exFAT, NTFS3, gamepad HID, CIFS,
ipset are all still compiled in. Only the package got smaller, not the feature set.

## BBR: v1, not v3

The image ships **BBR v1** (mainline `tcp_bbr`, default via `DEFAULT_BBR=y`) with `fq`,
`fq_codel` and CAKE. BBRv3 is not in mainline: it lives in Google's `google/bbr` `v3`
branch and has to be rebased onto 6.6 by hand, touching `tcp_input/output.c` - that is
exported-symbol CRC territory, the exact class of change that bootlooped r14. Its
documented wins are on Google-scale WAN paths; for a phone the honest expectation is
no measurable FPS change, because games use UDP. If it is ever added it will be an
opt-in build with a documented CRC exception, not the default.

## Release policy

- One release (`builds`), always the newest content; every other release is deleted
- Three builds live inside it, told apart by prefix, all from the same source:
  `HAVOC-bakasu-*` (`-4k-HAVOC`, BakaSU builtin), `GoldenEraV1-bakasu-*`
  (`-4k-GoldenEra-v1`, BakaSU builtin), `GoldenEraV1-vanilla-*` (same release string,
  no root)
- Each prefix has both shapes: `*-boot.img` (fastboot) and `*.zip` (recovery), plus
  `Image-*`, `SHA256SUMS`, `NOTES`, `FEATURES`, `gold-profiles.sh`, `perf-check.sh`
- A build only ever replaces its own prefix, so the three never overwrite each other
- The body is regenerated from the attached files, so it lists what is really there
- Artifacts stay labelled **not boot-tested** until a device run is recorded

## Credits

- **Star-caorui** — rebuilt gold's 360 vendor modules and compared them with stock;
  that work is where the stock GKI 15511674 `Module.symvers` (our CRC reference) comes from
- **WildKernels/GKI_KernelSU_SUSFS** — reference for the SukiSU/SUSFS pairing

## Naming

- Title / NOTES / docs: `HAVOC · 𝙴𝚟𝚘𝚛𝚎𝚣 • 6.6.118`
- `uname -r`: `6.6.118-android15-8-maybe-dirty-4k-HAVOC`
- `uname -r` cannot hold a space or `·` — it is a filesystem token
  (`/lib/modules/<release>`) and part of the module vermagic; `A-Za-z0-9 . - _` only
