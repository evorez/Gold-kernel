# Install guide — GoldenEra for gold

> **Read this first:** installing a custom kernel is your responsibility. The
> bootloader must be unlocked. Keep your ROM's **stock `boot.img`** — that is your
> rollback. No data wipe is needed, but a backup is still a good habit.

This guide is for the **Redmi Note 13 5G (codename `gold`)**, on Android 16 /
HyperOS 3 or any custom ROM for gold. The device layout:

```
boot        = kernel only (header v4, ramdisk 0, Image.gz)   <-- only the kernel changes
vendor_boot = dtb + vendor ramdisk (modules)
vendor_dlkm = MediaTek's prebuilt modules
init_boot   = does not exist on this device
```

**We do not ship a guessed `boot.img` — we ship the kernel** (`Image`, `Image.gz`,
and a recovery-flashable AnyKernel3 zip). Packing a boot image from scratch means
guessing the header/cmdline and (on gold) the dtb, and a wrong guess is a phone
that does not boot. Instead:

- the **AnyKernel3 zip** splits *your* existing boot on the device and swaps only the
  kernel — your stock header/dtb/ramdisk stay exactly as they were;
- if you do want a `boot.img`, section 2B builds one **from your own stock image**
  as the reference, not from guesses. Section 2C covers the `boot.img` the build
  produces for you when you give it your stock image.

---

## 0. TL;DR — rooted phone

```bash
adb push AnyKernel3-*.zip /sdcard/Download/
```

1. Open **KernelFlasher** (or any custom recovery) on the phone.
2. Pick `AnyKernel3-*.zip` → flash → reboot.

That is it. `vendor_boot` / `vbmeta` / `dtbo` are never touched.

Rollback (if something goes wrong):

```bash
fastboot flash boot stock-boot.img
fastboot reboot
```

---

## 1. What you need

| Item | Why | Where |
|---|---|---|
| Unlocked bootloader | flashing is rejected otherwise | Settings → Developer options → OEM unlocking + Mi Unlock |
| Root (KernelSU manager) | the AnyKernel3 zip is flashed by an app | already rooted, or root with any method first |
| `AnyKernel3-*.zip` | installs the kernel | GitHub Release (`gold-r*`) or an Actions artifact |
| raw `Image-*` / `Image-*.gz` | only if you build a boot.img yourself (2B) | same release |
| **`stock-boot.img`** | your rollback + the reference for 2B | from your ROM's package (below) |
| `platform-tools` | `adb`, `fastboot` | developer.android.com/tools/releases/platform-tools |
| 50–60% battery | a safe flash | — |

### How to get your stock boot.img

**From a HyperOS fastboot ROM (`.tgz`):**
```bash
tar -xzf <rom>.tgz
# inside: images/boot.img — keep it as stock-boot.img
```

**From a HyperOS recovery ROM (`.zip`):** it contains `payload.bin`; use
`payload-dumper-go`:
```bash
payload-dumper-go -p boot payload.bin    # produces boot.img
```

**From a LineageOS / custom ROM zip:** `boot.img` is inside the zip.

**Straight off the phone (if rooted):**
```bash
su -c 'dd if=/dev/block/by-name/boot of=/sdcard/stock-boot.img'
```

> **Never delete it** — it is what saves you from a bootloop.

---

## 2A. Install: recovery-flashable zip (recommended)

The `AnyKernel3-*.zip` artifact is the standard recovery-flashable package
(AnyKernel3 at a pinned commit). It carries `META-INF/com/android/update-binary`,
`tools/ak3-core.sh`, `anykernel.sh` and `Image`; CI checks the structure and the
permissions of every build.

**Option 1 — custom recovery (TWRP / SHRP / OrangeFox):**
1. Put the zip on the phone/SD card or a USB-OTG stick.
2. Boot into recovery → **Install** → pick `AnyKernel3-*.zip` → confirm.
3. The script detects the current slot, splits `boot`, replaces **only the kernel**,
   repacks and flashes. The screen shows `Installing GoldenEra …` then `Done`.
4. Reboot to system.

**Option 2 — KernelFlasher app (no recovery needed, needs root):**
App → "Flash kernel / AK3 zip" → pick the zip → Flash → Reboot.

Both use the same zip, and neither touches `vendor_boot` / `dtbo` / `vbmeta`.

### If recovery says "unsupported device"

The zip sets `do.devicecheck=1` and allows the names `gold`, `xiaomi_gold`,
`gold_global`, `gold_eea`, `Redmi Note 13 5G`. If your ROM's `ro.product.device`
does not match, the flash aborts — use **2C** (the ready-made `boot.img` via
fastboot) instead.

### Check after flashing from recovery

```bash
adb shell uname -r     # should end in …-4k-HAVOC
```

## 2C. Ready-made `boot.img` (produced by the build)

If you passed `boot_img_url` (your own ROM's `boot.img`) when starting the build,
the artifacts also contain a `boot.img`: it is **your own stock image** with only
the kernel payload swapped. Header (cmdline/os_version/page size), ramdisk and tail
(dtb, if any) are **byte-for-byte** identical, and CI verifies that.

```bash
fastboot flash boot boot.img
fastboot reboot
```

This is the straightest fastboot route. The AnyKernel3 zip (2A) is shipped as well —
use either one; both change the kernel only.

## 2B. Optional: build a `boot.img` yourself (advanced)

```bash
# 1) read the header values out of your stock boot (base, pagesize, cmdline, dtb)
unpack_bootimg --boot_img stock-boot.img --out stock/

# 2) repack with our kernel, using the values from stock
mkbootimg --header_version 4 \
  --kernel Image-GoldenEra-*.gz \
  --cmdline "bootopt=64S3,32N2,64N2" \
  --os_version 16.0.0 --os_patch_level 2026-01 \
  --output boot.img
```

Two things to watch:
- if the stock boot has a **dtb** (a `dtb` file in `unpack_bootimg`'s output), pass it
  with `--dtb stock/dtb` — otherwise the boot can fail;
- the kernel version must stay `6.6.118-android15-8`
  (`strings Image-* | grep 'Linux version'`), otherwise the vendor modules will not load.

That guess-work is exactly why **2A (AnyKernel3) is the default recommendation**.

### If the phone shows "dm-verity / device is corrupt"

That is the AVB message (a modified kernel no longer matches the hash). Disable
verification once — you need **your own ROM's `vbmeta.img`** (it is inside the ROM zip):

```bash
fastboot --disable-verity --disable-verification flash vbmeta vbmeta.img
fastboot reboot
```

This is a one-time step; later kernel flashes do not need it again.

---

## 3. Activating root (`root_flavor=kernelsu` / `ksu-next` / `sukisu` builds)

The root driver is **inside the kernel**, so there is no boot patching like Magisk.
You only need the manager app:

1. Install the **KernelSU** APK (`tiann/KernelSU` releases) — that is what the default
   `root_flavor=kernelsu` targets. For a `root_flavor=ksu-next` build use the
   **KernelSU-Next** APK, for `root_flavor=sukisu` use the **SukiSU-Ultra** APK.
2. Open the app → the status should show **"Working" / "Kernel: installed"**.
   "Not installed" means the wrong KMI/version kernel was flashed (see
   troubleshooting) or the APK does not match the kernel's KSU version.
3. SUSFS userspace (for hiding): flash susfs4ksu's `ksu_module_susfs` module zip in
   the manager, then reboot. The kernel side of SUSFS is already in the image
   (`CONFIG_KSU_SUSFS=y`).

> SUSFS lives in the kernel; the module that drives it is a separate userspace package.

---

## 4. Flashing from recovery (without KernelFlasher)

1. Put `AnyKernel3-*.zip` on the phone/SD card.
2. Boot into recovery (TWRP, or stock recovery with sideload).
3. Install → pick the zip (or `adb sideload AnyKernel3-*.zip`).
4. Reboot.

Same zip, same work — only the tool differs. `vendor_boot` is untouched here too.

---

## 5. Something went wrong? (troubleshooting)

| Symptom | Meaning | Fix |
|---|---|---|
| Stuck on the logo, no boot | kernel/ROM mismatch, or a self-built boot.img with a wrong header/dtb | flash your stock boot.img; then install the AnyKernel3 zip (2A) — it guesses nothing |
| Black screen, phone vibrates | vendor modules did not load (KMI/CRC) | restore stock boot; try a build with `crc_stub=true`, or pass `stock_symvers_url` so the CRC check runs |
| WiFi/BT dead | `MODULE_SIG_PROTECT` or protected-exports issue | we already keep it off; look for `module verification failed` in dmesg |
| "dm-verity / corrupt" | AVB hash mismatch | the `vbmeta` command in section 2 |
| Fastboot: "FAILED (remote: not allowed)" | bootloader locked | unlock with Mi Unlock |
| Fastboot does not see the device | driver/cable | another cable/port, `fastboot devices`, Google USB driver on Windows |
| Manager app: "Not installed" | root driver missing / KMI drift | check `verify-build.sh` output — `CONFIG_KSU=y` must be there |

Even in a bootloop **fastboot always works** on this device (no need to reach
recovery on MTK) — which is why having the stock boot.img is the biggest insurance.

---

## 6. Things never to do

- `fastboot flash vendor_boot` / `dtbo` / `super` — we never build those.
- `fastboot flashing lock` until you are 100% stock (restore stock boot + vbmeta first).
- Flashing a `boot.img` from a different ROM or an older build onto your ROM (KMI mismatch).
- Forgetting stock's dtb in a self-built boot.img (section 2B) — the first boot will fail.
- Flashing below 30% battery.

---

## 7. Checks after flashing

```bash
adb shell uname -r
# 6.6.118-android15-8-...-4k-HAVOC   (our suffix at the end)
```

Root check:
```bash
adb shell su -c id
# uid=0(root) after granting in the manager
```

Feature check (kernel side, no root needed):
```bash
adb shell 'zcat /proc/config.gz | grep -E "WIREGUARD|NTFS3|EXFAT|LRU_GEN|PSI=|SCHEDUTIL"'
adb shell 'ls /sys/fs/pstore'          # pstore/ramoops mount
adb shell 'cat /sys/power/suspend_stats/success'
```

---

## 8. Runtime profiles (optional, after root)

The kernel bakes in no fixed performance policy — balanced/gaming/sustained are
**runtime** profiles and every value is reversible:

```bash
adb push gold-profiles.sh /data/local/tmp/          # ships inside the artifacts
adb shell su -c 'sh /data/local/tmp/gold-profiles.sh status'
adb shell su -c 'sh /data/local/tmp/gold-profiles.sh gaming'      # freq ramp-up + top-app uclamp
adb shell su -c 'sh /data/local/tmp/gold-profiles.sh sustained'   # ~80% max freq cap (heat/battery)
adb shell su -c 'sh /data/local/tmp/gold-profiles.sh balanced'    # back to stock-like
adb shell su -c 'sh /data/local/tmp/gold-profiles.sh charge-limit 80'
adb shell su -c 'sh /data/local/tmp/gold-profiles.sh restore'     # restore everything from the snapshot
```

- The script **refuses** to run with any governor other than `schedutil`, and it never
  touches thermal zones or trips.
- The backup lives in `/data/adb/gold-profiles/backup`; `restore` writes it back.
- The charge limit only works if your ROM's vendor charger driver exposes a percentage
  node (`charge_control_end_threshold`); otherwise the script says so plainly and does
  not guess at a current node.
