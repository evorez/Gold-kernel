#!/usr/bin/env bash
# KMI gate: the prebuilt vendor modules in vendor_dlkm / vendor_boot /
# system_dlkm were linked against Google's GKI build of this exact tag. They
# resolve exported symbols by name AND compare the genksyms CRC recorded in their
# .mod.c. If a symbol disappears, or its CRC changes, the module is refused at
# load time - which on gold means no display, no WiFi, no touch: a black screen.
#
# Two checks:
#   1. every symbol of the KMI list (android/abi_gki_aarch64) is still exported
#      by our Image (a *removal* is always fatal),
#   2. if a reference symvers file is available (stock GKI build), the CRC of
#      every symbol in both must be identical (a *change* is fatal).
#
# Usage: check-kmi.sh <gki-workspace-root> [reference-Module.symvers]
set -euo pipefail

KROOT="${1:?usage: check-kmi.sh <repo-root> [reference-Module.symvers]}"
REF="${2:-}"
CRC_STUB="${CRC_STUB:-false}"
KDIR="$KROOT/common"

SYMVERS="$(find "$KROOT/bazel-bin" "$KROOT/out" -name 'Module.symvers' -size +100k 2>/dev/null \
           | head -n1 || true)"
[ -n "$SYMVERS" ] || { echo "::error::no Module.symvers found - cannot verify KMI"; exit 1; }
echo "==> symvers: $SYMVERS ($(wc -l <"$SYMVERS") symbols)"

KMI="$KDIR/android/abi_gki_aarch64"
[ -f "$KMI" ] || { echo "::error::KMI symbol list missing: $KMI"; exit 1; }

python3 - "$SYMVERS" "$KMI" "${REF:-}" "$CRC_STUB" <<'PY'
import sys

symvers, kmi_list, ref, crc_stub = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4] == "true"

def load(path):
    out = {}
    with open(path, encoding="utf-8", errors="replace") as fh:
        for line in fh:
            parts = line.rstrip("\n").split("\t")
            if len(parts) < 2 or not parts[0].startswith("0x"):
                continue
            out[parts[1]] = parts[0].lower()
    return out

ours = load(symvers)
print(f"    built kernel exports {len(ours)} symbols")

# --- 1. KMI removals -------------------------------------------------------
def is_meta(line):
    """KMI lists carry a section header ("[abi_symbol_list]") and # comments."""
    return line.startswith("#") or (line.startswith("[") and line.endswith("]"))

kmilist = [l.strip() for l in open(kmi_list, encoding="utf-8", errors="replace")
           if l.strip() and not is_meta(l.strip())]
missing = [s for s in kmilist if s not in ours]
if missing:
    print(f"::error::{len(missing)} KMI symbol(s) are missing from the built kernel:")
    for s in missing[:25]:
        print(f"::error::  {s}")
    print("::error::A missing KMI symbol means prebuilt vendor modules cannot load (black screen).")
    sys.exit(1)
print(f"::notice::KMI list: all {len(kmilist)} symbols still exported")

# --- 2. CRC parity against a reference build -------------------------------
if ref:
    try:
        theirs = load(ref)
    except OSError as exc:
        print(f"::warning::reference symvers not readable ({exc}); skipping CRC comparison")
        sys.exit(0)
    common = set(ours) & set(theirs)
    bad = sorted(s for s in common if ours[s] != theirs[s])
    gone = sorted(set(theirs) - set(ours))
    print(f"::notice::reference (stock) exports {len(theirs)} symbols, {len(common)} in common with ours")
    if gone:
        print(f"::error::{len(gone)} symbol(s) exported by the reference build are missing here:")
        for s in gone[:25]:
            print(f"::error::  {s}")
        sys.exit(1)
    if bad:
        print(f"::warning::{len(bad)} of {len(common)} shared symbols have a different CRC:")
        for s in bad[:15]:
            print(f"::warning::  {s}: ours {ours[s]} vs reference {theirs[s]}")
        if crc_stub:
            print("::warning::crc_stub=true, so the running kernel skips CRC comparison. Continuing.")
        else:
            print("::error::CRC mismatch: prebuilt vendor modules would be rejected at load time.")
            print("::error::Either build with the stock config/toolchain (default) or re-run with crc_stub=true.")
            sys.exit(1)
    else:
        print(f"::notice::CRC parity: all {len(common)} shared symbols identical to the stock build")
PY

echo "==> KMI gate passed"
