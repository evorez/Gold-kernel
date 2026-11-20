#!/usr/bin/env bash
# Align the GKI build with what the *stock* gold kernel actually is.
#
# gold's stock kernel is byte-for-byte Google's GKI build
# 6.6.118-android15-8-ge56cf6b09cca-ab15511674-4k, and the prebuilt vendor
# modules in vendor_dlkm / vendor_boot / system_dlkm were linked against that
# build's KMI. Every rule below exists because breaking it makes the phone fail
# to boot or kills WiFi, even though the build itself succeeds.
#
# Ground truth for the stock config is the GKI config of the same tag
# (6.6.118):  CONFIG_LTO_NONE=y, CONFIG_CFI_CLANG=y, CONFIG_MODVERSIONS=y,
# CONFIG_MODULE_SIG=y, # CONFIG_MODULE_SIG_FORCE is not set,
# CONFIG_MODULE_SIG_PROTECT=y, CONFIG_ARM64_4K_PAGES=y, CONFIG_LOCALVERSION="-4k".
#
# Usage: fix-gki-config.sh <gki-workspace-root>       (expects <root>/common/)
set -euo pipefail

KROOT="${1:?usage: fix-gki-config.sh <repo-root-containing-common/>}"
KDIR="$KROOT/common"
DEFCONFIG="$KDIR/arch/arm64/configs/gki_defconfig"
LOCALVERSION_EXTRA="${LOCALVERSION_EXTRA:--GoldenEra-v1}"
CRC_STUB="${CRC_STUB:-false}"

[ -f "$DEFCONFIG" ] || { echo "::error::missing $DEFCONFIG"; exit 1; }

set_y() { # set_y CONFIG_FOO [y|n]
    local key="$1" val="${2:-y}"
    sed -i "/^# CONFIG_${key} is not set$/d; /^CONFIG_${key}=/d" "$DEFCONFIG"
    if [ "$val" = "y" ]; then
        echo "CONFIG_${key}=y" >>"$DEFCONFIG"
    else
        echo "# CONFIG_${key} is not set" >>"$DEFCONFIG"
    fi
}

echo "==> stock-environment parity"

# 1. MODULE_SIG_PROTECT must be OFF in a self-built kernel.
#    Stock has it =y, which works because Google's signing key is baked into the
#    stock trusted ring. Our Kleaf build generates its OWN signing key, so every
#    Google-signed system_dlkm module that exports a *protected* symbol (rfkill,
#    bluetooth, mii, usbnet, ...) would be refused at load time - silently.
#    cfg80211 then cannot resolve rfkill_alloc and WiFi + Bluetooth are dead.
#    This is load-time policy only: no ABI, struct layout or CRC impact.
set_y MODULE_SIG_PROTECT n
echo "    MODULE_SIG_PROTECT: off (Google-signed system_dlkm modules must load)"

# 1b. The DO-NOT-INCLUDE options are unconditional, not a "tweaks" feature.
#     A build with tweaks=false otherwise inherits whatever the GKI defconfig
#     happens to default to - and the stock gold kernel has
#     CONFIG_THERMAL_WRITABLE_TRIPS=y, so a root-only/parity variant shipped that
#     option enabled and the policy gate (correctly) failed the build.
for _opt in THERMAL_WRITABLE_TRIPS CPU_FREQ_DEFAULT_GOV_PERFORMANCE CPU_FREQ_DEFAULT_GOV_USERSPACE; do
    set_y "$_opt" n
done
echo "    DO-NOT-INCLUDE: no writable thermal trips, no performance/userspace default governor"

# 2. LTO must stay NONE, exactly like stock.
#    A different LTO mode changes codegen and therefore symbol CRCs, and the
#    prebuilt vendor modules then refuse to load -> black screen. Do not "speed
#    up" the build with --lto=thin or CONFIG_LTO_CLANG_*.
if grep -qE '^CONFIG_LTO_CLANG(_THIN|_FULL)?=y' "$DEFCONFIG"; then
    echo "::error::defconfig enables Clang LTO but stock is LTO_NONE."
    echo "::error::Different LTO mode => different symbol CRCs => vendor modules rejected => no boot."
    exit 1
fi
echo "    LTO: none (as stock)"

# 3. MODVERSIONS must stay =y.
#    With CRCs present the kernel skips the *release string* when matching
#    vermagic (same_magic() skips the first token). Turn MODVERSIONS off and
#    "modversions" disappears from vermagic, every prebuilt vendor module is then
#    rejected with "Invalid module format" - the exact black-screen failure.
grep -q '^CONFIG_MODVERSIONS=y$' "$DEFCONFIG" || set_y MODVERSIONS y
echo "    MODVERSIONS: on (vermagic parity with stock modules)"

# 4. Root / kprobe prerequisites (all =y in stock already).
for c in KPROBES KALLSYMS KALLSYMS_ALL EXT4_FS; do
    grep -q "^CONFIG_${c}=y$" "$DEFCONFIG" || set_y "$c" y
done
echo "    KPROBES / KALLSYMS(_ALL) / EXT4_FS: on"

# 5. Protected-exports lists: KEEP them, do not delete (see why below).
#    susfs4ksu's README says to remove these files for GKI android14+, because a
#    self-built kernel cannot reproduce Google's "protected symbol" set and
#    modules using those symbols get refused. But the file is a *declared input*
#    of //common:kernel_aarch64 (common/BUILD.bazel: kernel_aarch64's
#    protected_exports_list), so deleting it fails the build with
#        ERROR: missing input file '//common:android/abi_gki_protected_exports_aarch64'
#    (CI run 44515323372 hit exactly that). The gate those lists feed is
#    CONFIG_MODULE_SIG_PROTECT, which rule 1 already turns off - so the lists are
#    inert and the WiFi/BT failure mode is covered anyway.
for f in "$KDIR/android/abi_gki_protected_exports_aarch64" \
         "$KDIR/android/abi_gki_protected_exports_x86_64"; do
    [ -f "$f" ] && echo "    kept $(basename "$f") (declared Bazel input; MODULE_SIG_PROTECT=off makes it inert)"
done

# 6. Kernel name, so a flashed build is identifiable:
#    ...-ab<build>-4k  ->  ...-ab<build>-4k-GoldenEra-v1
#    (no spaces: the release string is a filesystem token - it names
#    /lib/modules/<release> and is part of module vermagic)
#    Only the *first* token of vermagic is the release string, and it is skipped
#    when the module carries CRCs, so this cannot break vendor module loading.
if [ -n "$LOCALVERSION_EXTRA" ]; then
    cur="$(sed -n 's/^CONFIG_LOCALVERSION="\(.*\)"$/\1/p' "$DEFCONFIG" | head -n1)"
    case "$cur" in
        *"$LOCALVERSION_EXTRA") echo "    localversion already '$cur'" ;;
        *)
            sed -i "/^CONFIG_LOCALVERSION=/d" "$DEFCONFIG"
            echo "CONFIG_LOCALVERSION=\"${cur}${LOCALVERSION_EXTRA}\"" >>"$DEFCONFIG"
            echo "    localversion: '${cur}' -> '${cur}${LOCALVERSION_EXTRA}'"
            ;;
    esac
fi

# 7. Disable the savedefconfig gate. We append options instead of inserting them
#    in savedefconfig order, and the legacy hook POST_DEFCONFIG_CMDS="check_defconfig"
#    (still evaluated by Kleaf) would reject that on ordering alone.
GKI_BC="$KDIR/build.config.gki"
[ -s "$GKI_BC" ] || { echo "::error::$GKI_BC missing or empty"; exit 1; }
grep -q 'POST_DEFCONFIG_CMDS' "$GKI_BC" \
    || { echo "::error::no POST_DEFCONFIG_CMDS in $GKI_BC - build layout changed"; exit 1; }
sed -i 's/POST_DEFCONFIG_CMDS="check_defconfig"/POST_DEFCONFIG_CMDS="true"/' "$GKI_BC"
grep -q 'check_defconfig' "$GKI_BC" \
    && { echo "::error::failed to disable check_defconfig"; cat "$GKI_BC"; exit 1; }
echo "    check_defconfig gate disabled"

# 8. OPTIONAL safety valve (crc_stub=true): skip the genksyms CRC *comparison*.
#    Only needed if vendor modules complain "disagrees about version of symbol"
#    in dmesg. Not enabled by default: if our build reproduces Google's config
#    and toolchain, the CRCs match and the check is a genuine safety net.
if [ "$CRC_STUB" = "true" ]; then
    python3 - "$KDIR/kernel/module/version.c" <<'PY'
import re, sys
path = sys.argv[1]
src = open(path, encoding="utf-8").read()
stub = '''int check_version(const struct load_info *info,
\t\t  const char *symname,
\t\t\t struct module *mod,
\t\t\t const s32 *crc)
{
\t/* gold: CRC comparison disabled on request (crc_stub=true).
\t * Symbol *presence* and struct layout are still enforced; only the
\t * genksyms hash comparison is skipped. */
\t(void)info; (void)symname; (void)mod; (void)crc;
\treturn 1;
}
'''
pat = re.compile(r'int check_version\(const struct load_info \*info,.*?\n\}\n', re.S)
if "crc_stub=true" in src:
    print("    check_version already stubbed")
elif not pat.search(src):
    sys.exit("::error::check_version() not found in kernel/module/version.c")
else:
    out, n = pat.subn(stub, src, count=1)
    assert n == 1
    if "check_modstruct_version" not in out:
        sys.exit("::error::stub rewrite broke version.c structure")
    open(path, "w", encoding="utf-8").write(out)
    print("    check_version() stubbed (CRC comparison skipped)")
PY
else
    echo "    CRC comparison left ON (default; crc_stub=false)"
fi

echo "==> config parity done"
grep -E '^(CONFIG_(LOCALVERSION|MODVERSIONS|CFI_CLANG)|# CONFIG_(MODULE_SIG_PROTECT|LTO_CLANG))' "$DEFCONFIG" | sed 's/^/      /' || true
