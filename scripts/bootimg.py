#!/usr/bin/env python3
"""Inspect / repack an Android boot image — the *surgical* way.

Why surgery instead of building a boot image from scratch: on gold the header
carries values we cannot guess safely (cmdline, os_version, and whatever sits in
the tail of the image — a dtb on some ROM builds). So the only safe operation is:

    new boot.img = stock boot.img with ONLY the kernel payload replaced

Everything else — the 4096-byte header page (byte for byte, except kernel_size),
the ramdisk, and the trailing bytes — is copied from the user's own image. If the
stock image has a dtb appended, the new one has the exact same dtb.

Header layout (AOSP bootimg.h, v3/v4):
    0    magic "ANDROID!"   8
    8    kernel_size        u32
    12   ramdisk_size       u32
    16   os_version         u32
    20   header_size        u32   (1584 for v4)
    24   reserved[4]        u32*4
    40   header_version     u32   (3 or 4)
    44   cmdline[1536]
    1580 signature_size     u32   (v4 only)
    -> header (and optional signature) padded to 4096, then kernel, ramdisk, tail

vendor_boot (bootconfig image) is only *inspected*, never modified:
    0 magic "VNDRBOOT", 8 header_version, 12 page_size, 24 vendor_ramdisk_size,
    28 cmdline[2048], 2096 header_size, 2100 dtb_size, 2104 dtb_addr

Usage:
    bootimg.py inspect <image>                 JSON of the header + payload layout
    bootimg.py vendor  <vendor_boot.img>       JSON of the vendor_boot header
    bootimg.py repack  <stock> <kernel> <out>  stock image with the kernel swapped
    bootimg.py verify  <out> <kernel> <stock> [partition_size]
"""

import hashlib
import json
import struct
import sys

PAGE = 4096


def align(n, a=PAGE):
    return (n + a - 1) // a * a


def sniff_kernel(b):
    """What kind of payload is this? (helps prove gzip-for-gzip swap)"""
    if b[:2] == b"\x1f\x8b":
        return "gzip"
    if len(b) >= 0x40 and b[0x38:0x3C] == b"ARM\x64":
        return "arm64-Image"
    if b[:4] == b"\x04\x22\x4d\x18":
        return "lz4"
    if b[:4] == b"\xfd7zX" or b[:6] == b"\xfd7zXZ\x00":
        return "xz"
    if b[:4] == b"\x88\x16\x88\x58":
        return "mtk-header"          # MediaTek wraps the kernel with its own header
    if b[:2] == b"\x1f\x9d":
        return "lzo"
    return "unknown:" + b[:4].hex()


def inspect(path):
    d = open(path, "rb").read()
    if d[:8] != b"ANDROID!":
        raise SystemExit(f"::error::{path} is not an Android boot image (magic {d[:8]!r})")
    kernel_size, ramdisk_size = struct.unpack_from("<II", d, 8)
    os_version, header_size = struct.unpack_from("<II", d, 16)
    header_version = struct.unpack_from("<I", d, 40)[0]
    cmdline = d[44:44 + 1536].split(b"\x00", 1)[0].decode("ascii", "replace")
    sig_size = struct.unpack_from("<I", d, 1580)[0] if header_version >= 4 and len(d) >= 1584 else 0

    info = {
        "path": path,
        "file_size": len(d),
        "header_version": header_version,
        "header_size": header_size,
        "page_size": PAGE if header_version >= 3 else "unknown (v0/v1/v2 not supported)",
        "cmdline": cmdline,
        "os_version_raw": os_version,
        "kernel_size": kernel_size,
        "ramdisk_size": ramdisk_size,
        "signature_size": sig_size,
        "kernel_sha256": hashlib.sha256(d[PAGE:PAGE + kernel_size]).hexdigest(),
    }

    if header_version >= 3:
        hdr_region = PAGE + align(sig_size)
        kernel_off = hdr_region
        ramdisk_off = kernel_off + align(kernel_size)
        tail_off = ramdisk_off + align(ramdisk_size)
        tail = d[tail_off:]
        kernel = d[kernel_off:kernel_off + kernel_size]
        info.update({
            "header_region": hdr_region,
            "kernel_offset": kernel_off,
            "ramdisk_offset": ramdisk_off,
            "tail_offset": tail_off,
            "tail_size": len(tail),
            "tail_sha256": hashlib.sha256(tail).hexdigest(),
            "kernel_payload": sniff_kernel(kernel),
        })
    return info


def inspect_vendor(path):
    d = open(path, "rb").read()
    if d[:8] != b"VNDRBOOT":
        raise SystemExit(f"::error::{path} is not a vendor_boot image (magic {d[:8]!r})")
    hv, page = struct.unpack_from("<II", d, 8)
    ramdisk_size = struct.unpack_from("<I", d, 24)[0]   # vendor_ramdisk_size
    cmdline = d[28:28 + 2048].split(b"\x00", 1)[0].decode("ascii", "replace")
    header_size = struct.unpack_from("<I", d, 2096)[0]
    dtb_size = struct.unpack_from("<I", d, 2100)[0]
    return {
        "path": path,
        "file_size": len(d),
        "header_version": hv,
        "page_size": page,
        "vendor_ramdisk_size": ramdisk_size,
        "dtb_size": dtb_size,
        "header_size": header_size,
        "cmdline": cmdline,
        "note": "never modified by this project; the dtb here keeps working as-is",
    }


def repack(stock, kernel, out, partition_size=None):
    d = open(stock, "rb").read()
    old = inspect(stock)
    if old["header_version"] < 3:
        raise SystemExit(f"::error::stock boot.img uses header v{old['header_version']}; "
                         "only v3/v4 (GKI) is supported")
    if old["signature_size"]:
        raise SystemExit("::error::stock boot.img carries a v4 boot signature; "
                         "refusing to repack a signed image (flash would fail anyway)")

    newk = open(kernel, "rb").read()
    kind_old, kind_new = sniff_kernel(d[PAGE:PAGE + old["kernel_size"]]), sniff_kernel(newk)
    if kind_old != kind_new:
        raise SystemExit(f"::error::payload mismatch: stock kernel is {kind_old}, ours is {kind_new}. "
                         "Swapping different container formats produces an unbootable image.")
    if kind_new not in ("gzip", "arm64-Image"):
        raise SystemExit(f"::error::unexpected kernel payload ({kind_new}); refusing to repack")

    hdr = bytearray(d[:PAGE])
    struct.pack_into("<I", hdr, 8, len(newk))          # kernel_size only

    body = newk + b"\x00" * (align(len(newk)) - len(newk))
    body += d[old["ramdisk_offset"]:]                  # ramdisk + tail, byte for byte
    img = bytes(hdr) + body

    if partition_size and len(img) > partition_size:
        raise SystemExit(f"::error::new boot.img is {len(img)} bytes, larger than the "
                         f"{partition_size}-byte boot partition")
    open(out, "wb").write(img)
    new = inspect(out)
    print(json.dumps({
        "out": out,
        "size": len(img),
        "stock_size": old["file_size"],
        "kernel": f'{old["kernel_size"]} -> {new["kernel_size"]} bytes ({kind_new})',
        "ramdisk": new["ramdisk_size"],
        "tail_preserved": new["tail_sha256"] == old["tail_sha256"],
        "cmdline": new["cmdline"],
        "os_version_raw": new["os_version_raw"],
    }, indent=2))
    return 0


def verify(new_path, kernel, stock, partition_size=None):
    new, old = inspect(new_path), inspect(stock)
    k = open(kernel, "rb").read()
    problems = []

    if new["header_version"] != old["header_version"]:
        problems.append(f'header_version {new["header_version"]} != {old["header_version"]}')
    if new["kernel_size"] != len(k):
        problems.append(f'kernel_size {new["kernel_size"]} != {len(k)} bytes of {kernel}')
    if new["kernel_sha256"] != hashlib.sha256(k).hexdigest():
        problems.append("kernel payload differs from the built kernel")
    if new["tail_sha256"] != old["tail_sha256"] or new["tail_size"] != old["tail_size"]:
        problems.append("trailing bytes (dtb?) were not preserved")
    if new["ramdisk_size"] != old["ramdisk_size"]:
        problems.append("ramdisk was not preserved")
    if new["cmdline"] != old["cmdline"]:
        problems.append(f'cmdline changed: {new["cmdline"]!r} != {old["cmdline"]!r}')
    if (new["os_version_raw"] or old["os_version_raw"]) and new["os_version_raw"] != old["os_version_raw"]:
        problems.append("os_version changed")
    # every header byte except kernel_size (offset 8..12) must be identical
    a = open(new_path, "rb").read()[:PAGE]
    b = open(stock, "rb").read()[:PAGE]
    if a[:8] != b[:8] or a[12:PAGE] != b[12:PAGE]:
        problems.append("header page differs outside kernel_size")
    if partition_size and len(open(new_path, "rb").read()) > int(partition_size):
        problems.append(f"image larger than the {partition_size}-byte partition")

    if problems:
        for p in problems:
            print(f"::error::boot.img check failed: {p}")
        return 1
    print(f'    boot.img OK: header v{new["header_version"]}, kernel {new["kernel_size"]} bytes '
          f'({new["kernel_payload"]}), ramdisk {new["ramdisk_size"]}, tail {new["tail_size"]} bytes '
          f'identical, cmdline {new["cmdline"]!r}')
    return 0


def main(argv):
    if len(argv) < 3:
        raise SystemExit(__doc__)
    cmd = argv[1]
    def num(x):
        return int(x) if x else None
    if cmd == "inspect":
        print(json.dumps(inspect(argv[2]), indent=2))
    elif cmd == "vendor":
        print(json.dumps(inspect_vendor(argv[2]), indent=2))
    elif cmd == "repack":
        if len(argv) < 5:
            raise SystemExit("usage: bootimg.py repack <stock> <kernel> <out> [partition_size]")
        return repack(argv[2], argv[3], argv[4], num(argv[5]) if len(argv) > 5 else None)
    elif cmd == "verify":
        if len(argv) < 5:
            raise SystemExit("usage: bootimg.py verify <out> <kernel> <stock> [partition_size]")
        return verify(argv[2], argv[3], argv[4], num(argv[5]) if len(argv) > 5 else None)
    else:
        raise SystemExit(__doc__)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
