#!/usr/bin/env bash
# Integrate a root solution (+ optional SUSFS root hiding) into the GKI tree.
#
#   ROOT_FLAVOR=sukisu    SukiSU Ultra, branch `builtin` (carries KSU_SUSFS*
#                         itself, so SUSFS needs no KSU-side patch)
#   ROOT_FLAVOR=ksu-next  KernelSU-Next v3.x (no SUSFS - see below)
#   ROOT_FLAVOR=none      no root at all
#
# Verified facts this encodes (upstream + on-device CI evidence):
#  * In-tree SUSFS requires SukiSU Ultra. KernelSU-Next v3.4.x ships SUSFS only
#    as a separate LKM (kernel/susfs -> susfs_guard_lkm.ko, loaded by ksud), so it
#    cannot be linked into the Image; susfs4ksu's KSU-side patch
#    (10_enable_susfs_for_ksu.patch) targets weishu's original KernelSU layout:
#    it deletes hook/lsm_hook.o, hook/syscall_hook_manager.o and
#    infra/symbol_resolver.o from kernel/Kbuild - exactly the files v3.x is built
#    on. So ksu-next + susfs is redirected to sukisu, or refused.
#  * SukiSU `builtin` is required for SUSFS: the release branch has no
#    KSU_SUSFS* Kconfig symbols, and kconfig would then silently drop every
#    CONFIG_KSU_SUSFS* line we add.
#  * SukiSU `builtin` tip is not always buildable (kernel/feature/*.c referencing
#    functions/enums that do not exist). 6c5603f0 is the newest known-good
#    revision, so it is pinned by default; the coherence preflight below catches
#    the same class of breakage in ~1 s instead of 20 min into the build.
#  * SUSFS is pinned together with KSU on purpose: susfs4ksu commit 3f0b811 began
#    calling ksu_install_su_fd() from the 50_ patch, which pinned SukiSU trees do
#    not define ("undefined symbol: ksu_install_su_fd" at link time).
#
# Usage: apply-root.sh <gki-workspace-root>        (expects <root>/common/)
set -euo pipefail

KROOT="${1:?usage: apply-root.sh <repo-root-containing-common/>}"
KDIR="$KROOT/common"
DEFCONFIG="$KDIR/arch/arm64/configs/gki_defconfig"
ROOT_FLAVOR="${ROOT_FLAVOR:-sukisu}"
USE_SUSFS="${USE_SUSFS:-true}"
USE_KPM="${USE_KPM:-false}"
KSU_REF="${KSU_REF:-}"
SUSFS_BRANCH="${SUSFS_BRANCH:-gki-android15-6.6}"
SUSFS_REF="${SUSFS_REF:-09fec8aa}"

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

# ---------------------------------------------------- flavor/SUSFS compatibility
if [ "$ROOT_FLAVOR" = "ksu-next" ] && [ "$USE_SUSFS" = "true" ]; then
    echo "::warning::KernelSU-Next v3.x cannot take the susfs4ksu KSU-side patch;"
    echo "::warning::switching to SukiSU Ultra, which implements SUSFS natively."
    echo "::warning::(choose root_flavor=ksu-next + use_susfs=false to stay on Next)"
    ROOT_FLAVOR=sukisu
fi
if [ "$ROOT_FLAVOR" = "ksu-next" ] && [ "$USE_KPM" = "true" ]; then
    echo "::warning::KPM is a SukiSU feature; KernelSU-Next has no CONFIG_KPM. Ignoring."
    USE_KPM=false
fi

# ------------------------------------------------------------- root tree
case "$ROOT_FLAVOR" in
  sukisu)
    KSU_URL="https://github.com/SukiSU-Ultra/SukiSU-Ultra"
    KSU_REF="${KSU_REF:-6c5603f0}"
    KSU_DIR="$KROOT/KernelSU"
    ;;
  ksu-next)
    KSU_URL="https://github.com/KernelSU-Next/KernelSU-Next"
    # KernelSU-Next has no `stable` branch; pin the newest release tag. Its
    # SUSFS support is a *separate LKM* (kernel/susfs -> susfs_guard_lkm.ko), not
    # in-tree code, so it cannot be linked into the Image the way susfs4ksu's
    # patch can - which is why the SUSFS route stays on SukiSU.
    KSU_REF="${KSU_REF:-v3.4.2}"
    KSU_DIR="$KROOT/KernelSU-Next"
    ;;
  *) echo "::error::unknown ROOT_FLAVOR: $ROOT_FLAVOR"; exit 1 ;;
esac

echo "==> integrating $ROOT_FLAVOR (ref: $KSU_REF)"
rm -rf "$KSU_DIR"
git clone -q "$KSU_URL" "$KSU_DIR" || { echo "::error::clone of $KSU_URL failed"; exit 1; }
if ! git -C "$KSU_DIR" checkout -q "$KSU_REF" 2>/dev/null; then
    # A branch name / tag that only exists on a remote ref.
    git -C "$KSU_DIR" fetch -q --all --tags
    git -C "$KSU_DIR" checkout -q "$KSU_REF" 2>/dev/null || {
        echo "::error::KSU_REF '$KSU_REF' not found in $KSU_URL. Available:"
        git -C "$KSU_DIR" for-each-ref --format='%(refname:short)' refs/remotes/origin refs/tags \
            | tail -20 | while IFS= read -r r; do echo "::error::  $r"; done
        exit 1
    }
fi
KSU_SHA="$(git -C "$KSU_DIR" rev-parse --short HEAD)"
echo "    $ROOT_FLAVOR @ $KSU_SHA ($(git -C "$KSU_DIR" rev-parse --abbrev-ref HEAD))"
[ -d "$KSU_DIR/kernel" ] || { echo "::error::$KSU_DIR/kernel missing - unexpected layout"; exit 1; }

# Wire the driver into the kernel the same way upstream's setup.sh does.
# Relative to common/drivers/, so "../.." is the workspace root where the root
# repo is cloned. Keep it relative: an absolute link would point outside the
# Bazel workspace and Kleaf would refuse to follow it.
case "$ROOT_FLAVOR" in
    sukisu)   ksu_link="../../KernelSU/kernel" ;;
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
grep -q kernelsu "$KDIR/drivers/Makefile" || { echo "::error::drivers/Makefile not wired"; exit 1; }
echo "    driver wired: drivers/kernelsu -> $(readlink "$KDIR/drivers/kernelsu")"

set_y KSU
if [ "$USE_KPM" = "true" ]; then set_y KPM; fi

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
    echo "::error::Pin a known-good commit with the ksu_ref input (default 6c5603f0)."
    exit 1
fi
echo "    feature subsystem coherent"

# ------------------------------------------------------------------ SUSFS
if [ "$USE_SUSFS" = "true" ]; then
    echo "==> integrating SUSFS (branch $SUSFS_BRANCH, ref: $SUSFS_REF)"
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

    cp -f "$SUS"/kernel_patches/fs/* "$KDIR/fs/"
    cp -f "$SUS"/kernel_patches/include/linux/* "$KDIR/include/linux/"

    KPATCH="$SUS/kernel_patches/50_add_susfs_in_${SUSFS_BRANCH}.patch"
    [ -f "$KPATCH" ] || { echo "::error::missing $KPATCH"; exit 1; }
    patch -p1 -d "$KDIR" <"$KPATCH" || { echo "::error::SUSFS kernel patch failed"; exit 1; }

    grep -q 'KSU_SUSFS' "$KSU_DIR/kernel/Kconfig" \
        || { echo "::error::$ROOT_FLAVOR tree has no KSU_SUSFS symbols (not the builtin branch?)"; exit 1; }

    for c in KSU_SUSFS KSU_SUSFS_SUS_PATH KSU_SUSFS_SUS_MOUNT KSU_SUSFS_SUS_KSTAT \
             KSU_SUSFS_SPOOF_UNAME KSU_SUSFS_ENABLE_LOG KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS \
             KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG KSU_SUSFS_OPEN_REDIRECT; do
        set_y "$c"
    done
    echo "    SUSFS configs set"
fi

# ------------------------------------- keep new exports out of the KMI "trim"
# GKI builds trim exported symbols that are not in android/abi_gki_aarch64 and
# (strict mode) fail the build when new ones appear. KSU/SUSFS do export a few
# helpers they need across their own objects. Registering them in the symbol list
# is additive - stock symbols are untouched, so vendor modules keep their CRCs.
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
comments = [l for l in lines if l.strip().startswith("#")]
symbols = {l.strip() for l in lines if l.strip() and not l.strip().startswith("#")}
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

echo "==> root integration done ($ROOT_FLAVOR, susfs=$USE_SUSFS, kpm=$USE_KPM)"
grep -E '^CONFIG_(KSU|KPM)' "$DEFCONFIG" | sort | sed 's/^/      /'

{
    echo "EFFECTIVE_ROOT_FLAVOR=$ROOT_FLAVOR"
    echo "EFFECTIVE_USE_SUSFS=$USE_SUSFS"
    echo "EFFECTIVE_USE_KPM=$USE_KPM"
    echo "KSU_SHA=$KSU_SHA"
} >>"${GITHUB_ENV:-/dev/null}"
