# HAVOC — 101-point audit

Project: **HAVOC** · device: Xiaomi Redmi Note 13 5G (**gold**) · one kernel,
one root implementation (BakaSU builtin), performance-focused.
This file maps the 101 requirements to what is **implemented**, **preserved**,
**unsupported**, or **untested**. Nothing here is a benchmark claim.

Statuses: `IMPL` implemented/verified in the build · `PRES` stock behaviour preserved ·
`UNSUP` not possible in scope (reason given) · `UNTEST` not verified (no device) ·
`PROC` procedure/tool provided · `NEED` device data required.

## Project and honesty

- **001** act as an ARM64/GKI kernel engineer — the whole repo is that record (`docs/CHANGELOG.md`, `docs/RESEARCH.md`, `docs/BOOTLOOP.md`). `IMPL`
- **002** project name exactly *HAVOC* — release title, `NOTES`, docs, and inside the kernel (`uname -r` ends in `-HAVOC`). `IMPL`
- **003** target: Redmi Note 13 5G, `gold` — asserted before every build (`device check`). `IMPL`
- **004** one final performance kernel, no flavour zoo — the workflow exposes a single `root_flavor` (`bakasu`); one release, one kernel. `IMPL`
- **005** builtin BakaSU, one coherent root — `CONFIG_KSU=y`, only BakaSU compiled in. `IMPL`
- **006** primary goal: measured sustained gaming performance — procedure exists (`docs/BENCH.md`), **no measurement has been made**. `UNTEST`
- **007** also input latency, UI smoothness, CPU throughput — same procedure, sections 1 and 3. `PROC`
- **008** never substitute permanent max clocks — no permanent clock/governor change anywhere; `gold-profiles.sh` refuses to leave schedutil and snapshots every value. `IMPL`
- **009** 101 items are an audit checklist, not 101 patches — this file. `IMPL`
- **010** never fabricate support/benchmarks/tests — every unverified line below says `UNTEST`/`NEED`. `IMPL`

## Repository, source and build

- **011** inspect the repo before changing it — done; layout: `scripts/` (apply-tweaks, apply-root, fix-gki-config, check-policy, check-kmi, verify-build, package), `configs/`, `tools/`, `.github/workflows/`. `IMPL`
- **012** source branch, manifest, build system, toolchain — `android15-6.6-2026-01_r34` (GKI manifest via Kleaf), **Bazel/Kleaf**, Kleaf's pinned clang. `IMPL`
- **013** device `uname`, ROM build, Android version — `uname -r` from the phone: `6.6.118-android15-8-maybe-dirty-4k-golden`; Android 16. Exact ROM build fingerprint: `NEED` (`getprop ro.build.fingerprint`).
- **014** request missing compatibility info together — collected at the end of this file. `IMPL`
- **015** actual kernel branch independent of OS version — LTS **6.6.118**, ACK `android15-6.6`, exactly the tag stock runs. `IMPL`
- **016** required KMI generation and vendor-module compatibility — KMI **android15-6.6**; all **9444** exported symbol CRCs equal to stock GKI build 15511674, or the build fails. `IMPL`
- **017** stock boot image and layout inspected — boot header parsed with `scripts/bootimg.py` (header, cmdline, ramdisk size, dtb region). `IMPL`
- **018** preserve image format/compression/header/partition size — repack asserts header byte-identical apart from `kernel_size`; payload is gzip `Image.gz` as stock. `IMPL`
- **019** init_boot / vendor_boot / system_dlkm / vendor_dlkm relevance — boot carries the kernel, `vendor_boot` carries dtb+vendor ramdisk, dlkm partitions carry the vendor modules. `IMPL`
- **020** do not modify them merely because they exist — only `boot` is ever written; `vendor_boot`, `init_boot`, `system_dlkm`, `vendor_dlkm` are never touched. `PRES`
- **021** matching ACK/device sources, not an obsolete gold tree — build uses the same ACK tag the stock kernel came from, not an old `gold` branch. `IMPL`
- **022** pin everything — source `e56cf6b09cca`, BakaSU `v4.2.0-rc3` (`239e1e88`), AnyKernel3 `41f04bdb`, stock symvers build `15511674`, `SOURCE_DATE_EPOCH` from the run. `IMPL`
- **023** preserve exported symbols, module versioning, ABI config — `MODVERSIONS=y`, `TRIM_UNUSED_KSYMS=y`, same whitelist, `UCLAMP_BUCKETS_COUNT=20`, CRC gate. `IMPL`
- **024** unchanged baseline before patches — parity builds exist (no root, no tweaks); the config delta against stock is 12/44 lines. `IMPL`
- **025** unresolved compatibility must not be called flash-ready — artifacts are labelled *not boot-tested*; the BakaSU flavor has never run on this phone. `UNTEST`

## Root (BakaSU)

- **026** BakaSU from the official project at a recorded revision — `Baka-SU/BakaSU` tag `v4.2.0-rc3`. `IMPL`
- **027** read that revision's instructions and Kconfig first — its `kernel/setup.sh` and `Kconfig` were read; hook default is the tracepoint redirect. `IMPL`
- **028** builtin `CONFIG_KSU=y`, no extra root LKM — yes, and no `kernelsu.ko` is packaged. `IMPL`
- **029** hook method supported by that source and this branch — **Tracepoint Syscall Redirect** (GKI2), so no kernel source patches. `IMPL`
- **030** no second KernelSU fork — workflow only allows `bakasu`; other forks remain in the script for bisection and are not built. `IMPL`
- **031** exact compatible manager APK and its source — the manager APK published by `Baka-SU/BakaSU` at the same tag; see `docs/ROOT.md`. `PROC`
- **032** verify manager package/signature, no verification disabled — `apk_sign.c` untouched, expected size/hash left at defaults. `PRES`
- **033** explicit root control, no blanket root — BakaSU is allowlist-based; nothing widens it. `PRES`
- **034** no hiding/spoofing additions as performance — SUSFS is off for this kernel. `IMPL`
- **035** manager detect/grant/deny/persist tests — `UNTEST`, checklist in `docs/ROOT.md`.

## CPU, scheduler, thermal

- **036** real CPU topology and cpufreq policies — `NEED`: `sh tools/perf-check.sh` prints clusters, drivers, governors, freqs.
- **037** active scaling drivers and available governors — `NEED` (same dump); the image only guarantees `schedutil` exists. `IMPL` for the config side.
- **038** preserve the scheduler baseline — no core scheduler patch; CFS/EEVDF untouched. `PRES`
- **039** evaluate schedutil, never force a missing governor — `schedutil` is the default *and* `gold-profiles.sh` refuses to set anything else. `IMPL`
- **040** preserve capacity information and platform Energy Model — `ENERGY_MODEL=y`, capacities untouched. `PRES`
- **041** evaluate EAS/UClamp with real traces — `UNTEST`; needs `perf`/`task_monitor` traces on device.
- **042** inspect actual rate-limit tunables — the script probes `schedutil/up_rate_limit_us` / `down_rate_limit_us` per policy and skips what is absent. `IMPL`
- **043** tune frequency response only after measuring — no tuned values shipped as defaults; profiles are opt-in. `PROC`
- **044** bounded input boost that expires — no kernel-side input boost was added (that would need vendor/touch integration); the `gaming` profile raises `top-app` uclamp bounds only, which the scheduler decays through normal wake-up behaviour. `UNSUP` for a kernel input boost.
- **045** never force every thread to big cores — nothing sets affinity; cpusets stay as Android defines them. `PRES`
- **046** do not restrict audio/display/system threads — no cpuset values are written to those groups. `PRES`
- **047** conflicts with Power HAL / vendor perf requests — `NEED`/`UNTEST`: FPSGO/GED run in vendor modules and talk to the same scheduler; no conflict was observed because nothing ran on hardware.
- **048** preemption/timer changes only where supported — `PREEMPT_DYNAMIC=off` and `HZ=250` kept as stock; nothing changed. `PRES`
- **049** keep a change only if it beats repeat variation — no measurement ⇒ nothing beyond stock-equivalent config was kept. `PROC`

## GPU

- **050** identify the real Mali/MediaTek driver — vendor module **`mali_kbase_mt6833_r49.ko`** (MT6833, Mali r49), not part of the GKI Image. `IMPL`
- **051** what is in GKI vs vendor — GKI has the DRM/ioctl plumbing; OPP tables, DVFS and the GPU firmware live in that vendor module. `IMPL`
- **052** locate the real frequency table and voltage/clock code — inside the vendor module; not editable from this kernel tree. `UNSUP`
- **053** confirm frequency units before use — `devfreq` reports Hz, sysfs vendor nodes on MTK often report MHz; `perf-check.sh` prints the raw node so the unit can be confirmed per node. `PROC`
- **054** requested vs hardware-reported frequency — the dump records `cur_freq` (reported) next to `max_freq`/`available_frequencies` (requested range). `PROC`
- **055** the 1068 MHz reading is user data, unverified — recorded as reported only. `UNTEST`
- **056** keep kernel GPU driver compatible with userspace — we ship no GPU driver change at all, so compatibility is stock. `PRES`
- **057** inspect FPSGO/GED instead of inventing components — they are vendor modules; nothing was invented or replaced. `PRES`
- **058** evaluate ramp-up/idle under repeatable load — `UNTEST` (procedure only).
- **059** stock operating points as the baseline — untouched. `PRES`
- **060** OC only if the implementation allows it — it does not: frequencies/voltages are in the vendor module. `UNSUP`
- **061** no promised 1200 MHz — none promised. `IMPL`
- **062** never invent voltages/PLLs/silicon bins — none invented. `IMPL`
- **063** never bypass thermal shutdown/battery protection/fault handling — policy gate forbids thermal and charging writes; `gold-profiles.sh` writes no thermal node. `IMPL`
- **064** any experimental OC must be opt-in and revertible — not applicable: no OC was implemented. `UNSUP`
- **065** report the OC blocker honestly — documented here and in `docs/CHANGELOG.md`. `IMPL`

## Memory

- **066** know RAM, pressure, workload before changing defaults — `NEED`: RAM size/`MemTotal` comes from `perf-check.sh`; no default was changed meanwhile. 
- **067** only ZRAM algorithms this kernel supports — `lz4`, `lz4hc`, `lzo`, `842`, `zstd` backends are in the Image; the driver stays Google's `zram.ko`. `IMPL`
- **068** measure compression cost/savings/stalls — `UNTEST`; `mm_stat` is captured each run. `PROC`
- **069** preserve Android memory-pressure reporting — PSI stays enabled and not default-disabled; lmkd props untouched. `PRES`
- **070** no universal zram size/swappiness/app-killer profile — no value is baked; the profile script only reports swapiness/zram state. `PRES`
- **071** no large MM backport without evidence — MGLRU is the only MM feature enabled, it is upstream in 6.6 and gated per build. `IMPL`

## Storage and I/O

- **072** actual storage device and schedulers — `NEED`: UFS device and `queue/scheduler` list come from the dump; `mq-deadline` is compiled in. `IMPL`/`NEED`
- **073** compare none vs mq-deadline with one workload — `UNTEST` (procedure: same `fio` job under each scheduler). `PROC`
- **074** read-ahead only with measurements — untouched (stock value), recorded in the dump. `PRES`
- **075** preserve fsync, integrity, encryption, storage drivers — ext4/F2FS/EROFS/FBE/inline-crypto kept; no fsync removal. `PRES`

## Scope hygiene, security, toolchain

- **076** no unrelated networking/filesystem extras to inflate the count — CAKE/CIFS/IP_SET came from the earlier feature set and are documented as extras, not as performance work. `IMPL`
- **077** separate kernel changes from userspace/config — every runtime knob lives in `gold-profiles.sh`; `docs/FEATURES.md` marks each item kernel vs vendor vs userspace. `IMPL`
- **078** preserve security hardening unless documented — no permissive SELinux, no fsync removal. The one deliberate relaxation is `MODULE_SIG_PROTECT=off` (so Google-signed `system_dlkm` modules load under our key); it is documented. `PRES`
- **079** matching Clang/LLVM and reproducible environment — Kleaf's pinned toolchain, `SOURCE_DATE_EPOCH` from the run. `IMPL`
- **080** keep LTO/CFI, no random global flags — `LTO_NONE` + `CFI_CLANG`, both asserted after the build. `PRES`
- **081** no sanitizers/debug logging in the artifact — `dev_build` defaults to false. `IMPL`
- **082** keep crash logging/observability — `pstore`, `ramoops`, console logging kept. `IMPL`
- **083** reproducible build script, stops on errors, records logs — every step is `set -euo pipefail`; `/tmp/bazel.log` is now uploaded with the artifacts. `IMPL`
- **084** brand HAVOC (in `uname -r` too) without breaking module matching — release string `-4k-HAVOC`; with CRCs present the loader compares only the vermagic flags, not the release string (`same_magic()`), and r27 already booted with a changed release string. CRC gate still enforces all 9444 symbols. `IMPL`
- **085** package only after device/format/compatibility checks — device check, config read-back, policy gate, KMI gate, packaging assertions all run before upload. `IMPL`

## Measurement and testing

- **086** repeatable stock-vs-custom procedure — `docs/BENCH.md`. `PROC`
- **087** match settings, brightness, refresh rate, ambient, charging — required by the procedure. `PROC`
- **088** repeated short tests plus 30-minute sustained run — in `docs/BENCH.md`. `PROC`
- **089** FPS/throughput with frame-time percentiles and jank — `gfxinfo framestats` / game overlay. `PROC`
- **090** CPU/GPU frequency, utilisation, temperature — `tools/perf-check.sh` + the CSV loop. `PROC`
- **091** rule out colder-start artefacts — compare window temperatures, not peaks. `PROC`
- **092** cold boot, reboot, screen-off, suspend/resume, recovery — `UNTEST`.
- **093** calls/data, Wi-Fi, BT, cameras, audio, sensors, touch, charging — `UNTEST`.
- **094** root manager behaviour and crash/driver-error logs — `UNTEST` (`dmesg`, `logcat -b crash`). 
- **095** without device access, mark boot/stability/thermal/perf untested — this file and the release body say so. `IMPL`

## Deliverables

- **096** audit report mapping each requirement — this file. `IMPL`
- **097** source revisions, patch series, config diff, reasons — `docs/CHANGELOG.md` (delta + history), `docs/RESEARCH.md`, this file. `IMPL`
- **098** manager APK version/source and compatibility notes — `docs/ROOT.md`. `IMPL`
- **099** SHA-256 of artifacts and preserved build logs — `SHA256SUMS.txt` in every artifact set; `bazel.log` uploaded. `IMPL`
- **100** verified install prerequisites and rollback, never auto-flash — `docs/FLASH.md`, `NOTES.txt`; nothing in this project flashes anything. `IMPL`
- **101** one kernel with an honest summary of gains and blockers — see the summary below. `IMPL`

---

## Honest summary

Delivered: one kernel, `HAVOC`, stock ACK source `e56cf6b09cca`, 6.6.118, 4 KB
pages, BakaSU `v4.2.0-rc3` builtin, 9444/9444 KMI CRC parity, feature set from
`configs/gold-features.config`, runtime profiles plus a state dump tool.

Measured gains: **none claimed.** No benchmark has been run on this device.

Blockers:
- GPU OC cannot be implemented in a GKI Image: OPP tables, DVFS and firmware are in
  `mali_kbase_mt6833_r49.ko` (vendor).
- Kernel-side input boost needs vendor touch integration, not a GKI change.
- BakaSU flavor and the `-HAVOC` release string are **not boot-tested**; the
  last boot-confirmed build was the KernelSU+SUSFS one (`-4k-golden`).

## Device data still needed (one dump, all of it)

```bash
adb shell getprop ro.build.fingerprint
adb shell getprop ro.build.version.release
sh tools/perf-check.sh > perf-stock.txt      # from the phone, after copying it there
```

That single `perf-stock.txt` answers items 013, 036, 037, 042, 047, 053, 066, 072 and 074.
