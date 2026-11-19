#!/usr/bin/env bash
# Package the built kernel into everything needed to try it on gold.
#
# Outputs:
#   Image-<name> / Image-<name>.gz  <- the raw kernel (the actual deliverable)
#   boot.img                        <- only when STOCK_BOOT is given: the user's own
#                                      boot image with nothing but the kernel swapped
#   AnyKernel3-<name>-<ver>.zip     <- recovery-flashable zip (TWRP/SHRP/KernelFlasher)
#   Image / Image.gz                <- raw kernel, for manual repacking
#   NOTES.txt / SHA256SUMS.txt      <- what this is, how to flash, rollback
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
    python3 "$SCRIPT_DIR/bootimg.py" repack "$STOCK_BOOT" "$IMAGE_GZ" "$OUTDIR/boot.img" "$PART_SIZE" \
        || { echo "::error::could not repack the stock boot image"; exit 1; }
    python3 "$SCRIPT_DIR/bootimg.py" verify "$OUTDIR/boot.img" "$IMAGE_GZ" "$STOCK_BOOT" "$PART_SIZE" \
        || { echo "::error::repacked boot.img failed verification"; exit 1; }
    ls -lh "$OUTDIR/boot.img" | sed 's/^/    /'
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
    rm -rf "$AK3/.git" "$AK3/README.md"
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

ui_print " Installing $KERNEL_NAME $KVER"
ui_print " gold: boot carries the kernel only; vendor_boot is untouched"

split_boot
if [ -f "split_img/ramdisk.cpio" ]; then
    unpack_ramdisk
    write_boot
else
    flash_boot
fi

ui_print " Done. Reboot to system."
AKSH
    AKZIP="$OUTDIR/AnyKernel3-${BASE}.zip"
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
             tools/ak3-core.sh anykernel.sh Image; do
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
    hits="$(unzip -p "$AKZIP" Image | strings | grep -c "$KVER" || true)"
    [ "${hits:-0}" -gt 0 ] || { echo "::error::wrong Image packed into the zip"; exit 1; }
    ls -lh "$AKZIP" | sed 's/^/    /'
fi

# ------------------------------------------------------------------ raw kernel
if has image; then
    cp -f "$IMAGE" "$OUTDIR/Image-$BASE"
    cp -f "$IMAGE_GZ" "$OUTDIR/Image-$BASE.gz"
    echo "==> raw kernel: Image-$BASE / Image-$BASE.gz"
fi

# ------------------------------------------------------- runtime tools + docs
for f in "$SCRIPT_DIR/../tools/gold-profiles.sh" "$SCRIPT_DIR/../docs/FEATURES.md"; do
    [ -f "$f" ] && cp -f "$f" "$OUTDIR/" && echo "==> shipped $(basename "$f")"
done
chmod +x "$OUTDIR/gold-profiles.sh" 2>/dev/null || true

# the intermediate Image.gz is only a build aid; the artifact is Image-<base>.gz
[ "$GEN_GZ" = 1 ] && rm -f "$OUTDIR/Image.gz"

# ------------------------------------------------------------------- notes
{
    echo "GoldenEra v1 - custom kernel for the Redmi Note 13 5G (gold)"
    echo "author: 𝙴𝚅𝙾𝚁𝙴𝚉"
    echo "kernel: $KVER"
    echo "built:  $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "root flavor: ${EFFECTIVE_ROOT_FLAVOR:-none} (susfs=${EFFECTIVE_USE_SUSFS:-false})"
    echo "ksu: ${KSU_SHA:-n/a}"
    echo
    if [ -f "$OUTDIR/boot.img" ]; then
        echo "boot.img IS included - it is YOUR stock boot image with only the kernel"
        echo "payload swapped. Header/cmdline/ramdisk/tail (dtb) are byte-identical to"
        echo "the image you supplied, so there is nothing guessed:"
        echo "  fastboot flash boot boot.img"
        echo "  fastboot reboot"
        echo
    else
        echo "THIS ARTIFACT IS THE KERNEL ONLY (raw Image / Image.gz + AnyKernel3 zip)."
        echo "No boot.img was packed (no stock boot image was given) - see docs/FLASH.md."
        echo
    fi
    echo "INSTALL (recovery-flashable zip):"
    echo "  TWRP/SHRP  : Install -> AnyKernel3-*.zip"
    echo "  app        : KernelFlasher -> Flash kernel / AK3 zip (needs root)"
    echo "  Both split your existing boot and swap ONLY the kernel, so your stock"
    echo "  header/dtb/ramdisk stay byte-identical. vendor_boot is never touched."
    echo
    echo "ROLLBACK - keep your ROM's stock boot.img and:"
    echo "  fastboot flash boot <stock-boot.img>"
    echo "  fastboot reboot"
    echo
    echo "If the phone shows a dm-verity / 'device is corrupt' screen, disable"
    echo "verification once with your ROM's vbmeta:"
    echo "  fastboot --disable-verity --disable-verification flash vbmeta vbmeta.img"
    echo
    echo "Runtime profiles (after root):"
    echo "  adb push gold-profiles.sh /data/local/tmp/ && adb shell su -c 'sh /data/local/tmp/gold-profiles.sh gaming'"
    echo "  gold-profiles.sh {status|balanced|gaming|sustained|charge-limit 80|restore}"
    echo
    echo "Feature map: FEATURES.md (what is in the Image, what is vendor-side, what is refused)."
    echo "Read docs/FLASH.md (Hinglish) before the first flash."
} >"$OUTDIR/NOTES.txt"

( cd "$OUTDIR" && sha256sum boot.img AnyKernel3-*.zip Image-* 2>/dev/null >SHA256SUMS.txt || true )

echo "==> artifacts in $OUTDIR:"
ls -lh "$OUTDIR"
echo "==> sha256:"
cat "$OUTDIR/SHA256SUMS.txt" 2>/dev/null || true
