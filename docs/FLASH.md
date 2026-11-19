# Flash karne ki guide (Hinglish) — gold custom kernel

> **Pehle ye padh lo:** custom kernel flash karna = apni zimmedari. Bootloader
> unlocked hona chahiye. Ek **stock boot.img** zaroor rakhna, warna bootloop me
> phone fastboot se hi theek hoga. Data wipe ki zaroorat nahi hoti, par backup
> rakhna achhi aadat hai.

Ye guide **Redmi Note 13 5G (codename `gold`)** ke liye hai, Android 16 / HyperOS 3
ya gold ke kisi custom ROM ke saath. Device ki shakal:

```
boot        = sirf kernel (header v4, ramdisk 0, Image.gz)   <-- hum yahi badalte hain
vendor_boot = dtb + vendor ramdisk (modules)
vendor_dlkm = MediaTek ke prebuilt modules
init_boot   = is device par hai hi nahi
```

Iska matlab: **sirf `boot.img` flash karna hai**. `vendor_boot`, `vbmeta`, `dtbo`
ko haath mat lagao — humne unhe touch hi nahi kiya hai.

---

## 0. Ek nazar me (TL;DR)

```bash
# 1) phone fastboot me
adb reboot bootloader

# 2) check
fastboot devices          # serial dikhna chahiye

# 3) flash (artifacts se boot.img)
fastboot flash boot boot.img
fastboot reboot
```

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
| `boot.img` (humara artifact) | custom kernel | GitHub Actions run ka artifact |
| **`stock-boot.img`** | rollback ka sahara | apne ROM ke zip ke andar se (neeche dekho) |
| PC/laptop + USB cable | fastboot | — |
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

> `boot.img` sirf ~30-60 MB ka hota hai, isliye Google Drive/Telegram par rakhna
> aasan hai. Isko **kabhi delete mat karna**.

---

## 2. Flash (fastboot, sabse reliable tarika)

```bash
adb reboot bootloader
fastboot devices
fastboot flash boot boot.img
# output me "OKAY" aana chahiye
fastboot reboot
```

Pehla boot **2-5 minute** le sakta hai (dalvik/ART dobara compile hota hai).
Ghabrana nahi.

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

## 4. AnyKernel3 zip (rooted phone, bina PC)

Agar phone already rooted hai:

1. `AnyKernel3-*.zip` ko phone me copy karo.
2. **KernelFlasher** app (FatalBullet) kholo → "Flash kernel / AK3 zip" → zip chuno.
3. App khud `boot` partition unpack → kernel replace → repack karta hai, isliye
   tumhare ROM ka dtb/header jaisa hai waisa hi rehta hai.
4. Reboot.

Isme `vendor_boot` bhi touch nahi hota.

---

## 5. Kuch galat ho gaya? (troubleshooting)

| Lakshan | Matlab | Fix |
|---|---|---|
| Logo par atka, boot nahi | kernel/ROM mismatch ya galat header | stock boot.img flash karo, `stock_boot_url` de ke dobara build |
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
