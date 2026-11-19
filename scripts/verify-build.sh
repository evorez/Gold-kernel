#!/usr/bin/env bash
# Post-build gate: prove the Image we just built is the kernel gold expects.
#
# The config that matters is the one compiled INTO the image, so every check
# reads it back out of CONFIG_IKCONFIG instead of trusting the defconfig we wrote.
#
# Usage: verify-build.sh <gki-workspace-root>
# Env:   ROOT_FLAVOR / EFFECTIVE_USE_SUSFS / TWEAKS / EXPECTED_VERSION
set -euo pipefail

KROOT="${1:?usage: verify-build.sh <repo-root>}"
IMG=""
for cand in "$KROOT/bazel-bin/common/kernel_aarch64/Image" \
            "$KROOT"/bazel-bin/common/kernel_aarch64/Image \
            "$KROOT/out/kernel_aarch64/Image"; do
    [ -f "$cand" ] && { IMG="$cand"; break; }
done
[ -n "$IMG" ] || IMG="$(find "$KROOT" -name Image -path '*kernel_aarch64*' -not -path '*/dist/*' 2>/dev/null | head -n1)"
[ -n "$IMG" ] && [ -f "$IMG" ] || { echo "::error::built Image not found"; exit 1; }
echo "==> Image: $IMG ($(stat -c%s "$IMG") bytes)"

KVER="$(strings "$IMG" | grep -oE 'Linux version [0-9][^ ]*' | head -n1 | cut -d' ' -f3)"
[ -n "$KVER" ] || { echo "::error::no kernel version string in Image"; exit 1; }
echo "==> version: $KVER"

EXPECTED_VERSION="${EXPECTED_VERSION:-6.6.118}"
case "$KVER" in
    "$EXPECTED_VERSION"-*) : ;;
    *) echo "::error::kernel version $KVER is not $EXPECTED_VERSION.x"; exit 1 ;;
esac
case "$KVER" in
    *-android15-8*) : ;;
    *) echo "::error::KMI generation drifted: expected -android15-8 in '$KVER'"; exit 1 ;;
esac
echo "    version + KMI android15-8 OK"

CFG=/tmp/built.config
python3 - "$IMG" "$CFG" <<'PY'
import sys, zlib
img, out = sys.argv[1], sys.argv[2]
d = open(img, 'rb').read()
i = d.find(b'IKCFG_ST')
if i < 0:
    sys.exit("::error::no IKCFG_ST in Image (CONFIG_IKCONFIG disabled?)")
start = i + 8
if d[start:start + 3] != b'\x1f\x8b\x08':
    sys.exit("::error::IKCFG_ST not followed by a gzip stream")
cfg = zlib.decompressobj(16 + zlib.MAX_WBITS).decompress(d[start:])
open(out, 'wb').write(cfg)
print(f"    in-image config: {len(cfg)} bytes")
PY

need_y()   { grep -q "^CONFIG_$1=y$"          "$CFG" || { echo "::error::CONFIG_$1 must be =y"; exit 1; }; }
need_off() { grep -q "^# CONFIG_$1 is not set$" "$CFG" || { echo "::error::CONFIG_$1 must be off"; exit 1; }; }

# Stock parity - a mismatch here is the "it builds, it does not boot" class.
need_y CFI_CLANG
need_y LTO_NONE
need_y MODVERSIONS
need_y ARM64_4K_PAGES
need_off MODULE_SIG_PROTECT
need_y KPROBES
need_y KALLSYMS_ALL
echo "    4K pages, LTO_NONE, CFI_CLANG, MODVERSIONS, MODULE_SIG_PROTECT=off: OK"

# Root flavour consistency.
case "${EFFECTIVE_ROOT_FLAVOR:-none}" in
    kernelsu|ksu-next)
        need_y KSU; echo "    CONFIG_KSU=y"
        if [ "${EFFECTIVE_USE_SUSFS:-false}" = "true" ]; then
            need_y KSU_SUSFS; echo "    CONFIG_KSU_SUSFS=y"
            need_y KSU_SUSFS_SUS_MOUNT; need_y KSU_SUSFS_SUS_KSTAT
            echo "    SUSFS sus_mount + sus_kstat: on"
        fi
        ;;
    none)
        if grep -qE '^CONFIG_(KSU|KPM)=[ym]$' "$CFG"; then
            echo "::error::ROOT_FLAVOR=none but KSU/KPM is enabled"; exit 1
        fi
        echo "    no root driver, as requested"
        ;;
esac

# Tweaks actually made it in (kconfig silently drops unknown/blocked options).
if [ "${TWEAKS:-false}" = "true" ]; then
    # Hard requirements: these are the reason the tweaks exist.
    for c in TCP_CONG_BBR NET_SCH_FQ LRU_GEN LRU_GEN_ENABLED; do
        need_y "$c"
    done
    grep -q '^CONFIG_DEFAULT_TCP_CONG="bbr"$' "$CFG" \
        || { echo "::error::default TCP congestion control is not bbr"; exit 1; }
    echo "    tweaks present (bbr + fq default, MGLRU)"
    # Nice-to-have: source may be absent on some tags, warn instead of failing.
    for c in WIREGUARD NTFS3_FS; do
        grep -q "^CONFIG_$c=y$" "$CFG" || echo "::warning::CONFIG_$c did not make it into the Image (source absent for this tag?)"
    done
fi

echo "==> all build gates passed"
{
    echo "image=$IMG"
    echo "kver=$KVER"
} >>"${GITHUB_OUTPUT:-/dev/null}"
