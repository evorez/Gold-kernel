# Root: BakaSU, builtin

HAVOC ships **one** root implementation: **BakaSU**, compiled into the kernel
(`CONFIG_KSU=y`), no root LKM, no second KernelSU fork.

| Item | Value |
|---|---|
| Project | `Baka-SU/BakaSU` (KernelSU-based; SukiSU-Ultra lineage) |
| Revision | tag **`v4.2.0-rc3`**, commit `239e1e88` (pinned in `scripts/apply-root.sh`) |
| Integration | `common/drivers/kernelsu` → `../../BakaSU/kernel`, `obj-$(CONFIG_KSU) += kernelsu/`, `source "drivers/kernelsu/Kconfig"` (its own `kernel/setup.sh` does the same) |
| Config | `CONFIG_KSU=y` (builtin, not `=m`) |
| Hook method | **Tracepoint Syscall Redirect** — the fork's default for GKI2 (5.10+). No kernel source patches are required, which is why this kernel keeps stock `fs/`, `kernel/`, `security/` sources |
| KMI | Kleaf's `kmi_symbol_list_strict_mode` is relaxed for this flavor only; our own gate still requires all 9444 stock symbol CRCs to match and no stock symbol to disappear |
| Manager | the manager APK published by the same project at the same revision (`Baka-SU/BakaSU` releases). Do not mix it with another KernelSU manager build |

## Notes that matter

- **Manager verification stays on.** We do not patch `apk_sign.c`, and `KSU_EXPECTED_SIZE`/
  `KSU_EXPECTED_HASH` are left at the fork's defaults. A manager APK whose signature was
  changed (a rebranded build) will not be recognised — that is the intended behaviour.
- **Root is not granted to everything.** BakaSU is an allowlist root: an app gets root
  only after you approve it in the manager. Nothing in this kernel bypasses that.
- **No hiding/spoofing add-ons.** SUSFS is not part of the PERF kernel: the fork's
  in-tree SUSFS path needs kernel-side susfs4ksu patches, and hiding is not a
  performance feature.
- **SUSFS** remains available only in the older KernelSU flavor kept in
  `scripts/apply-root.sh` for bisection; it is not published.

## What is NOT verified

Everything runtime: manager detection, grant, denial, and persistence after reboot have
**not been tested** (no device access). Test list:

1. install the manager APK, open it — it must show the kernel version and "working"
2. an app requests root → approve → `su -c id` reports uid 0
3. deny the same app → it must fail, and the deny must survive a reboot
4. revoke → root gone without a reboot
5. `adb shell su -c 'cat /proc/version'` works from a shell too
