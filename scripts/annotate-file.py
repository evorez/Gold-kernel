#!/usr/bin/env python3
"""Turn a text file into GitHub ::notice:: annotations, several lines per annotation.

GitHub caps annotations at 10 per step, and run logs are not retrievable from
every environment, so this packs up to CHUNK lines into one annotation message.

Usage: annotate-file.py <file> <prefix> [chunk] [max_annotations]
"""

import sys

path, prefix = sys.argv[1], sys.argv[2]
chunk = int(sys.argv[3]) if len(sys.argv) > 3 else 8
max_ann = int(sys.argv[4]) if len(sys.argv) > 4 else 9

lines = [l.strip() for l in open(path, encoding="utf-8", errors="replace") if l.strip()]
if not lines:
    print(f"::notice::{prefix} (empty)")
    sys.exit(0)

print(f"::notice::{prefix}: {len(lines)} line(s) total")
shown = 0
for i in range(0, len(lines), chunk):
    if shown >= max_ann:
        print(f"::notice::{prefix}: ... {len(lines) - i} more line(s) not shown")
        break
    print(f"::notice::{prefix}{i + 1:>3}: " + " | ".join(lines[i:i + chunk]))
    shown += 1
