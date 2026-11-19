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
- `boot` carries **kernel only** → swapping the kernel needs no other image
  rebuilt or re-signed (`vendor_boot` holds the ramdisk and stays as it is).
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
| `android/abi_gki_protected_exports_*` | present | **kept** | susfs4ksu says to delete them, but they are a declared input of `//common:kernel_aarch64` — deleting fails the build (CI run 44515323372). The gate they feed is `MODULE_SIG_PROTECT`, which is off, so they are inert |
| `CONFIG_LOCALVERSION` | `"-4k"` | `"-4k-golden"` | only the first vermagic token (release string) changes, and it is skipped when CRCs are present — so this is safe and makes a flashed build identifiable |

The KMI safety net is `scripts/check-kmi.sh`: symbol **removal** is always fatal;
with a reference `Module.symvers` (stock GKI build) any **CRC change** is fatal
too, unless `crc_stub=true` is explicitly chosen.

## 4. Root solutions

- **KernelSU (tiann/KernelSU) + SUSFS** — the pairing upstream maintains:
  susfs4ksu ships two patches, and both are applied here:
  `50_add_susfs_in_gki-android15-6.6.patch` (kernel tree: `fs/susfs.c`,
  `include/linux/susfs{,_def}.h`, hooks) and
  `KernelSU/10_enable_susfs_for_ksu.patch` (root tree: supercall dispatch +
  the `KSU_SUSFS*` Kconfig symbols). Pins are a coherent pair: KernelSU
  `64833c00` (named as the synced upstream in the SUSFS branch tip's commit
  message) and SUSFS `f98f0822`. KernelSU at that revision defines `ksu_install_su_fd()`,
  which the `50_` patch's `exec.c` hunk calls — an older tree fails to link.
- **SukiSU Ultra `builtin`** was tried first and does not build with a pinned
  SUSFS: its `kernel/supercall/dispatch.c` carries SUSFS dispatch code that
  expects the *matching* susfs4ksu headers (`susfs_set_sid`,
  `susfs_get_sid_from_name`, `CMD_SUSFS_*`, ...). With the older SUSFS pinned,
  CI run 44519162981 died with a wall of `use of undeclared identifier
  'CMD_SUSFS_...'` / `call to undeclared function 'susfs_...'`. Its tip is also
  not buildable at every revision, so the pair is fragile.
- **KernelSU-Next v3.4.x** — works as a root solution, but SUSFS exists only as
  a separate LKM (`kernel/susfs` → `susfs_guard_lkm.ko`, loaded by `ksud`), so it
  cannot be linked into the Image. `ksu-next` + `use_susfs` is redirected to
  `kernelsu`.
- KSU/SUSFS exports are added to `android/abi_gki_aarch64`, so Kleaf's KMI strict
  mode does not reject the build and `TRIM_UNUSED_KSYMS` does not drop them.
  Stock symbols are untouched → vendor module CRCs are unaffected.

## 5. Packaging

- **This project does not pack a `boot.img`.** The deliverable is the kernel:
  `Image`, `Image.gz`, plus an AnyKernel3 zip. Reason: a boot image needs a
  header/cmdline *and*, on gold, a dtb; a wrong guess produces a non-booting phone
  and there is no way to verify the guess without the ROM's own `boot.img`.
- AnyKernel3 (`osm0sis/AnyKernel3`) zip does the safe version of the same job: it
  unpacks the *on-device* `boot.img`, swaps only the kernel and repacks, so whatever
  the ROM put in the header/dtb/ramdisk stays byte-identical. `vendor_boot` is
  untouched.
- If the user wants a fastboot-flashable image they build it themselves from
  `Image.gz` + their own stock boot.img as the reference (`docs/FLASH.md`, 2B).
- No AVB footer and no GKI boot signature are involved: verification will fail on a
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


## Bahar ka cross-check: Star-caorui ka module verification

gold ke vendor modules ko source se rebuild karke stock se compare karne wala
kaam: [Star-caorui/android_kernel_xiaomi_gold](https://github.com/Star-caorui/android_kernel_xiaomi_gold)
(branch `OS3.0.5.0.VNQMIXM`, `verify/`). Uske `verify/results.md` ke mutabik 360
stock vendor modules me se 332 build-id ke alawa byte-identical hain, 15 me
build-id + stock ke unpublished kernel ke BTF/line-number ka farq hai, 10 me
code/data identical hai par `.modinfo`/`__versions`/`__kcrctab` thoda alag, aur
3 (`binder_gki`, `mtk_charger_framework`, `mtk_pep50`) me code ka farq hai.

Humare liye iska seedha faayda: usi kaam me stock GKI build **15511674** ka
`kernel_aarch64_Module.symvers` milta hai
(`https://ci.android.com/builds/submitted/15511674/kernel_aarch64/latest/raw/kernel_aarch64_Module.symvers`),
jo ab build workflow me `stock_symvers_url` ka default hai - isse KMI gate har
shared symbol ka **CRC** compare karta hai, sirf symbol ka naam nahi.
