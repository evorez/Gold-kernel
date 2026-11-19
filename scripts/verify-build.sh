#!/usr/bin/env bash
# Post-build gate: prove the Image we just built is the kernel gold expects.
#
# The config that matters is the one compiled INTO the image, so every feature
# check reads it back out of CONFIG_IKCONFIG instead of trusting the defconfig we
# wrote. Requirements come from configs/gold-features.config (+ the devbuild
# fragment), so this file does not carry a second copy of the feature list.
#
# Usage: verify-build.sh <gki-workspace-root>
# Env:   EFFECTIVE_ROOT_FLAVOR / EFFECTIVE_USE_SUSFS / TWEAKS / DEV_BUILD /
#        EXPECTED_VERSION
set -euo pipefail

KROOT="${1:?usage: verify-build.sh <repo-root>}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

IMG=""
for cand in "$KROOT/bazel-bin/common/kernel_aarch64/Image" \
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

need_y()   { grep -q "^CONFIG_$1=y$"            "$CFG" || { echo "::error::CONFIG_$1 must be =y"; exit 1; }; }
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

# ------------------------------------------------------------------ features
# Every REQ line of the fragment must be in the Image; OPT lines only warn, so a
# kernel that does not offer one (source absent, dependency unmet) is visible in
# the run page without failing the build.
check_fragment() { # check_fragment <fragment> <label>
    local frag="$1" label="$2"
    [ -f "$frag" ] || { echo "::error::missing fragment $frag"; exit 1; }
    python3 - "$CFG" "$frag" "$label" <<'PY'
import sys

cfg_path, frag_path, label = sys.argv[1], sys.argv[2], sys.argv[3]
cfg = set(open(cfg_path, encoding="utf-8", errors="replace").read().splitlines())

def present(spec):
    if spec.startswith("!"):
        return f"# {spec[1:]} is not set" in cfg
    return spec in cfg

req_ok = req_bad = opt_ok = opt_missing = 0
missing_opt, failed = [], []
for raw in open(frag_path, encoding="utf-8", errors="replace"):
    line = raw.strip()
    if not line or line.startswith("#"):
        continue
    kind, _, spec = line.partition(" ")
    spec = spec.strip()
    if kind == "REQ":
        if present(spec):
            req_ok += 1
        else:
            req_bad += 1
            failed.append(spec)
    elif kind == "OPT":
        if present(spec):
            opt_ok += 1
        else:
            opt_missing += 1
            missing_opt.append(spec)

print(f"    {label}: {req_ok} required present, {opt_ok} optional present")
if missing_opt:
    shown = ", ".join(missing_opt[:12])
    more = "" if len(missing_opt) <= 12 else f" (+{len(missing_opt) - 12} more)"
    print(f"::warning::{label}: {opt_missing} optional option(s) not offered by this kernel: {shown}{more}")
if failed:
    for spec in failed[:25]:
        print(f"::error::{label}: required option missing from the Image: {spec}")
    print("::error::A required option that did not survive kconfig means the feature is NOT in the kernel.")
    sys.exit(1)
PY
}

if [ "${TWEAKS:-true}" = "true" ]; then
    check_fragment "$REPO_DIR/configs/gold-features.config" "features"
else
    echo "==> tweaks=false: feature fragment not applied, skipping its gate"
fi
if [ "${DEV_BUILD:-false}" = "true" ]; then
    check_fragment "$REPO_DIR/configs/gold-devbuild.config" "devbuild"
fi

echo "==> all build gates passed"
{
    echo "image=$IMG"
    echo "kver=$KVER"
} >>"${GITHUB_OUTPUT:-/dev/null}"
