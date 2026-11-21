#!/usr/bin/env bash
# Package the built kernel into everything needed to try it on gold.
#
# Outputs - exactly two files, nothing else:
#   "<label> kernel <ver>.zip"   <- recovery-flashable (TWRP/SHRP/KernelFlasher),
#                                   AnyKernel3 tree rebranded to 𝙴𝚟𝚘𝚛𝚎𝚣 ✩
#   "<label> Boot.img(A16)"      <- only when STOCK_BOOT is given: the user's own boot
#                                   image with nothing but the kernel payload swapped
#
# Labels (BRAND_LABEL / BOOT_LABEL) come from the workflow, so the same script produces
# "Havoc-GoldenEra Perf kernel 6.6.118.zip" and "Golden Era V1 kernel 6.6.118.zip".
#
# gold's boot partition is header v4 with ramdisk_size = 0 (there is no init_boot
# on this device; the ramdisk lives in vendor_boot), kernel = Image.gz, page size
# 4096, cmdline "bootopt=64S3,32N2,64N2", partition size 64 MiB. Those values
# come from the LineageOS device tree for gold (BoardConfig.mk) and can be
# No boot.img is packed here: this repo ships the kernel, nothing else.
#
# Usage: package.sh
# Env:   DIST (bazel dist dir) | IMAGE / IMAGE_GZ, OUTDIR, KERNEL_NAME,
#        FORMATS (comma list), ROOT_FLAVOR, STOCK_BOOT (optional), VENDOR_BOOT (optional),
#        PART_SIZE
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DIST="${DIST:-}"
OUTDIR="${OUTDIR:-$PWD/artifacts}"
KERNEL_NAME="${KERNEL_NAME:-GoldenEra}"
BRAND_LABEL="${BRAND_LABEL:-$KERNEL_NAME}"     # "Havoc-GoldenEra Perf" / "Golden Era V1"
BOOT_LABEL="${BOOT_LABEL:-$BRAND_LABEL}"       # "Havoc-GoldenEra"     / "Golden Era V1"
FORMATS="${FORMATS:-anykernel,image}"
STOCK_BOOT="${STOCK_BOOT:-}"
VENDOR_BOOT="${VENDOR_BOOT:-}"
PART_SIZE="${PART_SIZE:-67108864}"        # BOARD_BOOTIMAGE_PARTITION_SIZE for gold
case ",$FORMATS," in
    *,bootimg,*)
        echo "::warning::format 'bootimg' was removed from this project (kernel only); ignoring it"
        FORMATS="$(printf '%s' "$FORMATS" | sed -e 's/\<bootimg,\?//' -e 's/,\?bootimg//')"
        [ -n "$FORMATS" ] && [ "$FORMATS" != "," ] || FORMATS="image"
        echo "    using formats: $FORMATS"
        ;;
esac

mkdir -p "$OUTDIR"
has() { case ",$FORMATS," in *",$1,"*) return 0 ;; *) return 1 ;; esac; }

# ------------------------------------------------------------------ inputs
IMAGE="${IMAGE:-}"
IMAGE_GZ="${IMAGE_GZ:-}"
if [ -z "$IMAGE" ] && [ -n "$DIST" ]; then IMAGE="$DIST/Image"; fi
if [ -z "$IMAGE_GZ" ] && [ -n "$DIST" ]; then IMAGE_GZ="$DIST/Image.gz"; fi
[ -f "$IMAGE" ] || { echo "::error::Image not found (IMAGE/DIST unset?)"; exit 1; }

KVER="$(strings "$IMAGE" | grep -oE 'Linux version [0-9][^ ]*' | head -n1 | cut -d' ' -f3)"
[ -n "$KVER" ] || { echo "::error::cannot read kernel version from $IMAGE"; exit 1; }
KVER_SHORT="$(printf '%s' "$KVER" | grep -oE '^[0-9]+\.[0-9]+\.[0-9]+')"
[ -n "$KVER_SHORT" ] || KVER_SHORT="$KVER"
BASE="${KERNEL_NAME}-${KVER}"
echo "==> kernel:  $KVER"
echo "==> formats: $FORMATS"

GEN_GZ=0
if [ ! -f "$IMAGE_GZ" ]; then
    case "$IMAGE" in
        *.gz) IMAGE_GZ="$IMAGE" ;;
        *) IMAGE_GZ="$OUTDIR/Image.gz"; gzip -9n -c "$IMAGE" >"$IMAGE_GZ"
           GEN_GZ=1; echo "    compressed Image -> Image.gz" ;;
    esac
fi

# --------------------------------------------------------------- boot.img
# Built ONLY from the user's own stock boot image, and only by swapping the kernel
# payload: header (cmdline/os_version/page size), ramdisk and trailing bytes (the
# dtb, if the ROM puts one there) are copied byte for byte. No guessing.
if [ -n "$STOCK_BOOT" ] && [ -f "$STOCK_BOOT" ]; then
    echo "==> boot.img: repacking the provided stock boot image"
    python3 "$SCRIPT_DIR/bootimg.py" inspect "$STOCK_BOOT" | sed 's/^/      /'
    if [ -n "$VENDOR_BOOT" ] && [ -f "$VENDOR_BOOT" ]; then
        echo "==> vendor_boot.img (reference only, never modified)"
        python3 "$SCRIPT_DIR/bootimg.py" vendor "$VENDOR_BOOT" | sed 's/^/      /'
    fi
    BOOT_OUT="$OUTDIR/${BOOT_LABEL} Boot.img(A16)"
    python3 "$SCRIPT_DIR/bootimg.py" repack "$STOCK_BOOT" "$IMAGE_GZ" "$BOOT_OUT" "$PART_SIZE" \
        || { echo "::error::could not repack the stock boot image"; exit 1; }
    python3 "$SCRIPT_DIR/bootimg.py" verify "$BOOT_OUT" "$IMAGE_GZ" "$STOCK_BOOT" "$PART_SIZE" \
        || { echo "::error::repacked boot.img failed verification"; exit 1; }
    ls -lh "$BOOT_OUT" | sed 's/^/    /'
else
    echo "==> boot.img: not built (no stock boot image provided)"
    echo "    this build ships the kernel only; see docs/FLASH.md"
fi

# --------------------------------------------------------------- AnyKernel3
if has anykernel; then
    echo "==> building AnyKernel3 zip - flashable from a recovery (TWRP/SHRP) or KernelFlasher"
    AK3="$(mktemp -d)"
    trap 'rm -rf "$AK3"' EXIT
    # Pinned: a zip is a *flashing* artefact, so a moving upstream default branch is
    # not an acceptable input. Override with AK3_REF if the pin ever breaks.
    AK3_REPO="https://github.com/osm0sis/AnyKernel3"
    AK3_REF="${AK3_REF:-41f04bdb4ee30a44e429c2c1131d5e8bb32b15f1}"
    git init -q "$AK3" && git -C "$AK3" remote add origin "$AK3_REPO" \
        || { echo "::error::could not prepare the AnyKernel3 checkout"; exit 1; }
    if git -C "$AK3" fetch -q --depth=1 origin "$AK3_REF" 2>/dev/null; then
        git -C "$AK3" checkout -q FETCH_HEAD
        echo "    AnyKernel3 @ $(git -C "$AK3" rev-parse --short HEAD) (pinned)"
    else
        echo "::warning::pinned AnyKernel3 $AK3_REF unavailable, falling back to the default branch"
        git -C "$AK3" fetch -q --depth=1 origin HEAD && git -C "$AK3" checkout -q FETCH_HEAD \
            || { echo "::error::AnyKernel3 clone failed"; exit 1; }
    fi
    # Trim the upstream tree to what a boot-only flash needs. The image payload is
    # ~97% of the zip, so this is about a clean recovery package, not size:
    #   .github / LICENSE / README   - repository metadata, nothing a recovery reads
    #   patch/ ramdisk/ modules/     - empty placeholders for do.systemless/do.modules,
    #                                  both of which are 0 in our anykernel.sh
    #   tools/fec tools/magiskpolicy - not referenced by ak3-core.sh at all
    # Everything else stays: busybox, magiskboot, httools/lptools/snapshotupdater are
    # used by write_boot() and by flash_boot() (the no-ramdisk path we still allow).
    rm -rf "$AK3/.git" "$AK3/.github" "$AK3/README.md" "$AK3/LICENSE" \
           "$AK3/patch" "$AK3/ramdisk" "$AK3/modules"
    rm -f  "$AK3/tools/fec" "$AK3/tools/magiskpolicy"

    # Rebrand what the recovery actually prints. Everything the user sees while flashing
    # comes from update-binary (the banner) and our anykernel.sh; upstream's author tags
    # and XDA lines are removed rather than left in place.
    UPD="$AK3/META-INF/com/google/android/update-binary"
    sed -i -e 's/^# AnyKernel3 Backend (DO NOT CHANGE)$/# 𝙴𝚟𝚘𝚛𝚎𝚣 ✩ recovery backend (do not change)/' \
           -e 's/anykernel3-/havoc-/g' "$UPD"
    sed -i -e 's/^# osm0sis @ xda-developers$/# 𝙴𝚟𝚘𝚛𝚎𝚣 ✩/' \
           -e 's/^author=.*/author=𝙴𝚟𝚘𝚛𝚎𝚣 ✩/' \
           -e 's/AnyKernel3 by osm0sis @ xda-developers/𝙴𝚟𝚘𝚛𝚎𝚣 ✩/' \
           -e '/xda-developers/d' \
           -e '/osm0sis/d' "$UPD"
    sed -i -e '/xda-developers/d' -e '/osm0sis/d' "$AK3/tools/ak3-core.sh"
    # no "AnyKernel3" left in anything a recovery prints
    if grep -qi 'anykernel3' "$UPD"; then
        echo "::warning::update-binary still mentions AnyKernel3 in its output"
    fi
    cp -f "$SCRIPT_DIR/../tools/havoc-boot.sh" "$AK3/havoc-boot.sh"
    cp -f "$IMAGE" "$AK3/Image"
    cat >"$AK3/anykernel.sh" <<AKSH
### AnyKernel3 Ramdisk Mod Script
## $KERNEL_NAME for Xiaomi Redmi Note 13 5G (gold) - GKI android15-6.6 4K

properties() { '
kernel.string=$KERNEL_NAME $KVER (gold, GTI android15-6.6)
do.devicecheck=1
do.modules=0
do.systemless=0
do.cleanup=1
do.cleanuponabort=0
device.name1=gold
device.name2=xiaomi_gold
device.name3=gold_global
device.name4=gold_eea
device.name5=Redmi Note 13 5G
supported.versions=
supported.patchlevels=
supported.vendorpatchlevels=
'; } # end properties

### AnyKernel install
BLOCK=boot
IS_SLOT_DEVICE=auto
RAMDISK_COMPRESSION=auto
PATCH_VBMETA_FLAG=auto
NO_MAGISK_CHECK=1

. tools/ak3-core.sh

ui_print " " "𝙴𝚟𝚘𝚛𝚎𝚣 ✩  $KERNEL_NAME $KVER" " "
ui_print " gold: boot carries the kernel only; vendor_boot is untouched"

split_boot
if [ -f "split_img/ramdisk.cpio" ]; then
    unpack_ramdisk
    write_boot
else
    flash_boot
fi

# HAVOC default ceilings: drop the boot script where KernelSU/BakaSU runs services.
# Recovery often cannot see an encrypted /data - then the script simply is not installed
# and the kernel still runs, only without the boot-time ceilings.
if [ -d /data/adb ]; then
    ui_print " Installing boot-time frequency ceilings"
    mkdir -p /data/adb/service.d
    cp -f havoc-boot.sh /data/adb/service.d/99-havoc.sh
    chmod 0755 /data/adb/service.d/99-havoc.sh
else
    ui_print " /data not mounted - boot ceilings skipped"
    ui_print " flash the same zip from the app for the boot script to be installed"
fi

ui_print " " "𝙴𝚟𝚘𝚛𝚎𝚣 ✩  Done. Reboot to system." " "
AKSH
    AKZIP="$OUTDIR/${BRAND_LABEL} kernel ${KVER_SHORT}.zip"
    chmod +x "$AK3/tools/"* "$AK3/META-INF/com/google/android/update-binary" 2>/dev/null || true
    ( cd "$AK3" && zip -r9 -q "$AKZIP" . -x '.git/*' )
    ak_sh="$(unzip -p "$AKZIP" anykernel.sh)"
    case "$ak_sh" in
        *"BLOCK=boot"*) : ;;
        *) echo "::error::packed zip is missing anykernel.sh / BLOCK=boot"; exit 1 ;;
    esac
    # A zip that a recovery cannot actually run is worse than no zip: check the
    # structure the recovery executes, not just that the file exists.
    for f in META-INF/com/google/android/update-binary META-INF/com/google/android/updater-script \
             tools/ak3-core.sh anykernel.sh havoc-boot.sh Image; do
        unzip -l "$AKZIP" "$f" >/dev/null 2>&1 || { echo "::error::AnyKernel3 zip is missing $f"; exit 1; }
    done
    if unzip -Z "$AKZIP" | grep -E 'update-binary$' | grep -qv 'rwx'; then
        echo "::error::update-binary inside the zip is not executable (0755) - recovery would abort"
        exit 1
    fi
    printf '%s' "$ak_sh" | sh -n || { echo "::error::anykernel.sh does not parse"; exit 1; }
    printf '%s' "$ak_sh" | grep -q 'ak3-core.sh' || { echo "::error::anykernel.sh does not source ak3-core.sh"; exit 1; }
    printf '%s' "$ak_sh" | grep -qE 'flash_boot|write_boot' || { echo "::error::anykernel.sh has no install path"; exit 1; }
    echo "    recovery-flashable structure verified (update-binary 0755, ak3-core.sh, anykernel.sh, Image)"
    # the trim must never remove a tool ak3-core.sh actually calls
    missing_tool=""
    for t in $(grep -oE '(magiskboot|magiskpolicy|busybox|httools_static|lptools_static|snapshotupdater_static|fec)' \
                   "$AK3/tools/ak3-core.sh" | sort -u); do
        [ -e "$AK3/tools/$t" ] || missing_tool="$missing_tool $t"
    done
    if [ -n "$missing_tool" ]; then
        echo "::error::trimmed zip is missing tool(s):$missing_tool"
        exit 1
    fi
    echo "    every tool ak3-core.sh calls is still inside the zip"
    hits="$(unzip -p "$AKZIP" Image | strings | grep -c "$KVER" || true)"
    [ "${hits:-0}" -gt 0 ] || { echo "::error::wrong Image packed into the zip"; exit 1; }
    ls -lh "$AKZIP" | sed 's/^/    /'
fi

# the generated Image.gz is a build aid, never an artifact
if [ "$GEN_GZ" = 1 ]; then rm -f "$IMAGE_GZ"; fi

# --------------------------------------------------------------- final check
# Only the two deliverables may end up in OUTDIR: a release that also carries raw
# kernels, notes and helpers is exactly what we were told to stop doing.
expected_zip="${BRAND_LABEL} kernel ${KVER_SHORT}.zip"
expected_boot="${BOOT_LABEL} Boot.img(A16)"
leftovers=""
for f in "$OUTDIR"/*; do
    name="$(basename "$f")"
    if [ "$name" = "$expected_zip" ]; then continue; fi
    if [ "$name" = "$expected_boot" ] && [ -n "$STOCK_BOOT" ]; then continue; fi
    leftovers="$leftovers $name"
done
if [ -n "$leftovers" ]; then
    echo "::error::unexpected files in $OUTDIR:$leftovers (only the zip and the boot.img ship)"
    exit 1
fi

if has anykernel; then
    [ -f "$OUTDIR/$expected_zip" ] || { echo "::error::the recovery zip was not produced"; exit 1; }
fi
if [ -n "$STOCK_BOOT" ]; then
    [ -f "$OUTDIR/$expected_boot" ] || { echo "::error::the boot image was not produced"; exit 1; }
fi

echo "==> artifacts in $OUTDIR:"
ls -lh "$OUTDIR" | sed 's/^/    /'
