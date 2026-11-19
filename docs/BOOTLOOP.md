# Bootloop diagnosis (r14 ke baad)

r14 recovery zip `boot_b` par flash hua — device check `gold` pass, log me
`Installing gold-custom 6.6.118-android15-8-maybe-dirty-4k-gold … Done` bhi aaya —
par phone **bootloop** kar gaya aur stock boot wapas flash karne par thik hua.
Matlab: flash theek tha, kernel userspace tak nahi pahuncha.

## Kya already rule out ho gaya

1. **Packaging** — boot.img/zip ka structure CI me byte-assert hota hai: header
   sirf `kernel_size` me badla, ramdisk 0, tail 0 (dtb `vendor_boot` me hai aur
   waisa hi rehta hai), kernel payload ka sha256 `Image.gz` ke barabar.
2. **Source sha** — build `android15-6.6-2026-01_r34` (`e56cf6b09cca…`, 6.6.118)
   se, jo stock ke `uname -r` me bhi hai.
3. **Vermagic ka release string** — `CONFIG_MODVERSIONS=y` hone par kernel
   release string ko match *nahi* karta, sirf flags. Isliye `-4k-gold` suffix
   apne aap me vendor modules reject nahi kara sakta.

## Stock config (aapki boot.img se nikaala gaya)

`scripts/bootimg.py config` stock `boot.img` ke `IKCFG_ST` block se asli config
nikaalta hai (`check-stock-images`, `config-diff` workflows). 7.7k lines ka diff
kholne par sirf **12 lines stock-only, 44 lines ours-only** nikli — yaani source
ek hi hai, humne sirf apne features jaade.

ABI / module-loading ke liye jo matlab rakhta hai:

| Option | stock | ours | verdict |
|---|---|---|---|
| `CONFIG_MODVERSIONS` | `y` | `y` | ✅ same |
| `CONFIG_TRIM_UNUSED_KSYMS` | `y` | `y` | ✅ same |
| `CONFIG_UNUSED_KSYMS_WHITELIST` | `"abi_symbollist.raw"` | same | ✅ same |
| `CONFIG_HZ` | `250` | `250` | ✅ same |
| `CONFIG_NR_CPUS` | `32` | `32` | ✅ same |
| `CONFIG_PREEMPT_DYNAMIC` | off | off | ✅ same |
| `CONFIG_MODULE_SIG_PROTECT` | `y` | off | ⚠️ jaan-boojh kar (Google-signed modules load karne ke liye) |
| `CONFIG_UCLAMP_BUCKETS_COUNT` | `20` | **`5`** | ❌ **ABI change — fix ho gaya** |
| `CONFIG_THERMAL_WRITABLE_TRIPS` | `y` | off | jaan-boojh kar (DO NOT INCLUDE) |

`CONFIG_UCLAMP_BUCKETS_COUNT=5` `struct rq` ke andar uclamp arrays ka size badal
deta hai; vendor scheduler modules (FPSGO/GED/PPM/PBM) stock layout ke against
bane hain. Isliye ab `20` — stock wali value.

## Bisection (abhi chal raha hai)

Teen variants, teeno aapki hi stock `boot.img` + `vendor_boot` se, sirf
features/root ka farq:

| Variant | root | SUSFS | tweaks | Kya test karta hai |
|---|---|---|---|---|
| **P** parity | none | — | off | Build pipeline + packaging + stock-ABI config |
| **R** root only | KernelSU | on | off | KSU + SUSFS patches (leading suspect) |
| **T** tweaks only | none | — | on | Poora feature set (uclamp ab 20) |

Flash kram: **P → (boots?) → R → T**. Har flash ke baad rollback taiyar rakhein:

```bash
fastboot flash boot <aapka stock boot.img>
# ya KernelFlasher → Restore
```

Natija:
- P boot karta hai → packaging/pipeline saaf; culprit R ya T me hai.
- P bhi bootloop karta hai → problem baseline build/toolchain me hai (features
  ya root me nahi) aur wahi pehle dekhna hoga.
- R bootloop / T boot → KSU/SUSFS patch hi culprit.
- R boot / T bootloop → feature set me se koi ek option (crypto/NTFS3/BBR/PSI…).
