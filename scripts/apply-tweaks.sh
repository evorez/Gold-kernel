#!/usr/bin/env bash
# Apply gold's kernel feature set to the GKI tree.
#
# The list lives in configs/gold-features.config (and configs/gold-devbuild.config
# for the ftrace/perf extras). This script only *applies* it - it never invents
# options, so what the kernel ends up with is reviewable in one file.
#
# Why configs and not modules: the only thing a user flashes is boot.img. A .ko
# shipped in the artifact would never be loaded (it would need signing and a push
# to vendor_dlkm), so anything that must be present has to be linked in.
#
# KMI safety: nothing here adds, removes or retypes an exported symbol. These are
# new code paths behind configs, so the prebuilt MediaTek modules keep their CRCs.
# The one exception is the dev_build set, which is documented in the contract of
# that file and off by default.
#
# Usage: apply-tweaks.sh <gki-workspace-root>        (expects <root>/common/)
# Env:   DEV_BUILD=true|false, EXTRA_CONFIG (newline separated defconfig lines)
set -euo pipefail

KROOT="${1:?usage: apply-tweaks.sh <repo-root-containing-common/>}"
KDIR="$KROOT/common"
DEFCONFIG="$KDIR/arch/arm64/configs/gki_defconfig"
DEV_BUILD="${DEV_BUILD:-false}"
EXTRA_CONFIG="${EXTRA_CONFIG:-}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

[ -f "$DEFCONFIG" ] || { echo "::error::missing $DEFCONFIG"; exit 1; }

# replace a symbol: drop whatever the defconfig said, then append our line
set_cfg() { # set_cfg CONFIG_FOO=y | set_cfg !CONFIG_FOO
    local spec="$1" key line
    case "$spec" in
        '!'*)
            key="${spec#!}"
            [[ "$key" =~ ^CONFIG_[A-Z0-9_]+$ ]] \
                || { echo "::error::refusing to apply malformed option: $spec"; exit 1; }
            line="# ${key} is not set"
            ;;
        *)
            [[ "$spec" =~ ^CONFIG_[A-Z0-9_]+=[A-Za-z0-9_\"-]+$ ]] \
                || { echo "::error::refusing to apply malformed option: $spec"; exit 1; }
            key="${spec%%=*}"
            line="$spec"
            ;;
    esac
    sed -i "/^${key}=/d; /^# ${key} is not set$/d" "$DEFCONFIG"
    echo "$line" >>"$DEFCONFIG"
}

apply_fragment() { # apply_fragment <file>
    local file="$1" kind spec n_req=0 n_opt=0
    [ -f "$file" ] || { echo "::error::missing fragment $file"; exit 1; }
    echo "==> $(basename "$file")"
    while IFS= read -r raw || [ -n "$raw" ]; do
        # strip trailing CR and surrounding whitespace, keep '#' comments out
        raw="$(printf '%s' "$raw" | tr -d '\r' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
        case "$raw" in ''|'#'*) continue ;; esac
        kind="${raw%% *}"
        spec="${raw#* }"
        case "$kind" in
            REQ) set_cfg "$spec"; n_req=$((n_req + 1)) ;;
            OPT) set_cfg "$spec"; n_opt=$((n_opt + 1)) ;;
            *) echo "::error::$file: unknown marker '$kind' (expected REQ or OPT): $raw"; exit 1 ;;
        esac
    done <"$file"
    echo "    applied $n_req required + $n_opt optional options"
}

apply_fragment "$REPO_DIR/configs/gold-features.config"
if [ "$DEV_BUILD" = "true" ]; then
    apply_fragment "$REPO_DIR/configs/gold-devbuild.config"
else
    echo "==> dev build extras: off (dev_build=false)"
fi

# --- user supplied extra options (workflow input: extra_config) -------------
if [ -n "$EXTRA_CONFIG" ]; then
    echo "==> extra config from input"
    while IFS= read -r line; do
        line="$(printf '%s' "$line" | tr -d '\r' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
        [ -z "$line" ] && continue
        case "$line" in \#*) echo "    (comment ignored) $line"; continue ;; esac
        case "$line" in '!'*) set_cfg "$line" ;; *) set_cfg "$line" ;; esac
        echo "    $line"
    done <<<"$EXTRA_CONFIG"
fi

echo "==> feature set applied"
