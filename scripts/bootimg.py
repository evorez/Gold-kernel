#!/usr/bin/env python3
"""Inspect / verify an Android boot image (header v3/v4, the shape gold uses).

gold (Redmi Note 13 5G) ships a GKI boot image:
  * header v4, page size 4096, kernel = Image.gz, **no ramdisk** (the ramdisk
    lives in vendor_boot; there is no init_boot partition on this device),
  * cmdline "bootopt=64S3,32N2,64N2", os_version 16.0.0,
  * boot partition is 64 MiB (BOARD_BOOTIMAGE_PARTITION_SIZE := 67108864).

Header v3/v4 layout (offset in bytes, from AOSP system/tools/mkbootimg/bootimg.h):
    0    magic "ANDROID!"        8
    8    kernel_size             u32
    12   ramdisk_size            u32
    16   os_version              u32  (major<<11 | patch_level)
    20   header_size             u32  (1580 for v3, 1584 for v4)
    24   reserved[4]             u32*4
    40   header_version          u32  (3 or 4)
    44   cmdline[1536]           char[BOOT_ARGS_SIZE + BOOT_EXTRA_ARGS_SIZE]
    1580 signature_size          u32  (v4 only)
    -> header padded to 4096, then kernel, ramdisk, ...

Usage:
    bootimg.py inspect <boot.img>            # JSON on stdout
    bootimg.py verify  <boot.img> <kernel> [partition_size]
"""
import hashlib
import json
import struct
import sys

MAGIC = b"ANDROID!"
V3_HEADER_SIZE = 1580
V4_HEADER_SIZE = 1584
PAGE = 4096


def os_version_parts(packed):
    """Unpack the v3+ os_version word: mkbootimg packs
    (major<<14 | minor<<7 | patch << 11) | (year-2000)<<4 | month."""
    return ((packed >> 25) & 0x7F,                 # major  (bits 25-31)
            (packed >> 18) & 0x7F,                 # minor  (bits 18-24)
            ((packed >> 4) & 0x7F) + 2000,         # year   (bits 4-10)
            packed & 0x0F)                         # month  (bits 0-3)


def inspect(path):
    d = open(path, "rb").read()
    if d[:8] != MAGIC:
        raise SystemExit(f"{path}: not an Android boot image (magic {d[:8]!r})")
    kernel_size, ramdisk_size, packed_os, header_size = struct.unpack_from("<4I", d, 8)
    header_version = struct.unpack_from("<I", d, 40)[0]
    cmdline = d[44:44 + 1536].split(b"\x00", 1)[0].decode("ascii", "replace")
    info = {
        "path": path,
        "file_size": len(d),
        "header_version": header_version,
        "header_size": header_size,
        "kernel_size": kernel_size,
        "ramdisk_size": ramdisk_size,
        "cmdline": cmdline,
        "os_version": "{}.{}.0".format(*os_version_parts(packed_os)[:2]),
        "os_patch_level": "{:04d}-{:02d}".format(*os_version_parts(packed_os)[2:]),
        "kernel_offset": PAGE,
        "kernel_sha256": hashlib.sha256(d[PAGE:PAGE + kernel_size]).hexdigest(),
    }
    if header_version >= 4:
        info["signature_size"] = struct.unpack_from("<I", d, 1580)[0]
    # Any non-zero bytes that follow kernel+ramdisk (vendor extras, AVB footer).
    end = PAGE + ((kernel_size + PAGE - 1) // PAGE) * PAGE
    end += ((ramdisk_size + PAGE - 1) // PAGE) * PAGE
    tail = d[end:]
    info["tail_size"] = len(tail)
    if tail[-64:-60] == b"AVBf":
        info["avb_footer"] = True
    if tail.lstrip(b"\x00"):
        info["note"] = "non-zero data after kernel/ramdisk (vendor blob or AVB)"
    return info


def verify(boot, kernel, partition_size=None):
    info = inspect(boot)
    raw = open(kernel, "rb").read()
    problems = []
    if info["header_version"] != 4:
        problems.append(f"header_version {info['header_version']} != 4")
    if info["ramdisk_size"] != 0:
        problems.append(f"ramdisk_size {info['ramdisk_size']} != 0 (gold's boot carries the kernel only)")
    if info["kernel_size"] != len(raw):
        problems.append(f"kernel_size {info['kernel_size']} != {len(raw)} bytes of {kernel}")
    if info["kernel_sha256"] != hashlib.sha256(raw).hexdigest():
        problems.append("kernel payload differs from the built kernel")
    if partition_size is not None and info["file_size"] > partition_size:
        problems.append(f"image is {info['file_size']} bytes, larger than the {partition_size}-byte partition")
    if problems:
        for p in problems:
            print(f"::error::boot.img check failed: {p}")
        return 1
    print(f"    boot.img OK: header v{info['header_version']}, "
          f"kernel {info['kernel_size']} bytes, ramdisk 0, "
          f"os {info['os_version']}, cmdline {info['cmdline']!r}, "
          f"{info['file_size'] // 1024} KiB")
    return 0


def main():
    if len(sys.argv) < 3:
        raise SystemExit(__doc__)
    cmd = sys.argv[1]
    if cmd == "inspect":
        print(json.dumps(inspect(sys.argv[2]), indent=2))
        return 0
    if cmd == "verify":
        part = int(sys.argv[4]) if len(sys.argv) > 4 else None
        return verify(sys.argv[2], sys.argv[3], part)
    raise SystemExit(f"unknown command {cmd}")


if __name__ == "__main__":
    sys.exit(main())
