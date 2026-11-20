#!/system/bin/sh
# perf-check - dump the state that the HAVOC work actually touches.
#
# Why this exists: the only honest way to talk about performance on this device is
# to compare two dumps taken from the same phone under the same conditions. This
# script writes nothing to the system; it only reads. Run it once on stock, once on
# the custom kernel (and once per gold-profiles profile) and diff the output.
#
# Usage:
#   sh perf-check.sh            print to stdout
#   sh perf-check.sh > a.txt    keep it, diff later (diff -u stock.txt perf.txt)
#
# Root is not required for most sections; the ones that need it are skipped with a
# note instead of failing.

set -u
OUT=${1:-/dev/stdout}

# ---------------------------------------------------------------- helpers
have() { [ -e "$1" ]; }
gp()   { command -v getprop >/dev/null 2>&1 && getprop "$1" 2>/dev/null; }
rd()   { [ -r "$1" ] && cat "$1" 2>/dev/null; }
head1() { printf '\n== %s ==\n' "$*"; }
kv()   { printf '%-34s %s\n' "$1" "$2"; }

{
head1 "identity"
kv "kernel release"      "$(uname -r)"
kv "kernel version"      "$(uname -v)"
kv "build date (from uname -v)" "$(uname -v | sed -n 's/#[0-9]* .*[A-Z][a-z][a-z] //p')"
kv "model"               "$(gp ro.product.model)"
kv "device"              "$(gp ro.product.device)"
kv "android release"     "$(gp ro.build.version.release)"
kv "build fingerprint"   "$(gp ro.build.fingerprint)"
kv "abi"                 "$(gp ro.product.cpu.abi)"
kv "root present"        "$([ -d /data/adb/ksu ] && echo 'ksu (/data/adb/ksu)' || { [ -d /data/adb/ksud ] && echo 'ksud' || echo 'no /data/adb/ksu*'; })"
kv "manager packages"    "$(command -v pm >/dev/null 2>&1 && pm list packages 2>/dev/null | grep -iE 'ksu|kernelsu|sukisu|bakasu|resukisu|apatch' | tr '\n' ' ')"

head1 "cpu topology"
for c in /sys/devices/system/cpu/cpu[0-9]*; do
    n=${c##*/cpu}
    [ -f "$c/cpufreq/cpuinfo_max_freq" ] || continue
    printf 'cpu%-2s max=%-9s cur=%-9s scaling_driver=%s\n' "$n" \
        "$(rd "$c/cpufreq/cpuinfo_max_freq")" "$(rd "$c/cpufreq/scaling_cur_freq")" \
        "$(rd "$c/cpufreq/scaling_driver")"
done

head1 "cpufreq policies"
for p in /sys/devices/system/cpu/cpufreq/policy[0-9]*; do
    have "$p" || continue
    printf '%s: gov=%s avail=[%s] min=%s max=%s cur=%s hw_max=%s\n' "${p##*/}" \
        "$(rd "$p/scaling_governor")" "$(rd "$p/scaling_available_governors")" \
        "$(rd "$p/scaling_min_freq")" "$(rd "$p/scaling_max_freq")" \
        "$(rd "$p/scaling_cur_freq")" "$(rd "$p/cpuinfo_max_freq")"
    for f in up_rate_limit_us down_rate_limit_us; do
        [ -f "$p/schedutil/$f" ] && printf '    schedutil/%s = %s\n' "$f" "$(rd "$p/schedutil/$f")"
    done
done

head1 "uclamp (cpusets)"
for c in /dev/cpuset/top-app /dev/cpuset/foreground /dev/cpuset/background /dev/cpuset/system-background; do
    have "$c" || continue
    printf '%-26s min=%-6s max=%-6s cpus=%s\n' "${c##*/}" \
        "$(rd "$c/uclamp.min")" "$(rd "$c/uclamp.max")" "$(rd "$c/cpus")"
done

head1 "thermal (read only)"
for z in /sys/class/thermal/thermal_zone*; do
    t=$(rd "$z/temp"); [ -n "$t" ] || continue
    printf '%-28s %8s  %s\n' "$(rd "$z/type")" "$t" "$(rd "$z/policy")"
done

head1 "gpu"
for d in /sys/class/misc/mali0/device/devfreq/* /sys/class/devfreq/*mali* /sys/kernel/gpu; do
    have "$d" || continue
    echo "-- $d"
    for f in cur_freq min_freq max_freq available_frequencies governor governor/available_governors gpu_cur_freq gpu_max_freq; do
        [ -f "$d/$f" ] && printf '   %-28s %s\n' "$f" "$(rd "$d/$f")"
    done
done

head1 "zram"
for z in /sys/block/zram*; do
    have "$z" || continue
    printf '%s disksize=%s algorithm=%s\n' "${z##*/}" "$(rd "$z/disksize")" "$(rd "$z/comp_algorithm")"
    [ -f "$z/mm_stat" ] && printf '   mm_stat: %s\n' "$(rd "$z/mm_stat")"
done
kv "swap total" "$(awk '/SwapTotal/{print $2" kB"}' /proc/meminfo 2>/dev/null)"
kv "swappiness" "$(rd /proc/sys/vm/swappiness)"

head1 "io"
for b in /sys/block/sd* /sys/block/ufs* /sys/block/mmcblk* /sys/block/dm-*; do
    have "$b/queue/scheduler" || continue
    printf '%s sched=[%s] nr_requests=%s read_ahead_kb=%s\n' "${b##*/}" \
        "$(tr -d '\n' < "$b/queue/scheduler")" "$(rd "$b/queue/nr_requests")" "$(rd "$b/queue/read_ahead_kb")"
done

head1 "memory"
grep -E 'MemTotal|MemAvailable|MemFree|SwapTotal|SwapFree' /proc/meminfo 2>/dev/null | sed 's/^/   /'
[ -f /proc/pressure/memory ] && printf '   PSI: %s\n' "$(cat /proc/pressure/memory)"
kv "mglru enabled" "$([ -f /sys/kernel/mm/lru_gen/enabled ] && cat /sys/kernel/mm/lru_gen/enabled || echo 'node absent')"

head1 "lmkd / low memory"
command -v getprop >/dev/null 2>&1 && getprop | grep -iE 'lmkd|lowmemorykiller|sys\.perf' | sed 's/^/   /'

head1 "gold-profiles state"
[ -d /data/adb/gold-profiles ] && ls -l /data/adb/gold-profiles 2>/dev/null | sed 's/^/   /' || echo "   not applied"

printf '\n-- end --\n'
} >"$OUT" 2>&1

[ "$OUT" = "/dev/stdout" ] || echo "written: $OUT"
