# gold custom kernel — feature map

Every line of the requested feature list, mapped to **how it is actually delivered**
on this device, and — just as important — how the "do not include" list is
**machine-checked** rather than promised.

Legend

| Mark | Meaning |
|---|---|
| ✅ | compiled into the Image from `configs/gold-features.config` (config name given) |
| 🧩 | runtime, via `tools/gold-profiles.sh` (no fixed policy baked into the kernel) |
| 🔧 | vendor side: already on the phone (MediaTek modules / DT), kept compatible by the KMI gate |
| 🔀 | optional, behind a workflow input |
| ⛔ | refused by design, enforced by `scripts/check-policy.sh` |

> Short version: whatever can live in a kernel image comes from **config**; MTK's
> FPSGO/GED/thermal/UFS/charging all live in **vendor modules** that already exist on
> the phone — we neither break them (KMI gate) nor duplicate them.
> Kuch cheezein **runtime** hain (profiles), aur "DO NOT" list ko build **fail** kar
> enforces that.

---

## BASE

| Item | Status | Detail |
|---|---|---|
| Xiaomi gold source + matching MTK modules | 🔧 (+⚠️) | Stock gold ships **Google's GKI kernel**; MediaTek's modules are built against it. Xiaomi's `gold-s-oss` is Android 13 / 5.10 and cannot boot this phone — so the base is the exact GKI tag the device runs (`6.6.118`, `e56cf6b09cca`). "Matching MTK modules" is honoured by **not** changing the KMI (`scripts/check-kmi.sh`). |
| Stock DTB/DTBO + vendor-module compatibility | 🔧 | `boot` carries the kernel only (header v4, no ramdisk). DTB/DTBO live in `vendor_boot`/`dtbo` and are never touched. Vendor modules must keep resolving symbols — the KMI gate fails the build if a KMI symbol disappears, and compares CRCs when a reference `Module.symvers` is supplied. |
| LTS security/bug fixes | ⚠️ partial | The source is pinned to **exactly** `android15-6.6-2026-01_r34` (6.6.118) — that is what the prebuilt vendor modules were linked against, so a newer sublevel is not a free upgrade. Path to newer fixes: same-KMI build (e.g. 6.6.143 / build `16498190`), then revalidate the vendor modules and CRCs. Documented, not silently attempted. |
| Stock CPU/GPU OPP tables | 🔧 + ⛔ | OPP tables are untouched: the policy gate fails the build if anything under `drivers/opp`, `drivers/cpufreq`, `drivers/devfreq`, `drivers/gpu` or `arch/arm64/boot` changes. |

## PERFORMANCE

| Item | Status | Detail |
|---|---|---|
| Schedutil | ✅ | `CONFIG_CPU_FREQ_GOV_SCHEDUTIL=y` **and** `CONFIG_CPU_FREQ_DEFAULT_GOV_SCHEDUTIL=y` (default governor, asserted in the Image) |
| EAS | ✅ | `CONFIG_ENERGY_MODEL=y` — the energy model itself comes from the vendor DT, schedutil consumes it |
| UClamp | ✅ | `CONFIG_UCLAMP_TASK=y`, `CONFIG_UCLAMP_TASK_GROUP=y`, `CONFIG_UCLAMP_BUCKETS_COUNT=20` (stock wali value — ABI) |
| Android cpusets / task profiles | ✅ | `CONFIG_CPUSETS=y`, `CONFIG_CGROUP_SCHED=y` — cpusets + uclamp are what `task_profiles.json` drives (userspace part is stock Android) |
| MTK FPSGO / GED / PPM / PBM compatibility | 🔧 | These are vendor modules; they work because the scheduler ABI is unchanged. No duplicate/competing implementation is added. |
| Dynamic CPU + GPU DVFS | ✅ / 🔧 | CPU: schedutil + `PM_DEVFREQ`/`DEVFREQ_THERMAL`; GPU DVFS is MediaTek's (`ged`, `gpufreq`) and stays untouched. |
| Balanced + gaming + sustained profiles | 🧩 | `gold-profiles.sh {balanced,gaming,sustained}` — runtime, reversible, snapshot/restore per value. Never a permanent max clock, never a non-schedutil governor. |

## MEMORY

| Item | Status | Detail |
|---|---|---|
| ZRAM with LZ4 / LZ4-RLE | ✅/🔧 | The zram **driver** stays Google's `zram.ko` (the ROM loads it; flipping it to `=y` would not change what runs). The compression backends it can use are in the Image: `CRYPTO_LZ4`, `CRYPTO_LZ4HC`, `CRYPTO_LZO` (lzo-rle), optional `842`/`ZSTD`. |
| PSI | ✅ | `CONFIG_PSI=y`, `# CONFIG_PSI_DEFAULT_DISABLED` (asserted) |
| Userspace LMKD compatibility | ✅ | LMKD needs PSI + memcg + oom handling in the kernel — all present; the kill policy stays userspace (stock) |
| Memory cgroups | ✅ | `CONFIG_MEMCG=y` |
| Optional tested MGLRU | ✅ | `CONFIG_LRU_GEN=y`, `CONFIG_LRU_GEN_ENABLED=y` — on by default (it has been building green on this tree; drop the two lines if you want it off) |

## STORAGE

| Item | Status | Detail |
|---|---|---|
| UFS 2.2 compatibility | 🔧 | UFS host controller + the gear/HS tuning are vendor side (`ufs` driver in GKI, platform data in DT). Nothing is patched. |
| `none` + `mq-deadline` | ✅ | `CONFIG_MQ_IOSCHED_DEADLINE=y`; `none` is the blk-mq default and needs no config. No other scheduler is added (policy). |
| F2FS / ext4 / EROFS | ✅ | `CONFIG_F2FS_FS`, `CONFIG_EXT4_FS`, `CONFIG_EROFS_FS` (+ optional `EROFS_FS_ZIP`, `F2FS_FS_COMPRESSION`) |
| Inline encryption + TRIM | ✅ | `FS_ENCRYPTION`, `BLK_INLINE_ENCRYPTION`, `FS_ENCRYPTION_INLINE_CRYPT`, optional `SCSI_UFS_CRYPTO`. TRIM/discard is stock behaviour — nothing disables it. |
| Fsync always enabled | ✅ | Never patched. The policy gate greps the actual kernel diff for any `fsync` line and fails the build if one appears. |

## POWER

| Item | Status | Detail |
|---|---|---|
| Stock thermal protection | ✅ + ⛔ | `CONFIG_THERMAL=y`, `# CONFIG_THERMAL_WRITABLE_TRIPS` (asserted). `drivers/thermal` may not be modified — policy gate. |
| CPU idle and deep sleep | ✅ | `CONFIG_CPU_IDLE`, `CONFIG_ARM_PSCI_CPUIDLE`, `CONFIG_SUSPEND` (+ optional menu governor) |
| Battery-aware CPU/GPU limits | 🧩 | `gold-profiles.sh sustained` (caps CPU at ~80 % of max while it is active) and `charge-limit` |
| Optional charge limit | 🧩 | `gold-profiles.sh charge-limit 80` / `off` — writes the vendor power-supply node when the ROM exposes one, and says so when it does not |
| Wakelock and suspend statistics | ✅ | `CONFIG_PM_SLEEP_DEBUG` → `/sys/power/suspend_stats` (`gold-profiles.sh status` prints it). Android's wakelock accounting itself is userspace/HAL in 6.6. |
| Charging overclock | ⛔ | **Not implemented.** It means writing MediaTek's charger driver (vendor module, not in this Image), where a wrong current/voltage setting is a hardware-safety issue, not a performance tweak. If you want faster charging, use the vendor's own fast-charge path. |

## EXTRAS

| Item | Status | Detail |
|---|---|---|
| WireGuard | ✅ | `CONFIG_WIREGUARD=y` (built in, no userspace module needed) |
| exFAT | ✅ | `CONFIG_EXFAT_FS=y` |
| NTFS3 | ✅ | `CONFIG_NTFS3_FS=y` |
| USB gamepad / HID | ✅ | `CONFIG_HID_GENERIC`, `CONFIG_INPUT_JOYDEV` + optional `JOYSTICK_XPAD`, `HID_PLAYSTATION`, `HID_NINTENDO`, `HID_SONY`, `HID_MICROSOFT` |
| Optional KernelSU | 🔀 | `root_flavor` input: `kernelsu` (default, KernelSU + SUSFS), `ksu-next` (KernelSU-Next, no in-tree SUSFS), `none` |
| pstore / ramoops | ✅ | `CONFIG_PSTORE`, `CONFIG_PSTORE_RAM`, `CONFIG_PSTORE_CONSOLE` (+ optional `PSTORE_PMSG`) — last kernel log survives a reboot |
| Ftrace / perf development build | 🔀 | `dev_build=true` applies `configs/gold-devbuild.config` (`FUNCTION_TRACER`, `DYNAMIC_FTRACE`, `FTRACE_SYSCALLS`, `KPROBE_EVENTS`, …). Off by default: debug infrastructure, extra exported symbols, bigger Image. |

---

## DO NOT INCLUDE — and how it is enforced

| Forbidden | Enforced by |
|---|---|
| Thermal bypass | Tree policy: any change under `drivers/thermal` fails the build; `CONFIG_THERMAL_WRITABLE_TRIPS` must stay off; `thermal_bypass`/`disable_thermal` string scan |
| Permanent maximum clocks | No perf/userspace-default governor (`REQ !CONFIG_CPU_FREQ_DEFAULT_GOV_PERFORMANCE`); profiles are runtime and revertible; nothing writes `scaling_max_freq` at boot |
| Unsafe CPU/GPU overclock | Tree policy denylist: `drivers/cpufreq`, `drivers/opp`, `drivers/devfreq`, `drivers/gpu`, `arch/arm64/boot` |
| Fsync disable | Policy greps the kernel diff for `fsync` — any touched line fails the build |
| SELinux permissive | `REQ CONFIG_SECURITY_SELINUX=y` in the Image; scan for `androidboot.selinux=permissive`, `setenforce 0`, `selinux=0` in this repo |
| Display overclock | Device-tree / GPU paths are in the denylist; nothing writes panel or display clocks |
| Random untested governors | Only schedutil is enabled as default; the same scan rejects a performance/userspace governor default |

## How the claims above are verified in CI

| Gate | Script |
|---|---|
| source is the exact GKI build the phone runs | workflow step "Verify the pinned source" |
| every `REQ` option really is in the Image, `OPT` ones reported | `scripts/verify-build.sh` (reads config **out of the Image**) |
| no thermal/OPP/governor/display/fsync changes, SELinux on | `scripts/check-policy.sh` |
| prebuilt vendor modules can still load | `scripts/check-kmi.sh` |
| the artifact really contains this kernel (and nothing else) | `scripts/package.sh` (zip checks: `BLOCK=boot`, kernel version inside the packed `Image`) |
