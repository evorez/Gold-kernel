# Research notes — why this build is shaped the way it is

Everything below is either verified from the device/ROM or from upstream sources.
It is written down because each item is a "compiles fine, then the phone does not
boot / has no WiFi" class of mistake.

## 1. What gold actually runs

```
ro.build.version.release      16 (Android 16)
ro.build.version.incremental  1791896677
uname -r                      6.6.118-android15-8-ge56cf6b09cca-ab15511674-4k
```

- GKI `android15-6.6`, KMI generation **android15-8**, **4 KB** pages.
- Build `15511674` ↔ tag `android15-6.6-2026-01_r34` ↔ commit
  `e56cf6b09cca2151bcee244b3d334fb68685ff57` (kernel 6.6.118).
- Community device trees confirm the stock kernel image in the boot partition is
  Google's GKI `Image.gz` for that build, used unmodified.
- `TARGET_FORCE_PREBUILT_KERNEL := true` in the LineageOS device tree for gold —
  even custom ROMs ship Google's GKI kernel here, they only rebuild the vendor
  modules, linked against that build's KMI.

## 2. Boot partition shape (LineageOS device tree, `BoardConfig.mk`)

```
BOARD_BOOTIMAGE_PARTITION_SIZE      := 67108864      # 64 MiB
BOARD_VENDOR_BOOTIMAGE_PARTITION_SIZE := 67108864
BOARD_BOOT_HEADER_VERSION           := 4
BOARD_KERNEL_PAGESIZE               := 4096
BOARD_KERNEL_IMAGE_NAME             := Image.gz
BOARD_KERNEL_CMDLINE                := bootopt=64S3,32N2,64N2
BOARD_KERNEL_BASE                   := 0x40078000
BOARD_MOVE_RECOVERY_RESOURCES_TO_VENDOR_BOOT := true
BOARD_INCLUDE_RECOVERY_RAMDISK_IN_VENDOR_BOOT := true
```

Consequences:

- **No `init_boot` partition.** The ramdisk lives inside `vendor_boot`
  (`init_boot.cpio` is gold's fallback ramdisk). That is why rooting guides for
  this device patch `vendor_boot`, not `boot`.
- `boot` carries **kernel only** → a custom kernel is one `boot.img`, and nothing
  else has to be rebuilt or re-signed.
- Header v3/v4 use a fixed 4096-byte page for the header/kernel layout, and no
  kernel/ramdisk load addresses are stored, so `--base`/`--*_offset` do not matter
  here (they are kept in the device tree for the vendor_boot image).

## 3. Config parity rules (the bootloop traps)

Ground truth: the GKI config of the same tag (6.6.118). The rules are enforced by
`scripts/fix-gki-config.sh` and re-checked from the built `Image` by
`scripts/verify-build.sh`.

| Option | Stock | Ours | Why |
|---|---|---|---|
| `CONFIG_LTO_NONE` | `y` | `y` (never `LTO_CLANG_*`) | LTO changes codegen → symbol CRCs change → vendor modules rejected |
| `CONFIG_CFI_CLANG` | `y` | `y` | same reason; also CFI metadata is part of the ABI contract |
| `CONFIG_MODVERSIONS` | `y` | `y` | with CRCs present the kernel skips the *release string* in vermagic; without it every prebuilt module fails with "Invalid module format" |
| `CONFIG_MODULE_SIG_PROTECT` | `y` | **off** | stock trusts Google's signing key; a self-built kernel trusts only its own Kleaf key, so Google-signed `system_dlkm` modules exporting protected symbols (rfkill, bluetooth, mii, usbnet…) are refused → dead WiFi/BT |
| `CONFIG_MODULE_SIG_FORCE` | *not set* | *not set* | good news: signature enforcement cannot block the stock modules |
| `CONFIG_ARM64_4K_PAGES` | `y` | `y` | page-size mismatch with the vendor partitions does not boot |
| `CONFIG_KPROBES`, `KALLSYMS_ALL` | `y` | `y` | KernelSU runtime symbol resolution |
| `android/abi_gki_protected_exports_*` | present | removed | susfs4ksu README step 11 for GKI android14+: a self-built kernel cannot reproduce Google's protected set |
| `CONFIG_LOCALVERSION` | `"-4k"` | `"-4k-gold"` | only the first vermagic token (release string) changes, and it is skipped when CRCs are present — so this is safe and makes a flashed build identifiable |

The KMI safety net is `scripts/check-kmi.sh`: symbol **removal** is always fatal;
with a reference `Module.symvers` (stock GKI build) any **CRC change** is fatal
too, unless `crc_stub=true` is explicitly chosen.

## 4. Root solutions

- **SukiSU Ultra**, branch `builtin` — implements `KSU_SUSFS*` itself, so SUSFS
  needs no KSU-side patch. Pinned `6c5603f0` (newest revision whose feature
  subsystem is self-consistent). Its tip is *not* always buildable: commits
  referencing `kernel_umount_feature_set` / `KSU_FEATURE_WEBVIEW_ZYGOTE_UMOUNT`
  fail ~20 min into the build. A ~1 s static preflight in `apply-root.sh` catches
  that class of breakage up front.
- **KernelSU-Next v3.x** — works, but cannot take the susfs4ksu KSU-side patch:
  `10_enable_susfs_for_ksu.patch` deletes `hook/lsm_hook.o`,
  `hook/syscall_hook_manager.o` and `infra/symbol_resolver.o` from
  `kernel/Kbuild`, which are exactly the files v3.x is built on. Requesting
  `ksu-next` + `use_susfs=true` is therefore redirected to SukiSU.
- **SUSFS** — `gitlab.com/simonpunk/susfs4ksu`, branch `gki-android15-6.6`.
  Kernel side = copy `kernel_patches/fs/*`, `kernel_patches/include/linux/*`,
  apply `50_add_susfs_in_gki-android15-6.6.patch`. The userspace (module) part is
  separate and installed from the manager app after boot.
- KSU/SUSFS exports are added to `android/abi_gki_aarch64`, so Kleaf's KMI strict
  mode does not reject the build and `TRIM_UNUSED_KSYMS` does not drop them.
  Stock symbols are untouched → vendor module CRCs are unaffected.

## 5. Packaging

- `mkbootimg` (vendored AOSP `scripts/mkbootimg.py`) builds a header-v4 image with
  the kernel only, 4096-byte pages, `cmdline bootopt=64S3,32N2,64N2`,
  `os_version 16.0.0`, `os_patch_level 2026-01`. If `stock_boot_url` is given,
  cmdline/os_version/patch level are copied from that image's header instead.
- AnyKernel3 (`osm0sis/AnyKernel3`) zip is the root-friendly alternative: it
  unpacks the *on-device* `boot.img`, swaps the kernel and repacks, so whatever
  the ROM put in the header/dtb stays intact.
- No AVB footer and no GKI boot signature are added: verification will fail on a
  locked/verified device, which is expected — flash with verification disabled
  (see FLASH.md).

## 6. Uncertainty / what has not been proven yet

- **No on-device boot test yet.** The first flash of any build from this repo is
  the real acceptance test; keep a stock `boot.img` handy.
- The CRC gate is only as good as the reference `Module.symvers`. Without one,
  only removals are checked; identical CRCs are *expected* (same tag, same
  config, same pinned toolchain) but not *proven* until a reference is supplied.
- MediaTek's ABL behaviour around a modified `boot` with a stale AVB hash is
  device-specific; the standard workaround (`--disable-verity
  --disable-verification flash vbmeta`) is documented, not yet verified on gold
  by this repo.
- Prior art for the general approach (different device, same kernel family):
  `WildKernels/GKI_KernelSU_SUSFS`, `liu56646/Mi15-Droidspaces-Kernel`,
  `thaomaitam/Build-Kernel-GKI2.0-Susfs`. Device facts:
  `Dhterech/android_device_xiaomi_gold` (LineageOS 23.2 device tree).
