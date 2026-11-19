#!/usr/bin/env python3
"""Fetch a stock boot/vendor_boot image from a URL — including Google Drive links.

GitHub runners have real internet, this sandbox does not, so the download happens
in CI. Drive is deliberately awkward for scripts:

  * a share link (/file/d/<id>/view) is an HTML page, not the file;
  * large files go through a "can't scan for viruses" confirm form;
  * a file that is not shared with "anyone with the link" returns a sign-in page.

So this script: builds the direct URL, sends a browser User-Agent, and if it gets
HTML back it either (a) follows the confirm form, or (b) prints exactly why it
failed (sign-in / no access / quota) instead of dumping 900 KB of HTML into the log.

Usage: fetch_image.py <url> <dest> <magic>      (magic e.g. ANDROID! or VNDRBOOT)
"""

import html
import re
import sys
import urllib.error
import urllib.parse
import urllib.request

UA = ("Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) "
      "Chrome/124.0 Safari/537.36")


def drive_id(url):
    m = re.search(r"/file/d/([A-Za-z0-9_-]{10,})", url)
    if m:
        return m.group(1)
    m = re.search(r"[?&]id=([A-Za-z0-9_-]{10,})", url)
    return m.group(1) if m else None


def get(url, dest=None):
    req = urllib.request.Request(url, headers={"User-Agent": UA, "Accept": "*/*"})
    with urllib.request.urlopen(req, timeout=300) as r:
        ctype = r.headers.get("Content-Type", "")
        if dest is None:
            return r.read(), ctype, r.geturl()
        total = 0
        with open(dest, "wb") as f:
            while True:
                chunk = r.read(1 << 20)
                if not chunk:
                    break
                f.write(chunk)
                total += len(chunk)
                if total % (10 << 20) < (1 << 20):
                    print(f"    ... {total >> 20} MiB", flush=True)
        return None, ctype, r.geturl()


def diagnose(page):
    low = page.lower()
    hints = [
        ("sign in", "file is private: open it in Drive → Share → General access → 'Anyone with the link' → Viewer"),
        ("you need access", "no permission for anonymous download - share it as 'Anyone with the link'"),
        ("request access", "no permission for anonymous download - share it as 'Anyone with the link'"),
        ("too many users", "Drive download quota exceeded - try again later or use another host"),
        ("quota", "Drive download quota exceeded - try again later or use another host"),
        ("virus scan", "Drive showed its virus-scan warning page and the confirm form was not usable"),
    ]
    for needle, msg in hints:
        if needle in low:
            return msg
    m = re.search(r"<title[^>]*>(.*?)</title>", page, re.S | re.I)
    return f"unexpected HTML page (title: {html.unescape(m.group(1).strip())[:120] if m else 'none'})"


def follow_confirm_form(page, referer):
    """Google's 'download anyway' form: action + hidden inputs."""
    m = re.search(r'<form[^>]+id="download-form"[^>]+action="([^"]+)"', page, re.I)
    if not m:
        m = re.search(r'<form[^>]+action="(https://[^"]*(?:download|uc)[^"]*)"', page, re.I)
    if not m:
        return None
    action = html.unescape(m.group(1))
    params = dict(re.findall(r'<input[^>]+name="([^"]+)"[^>]+value="([^"]*)"', page, re.I))
    params.setdefault("confirm", "t")
    params.setdefault("export", "download")
    params = {k: html.unescape(v) for k, v in params.items()}
    if "?" in action:
        base, _, _ = action.partition("?")
        return base + "?" + urllib.parse.urlencode(params)
    return action + "?" + urllib.parse.urlencode(params)


def main(argv):
    if len(argv) != 4:
        raise SystemExit(__doc__)
    url, dest, magic = argv[1:]
    did = drive_id(url)
    candidates = []
    if did:
        candidates.append(f"https://drive.usercontent.google.com/download?id={did}&export=download&confirm=t")
        candidates.append(f"https://drive.google.com/uc?export=download&id={did}&confirm=t")
    candidates.append(url)

    last_err = None
    for cand in candidates:
        try:
            print(f"==> fetching {cand.split('?')[0]} → {dest}", flush=True)
            _, ctype, final = get(cand, dest)
            head = open(dest, "rb").read(512)
            if head[:len(magic)] == magic.encode():
                print(f"    ok: {dest} ({len(open(dest,'rb').read())} bytes, {final.split('?')[0]})")
                return 0
            if head.lstrip()[:1] == b"<":
                page = open(dest, "rb").read(2 << 20).decode("utf-8", "replace")
                again = follow_confirm_form(page, final)
                if again:
                    print("    Drive returned its confirm page - following the download form")
                    get(again, dest)
                    head = open(dest, "rb").read(512)
                    if head[:len(magic)] == magic.encode():
                        print(f"    ok: {dest} ({len(open(dest,'rb').read())} bytes)")
                        return 0
                last_err = diagnose(page)
                print(f"::error::Drive did not return the file ({ctype}): {last_err}")
            else:
                last_err = f"magic {head[:len(magic)]!r} != {magic!r}"
                print(f"::error::{dest} is not the expected image: {last_err}")
        except urllib.error.HTTPError as e:
            last_err = f"HTTP {e.code} {e.reason}"
            print(f"::error::download failed: {last_err}")
        except Exception as e:                                   # noqa: BLE001
            last_err = str(e)
            print(f"::error::download failed: {last_err}")

    if last_err:
        print(f"::error::giving up: {last_err}")
        print("::error::Fix: open the file in Drive → Share → General access → "
              "'Anyone with the link' → Viewer, then pass the same /file/d/<id>/ link.")
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
