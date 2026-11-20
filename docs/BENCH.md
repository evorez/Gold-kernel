# Benchmark procedure — HAVOC

This is the only accepted way to claim a performance difference on this project.
Nothing in the repo has been measured on the phone yet (see `docs/AUDIT.md`), so treat
every number you see elsewhere with suspicion until it was produced by this procedure.

Two rules decide whether a result counts:

1. **Same conditions.** Stock and custom runs must share ROM build, ambient
   temperature, starting battery temperature, brightness, refresh rate, charging state
   (unplugged), and the same game/benchmark settings.
2. **Repeat-to-repeat variation decides.** Run each case 3x. A change is only kept if
   the difference is larger than the spread between those repeats.

---

## 0. Collect state first (no root needed for most of it)

```bash
adb push tools/perf-check.sh /data/local/tmp/
adb shell sh /data/local/tmp/perf-check.sh /sdcard/perf-stock.txt
```

Run it on stock, then on the custom kernel, then per profile (`balanced`, `gaming`,
`sustained`). `diff -u perf-stock.txt perf-custom.txt` shows exactly what changed.

## 1. Short tests (3 repeats each)

| Test | Command / app | Record |
|---|---|---|
| CPU throughput | `sysbench cpu --threads=8 run` (or Geekbench 6) | score, 3 runs |
| GPU / game | the game you actually play, same map/scene, 10 min | avg FPS, 1% low, jank |
| Storage | `fio` sequential + random 4K, `dd` if `fio` is absent | MB/s, IOPS |
| Memory | `am kill-all` then open 8 apps | reload count |

Frame times: `adb shell dumpsys gfxinfo <package> framestats` before/after, or the
game's own overlay. Percentiles matter more than the average.

## 2. Sustained test (the one that counts)

30 minutes of the same game, screen on, unplugged, brightness fixed:

```bash
# every 10 s, one CSV line
while true; do
  echo "$(date +%s),$(cat /sys/class/thermal/thermal_zone0/temp),$(cat /sys/devices/system/cpu/cpufreq/policy0/scaling_cur_freq),$(cat /sys/class/misc/mali0/device/devfreq/*/cur_freq 2>/dev/null)" \
    >> /sdcard/sustain.csv
  sleep 10
done
```

Record FPS (avg + 1% low) for minutes 0-5 vs 25-30. A kernel that only looks faster
because it starts colder is not faster — compare the temperature at the start of each
window, not the peak.

## 3. Responsiveness and smoothness

| Test | How |
|---|---|
| Input latency | `adb shell dumpsys input` event → frame timing, or a high-speed capture |
| Jank | `adb shell dumpsys gfxinfo <pkg> framestats`, `dumpsys SurfaceFlinger --latency` |
| Scroll smoothness | the same 60 s scroll in the same app, `gfxinfo` janky frame % |

## 4. Correctness must be re-checked after any tuning change

Cold boot, reboot, screen off/on, suspend/resume, recovery boot, calls + mobile data,
Wi-Fi, Bluetooth, camera photo/video, audio (speaker/headset/mic), sensors, touch,
charging, and `dmesg | grep -iE 'error|fail|denied'` plus `logcat -b crash`.

## 5. What to send back

- the three `perf-check.sh` dumps per configuration
- the CSV from the sustained run
- FPS/frame-time numbers with the test name and version
- which profile was active and the exact game settings

Without those, a claim stays in the UNTESTED column of `docs/AUDIT.md`.
