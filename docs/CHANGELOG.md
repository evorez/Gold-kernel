# Changelog — GoldenEra

Redmi Note 13 5G (**gold**) · author **𝙴𝚅𝙾𝚁𝙴𝚉** 🥹
Har entry ek GitHub Actions run se bani release hai (`gold-r<N>`), teeno variants
(`root`, `susfs`, `tweaks`) ke saath. Sab kuch aapki hi stock `boot.img` +
`vendor_boot` par, sirf kernel payload swap.

---

## GoldenEra v1 — (agla build, taiyaari ho rahi hai)

Pehli baar kernel ka naam + author: **GoldenEra v1 by 𝙴𝚅𝙾𝚁𝙴𝚉**.
`uname -r` ab `…-4k-golden` par khatam hoga, release title/notes, zip/boot.img
ke naam aur `NOTES.txt` sab GoldenEra brand karte hain.

- **Naam**: project = GoldenEra v1, artifact = `GoldenEra-<root>-susfs<..>-<run>`,
  kernel suffix `-4k-golden`
- **ABI fix (asli wajah bootloop ki)**: `CONFIG_UCLAMP_BUCKETS_COUNT` 5 → **20**
  (stock value; `struct rq` ka layout stock jaisa)
- **Policy**: DO-NOT-INCLUDE options ab *hamesha* off (`fix-gki-config.sh`), sirf
  tweaks fragment par depend nahi — tweaks=false build bhi contract follow karta hai
- **CI fix**: manual dispatch ab doosri build ko cancel nahi karta (bisection
  parallel chalti hai)
- **Naye diagnostics**: `bootimg.py config` (stock config extraction),
  `check-stock-images` stock config delta, `config-diff` workflow (stock vs ours,
  annotations me)

## gold-r17 — pehla build jo phone par **boot hua** ✅

- `root=none`, `susfs=false`, `tweaks=true`, `CONFIG_UCLAMP_BUCKETS_COUNT=20`
- Phone boot hua, `uname -r` = `6.6.118-android15-8-maybe-dirty-4k-gold`
- Matlab: build pipeline, packaging, source aur **poora feature set** sahi hai
- Isme root nahi hai — ye diagnostic build tha

## gold-r14 — root + SUSFS (bootloop ❌)

- `root=kernelsu`, `susfs=true`, `tweaks=true`, `CONFIG_UCLAMP_BUCKETS_COUNT=5`
- Flash safal (`Done!`, device check `gold` pass), phir **bootloop** → stock boot
  wapas flash karke recover kiya
- Do hi cheezein baad me badli: root hataya + uclamp 5 → 20

## gold-r13 — recovery-flashable zip

- AnyKernel3 zip (pinned `41f04bd`) pehli baar, `boot.img` ke saath
- Zip structure CI me assert hota hai (update-binary 755, anykernel.sh, ak3-core.sh,
  device names `gold`/`xiaomi_gold`/…)

## Pehle (r6–r11)

- GitHub Actions par GKI baseline + custom kernel build, KMI gate, policy gate,
  Drive docs, feature fragment (`configs/gold-features.config`)

---

## Bisection ladder (ek-ek option add karke)

| Step | Kya andar | Natija |
|---|---|---|
| 0 | features only (`tweaks=true`, root=none) | **r17 — booted** ✅ |
| 1 | features + KernelSU + SUSFS | chal raha hai |
| 2 | agar 1 fail → features + KernelSU (SUSFS ke bina) | — |
| 3 | agar 2 pass → SUSFS patches ek-ek (sus_mount, sus_kstat, sus_path, spoof_uname, open_redirect, hide_symbols) | — |
| 4 | `UCLAMP_BUCKETS_COUNT=5` dobara try (alag test, ABI risk) | — |
| 5 | full: features + root + SUSFS + branding → **GoldenEra v1 final** | — |

Har step ke baad rollback: `fastboot flash boot <stock boot.img>` ya
KernelFlasher → **Restore**.
