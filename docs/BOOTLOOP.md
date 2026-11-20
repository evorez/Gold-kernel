# Bootloop diagnosis (after r14)

The r14 recovery zip flashed to `boot_b` — device check `gold` passed, the log said
`Installing GoldenEra 6.6.118-...-4k-golden … Done` — and the phone then
**bootlooped**. Flashing the stock boot back fixed it. So the flash itself was fine:
the kernel never reached userspace.

## What is already ruled out

1. **Packaging** — the boot.img/zip structure is byte-asserted in CI: the header
   differs only in `kernel_size`, ramdisk is 0, tail is 0 (the dtb lives in
   `vendor_boot` and is untouched), and the kernel payload's sha256 equals `Image.gz`.
2. **Source sha** — built from `android15-6.6-2026-01_r34` (`e56cf6b09cca…`, 6.6.118),
   the same commit that is in stock's `uname -r`.
3. **The vermagic release string** — with `CONFIG_MODVERSIONS=y` the kernel does *not*
   compare the release string, only the flags. So the `-4k-HAVOC` suffix cannot
   by itself make the vendor modules refuse to load.

## The stock config (recovered from the user's own boot.img)

`scripts/bootimg.py config` pulls the real config out of the stock `boot.img`'s
`IKCFG_ST` block (`check-stock-images` and `config-diff` workflows). Opening up the
7.7k-line diff left only **12 stock-only lines and 44 ours-only lines** — the same
source, we only added our own features.

What matters for ABI / module loading:

| Option | stock | ours | verdict |
|---|---|---|---|
| `CONFIG_MODVERSIONS` | `y` | `y` | ✅ same |
| `CONFIG_TRIM_UNUSED_KSYMS` | `y` | `y` | ✅ same |
| `CONFIG_UNUSED_KSYMS_WHITELIST` | `"abi_symbollist.raw"` | same | ✅ same |
| `CONFIG_HZ` | `250` | `250` | ✅ same |
| `CONFIG_NR_CPUS` | `32` | `32` | ✅ same |
| `CONFIG_PREEMPT_DYNAMIC` | off | off | ✅ same |
| `CONFIG_MODULE_SIG_PROTECT` | `y` | off | ⚠️ deliberate (so Google-signed modules load) |
| `CONFIG_UCLAMP_BUCKETS_COUNT` | `20` | **`5`** | ❌ **ABI change — fixed** |
| `CONFIG_THERMAL_WRITABLE_TRIPS` | `y` | off | deliberate (DO NOT INCLUDE) |

`CONFIG_UCLAMP_BUCKETS_COUNT=5` changes the size of the uclamp arrays inside
`struct rq`; the vendor scheduler modules (FPSGO/GED/PPM/PBM) were built against the
stock layout. It is `20` now — the stock value.

## The bisection (record)

Three variants, all from the user's own stock `boot.img` + `vendor_boot`, differing
only in features/root:

| Variant | root | SUSFS | tweaks | What it tests |
|---|---|---|---|---|
| **P** parity | none | — | off | build pipeline + packaging + stock-ABI config |
| **R** root only | KernelSU | on | off | the KSU + SUSFS patches |
| **T** tweaks only | none | — | on | the whole feature set (uclamp now 20) |

Result: **T booted** (r17) → the pipeline and the feature set are fine;
**R booted** (r22 → r27) → KernelSU + SUSFS are fine too. Rollback during any test:

```bash
fastboot flash boot <your stock boot.img>
# or KernelFlasher → Restore
```
