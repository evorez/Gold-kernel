#!/system/bin/sh
# havoc-boot - apply the HAVOC default frequency ceilings at boot.
#
# Installed by the HAVOC zip as /data/adb/service.d/99-havoc.sh (BakaSU / KernelSU
# runs everything in service.d as root at boot).
#
# What it does, and what it deliberately does not:
#   * sets each cluster's scaling_MAX_freq to the hardware ceiling (MT6833: 2000 MHz on
#     the 6x A55 cluster, 2400 MHz on the 2x A76 cluster, but the numbers are read from
#     the device, never assumed),
#   * sets the GPU devfreq max to 1068 MHz (again: clamped to what the node reports),
#   * leaves scaling_min_freq alone, so thermal and the Power HAL can still bring the
#     clock down when the phone gets hot - a pinned min==max would defeat thermal
#     mitigation and cook the battery,
#   * never touches thermal zones, trip points, voltages, or the GPU OPP table.
#
# Idempotent, prints nothing unless something is off, exits 0 always: a boot script that
# fails must never block boot.

LOG=/data/adb/havoc-boot.log
# `:` is a POSIX special builtin: a failed redirection there kills the shell,
# so use a normal command and fall back to /dev/null instead.
touch "$LOG" 2>/dev/null || LOG=/dev/null

say() { { echo "$*" >>"$LOG"; } 2>/dev/null || true; }

# target ceiling per cluster, from the values HAVOC ships with
want_max() { # want_max <hw_max_khz>
    if [ "${1:-0}" -ge 2200000 ]; then echo 2400000; else echo 2000000; fi
}

[ "$(id -u)" = "0" ] || { say "not root, nothing applied"; exit 0; }

for p in /sys/devices/system/cpu/cpufreq/policy*; do
    [ -d "$p" ] || continue
    hw=$(cat "$p/cpuinfo_max_freq" 2>/dev/null) || continue
    [ "${hw:-0}" -gt 0 ] || continue
    target=$(want_max "$hw")
    [ "$target" -gt "$hw" ] && target=$hw          # never exceed the hardware
    min=$(cat "$p/scaling_min_freq" 2>/dev/null)
    if [ "${min:-0}" -gt "$target" ]; then
        say "$(basename "$p"): min $min > target $target, skipped"
        continue
    fi
    echo "$target" >"$p/scaling_max_freq" 2>/dev/null \
        && say "$(basename "$p"): scaling_max_freq $target (hw $hw)" \
        || say "$(basename "$p"): could not write scaling_max_freq"
done

# GPU: find the Mali devfreq node without assuming one path, and work out the unit from
# the magnitude instead of trusting a name.
for d in /sys/class/misc/mali0/device/devfreq/* /sys/class/devfreq/*mali*; do
    [ -d "$d" ] || continue
    cur=$(cat "$d/max_freq" 2>/dev/null) || continue
    case "$cur" in ''|*[!0-9]*) continue ;; esac
    if [ "$cur" -gt 10000000 ]; then target=1068000000; else target=1068; fi
    [ "$target" -gt "$cur" ] && target=$cur
    echo "$target" >"$d/max_freq" 2>/dev/null \
        && say "gpu $(basename "$d"): max_freq $target" \
        || say "gpu $(basename "$d"): could not write max_freq"
done

# scheduler responsiveness: faster ramp-up, unchanged governor
for p in /sys/devices/system/cpu/cpufreq/policy*; do
    [ -f "$p/schedutil/up_rate_limit_us" ] && echo 500 >"$p/schedutil/up_rate_limit_us" 2>/dev/null
    [ -f "$p/schedutil/down_rate_limit_us" ] && echo 20000 >"$p/schedutil/down_rate_limit_us" 2>/dev/null
done

# top-app gets a uclamp floor, background stays capped
[ -f /dev/cpuset/top-app/uclamp.min ] && echo 512 >/dev/cpuset/top-app/uclamp.min 2>/dev/null
[ -f /dev/cpuset/background/uclamp.max ] && echo 512 >/dev/cpuset/background/uclamp.max 2>/dev/null

# storage: deadline for latency-sensitive IO
for q in /sys/block/*/queue/scheduler; do
    [ -f "$q" ] || continue
    case "$(cat "$q" 2>/dev/null)" in
        *"[mq-deadline]"*) : ;;
        *mq-deadline*) echo mq-deadline >"$q" 2>/dev/null ;;
    esac
done

say "done"
exit 0
