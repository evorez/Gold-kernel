# Gold-kernel

Custom-kernel workspace for the **Xiaomi Redmi Note 13 5G** (codename **gold**), driven from GitHub Actions (no PC required — only a phone with a browser).

## Device / current kernel (from the phone)

- `ro.build.version.release` = 16 (Android 16)
- `ro.build.version.incremental` = 1791896677
- `uname -r` = `6.6.118-android15-8-ge56cf6b09cca-ab15511674-4k`
  → Google GKI, `android15-6.6` branch, commit `e56cf6b09cca`, build `15511674`, **4 KB** pages

The old Xiaomi `gold-s-oss` source is Android 13 / kernel 5.10 — **not** compatible with this device as-is. The baseline build uses Google's canonical `kernel/common` GKI source for the exact running build.

## Workflow: `Build GOLD GKI baseline (android15-6.6, 4 KB)`

`.github/workflows/build-gold-gki.yml` — manual trigger (`workflow_dispatch`). It:

1. syncs `kernel/manifest` (`common-android15-6.6-2026-01`, release tag tried first),
2. **verifies** that `common` is exactly `e56cf6b09cca` / version `6.6.118` (fails loudly otherwise),
3. builds `//common:kernel_aarch64_dist` (aarch64, 4 KB, unmodified config),
4. uploads `gold-gki-baseline-15511674-NOT-FLASHABLE` (raw `Image`/modules — **not** a boot.img, **not** for flashing).

## Safety

- Nothing is flashed by CI. The artifact is a raw kernel, not a flashable image.
- Before any on-device test: confirm the ROM, its vendor modules (`modules.load` / KMI symbols), and the `boot.img`/`vbmeta` repack + recovery path. Keep a way back to stock (fastboot + stock images) before flashing anything.
