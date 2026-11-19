#!/usr/bin/env bash
# Package the built kernel into everything needed to try it on gold.
#
# Outputs:
#   Image-<name> / Image-<name>.gz  <- the raw kernel (the actual deliverable)
#   AnyKernel3-<name>-<ver>.zip     <- flash from a rooted phone (KernelFlasher)
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
#        FORMATS (comma list), ROOT_FLAVOR
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DIST="${DIST:-}"
OUTDIR="${OUTDIR:-$PWD/artifacts}"
KERNEL_NAME="${KERNEL_NAME:-gold-custom}"
FORMATS="${FORMATS:-anykernel,image}"
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

# NOTE: there is deliberately no boot.img step. Packing one means guessing
# header/cmdline/os_version and (on gold) the dtb, and a wrong guess is a
# non-booting phone. The artifact is the kernel; packing it into a boot image is
# the user's call, with their own stock boot.img as the reference.

# --------------------------------------------------------------- AnyKernel3
if has anykernel; then
    echo "==> building AnyKernel3 zip (for KernelFlasher / recovery on a rooted phone)"
    AK3="$(mktemp -d)"
    trap 'rm -rf "$AK3"' EXIT
    git clone --depth=1 -q https://github.com/osm0sis/AnyKernel3 "$AK3" \
        || { echo "::error::AnyKernel3 clone failed"; exit 1; }
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
device.name2=Redmi Note 13 5G
device.name3=xiaomi_gold
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
    echo "gold custom kernel - $KVER"
    echo "built: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "root flavor: ${EFFECTIVE_ROOT_FLAVOR:-none} (susfs=${EFFECTIVE_USE_SUSFS:-false})"
    echo "ksu: ${KSU_SHA:-n/a}"
    echo
    echo "THIS ARTIFACT IS THE KERNEL ONLY (raw Image / Image.gz + AnyKernel3 zip)."
    echo "No boot.img is packed - see docs/FLASH.md for why."
    echo
    echo "INSTALL (rooted phone, KernelFlasher app or a recovery):"
    echo "  flash AnyKernel3-*.zip - it splits your existing boot and swaps only the kernel,"
    echo "  so your stock header/dtb/ramdisk stay exactly as they are"
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

( cd "$OUTDIR" && sha256sum AnyKernel3-*.zip Image-* 2>/dev/null >SHA256SUMS.txt || true )

echo "==> artifacts in $OUTDIR:"
ls -lh "$OUTDIR"
echo "==> sha256:"
cat "$OUTDIR/SHA256SUMS.txt" 2>/dev/null || true
