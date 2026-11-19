#!/usr/bin/env bash
# Performance / usability tweaks for gold, all **built in** (=y).
#
# Why built in and not modules: the only thing a user flashes is boot.img, so a
# .ko shipped in the artifact would never be loaded (it would have to be signed
# and pushed to vendor_dlkm, which means touching system partitions). Everything
# here is small enough to link into the Image.
#
# KMI safety: none of these add, remove or retype an *exported* symbol. They are
# new code paths behind configs, so the vendor_dlkm modules keep their CRCs.
# Nothing here touches HZ / preempt model / scheduler class tables, because those
# change vermagic tokens or codegen and would break the prebuilt modules.
#
# Usage: apply-tweaks.sh <gki-workspace-root>        (expects <root>/common/)
set -euo pipefail

KROOT="${1:?usage: apply-tweaks.sh <repo-root-containing-common/>}"
KDIR="$KROOT/common"
DEFCONFIG="$KDIR/arch/arm64/configs/gki_defconfig"
EXTRA_CONFIG="${EXTRA_CONFIG:-}"

[ -f "$DEFCONFIG" ] || { echo "::error::missing $DEFCONFIG"; exit 1; }

echo "==> applying tweaks"

# --- networking -------------------------------------------------------------
# BBR congestion control + fq qdisc: the single biggest win on a 5G handset
# (higher throughput on lossy mobile links, lower latency under load).
apply() { # apply CONFIG_FOO=y
    local line="$1"
    [[ "$line" =~ ^(#\ )?CONFIG_[A-Z0-9_]+(=|$) ]] \
        || { echo "::error::refusing to append non-config line: $line"; exit 1; }
    local key="${line#\# }"
    key="${key%%=*}"
    sed -i "/^${key}=/d; /^# ${key} is not set$/d" "$DEFCONFIG"
    echo "$line" >>"$DEFCONFIG"
}

for opt in \
    CONFIG_TCP_CONG_BBR=y \
    CONFIG_NET_SCH_FQ=y \
    CONFIG_NET_SCH_FQ_CODEL=y \
    CONFIG_LRU_GEN=y \
    CONFIG_LRU_GEN_ENABLED=y \
    CONFIG_WIREGUARD=y \
    CONFIG_NTFS3_FS=y \
    CONFIG_TMPFS_XATTR=y
do
    apply "$opt"
    echo "    $opt"
done

# --- BBR as the *default* congestion control --------------------------------
# CONFIG_DEFAULT_TCP_CONG is a *derived* string (net/ipv4/Kconfig builds it from a
# choice), so it cannot be set from a defconfig at all - kconfig ignores values for
# symbols without a prompt. Stock proves the shape:
#     CONFIG_DEFAULT_CUBIC=y
#     # CONFIG_DEFAULT_BBR is not set
#     CONFIG_DEFAULT_TCP_CONG="cubic"
# Selecting the choice member is what actually changes it.
apply 'CONFIG_TCP_CONG_ADVANCED=y'
apply 'CONFIG_DEFAULT_BBR=y'
echo '    CONFIG_TCP_CONG_ADVANCED=y, CONFIG_DEFAULT_BBR=y (-> CONFIG_DEFAULT_TCP_CONG="bbr")'

# --- user supplied extra options (workflow input: extra_config) -------------
if [ -n "$EXTRA_CONFIG" ]; then
    echo "==> extra config from input"
    while IFS= read -r line; do
        line="$(printf '%s' "$line" | sed -e 's/[[:space:]]*$//' -e 's/^[[:space:]]*//')"
        [ -z "$line" ] && continue
        case "$line" in \#*) # keep a user comment out of the defconfig
            echo "    (comment ignored) $line"; continue ;;
        esac
        apply "$line"
        echo "    $line"
    done <<<"$EXTRA_CONFIG"
fi

echo "==> tweaks applied"
