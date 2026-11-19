# Building the custom kernel (GitHub Actions only — no PC needed)

Workflow: **Actions → "Build GOLD custom kernel (android15-6.6, 4 KB, root + tweaks)" → Run workflow**

One build takes roughly **22 minutes measured** on a stock `ubuntu-latest` runner
(run 44540769002: repo sync ~9 min, config + root ~2 min, Bazel 11 min, verify +
KMI + package <1 min). Budget up to 60 min if the runner is slow.

## Inputs

| Input | Default | What it does |
|---|---|---|
| `root_flavor` | `kernelsu` | `kernelsu` (tiann/KernelSU — required for SUSFS), `ksu-next` (KernelSU-Next v3.4.x), `none` (no root) |
| `use_susfs` | `true` | SUSFS root hiding: susfs4ksu kernel patch **and** its `10_enable_susfs_for_ksu.patch`. Redirected to `kernelsu` when `ksu-next` is chosen (Next only has SUSFS as an LKM). |
| `tweaks` | `true` | The feature set of `configs/gold-features.config` (schedutil/EAS/uclamp, PSI, memcg, MGLRU, zram algos, ext4/F2FS/EROFS + inline crypto, mq-deadline, pstore, WireGuard, exFAT, NTFS3, HID, BBR+fq) — all built in (`=y`) |
| `publish_release` | `false` | Publishes the build files as a GitHub **Release** (`gold-r<run>`) instead of only a 14-day Actions artifact. Useful when the build has to survive longer than the artifact retention — phone-friendly download, no login for a public repo. |
| `dev_build` | `false` | Adds `configs/gold-devbuild.config` (ftrace, dynamic ftrace, kprobe events, perf). Debug only: bigger Image, extra symbols. |
| `ksu_ref` | *(empty)* | Pin the root repo. Empty = the verified pin (`64833c00` for KernelSU, `v3.4.2` for Next). |
| `susfs_ref` | `f98f0822` | susfs4ksu commit on branch `gki-android15-6.6`. Its commit message names KernelSU `64833c00` as the synced upstream — the two pins must stay a coherent pair. |
| `crc_stub` | `false` | Patch `check_version()` to skip genksyms CRC comparison. Use **only** if vendor modules complain at boot. |
| `extra_config` | *(empty)* | Extra defconfig lines, one per row, e.g. `CONFIG_IP_NF_TARGET_TTL=y` |
| `stock_boot_url` | *(empty)* | Direct link to your ROM's `boot.img`. Header/cmdline/os_version are copied from it. |
| `stock_symvers_url` | *(empty)* | Direct link to a reference `Module.symvers` (stock GKI build) → enables the **hard CRC gate**. |
| `formats` | `bootimg,anykernel,image` | Which artifacts to package. |

## What the job does

1. **Verify the source.** Syncs `kernel/manifest` at `common-android15-6.6-2026-01`,
   pins `common` to tag `android15-6.6-2026-01_r34`, and **fails** unless HEAD is
   exactly `e56cf6b09cca2151bcee244b3d334fb68685ff57` / version `6.6.118` — the
   build the phone is actually running.
2. **Stock parity** (`scripts/fix-gki-config.sh`) — `MODULE_SIG_PROTECT` off,
   LTO stays `NONE`, CFI stays on, `MODVERSIONS=y`, KPROBES/KALLSYMS on, protected
   export lists removed, `check_defconfig` gate disabled, kernel name suffixed
   `-4k-gold`.
3. **Feature set** (`scripts/apply-tweaks.sh` + `configs/gold-features.config`,
   `configs/gold-devbuild.config` when `dev_build=true`) — a fragment of `REQ`/`OPT`
   lines is applied to `gki_defconfig`; built-in only, no `.ko` to push. Per-item
   mapping (Image vs MediaTek vendor module vs runtime script): `docs/FEATURES.md`.
4. **Root + SUSFS** (`scripts/apply-root.sh`) — clones KernelSU / KernelSU-Next,
   wires `drivers/kernelsu`, runs a 1-second static coherence preflight (catches
   upstream breakage before the 20-minute compile), applies **both** susfs4ksu
   patches (`50_add_susfs_in_gki-android15-6.6.patch` in the kernel tree,
   `KernelSU/10_enable_susfs_for_ksu.patch` in the root tree), and registers any
   newly exported symbols in the KMI list.
5. **Build** — `tools/bazel run //common:kernel_aarch64_dist`.
6. **Verify** (`scripts/verify-build.sh`) — reads the config **back out of the
   Image** (`IKCONFIG`) and asserts 4 KB pages, `LTO_NONE`, `CFI_CLANG`,
   `MODVERSIONS`, `MODULE_SIG_PROTECT` off, `KSU`/`KSU_SUSFS` when requested, and
   every `REQ` line of the feature fragment (`OPT` ones only warn, so an option the
   kernel does not offer is visible on the run page instead of failing it); asserts
   the version string is `6.6.118-...-android15-8`.
6b. **Policy gate** (`scripts/check-policy.sh`) — enforces the do-not-include list:
   no changes under `drivers/{thermal,gpu,cpufreq,devfreq,opp,clk}`, `block`, `mm`,
   `net`, `kernel/{sched,power}`, `arch/arm64/boot` (unless the file comes from a
   vendored SUSFS/root patch, which is reported as a warning); no added line that
   mentions `fsync`, thermal bypass or permissive SELinux; in the Image, SELinux on,
   no performance/userspace-default governor, no writable thermal trips.
7. **KMI gate** (`scripts/check-kmi.sh`) — every symbol of
   `android/abi_gki_aarch64` must still be exported, and (when a reference
   `Module.symvers` is supplied) every shared symbol must have an identical CRC.
   This is the check that prevents "compiles fine, black screen on boot".
8. **Package** (`scripts/package.sh`) — `boot.img` (header v4, kernel only),
   `AnyKernel3-*.zip`, raw `Image`/`Image.gz`, `NOTES.txt`, `SHA256SUMS.txt`, plus
   `gold-profiles.sh` and `FEATURES.md` so the runtime profiles travel with the build.
   With `publish_release=true` the same files are attached to a GitHub Release, which
   is the copy to keep (Actions artifacts expire after 14 days).

## Artifacts

| File | Use |
|---|---|
| `boot.img` | `fastboot flash boot boot.img` — primary |
| `AnyKernel3-*.zip` | rooted phone, KernelFlasher app (keeps your dtb/header) |
| `Image-*.gz` / `Image-*` | manual repacking |
| `SHA256SUMS.txt` | integrity check before flashing |

Artifacts are **not** flashable by CI on their own: they need an unlocked
bootloader, and you must keep a stock `boot.img` for rollback. See
[FLASH.md](FLASH.md).

## Known-good baseline

| | |
|---|---|
| Last green run | `44571462688` (`main`, 2026-11-19, 24 min) — full feature set **+ published release** |
| Release | `gold-r10` — `boot.img`, AnyKernel3 zip, raw images, `SHA256SUMS.txt`, profiles, `FEATURES.md` |
| Inputs | defaults: `kernelsu` + SUSFS + tweaks, `dev_build=false`, no stock boot.img |
| Artifact | `gold-custom-kernelsu-susfstrue-9` (~63 MB) |
| Root pin | KernelSU `64833c00` |
| SUSFS pin | `f98f0822` (`gki-android15-6.6`) |
| Feature gates | in-Image config: 48 `REQ` + 20 `OPT` all present; policy gate passed (2 vendored-patch warnings); KMI list intact |

## When a build fails

Every risky step echoes its interesting lines as `::error::` **annotations**
(the run's summary page shows them even when raw logs are not accessible):

- `::error::sync: ...` — repo sync / tag pin problem.
- `::error::KSU_REF ... is not buildable` — upstream root repo regression;
  pin a good commit with `ksu_ref`.
- `::error::SUSFS_REF ... not in branch` — susfs pin is wrong for the branch.
- `::error::bazel: ...` / `::error::tail: ...` — compile errors.
- `::error::CONFIG_X must be =y` — a Kconfig option was silently dropped
  (typo, or blocked by a dependency).
- `::error::N KMI symbol(s) are missing` — source pin or config change broke the
  ABI; do not flash such a build.

## Why not just `--lto=thin` to make it faster?

Because LTO changes codegen → changes symbol CRCs → the prebuilt MediaTek
modules refuse to load → black screen. Stock is `LTO_NONE` + `CFI_CLANG`; the
build keeps exactly that. Same reason `MODVERSIONS` stays on.
