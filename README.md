# HAVOC — custom kernel for the Redmi Note 13 5G (gold)

**HAVOC · 𝙴𝚟𝚘𝚛𝚎𝚣 • 6.6.118**

Custom-kernel workspace for the **Xiaomi Redmi Note 13 5G** (codename **gold**), driven from GitHub Actions (no PC required — only a phone with a browser).

- Audit, 101-item checklist: [`docs/AUDIT.md`](docs/AUDIT.md)
- Benchmark procedure: [`docs/BENCH.md`](docs/BENCH.md)
- Root (BakaSU builtin): [`docs/ROOT.md`](docs/ROOT.md)
- Release history / bisection ladder: [`docs/CHANGELOG.md`](docs/CHANGELOG.md)
- Bootloop diagnosis: [`docs/BOOTLOOP.md`](docs/BOOTLOOP.md)
- Flash guide: [`docs/FLASH.md`](docs/FLASH.md)

Two workflows, in the order they should be used:

| Workflow | Purpose | Output |
|---|---|---|
| **Build GOLD GKI baseline** (`build-gold-gki.yml`) | Unmodified GKI at the exact build the phone runs — a reference point | raw `Image` + modules, **not** flashable |
| **Build GOLD custom kernel** (`build-gold-custom.yml`) | The actual custom kernel: root + SUSFS + feature set | raw `Image`/`Image.gz`, AnyKernel3 zip |

## Device / current kernel (from the phone)

- `ro.build.version.release` = 16 (Android 16)
- `ro.build.version.incremental` = 1791896677
- `uname -r` = `6.6.118-android15-8-ge56cf6b09cca-ab15511674-4k`
  → Google GKI, `android15-6.6` branch, commit `e56cf6b09cca`, build `15511674`, **4 KB** pages

The old Xiaomi `gold-s-oss` source is Android 13 / kernel 5.10 — **not** compatible with this device as-is. Both workflows build Google's canonical `kernel/common` GKI source for the exact running build.

## Custom kernel — what you get

- **Root built into the kernel**: KernelSU (default, the fork SUSFS patches are maintained against) or KernelSU-Next — no Magisk-style patching needed.
- **SUSFS** root hiding: the upstream pair (susfs4ksu + its `10_enable_susfs_for_ksu.patch`), both ends pinned to a coherent commit pair.
- **Feature set** (`configs/gold-features.config`, one reviewable list): schedutil +
  EAS + uclamp + cpusets, PSI + memcg + MGLRU, zram compression backends (LZ4 /
  LZ4-RLE / lzo-rle), ext4/F2FS/EROFS + inline encryption, mq-deadline, stock
  thermal + cpuidle/suspend stats, WireGuard, exFAT, NTFS3, HID/gamepads,
  pstore/ramoops, BBR + fq. All built in (`=y`) — no `.ko` to push.
- **Runtime profiles** (`tools/gold-profiles.sh`, shipped in the artifact):
  `balanced` / `gaming` / `sustained` / `charge-limit` — reversible, never a fixed
  max clock or a fixed performance governor.
- **[docs/FEATURES.md](docs/FEATURES.md)**: every requested item → where it actually
  lives (Image config vs MediaTek vendor module vs runtime script) and how the
  "do not include" list is machine-checked.
- Kernel name ends in `-4k-HAVOC`, so `uname -r` tells you a custom build is running.
- Guard rails: stock config parity, in-image config verification, and a **KMI gate** so the prebuilt MediaTek vendor modules still load.

### Run it

Actions → **Build GOLD custom kernel (android15-6.6, 4 KB, root + tweaks)** → *Run workflow*.
Defaults are the sensible ones (`kernelsu` + SUSFS + tweaks). A build takes ~40–70 min.
`dev_build=true` adds ftrace/perf tracing (debug only, bigger Image).

Artifacts: `boot.img` (when you pass `boot_img_url`: your own stock image with only the
kernel swapped), `AnyKernel3-*.zip` (**recovery-flashable**: TWRP/SHRP Install, or the
KernelFlasher app), raw `Image`/`Image.gz`, `SHA256SUMS.txt`.

Actions artifacts expire after 14 days — set **`publish_release: true`** to also attach
the same files to a GitHub **Release** (`releases/tag/gold-r<run>`), which is the copy
to keep and the easiest one to download on the phone.

### Status

**Permanent download:** [`releases/tag/gold-r11`](https://github.com/evorez/Gold-kernel/releases/tag/gold-r11)
— **kernel only**: raw `Image`/`Image.gz`, `AnyKernel3-*.zip`, `SHA256SUMS.txt`,
`NOTES.txt`, `gold-profiles.sh`, `FEATURES.md`. No `boot.img` is built or shipped
(see below). Published by run `44579469714` with `publish_release=true`.

Last full CI build: **run 44579469714 — green** (`main`, 2026-11-19, 24 min end to
end, ~11 min of that is Bazel). Artifact: `GoldenEra-kernelsu-susfstrue-11`.

- The pipeline verifies its own output: source pinned to `e56cf6b09cca`, the config
  read back **out of the built Image** satisfied all **48 required** feature options
  (and all 20 optional ones), the policy gate passed, and the KMI list is intact.
- Policy gate warnings were exactly the vendored SUSFS hunks (`mm/memory.c`,
  `block/ioprio.c`) — reported, not silently allowed.
- **Not flashed on hardware yet.** The first flash is the acceptance test — keep
  your ROM's stock `boot.img` for rollback.
- Two optional inputs make the first flash safer: `stock_symvers_url` (hard CRC
  comparison against the stock build) and `boot_img_url` (your ROM's boot.img → the
  build returns a ready-to-flash `boot.img` with only the kernel swapped, dtb and
  header untouched).

### Read before flashing

- **[docs/FLASH.md](docs/FLASH.md)** — step-by-step (backup, flash, rollback, dm-verity, troubleshooting). **Read this first.**
- **[docs/BUILD.md](docs/BUILD.md)** — every workflow input, what each step does, how to read failure annotations.
- **[docs/FEATURES.md](docs/FEATURES.md)** — the feature map: what is in the Image, what is vendor-side, what is refused (and which gate enforces it).
- **[docs/RESEARCH.md](docs/RESEARCH.md)** — the device facts and config rules behind the design.

> Custom kernel + unlocked bootloader = your responsibility. Keep a stock `boot.img`
> for your ROM; it is the only thing standing between a bad flash and a bootloop.
> Nothing in this repo has been boot-tested on hardware yet — the first flash is the
> real acceptance test.

## Safety

- Nothing is flashed by CI. Artifacts are built, not installed.
- gold's `boot` partition holds **only the kernel** (header v4, no ramdisk, no
  `init_boot` partition; the ramdisk lives in `vendor_boot`), so swapping the kernel
  touches nothing else — `vendor_boot`/`vbmeta`/`dtbo` are left alone.
- **This repo ships the kernel, not a `boot.img`.** Packing a boot image means
  guessing header/cmdline and (on gold) the dtb; a wrong guess is a non-booting
  phone. The AnyKernel3 zip does the opposite: it splits *your* existing boot and
  swaps only the kernel, so your stock header/dtb/ramdisk stay byte-identical.
- Keep a way back to stock (fastboot + your ROM's `boot.img`, and `vbmeta` if AVB
  complains) before flashing anything.
