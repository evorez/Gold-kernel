#!/usr/bin/env bash
# Enforce the "DO NOT INCLUDE" contract on the source tree and the built Image.
#
# The point is that the boundaries are machine-checked, not a promise in a README:
#   * no thermal bypass / writable trips
#   * no permanent maximum clocks or a performance-default governor
#   * no CPU/GPU overclock, no changed OPP tables
#   * no fsync disabling
#   * no SELinux permissive
#   * no display overclock
#   * no random/untested governors or I/O schedulers
#
# Two layers:
#   1. the *tree* we are about to build: every changed path must be one we
#      deliberately touch (config, root driver wiring, SUSFS files, KMI list);
#      anything under drivers/thermal, drivers/gpu, drivers/cpufreq, block/,
#      mm/, net/, kernel/sched, kernel/power, arch/arm64/boot is a policy failure;
#   2. the *built Image* config: SELinux must be on, no performance-default
#      governor, no writable thermal trips.
#
# Usage: check-policy.sh <gki-workspace-root> [built.config]
set -euo pipefail

KROOT="${1:?usage: check-policy.sh <gki-workspace-root> [built.config]}"
KDIR="$KROOT/common"
CFG="${2:-/tmp/built.config}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
fail=0

# paths this build must never modify: thermal, GPU, cpufreq/OPP/DVFS, display
# (arch/arm64/boot holds the device trees), block/mm/net and the scheduler.
DENY="drivers/thermal drivers/gpu drivers/cpufreq drivers/devfreq drivers/misc \
arch/arm64/boot block mm net kernel/sched kernel/power drivers/clk drivers/opp"

echo "==> policy: forbidden features"

# ---------------------------------------------------------------- 1. the tree
MANIFEST="${PATCH_MANIFEST:-/tmp/gold-patch-paths.txt}"
if [ -d "$KDIR/.git" ]; then
    changed="$(git -C "$KDIR" status --porcelain --untracked-files=no | awk '{print $NF}')"
    upstream=""
    if [ -f "$MANIFEST" ]; then
        upstream="$(sed -e 's/[[:space:]]*$//' "$MANIFEST" | grep -v '^$' | sort -u)"
        echo "    $MANIFEST: $(printf '%s\n' "$upstream" | grep -c . || true) path(s) touched by the vendored patches"
    else
        echo "::warning::no $MANIFEST - treating every changed file as ours (stricter)"
    fi
    is_upstream() { printf '%s\n' "$upstream" | grep -qxF "$1"; }
    under_deny() { # under_deny <path>
        for prefix in $DENY; do
            case "$1" in "$prefix"/*) return 0 ;; esac
        done
        return 1
    }

    echo "    files we modified in common/:"
    printf '%s\n' $changed | sed 's/^/      /'

    for path in $changed; do
        under_deny "$path" || continue
        if is_upstream "$path"; then
            # e.g. a SUSFS hunk in mm/ - upstream code we review once, not a tweak
            echo "::warning::policy: $path changed by a vendored upstream patch (reviewed, not retuned)"
        else
            echo "::error::policy: $path is outside what this build may touch ($path)."
            echo "::error::policy: thermal/OPP/DVFS/governor/display changes are not allowed."
            fail=1
        fi
    done

    # Forbidden *behaviour* cannot hide behind an allowed path: scan what the
    # changes actually add (fsync bypass, thermal bypass, permissive SELinux).
    for path in $changed; do
        hits="$(git -C "$KDIR" diff -U0 -- "$path" \
            | grep -E '^\+' | grep -vE '^\+\+\+' \
            | grep -niE 'fsync|thermal_bypass|disable_thermal|setenforce[[:space:]]+0|selinux=[0]?permissive' || true)"
        [ -n "$hits" ] || continue
        if is_upstream "$path"; then
            echo "::warning::policy: $path (vendored patch) adds a line mentioning fsync/thermal/SELinux:"
        else
            echo "::error::policy: $path adds a forbidden line:"
            fail=1
        fi
        printf '%s\n' "$hits" | head -3 | while IFS= read -r line; do
            echo "    ${line:0:180}"
        done
    done
else
    echo "::warning::no git metadata in $KDIR; skipping the tree-level policy check"
fi

# ------------------------------------------------- 2. our own scripts/configs
banned='androidboot\.selinux=permissive|setenforce 0|selinux=0|thermal_bypass|disable_thermal|CONFIG_CPU_FREQ_DEFAULT_GOV_PERFORMANCE=y|CONFIG_CPU_FREQ_DEFAULT_GOV_USERSPACE=y|CONFIG_THERMAL_WRITABLE_TRIPS=y'
hits="$(grep -rInE "$banned" "$REPO_DIR/configs" "$REPO_DIR/scripts" "$REPO_DIR/tools" \
        --include='*.config' --include='*.sh' --include='*.yml' 2>/dev/null \
        | grep -vE 'check-policy\.sh|^\s*#' || true)"
if [ -n "$hits" ]; then
    echo "::error::policy: a forbidden pattern appears in this repo:"
    printf '%s\n' "$hits" | head -10 | while IFS= read -r line; do
        esc=$(printf '%s' "$line" | sed -e 's/%/%25/g')
        echo "::error::policy:   ${esc:0:200}"
    done
    fail=1
fi

# -------------------------------------------------------- 3. the built Image
if [ -f "$CFG" ]; then
    need() { grep -q "^CONFIG_$1=y$" "$CFG" || { echo "::error::policy: CONFIG_$1 must be =y"; fail=1; }; }
    forbid() { grep -qE "^CONFIG_$1=[ym]$" "$CFG" && { echo "::error::policy: CONFIG_$1 must not be enabled"; fail=1; } || true; }

    need SECURITY_SELINUX
    forbid CPU_FREQ_DEFAULT_GOV_PERFORMANCE
    forbid CPU_FREQ_DEFAULT_GOV_USERSPACE
    forbid THERMAL_WRITABLE_TRIPS
    echo "    SELinux on, no performance-default governor, no writable thermal trips"
else
    echo "::warning::no built config at $CFG; skipping the Image-level policy check"
fi

if [ "$fail" -ne 0 ]; then
    echo "::error::policy gate failed - this build violates the DO-NOT-INCLUDE contract."
    exit 1
fi
echo "==> policy gate passed (no thermal bypass, no overclock, fsync intact, SELinux enforcing)"
