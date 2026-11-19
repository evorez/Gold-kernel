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
# 6.6 does not hardcode "cubic" in tcp_cong.c any more; the default is the
# kconfig string CONFIG_DEFAULT_TCP_CONG ("cubic" when unset). Setting it is
# cleaner than patching the source and cannot break the sysctl path.
apply 'CONFIG_DEFAULT_TCP_CONG="bbr"'
echo '    CONFIG_DEFAULT_TCP_CONG="bbr"'
TCPCONG="$KDIR/net/ipv4/tcp_cong.c"
if [ -f "$TCPCONG" ]; then
    grep -q 'CONFIG_DEFAULT_TCP_CONG' "$TCPCONG" \
        || echo "::warning::tcp_cong.c does not reference CONFIG_DEFAULT_TCP_CONG; verify the sysctl default after boot"
fi

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
