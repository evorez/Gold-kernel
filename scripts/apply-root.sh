#!/usr/bin/env bash
# Integrate a root solution (+ optional SUSFS root hiding) into the GKI tree.
#
#   ROOT_FLAVOR=kernelsu  KernelSU (tiann) + SUSFS - the pair SUSFS is written for
#   ROOT_FLAVOR=ksu-next  KernelSU-Next v3.4.x, no in-tree SUSFS
#   ROOT_FLAVOR=none      no root at all
#
# Why KernelSU and not SukiSU Ultra (verified against upstream, CI run 44519162981):
#  * susfs4ksu ships TWO patches: the kernel-side one (50_add_susfs_in_<kmi>.patch)
#    and the root-side one (KernelSU/10_enable_susfs_for_ksu.patch) which adds the
#    SUSFS supercall dispatch and the KSU_SUSFS* Kconfig symbols. The latter is
#    maintained against tiann/KernelSU - that is the pairing upstream tests.
#  * SukiSU Ultra's `builtin` branch carries its own SUSFS dispatch code in
#    kernel/supercall/dispatch.c, but it expects the *matching* susfs4ksu headers
#    (susfs.h / susfs_def.h with selinux-hide helpers, susfs_set_sid, ...). Pin
#    them wrong and the build dies in dispatch.c:
#        error: use of undeclared identifier 'CMD_SUSFS_...'
#        error: call to undeclared function 'susfs_...'
#    Its tree is also not buildable at every revision, so a coherent
#    (KernelSU, SUSFS) pair is much easier to guarantee with tiann/KernelSU.
#  * KernelSU-Next v3.4.x ships SUSFS only as a separate LKM
#    (kernel/susfs -> susfs_guard_lkm.ko loaded by ksud), so it cannot be linked
#    into the Image; ksu-next + susfs is therefore redirected to kernelsu.
#
# Pins are a coherent pair on purpose:
#   KernelSU 64833c00 = the commit susfs4ksu's tip (f98f0822) names as its synced
#   upstream ("feat(kernel): Add LSM hook for inode_setxattr", the hook the SUSFS
#   selinux patches build on); SUSFS f98f0822 = that branch tip. KernelSU at that
#   revision also defines ksu_install_su_fd(), which the 50_ patch's exec.c hunk
#   calls - an older KSU tree fails to link instead.
#
# Usage: apply-root.sh <gki-workspace-root>        (expects <root>/common/)
set -euo pipefail

KROOT="${1:?usage: apply-root.sh <repo-root-containing-common/>}"
KDIR="$KROOT/common"
DEFCONFIG="$KDIR/arch/arm64/configs/gki_defconfig"
ROOT_FLAVOR="${ROOT_FLAVOR:-kernelsu}"
USE_SUSFS="${USE_SUSFS:-true}"
KSU_REF="${KSU_REF:-}"
SUSFS_BRANCH="${SUSFS_BRANCH:-gki-android15-6.6}"
SUSFS_REF="${SUSFS_REF:-}"

[ -d "$KDIR/drivers" ] || { echo "::error::expected kernel tree at $KDIR"; exit 1; }

set_y() {
    local key="$1"
    sed -i "/^# CONFIG_${key} is not set$/d; /^CONFIG_${key}=/d" "$DEFCONFIG"
    echo "CONFIG_${key}=y" >>"$DEFCONFIG"
}

# ---------------------------------------------------------------- no root
if [ "$ROOT_FLAVOR" = "none" ]; then
    sed -i -E '/^CONFIG_KSU[A-Z_]*=[ym]$/d; /^CONFIG_KPM=[ym]$/d' "$DEFCONFIG"
    if grep -qE '^CONFIG_(KSU|KPM)' "$DEFCONFIG"; then
        echo "::error::defconfig still enables KSU/KPM"; exit 1
    fi
    echo "==> ROOT_FLAVOR=none: clean kernel, no root driver"
    exit 0
fi

# ------------------------------------------------------- patch path manifest
# check-policy.sh needs to know which files are modified by the *vendored*
# upstream patches (SUSFS/root) vs by us. Without that, a legitimate hunk in,
# say, mm/ would look like a policy violation. Every patch we apply records the
# files it touches here, and the policy gate treats those as "reviewed upstream".
PATCH_MANIFEST="${PATCH_MANIFEST:-/tmp/gold-patch-paths.txt}"
: >"$PATCH_MANIFEST"
record_patch() { # record_patch <patch-file>
    grep -E '^\+\+\+ ' "$1" 2>/dev/null \
        | sed -E -e 's/^\+\+\+ +//' -e 's/\t.*$//' -e 's/^[ab]\///' \
        | grep -v '^/dev/null$' >>"$PATCH_MANIFEST" || true
    echo "    recorded $(grep -c . "$PATCH_MANIFEST" || true) patched path(s) for the policy gate"
}

# ---------------------------------------------------- flavor/SUSFS compatibility
if [ "$ROOT_FLAVOR" = "ksu-next" ] && [ "$USE_SUSFS" = "true" ]; then
    echo "::warning::KernelSU-Next only has SUSFS as a loadable module (not in-tree);"
    echo "::warning::switching to root_flavor=kernelsu + SUSFS, the pairing susfs4ksu maintains."
    echo "::warning::(use root_flavor=ksu-next + use_susfs=false to stay on Next)"
    ROOT_FLAVOR=kernelsu
fi

# ------------------------------------------------------------- root tree
case "$ROOT_FLAVOR" in
  kernelsu)
    KSU_URL="https://github.com/tiann/KernelSU"
    KSU_REF="${KSU_REF:-64833c005eca6a8dc3d73ec2d37d84c37e0d9ad2}"
    KSU_DIR="$KROOT/KernelSU"
    ;;
  ksu-next)
    KSU_URL="https://github.com/KernelSU-Next/KernelSU-Next"
    KSU_REF="${KSU_REF:-v3.4.2}"
    KSU_DIR="$KROOT/KernelSU-Next"
    ;;
  *) echo "::error::unknown ROOT_FLAVOR: $ROOT_FLAVOR"; exit 1 ;;
esac

echo "==> integrating $ROOT_FLAVOR (ref: $KSU_REF)"
rm -rf "$KSU_DIR"
git clone -q "$KSU_URL" "$KSU_DIR" || { echo "::error::clone of $KSU_URL failed"; exit 1; }
if ! git -C "$KSU_DIR" checkout -q "$KSU_REF" 2>/dev/null; then
    git -C "$KSU_DIR" fetch -q --all --tags
    git -C "$KSU_DIR" checkout -q "$KSU_REF" 2>/dev/null || {
        echo "::error::KSU_REF '$KSU_REF' not found in $KSU_URL. Available:"
        git -C "$KSU_DIR" for-each-ref --format='%(refname:short)' refs/remotes/origin refs/tags \
            | tail -20 | while IFS= read -r r; do echo "::error::  $r"; done
        exit 1
    }
fi
KSU_SHA="$(git -C "$KSU_DIR" rev-parse --short HEAD)"
echo "    $ROOT_FLAVOR @ $KSU_SHA"
[ -d "$KSU_DIR/kernel" ] || { echo "::error::$KSU_DIR/kernel missing - unexpected layout"; exit 1; }

# Wire the driver into the kernel the way upstream's setup.sh does. The link is
# relative to common/drivers, so "../.." is the workspace root: an absolute link
# would point outside the Bazel workspace and Kleaf would not follow it.
case "$ROOT_FLAVOR" in
    kernelsu) ksu_link="../../KernelSU/kernel" ;;
    ksu-next) ksu_link="../../KernelSU-Next/kernel" ;;
esac
ln -sfn "$ksu_link" "$KDIR/drivers/kernelsu"
grep -q 'kernelsu' "$KDIR/drivers/Makefile" \
    || echo 'obj-$(CONFIG_KSU) += kernelsu/' >>"$KDIR/drivers/Makefile"
if ! grep -q 'drivers/kernelsu/Kconfig' "$KDIR/drivers/Kconfig"; then
    # Insert before the *last* endmenu: drivers/Kconfig may nest menus, and a
    # plain `/^endmenu/i` would add a duplicate source line at every one.
    python3 - "$KDIR/drivers/Kconfig" <<'KCONF'
import sys
path = sys.argv[1]
lines = open(path, encoding="utf-8").read().splitlines()
idx = [i for i, l in enumerate(lines) if l.strip() == "endmenu"]
if not idx:
    sys.exit("::error::drivers/Kconfig has no endmenu - refusing to guess where KSU belongs")
lines.insert(idx[-1], 'source "drivers/kernelsu/Kconfig"')
open(path, "w", encoding="utf-8").write("\n".join(lines) + "\n")
print("    drivers/Kconfig: source line inserted before the last endmenu")
KCONF
fi
[ -e "$KDIR/drivers/kernelsu" ] || { echo "::error::drivers/kernelsu symlink missing"; exit 1; }
echo "    driver wired: drivers/kernelsu -> $(readlink "$KDIR/drivers/kernelsu")"

set_y KSU

# --------------------------------------- preflight: feature subsystem coherence
# Upstream breakage in kernel/feature/*.c is invisible until drivers/kernelsu is
# compiled (tens of minutes in). Check statically: every function named by a
# *_handler assignment must exist in that file, and every KSU_FEATURE_* enum
# reference must exist in kernel/include/uapi/feature.h.
missing=""
FEATURE_H="$KSU_DIR/kernel/include/uapi/feature.h"
enum_defs=""
[ -f "$FEATURE_H" ] && enum_defs="$(grep -ohE '\bKSU_FEATURE_[A-Z0-9_]+' "$FEATURE_H" | sort -u)"
for src in "$KSU_DIR"/kernel/feature/*.c "$KSU_DIR"/kernel/policy/feature.c; do
    [ -f "$src" ] || continue
    for fn in $(grep -oE '(get|set)_handler[[:space:]]*=[[:space:]]*[A-Za-z0-9_]+' "$src" \
                | sed 's/.*=[[:space:]]*//' | sort -u); do
        case "$fn" in NULL|0) continue ;; esac
        grep -qE "^[a-zA-Z_].*[[:space:]]\*?${fn}[[:space:]]*\(" "$src" \
            || missing="$missing $(basename "$src"):$fn"
    done
    [ -n "$enum_defs" ] || continue
    for r in $(grep -oE '(^|[^A-Z_])KSU_FEATURE_[A-Z0-9_]+' "$src" \
               | grep -oE 'KSU_FEATURE_[A-Z0-9_]+' | sort -u); do
        printf '%s\n' "$enum_defs" | grep -qx "$r" || missing="$missing $(basename "$src"):$r"
    done
done
if [ -n "$missing" ]; then
    echo "::error::$ROOT_FLAVOR @ $KSU_SHA is not buildable (upstream bug):"
    for m in $missing; do echo "::error::  $m"; done
    echo "::error::Pin a known-good commit with the ksu_ref input."
    exit 1
fi
echo "    feature subsystem coherent"

# ------------------------------------------------------------------ SUSFS
if [ "$USE_SUSFS" = "true" ]; then
    echo "==> integrating SUSFS (branch $SUSFS_BRANCH, ref: ${SUSFS_REF:-tip})"
    SUS="/tmp/susfs4ksu"
    rm -rf "$SUS"
    git clone -q -b "$SUSFS_BRANCH" https://gitlab.com/simonpunk/susfs4ksu.git "$SUS" \
        || { echo "::error::clone of susfs4ksu failed (gitlab.com unreachable?)"; exit 1; }
    if [ -n "$SUSFS_REF" ]; then
        git -C "$SUS" cat-file -e "${SUSFS_REF}^{commit}" 2>/dev/null \
            || { echo "::error::SUSFS_REF $SUSFS_REF not in branch $SUSFS_BRANCH"; exit 1; }
        git -C "$SUS" checkout -q --detach "$SUSFS_REF"
    fi
    echo "    susfs @ $(git -C "$SUS" rev-parse --short HEAD)"
    SUSFS_VER="$(grep -m1 'SUSFS_VERSION' "$SUS/kernel_patches/include/linux/susfs.h" 2>/dev/null | cut -d'"' -f2 || true)"
    [ -n "$SUSFS_VER" ] && echo "    susfs version: $SUSFS_VER"

    # kernel side: fs/susfs.c, include/linux/susfs{,_def}.h, hooks in fs/*, mm/*, ...
    cp -f "$SUS"/kernel_patches/fs/* "$KDIR/fs/"
    cp -f "$SUS"/kernel_patches/include/linux/* "$KDIR/include/linux/"
    for f in "$SUS"/kernel_patches/fs/*; do echo "fs/$(basename "$f")" >>"$PATCH_MANIFEST"; done
    for f in "$SUS"/kernel_patches/include/linux/*; do echo "include/linux/$(basename "$f")" >>"$PATCH_MANIFEST"; done
    KPATCH="$SUS/kernel_patches/50_add_susfs_in_${SUSFS_BRANCH}.patch"
    [ -f "$KPATCH" ] || { echo "::error::missing $KPATCH"; exit 1; }
    patch -p1 -d "$KDIR" <"$KPATCH" || { echo "::error::SUSFS kernel patch failed to apply"; exit 1; }
    record_patch "$KPATCH"
    echo "    kernel-side patch applied"

    # root side: supercall dispatch + KSU_SUSFS* Kconfig, maintained against
    # tiann/KernelSU. This is what makes CONFIG_KSU_SUSFS* exist at all.
    KPATCH_KSU="$SUS/kernel_patches/KernelSU/10_enable_susfs_for_ksu.patch"
    [ -f "$KPATCH_KSU" ] || { echo "::error::missing $KPATCH_KSU"; exit 1; }
    if ! patch -p1 -d "$KSU_DIR" <"$KPATCH_KSU"; then
        echo "::error::SUSFS KernelSU patch failed to apply against $ROOT_FLAVOR @ $KSU_SHA."
        echo "::error::The two pins must be a coherent pair: the SUSFS commit names its"
        echo "::error::synced KernelSU commit in its message - set ksu_ref to that commit."
        for rej in "$KSU_DIR"/*.rej "$KSU_DIR"/kernel/*.rej; do
            [ -f "$rej" ] || continue
            echo "::error::rejects in ${rej#$KSU_DIR/}:"
            head -12 "$rej" | while IFS= read -r line; do
                esc=$(printf '%s' "$line" | sed -e 's/%/%25/g' -e 's/\r//g')
                echo "::error::  ${esc:0:200}"
            done
        done
        exit 1
    fi
    echo "    KernelSU-side patch applied"

    grep -q 'KSU_SUSFS' "$KSU_DIR/kernel/Kconfig" \
        || { echo "::error::$ROOT_FLAVOR tree has no KSU_SUSFS symbols after the patch"; exit 1; }

    for c in KSU_SUSFS KSU_SUSFS_SUS_PATH KSU_SUSFS_SUS_MOUNT KSU_SUSFS_SUS_KSTAT \
             KSU_SUSFS_SPOOF_UNAME KSU_SUSFS_ENABLE_LOG KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS \
             KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG KSU_SUSFS_OPEN_REDIRECT; do
        set_y "$c"
    done
    echo "    SUSFS configs set"
fi

# ------------------------------------- keep new exports out of the KMI "trim"
# GKI builds trim exported symbols that are not in android/abi_gki_aarch64 and
# (strict mode) fail the build when new ones appear. KSU/SUSFS export a few
# helpers. Registering them is additive - stock symbols are untouched, so vendor
# modules keep their CRCs.
KMI="$KDIR/android/abi_gki_aarch64"
if [ -f "$KMI" ]; then
    python3 - "$KMI" "$KSU_DIR/kernel" "$KDIR/fs" "$KDIR/include/linux" <<'KMISYMS'
import glob, os, re, sys

kmi, ksu_kernel, fs_dir, inc_dir = sys.argv[1:]
pat = re.compile(r"EXPORT_SYMBOL(?:_GPL)?\(\s*([A-Za-z_][A-Za-z0-9_]*)\s*\)")

targets = []
if os.path.isdir(ksu_kernel):
    targets += glob.glob(os.path.join(ksu_kernel, "**", "*.[chS]"), recursive=True)
# SUSFS in-tree files only - do not walk the whole include/linux tree.
targets += glob.glob(os.path.join(fs_dir, "susfs*.[ch]"))
targets += glob.glob(os.path.join(inc_dir, "susfs*.[ch]"))

found = set()
for path in targets:
    try:
        found.update(pat.findall(open(path, encoding="utf-8", errors="replace").read()))
    except OSError:
        continue

lines = open(kmi, encoding="utf-8").read().splitlines()

def is_meta(line):
    """Keep the list's own furniture: "[abi_symbol_list]" header and # comments."""
    return line.startswith("#") or (line.startswith("[") and line.endswith("]"))

comments = [l for l in lines if is_meta(l.strip())]
symbols = {l.strip() for l in lines if l.strip() and not is_meta(l.strip())}
new = sorted(found - symbols)
if new:
    # Keep the list sorted: Kleaf diffs this file against the built export table.
    with open(kmi, "w", encoding="utf-8") as fh:
        fh.write("\n".join(comments + sorted(symbols | found)) + "\n")
print(f"    KMI list: {len(new)} newly exported symbol(s) registered")
for s in new[:10]:
    print(f"      + {s}")
KMISYMS
fi

echo "==> root integration done ($ROOT_FLAVOR, susfs=$USE_SUSFS)"
grep -E '^CONFIG_(KSU|KPM)' "$DEFCONFIG" | sort | sed 's/^/      /'

{
    echo "EFFECTIVE_ROOT_FLAVOR=$ROOT_FLAVOR"
    echo "EFFECTIVE_USE_SUSFS=$USE_SUSFS"
    echo "KSU_SHA=$KSU_SHA"
} >>"${GITHUB_ENV:-/dev/null}"
