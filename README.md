# Gold-kernel

Custom-kernel workspace for the **Xiaomi Redmi Note 13 5G** (codename **gold**), driven from GitHub Actions (no PC required — only a phone with a browser).

Two workflows, in the order they should be used:

| Workflow | Purpose | Output |
|---|---|---|
| **Build GOLD GKI baseline** (`build-gold-gki.yml`) | Unmodified GKI at the exact build the phone runs — a reference point | raw `Image` + modules, **not** flashable |
| **Build GOLD custom kernel** (`build-gold-custom.yml`) | The actual custom kernel: root + SUSFS + tweaks | `boot.img`, AnyKernel3 zip, raw `Image` |

## Device / current kernel (from the phone)

- `ro.build.version.release` = 16 (Android 16)
- `ro.build.version.incremental` = 1791896677
- `uname -r` = `6.6.118-android15-8-ge56cf6b09cca-ab15511674-4k`
  → Google GKI, `android15-6.6` branch, commit `e56cf6b09cca`, build `15511674`, **4 KB** pages

The old Xiaomi `gold-s-oss` source is Android 13 / kernel 5.10 — **not** compatible with this device as-is. Both workflows build Google's canonical `kernel/common` GKI source for the exact running build.

## Custom kernel — kya milta hai

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
- Kernel name ends in `-4k-gold`, so `uname -r` tells you a custom build is running.
- Guard rails: stock config parity, in-image config verification, and a **KMI gate** so the prebuilt MediaTek vendor modules still load.

### Run it

Actions → **Build GOLD custom kernel (android15-6.6, 4 KB, root + tweaks)** → *Run workflow*.
Defaults are the sensible ones (`kernelsu` + SUSFS + tweaks). A build takes ~40–70 min.
`dev_build=true` adds ftrace/perf tracing (debug only, bigger Image).

Artifacts: `boot.img` (fastboot), `AnyKernel3-*.zip` (rooted phone), raw `Image`/`Image.gz`, `SHA256SUMS.txt`.

### Status

Last full CI build: **run 44540769002 — green** (`main`, 2026-11-19, 22 min end to end,
~11 min of that is Bazel). Artifact: `gold-custom-kernelsu-susfstrue-8`
(`boot.img` + AnyKernel3 zip + raw images + `SHA256SUMS.txt`).

- Kernel side is verified by the pipeline itself: source pinned to `e56cf6b09cca`,
  config read back **out of the built Image**, KMI list intact.
- **Not flashed on hardware yet.** The first flash is the acceptance test — keep
  your ROM's stock `boot.img`.
- Two optional inputs make the first flash safer: `stock_boot_url` (copies
  cmdline/os_version from your own boot.img) and `stock_symvers_url` (turns the
  KMI gate into a hard CRC comparison against the stock build).

### Read before flashing

- **[docs/FLASH.md](docs/FLASH.md)** — Hinglish step-by-step (backup, flash, rollback, dm-verity, troubleshooting). **Read this first.**
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
  `init_boot` partition; the ramdisk lives in `vendor_boot`), so a custom kernel is
  a single `boot.img` flash — `vendor_boot`/`vbmeta`/`dtbo` are left alone.
- Keep a way back to stock (fastboot + your ROM's `boot.img`, and `vbmeta` if AVB
  complains) before flashing anything.
