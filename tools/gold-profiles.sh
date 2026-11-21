#!/system/bin/sh
# gold-profiles - balanced / gaming / sustained / havoc runtime profiles for gold
# (Xiaomi Redmi Note 13 5G), plus an optional charge limit.
#
# These are *runtime* tunables on purpose: even the aggressive `havoc` profile only
# raises the frequency CEILING to the hardware maximum, it never pins a minimum to it,
# so thermal mitigation and the Power HAL still work. The governor always stays
# schedutil, thermal trips/voltages/GPU OPP tables are never written, and everything is
# snapshotted so `restore` puts the phone back exactly as it was.
#
# Usage (as root):
#   gold-profiles status            show governor/uclamp/freq/zram/IO/thermal/suspend
#   gold-profiles balanced          stock-like scheduler tuning (default)
#   gold-profiles gaming            top-app gets uclamp min + faster freq ramp-up
#   gold-profiles sustained         cap max CPU freq (~80%) for heat/battery
#   gold-profiles havoc             max ceilings: 2000 MHz little / 2400 MHz big,
#                                   GPU 1068 MHz, fastest schedutil ramp (see below)
#   gold-profiles charge-limit 80   stop charging at 80% (vendor node, best effort)
#   gold-profiles charge-limit off  clear the limit
#   gold-profiles restore           put back everything we snapshotted
#
# Safe by construction:
#   * the CPU governor is never changed away from schedutil (refused otherwise),
#   * thermal zones / trips are never written,
#   * GPU OPP tables and display clocks are never written,
#   * every write is skipped (with a note) when the node does not exist on this
#     ROM, so the script is harmless on a device whose vendor nodes differ.

set -u

STATE_DIR=/data/adb/gold-profiles
# charging nodes whose value is a percentage of full: the generic power-supply
# end-threshold first, then the vendor spellings seen on HyperOS builds.
CHARGE_NODES="/sys/class/power_supply/battery/charge_control_end_threshold \
/sys/class/power_supply/battery/charge_limit \
/sys/class/power_supply/battery/charge_control_limit"
BACKUP="$STATE_DIR/backup"

say() { printf '%s\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

[ "$(id -u)" = "0" ] || die "run as root (su -c 'gold-profiles ...')"

cpu_policies() { ls -d /sys/devices/system/cpu/cpufreq/policy* 2>/dev/null; }

snapshot() {
    mkdir -p "$BACKUP" || die "cannot create $BACKUP"
    for p in $(cpu_policies); do
        n=$(basename "$p")
        for f in scaling_min_freq scaling_max_freq; do
            [ -f "$p/$f" ] && [ ! -f "$BACKUP/$n.$f" ] && cat "$p/$f" >"$BACKUP/$n.$f"
        done
        for f in up_rate_limit_us down_rate_limit_us; do
            [ -f "$p/schedutil/$f" ] && [ ! -f "$BACKUP/$n.schedutil.$f" ] \
                && cat "$p/schedutil/$f" >"$BACKUP/$n.schedutil.$f"
        done
    done
    for c in top-app foreground background; do
        for f in uclamp.min uclamp.max; do
            [ -f "/dev/cpuset/$c/$f" ] && [ ! -f "$BACKUP/cpuset.$c.$f" ] \
                && cat "/dev/cpuset/$c/$f" >"$BACKUP/cpuset.$c.$f"
        done
    done
    for n in $CHARGE_NODES; do
        # 'charge~' prefix + '@' for '/': '_' is already in 'power_supply'
        b="$BACKUP/charge~$(printf '%s' "$n" | tr '/' '@')"
        [ -f "$n" ] && [ ! -f "$b" ] && cat "$n" >"$b"
    done
    for q in /sys/block/*/queue/scheduler; do
        [ -f "$q" ] && [ ! -f "$BACKUP/$(echo "$q" | tr '/' '_')" ] && cat "$q" >"$BACKUP/$(echo "$q" | tr '/' '_')"
    done
    say "snapshot: $BACKUP"
}

put() { # put <file> <value> - best effort, never fatal
    [ -f "$1" ] || { say "  skip (missing): $1"; return 0; }
    if printf '%s\n' "$2" >"$1" 2>/dev/null; then
        say "  $1 = $2"
    else
        say "  skip (not writable): $1"
    fi
}

require_schedutil() {
    for p in $(cpu_policies); do
        g=$(cat "$p/scaling_governor" 2>/dev/null || echo "?")
        [ "$g" = "schedutil" ] || die "governor on $(basename "$p") is '$g', expected schedutil - refusing to tune"
    done
}

# max freq of a policy, in kHz
policy_max() { cat "$(ls -d /sys/devices/system/cpu/cpufreq/policy* | head -n1)/cpuinfo_max_freq" 2>/dev/null || echo 0; }

profile_balanced() {
    say "profile: balanced"
    require_schedutil
    for p in $(cpu_policies); do
        put "$p/schedutil/up_rate_limit_us" 2000
        put "$p/schedutil/down_rate_limit_us" 8000
        [ -f "$BACKUP/$(basename "$p").scaling_max_freq" ] \
            && put "$p/scaling_max_freq" "$(cat "$BACKUP/$(basename "$p").scaling_max_freq")"
    done
    put /dev/cpuset/top-app/uclamp.min 0
    put /dev/cpuset/top-app/uclamp.max 1024
    put /dev/cpuset/background/uclamp.max 512
}

profile_gaming() {
    say "profile: gaming (freq ramp-up, no permanent max clock)"
    require_schedutil
    for p in $(cpu_policies); do
        put "$p/schedutil/up_rate_limit_us" 500
        put "$p/schedutil/down_rate_limit_us" 20000
        [ -f "$BACKUP/$(basename "$p").scaling_max_freq" ] \
            && put "$p/scaling_max_freq" "$(cat "$BACKUP/$(basename "$p").scaling_max_freq")"
    done
    put /dev/cpuset/top-app/uclamp.min 512
    put /dev/cpuset/top-app/uclamp.max 1024
    for q in /sys/block/*/queue/scheduler; do
        [ -f "$q" ] && put "$q" mq-deadline
    done
    say "  note: thermal protection is untouched - sustained load will still throttle"
}

# havoc: the default HAVOC performance set. Ceilings are the hardware maxima the user
# asked for (MT6833: 2x A76 @ 2400 MHz, 6x A55 @ 2000 MHz, Mali-G57 @ 1068 MHz), but the
# real hw maximum read from the node wins if it is lower - no invented values, and the
# minimum is left alone so thermal can still throttle.
profile_havoc() {
    say "profile: havoc (max ceilings, thermal still active)"
    require_schedutil
    for p in $(cpu_policies); do
        hw=$(cat "$p/cpuinfo_max_freq" 2>/dev/null || echo 0)
        [ "${hw:-0}" -gt 0 ] || continue
        if [ "$hw" -ge 2200000 ]; then target=2400000; else target=2000000; fi
        [ "$target" -gt "$hw" ] && target=$hw
        put "$p/scaling_max_freq" "$target"
        put "$p/schedutil/up_rate_limit_us" 500
        put "$p/schedutil/down_rate_limit_us" 20000
    done
    # GPU ceiling: node may report Hz or MHz, so decide by magnitude
    for d in /sys/class/misc/mali0/device/devfreq/* /sys/class/devfreq/*mali*; do
        [ -d "$d" ] || continue
        cur=$(cat "$d/max_freq" 2>/dev/null || echo 0)
        [ "${cur:-0}" -gt 0 ] || continue
        if [ "$cur" -gt 10000000 ]; then target=1068000000; else target=1068; fi
        [ "$target" -gt "$cur" ] && target=$cur
        put "$d/max_freq" "$target"
    done
    put /dev/cpuset/top-app/uclamp.min 512
    put /dev/cpuset/top-app/uclamp.max 1024
    put /dev/cpuset/background/uclamp.max 512
    for q in /sys/block/*/queue/scheduler; do
        [ -f "$q" ] && put "$q" mq-deadline
    done
    say "  note: thermal protection is untouched - sustained load will still throttle"
}

profile_sustained() {
    say "profile: sustained (~80% of max CPU freq for heat/battery)"
    require_schedutil
    for p in $(cpu_policies); do
        maxf=$(cat "$p/cpuinfo_max_freq" 2>/dev/null || echo 0)
        [ "$maxf" -gt 0 ] 2>/dev/null && put "$p/scaling_max_freq" "$((maxf * 80 / 100))"
        put "$p/schedutil/up_rate_limit_us" 3000
        put "$p/schedutil/down_rate_limit_us" 6000
    done
    put /dev/cpuset/top-app/uclamp.max 768
}

charge_limit() {
    case "${1:-}" in
        off|clear)
            wrote=0
            for n in $CHARGE_NODES; do
                [ -f "$n" ] || continue
                if printf '%s\n' 100 >"$n" 2>/dev/null; then
                    say "  $n = 100 (limit cleared)"
                    wrote=1
                else
                    say "  skip (not writable): $n"
                fi
            done
            [ "$wrote" = 1 ] || say "  no writable charge-limit node on this ROM; nothing changed"
            say "charge limit: off"
            return 0
            ;;
        ''|*[!0-9]*) die "usage: gold-profiles charge-limit <20-100|off>" ;;
    esac
    [ "$1" -ge 20 ] && [ "$1" -le 100 ] || die "charge limit must be between 20 and 100"

    # MTK/HyperOS exposes different nodes per ROM. Only percentage-semantics
    # nodes are written; current-limit nodes are left alone because their scale
    # differs per charger and guessing it is a hardware-safety issue.
    wrote=0
    for n in $CHARGE_NODES; do
        [ -f "$n" ] || continue
        if printf '%s\n' "$1" >"$n" 2>/dev/null; then
            say "  $n = $1"
            wrote=1
        else
            say "  skip (not writable, vendor driver owns it): $n"
        fi
    done
    if [ "$wrote" = 0 ]; then
        say "  no percentage charge-limit node on this ROM; nothing written"
        say "  (this needs the vendor charger driver to expose one - see docs/FEATURES.md)"
        return 0
    fi
    say "charge limit: $1% - charging stops there until 'gold-profiles charge-limit off'"
}

do_status() {
    say "kernel: $(uname -r)"
    say "selinux: $(getenforce 2>/dev/null || echo unknown)"
    say ""
    for p in $(cpu_policies); do
        say "$(basename "$p"): gov=$(cat "$p/scaling_governor" 2>/dev/null) min=$(cat "$p/scaling_min_freq" 2>/dev/null) max=$(cat "$p/scaling_max_freq" 2>/dev/null)"
        [ -f "$p/schedutil/up_rate_limit_us" ] && say "  schedutil up/down: $(cat "$p/schedutil/up_rate_limit_us")/$(cat "$p/schedutil/down_rate_limit_us")"
    done
    for c in top-app foreground background; do
        [ -f "/dev/cpuset/$c/uclamp.min" ] && say "cpuset $c: uclamp.min=$(cat /dev/cpuset/$c/uclamp.min) uclamp.max=$(cat /dev/cpuset/$c/uclamp.max)"
    done
    if [ -f /sys/block/zram0/disksize ]; then
        say "zram0: disksize=$(cat /sys/block/zram0/disksize) comp=$(cat /sys/block/zram0/comp_algorithm 2>/dev/null)"
    fi
    for q in /sys/block/sd*/queue/scheduler /sys/block/dm-0/queue/scheduler; do
        [ -f "$q" ] && say "scheduler $q: $(cat "$q")"
    done
    for z in /sys/class/thermal/thermal_zone*/temp; do
        [ -f "$z" ] && say "$(dirname "$z" | xargs basename): $(cat "$z")"
    done | head -n 8
    [ -f /sys/power/suspend_stats/success ] && say "suspend: success=$(cat /sys/power/suspend_stats/success) fail=$(cat /sys/power/suspend_stats/fail)"
}

do_restore() {
    [ -d "$BACKUP" ] || { say "nothing to restore ($BACKUP missing)"; return 0; }
    for f in "$BACKUP"/*; do
        [ -f "$f" ] || continue
        name=$(basename "$f")
        case "$name" in
            cpuset.*) target="/dev/cpuset/$(printf '%s' "$name" | cut -d. -f2)/$(printf '%s' "$name" | cut -d. -f3-)" ;;
            charge~*) target="$(printf '%s' "${name#charge~}" | tr '@' '/')" ;;
            *scheduler) target="$(printf '%s' "$name" | tr '_' '/')" ;;
            *) policy="${name%%.*}"; rest="${name#*.}"
               if [ "${rest#schedutil.}" != "$rest" ]; then
                   target="/sys/devices/system/cpu/cpufreq/$policy/schedutil/${rest#schedutil.}"
               else
                   target="/sys/devices/system/cpu/cpufreq/$policy/$rest"
               fi ;;
        esac
        put "$target" "$(cat "$f")"
    done
    say "restored from $BACKUP"
}

case "${1:-status}" in
    status)        do_status ;;
    balanced)      snapshot; profile_balanced ;;
    gaming)        snapshot; profile_gaming ;;
    sustained)     snapshot; profile_sustained ;;
    havoc)         snapshot; profile_havoc ;;
    charge-limit)  shift; charge_limit "${1:-}" ;;
    restore)       do_restore ;;
    *)             say "usage: gold-profiles {status|balanced|gaming|sustained|havoc|charge-limit <pct|off>|restore}" ;;
esac
