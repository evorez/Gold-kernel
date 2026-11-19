# Install karne ki guide (Hinglish) — gold custom kernel

> **Pehle ye padh lo:** custom kernel install karna = apni zimmedari. Bootloader
> unlocked hona chahiye. Apne ROM ka **stock `boot.img`** zaroor sambhal ke rakho —
> wo hi rollback hai. Data wipe ki zaroorat nahi hoti, par backup achhi aadat hai.

Ye guide **Redmi Note 13 5G (codename `gold`)** ke liye hai, Android 16 / HyperOS 3
ya gold ke kisi custom ROM ke saath. Device ki shakal:

```
boot        = sirf kernel (header v4, ramdisk 0, Image.gz)   <-- sirf kernel badalta hai
vendor_boot = dtb + vendor ramdisk (modules)
vendor_dlkm = MediaTek ke prebuilt modules
init_boot   = is device par hai hi nahi
```

**Hum `boot.img` nahi dete — sirf kernel dete hain** (`Image`, `Image.gz`, aur ek
AnyKernel3 zip). Wajah: boot.img banane ka matlab header/cmdline aur (gold par) dtb
guess karna, aur galat guess ka result non-booting phone hai. Iske bajaye:

- **AnyKernel3 zip** aapke phone ke *existing* boot ko split karta hai aur sirf kernel
  swap karta hai — aapka stock header/dtb/ramdisk bilkul waisa hi rehta hai.
- Agar aapko khud boot.img chahiye, to neeche 2B dekho (apne stock boot ko reference
  rakh ke banega, andaza nahi).

---

## 0. Ek nazar me (TL;DR) — rooted phone

```bash
# zip phone me daalo
adb push AnyKernel3-*.zip /sdcard/Download/
```

1. Phone pe **KernelFlasher** app (ya koi recovery) kholo.
2. `AnyKernel3-*.zip` chuno → flash → reboot.

Bas. `vendor_boot` / `vbmeta` / `dtbo` ko haath nahi lagta.

Rollback (agar kuch gadbad ho):

```bash
fastboot flash boot stock-boot.img
fastboot reboot
```

---

## 1. Kya-kya chahiye

| Cheez | Kyun | Kahan se |
|---|---|---|
| Unlocked bootloader | bina iske flash reject hoga | Settings → Developer options → OEM unlocking + Mi Unlock |
| Root (KernelSU manager) | AnyKernel3 zip ke liye (app flash karta hai) | pehle se root ho to ho gaya; nahi to pehle koi bhi root method |
| `AnyKernel3-*.zip` | kernel install | GitHub Release (`gold-r*`) ya Actions artifact |
| raw `Image-*` / `Image-*.gz` | agar khud boot.img banana ho (2B) | wahi release |
| **`stock-boot.img`** | rollback ka sahara + 2B ke liye reference | apne ROM ke zip se (neeche) |
| `platform-tools` | `adb`, `fastboot` | developer.android.com/tools/releases/platform-tools |
| 50-60% battery | safe flash | — |

### stock boot.img kaise nikalein

**HyperOS fastboot ROM (`.tgz`) se:**
```bash
tar -xzf <rom>.tgz
# andar images/boot.img milta hai — usko stock-boot.img naam se sambhal lo
```

**HyperOS recovery ROM (`.zip`) se:** andar `payload.bin` hota hai.
`payload-dumper-go` se:
```bash
payload-dumper-go -p boot payload.bin    # boot.img niklega
```

**LineageOS / custom ROM zip se:** zip ke andar `boot.img` seedha mil jaata hai.

**Phone se hi (root hai to):**
```bash
su -c 'dd if=/dev/block/by-name/boot of=/sdcard/stock-boot.img'
```

> Isko **kabhi delete mat karna** — bootloop me yahi bachata hai.

---

## 2C. Ready-made `boot.img` (jab build ne banayi ho)

Agar aapne build ke waqt `boot_img_url` (apne ROM ka `boot.img`) diya, to artifact me
`boot.img` bhi aati hai — wo **aapki hi stock image** hai jisme sirf kernel payload
badla gaya hai. Header (cmdline/os_version/page size), ramdisk aur tail (dtb, agar hai)
**byte-for-byte** wahi hain; CI khud verify karta hai.

```bash
fastboot flash boot boot.img
fastboot reboot
```

Ye fastboot wala sabse seedha raasta hai. AnyKernel3 zip (2A) bhi saath aata hai —
dono me se koi ek use karo, dono me sirf kernel badalta hai.

## 2A. Install: recovery-flashable zip (recommended)

Jo `AnyKernel3-*.zip` artifact me aata hai wo **recovery se flash hone wala** standard
package hai (AnyKernel3, pinned commit). Isme `META-INF/com/android/update-binary`,
`tools/ak3-core.sh`, `anykernel.sh` aur `Image` hote hain — CI har build par inki
structure + permissions check karta hai.

**Tarika 1 — custom recovery (TWRP / SHRP / OrangeFox):**
1. Zip phone/SD card ya USB-OTG me rakho.
2. Recovery me boot karo → **Install** → `AnyKernel3-*.zip` chuno → swipe to confirm.
3. Script khud: current slot detect → `boot` split → **sirf kernel** replace → repack →
   flash. Screen par `Installing gold-custom …` phir `Done` dikhega.
4. Reboot to system.

**Tarika 2 — KernelFlasher app (recovery ki zaroorat nahi, root chahiye):**
App → "Flash kernel / AK3 zip" → zip chuno → Flash → Reboot.

Dono me same zip chalta hai, aur `vendor_boot` / `dtbo` / `vbmeta` ko haath nahi lagta.

### Agar recovery "unsupported device" bole

Zip me `do.devicecheck=1` hai aur allowed names: `gold`, `xiaomi_gold`, `gold_global`,
`gold_eea`, `Redmi Note 13 5G`. Aapke ROM ka `ro.product.device` in se match nahi kar
raha to flash abort hoga — tab **2C** (ready-made `boot.img`, fastboot se) use karo.

### Recovery se flash ke baad check

```bash
adb shell uname -r     # …-4k-gold dikhna chahiye
```

## 2B. Optional: khud `boot.img` banana (advanced)

Agar aap fastboot se hi flash karna chahte ho, boot image khud banao — par **apne
stock boot ko reference** rakh ke, andaze se nahi:

```bash
# 1) stock boot se header ki values dekho (base, pagesize, cmdline, dtb)
#    AOSP ke mkbootimg/unpack_bootimg, ya kisi bhi boot.img inspector se
unpack_bootimg --boot_img stock-boot.img --out stock/

# 2) humara kernel daal ke repack karo (values stock se hi lo)
mkbootimg --header_version 4 \
  --kernel Image-gold-custom-*.gz \
  --cmdline "bootopt=64S3,32N2,64N2" \
  --os_version 16.0.0 --os_patch_level 2026-01 \
  --output boot.img
```

Do baatein dhyan me rakho:
- Agar stock boot me **dtb** hai (`unpack_bootimg` ke output me `dtb` file), to usko
  `--dtb stock/dtb` se saath do — warna boot fail ho sakta hai.
- Humari build ka kernel version `6.6.118-android15-8` hona chahiye
  (`strings Image-* | grep 'Linux version'`), warna vendor modules load nahi honge.

Isi wajah se **2A (AnyKernel3) default recommendation hai** — usme ye guess-work hi nahi hai.

### Agar phone "dm-verity / device is corrupt" dikhaye

Ye AVB ka message hai (kernel badalne se hash match nahi karta). Verification
ek baar band karo — **apne ROM ka `vbmeta.img`** chahiye (ROM zip me hota hai):

```bash
fastboot --disable-verity --disable-verification flash vbmeta vbmeta.img
fastboot reboot
```

Ye step sirf ek baar karna hota hai. Baad me dobara kernel flash karne par
zaroorat nahi.

---

## 3. Root activate karna (agar `root_flavor=kernelsu` / `ksu-next` build liya hai)

Build me **kernel ke andar** root driver hota hai — isliye Magisk jaisa boot
patching nahi karna. Sirf manager app chahiye:

1. **KernelSU** ka APK install karo (`tiann/KernelSU` releases) — default
   `root_flavor=kernelsu` isi ke liye hai.
   `root_flavor=ksu-next` build liya ho to **KernelSU-Next** ka APK.
2. App kholo → status me **"Working" / "Kernel: installed"** dikhna chahiye.
   Agar "Not installed" dikhe → galat KMI/version ka kernel flash ho gaya hai
   (neeche troubleshooting), ya APK kernel ke KSU version se match nahi karta.
3. SUSFS userspace (hiding ke liye): manager me susfs4ksu ka
   `ksu_module_susfs` module zip flash karo, phir reboot. Kernel side SUSFS
   pehle se image me hai (`CONFIG_KSU_SUSFS=y`).

> SUSFS kernel me hai, par usko control karne wala userspace module alag hota hai.

---

## 4. Recovery se flash (KernelFlasher ke bina)

1. `AnyKernel3-*.zip` ko phone/SD card me rakho.
2. Recovery (TWRP / stock recovery with sideload) me boot karo.
3. Install → zip chuno (ya `adb sideload AnyKernel3-*.zip`).
4. Reboot.

Same zip, same kaam — sirf tool alag hai. `vendor_boot` yahan bhi touch nahi hota.

---

## 5. Kuch galat ho gaya? (troubleshooting)

| Lakshan | Matlab | Fix |
|---|---|---|
| Logo par atka, boot nahi | kernel/ROM mismatch, ya khud banaye boot.img me header/dtb galat | stock boot.img flash karo; phir AnyKernel3 zip (2A) se install karo — usme header/dtb guess nahi hota |
| Black screen, phone vibrate karta hai | vendor modules load nahi hue (KMI/CRC) | stock boot wapas; build me `crc_stub=true` try karo, ya `stock_symvers_url` de ke CRC check chalao |
| WiFi/BT band | `MODULE_SIG_PROTECT` ya protected-exports issue | humne already off rakha hai; dmesg me `module verification failed` dekho |
| "dm-verity / corrupt" | AVB hash mismatch | section 2 ka `vbmeta` command |
| Fastboot me "FAILED (remote: not allowed)" | bootloader locked | Mi Unlock se unlock karo |
| Fastboot device hi nahi dikhta | driver/cable | dusra cable/port, `fastboot devices`, Windows par Google USB driver |
| Manager app: "Not installed" | root driver missing / KMI drift | `verify-build.sh` ka output dekho, `CONFIG_KSU=y` hona chahiye |

Bootloop me bhi **fastboot** hamesha kaam karta hai (MTK par recovery me jaane ki
zaroorat nahi) — isliye stock boot.img ka hona hi sabse bada insurance hai.

---

## 6. Kya kabhi mat karna

- `fastboot flash vendor_boot` / `dtbo` / `super` — humne wo banaye hi nahi.
- `fastboot flashing lock` jab tak 100% stock na ho jao (lock karne se pehle
  stock boot + vbmeta wapas).
- Purane/dusre ROM ka `boot.img` apne ROM par flash karna (KMI mismatch).
- Khud banaye boot.img me stock ka dtb bhool jana (section 2B) — pehla boot fail hoga.
- Battery 30% se neeche flash karna.

---

## 7. Flash ke baad check

```bash
adb shell uname -r
# 6.6.118-android15-8-g<sha>-ab...
# ...-4k-gold par khatam hona chahiye (humara custom suffix)
```

Root check:
```bash
adb shell su -c id
# uid=0(root) aana chahiye (manager me grant karne ke baad)
```

Feature check (kernel side, bina root ke bhi):
```bash
adb shell 'zcat /proc/config.gz | grep -E "WIREGUARD|NTFS3|EXFAT|LRU_GEN|PSI=|SCHEDUTIL"'
adb shell 'ls /sys/fs/pstore'          # pstore/ramoops mount
adb shell 'cat /sys/power/suspend_stats/success'
```

---

## 8. Runtime profiles (root ke baad, optional)

Kernel me koi fixed performance policy nahi hai — balanced/gaming/sustained
**runtime** profiles hain, aur har value reversible hai:

```bash
adb push gold-profiles.sh /data/local/tmp/          # artifact ke andar milta hai
adb shell su -c 'sh /data/local/tmp/gold-profiles.sh status'
adb shell su -c 'sh /data/local/tmp/gold-profiles.sh gaming'      # freq ramp-up + top-app uclamp
adb shell su -c 'sh /data/local/tmp/gold-profiles.sh sustained'   # ~80% max freq cap (heat/battery)
adb shell su -c 'sh /data/local/tmp/gold-profiles.sh balanced'    # wapas stock-like
adb shell su -c 'sh /data/local/tmp/gold-profiles.sh charge-limit 80'
adb shell su -c 'sh /data/local/tmp/gold-profiles.sh restore'     # snapshot se sab wapas
```

- Governor `schedutil` ke alawa kuch bhi ho to script **mana** kar deti hai
  (refuse), thermal zones/trips ko ye script kabhi touch nahi karti.
- Backup `/data/adb/gold-profiles/backup` me rehta hai; `restore` wahi wapas likhta hai.
- Charge limit sirf tab kaam karti hai jab aapke ROM ka vendor charger driver
  percentage node expose kare (`charge_control_end_threshold`); warna script saaf
  saaf bol deti hai ki kuch nahi likha — guess karke current node nahi chhedta.
