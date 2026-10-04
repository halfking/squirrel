#!/usr/bin/env python3
"""Build a minimal Debian sysroot for cross-compiling the GTK3 setup program.

Downloads the -dev/-0 packages listed below plus their runtime libraries from a
Debian mirror, unpacks them into $SYSROOT, and prints a zig cc recipe.
No apt/dpkg required: .deb files are ar archives holding a data tarball.
"""
import gzip
import os
import subprocess
import sys
import urllib.request

MIRROR = os.environ.get("DEB_MIRROR", "http://deb.debian.org/debian")
DIST = os.environ.get("DEB_DIST", "bookworm")
ARCH = os.environ.get("DEB_ARCH", "amd64")
SYSROOT = os.environ.get("SYSROOT", "/tmp/sysroot")

PACKAGES = [
    # C runtime / kernel headers
    "libc6", "libc6-dev", "linux-libc-dev", "libgcc-s1",
    # GTK stack: dev packages carry headers + .so symlinks
    "libgtk-3-dev", "libgtk-3-0", "libglib2.0-dev", "libglib2.0-0",
    "libpango1.0-dev", "libpango-1.0-0", "libpangocairo-1.0-0", "libpangoft2-1.0-0",
    "libcairo2-dev", "libcairo2", "libcairo-gobject2",
    "libgdk-pixbuf-2.0-dev", "libgdk-pixbuf-2.0-0",
    "libatk1.0-dev", "libatk1.0-0",
    "libharfbuzz-dev", "libharfbuzz0b",
    "libfribidi-dev", "libfribidi0",
    "libepoxy-dev", "libepoxy0",
    "libgraphite2-dev", "libgraphite2-3",
    "libfreetype6-dev", "libfontconfig1-dev", "libfontconfig1",
    "libpng-dev", "libpng16-16", "libpixman-1-dev", "libpixman-1-0",
    "libx11-dev", "libx11-6", "libxext-dev", "libxext6", "libxrender-dev", "libxrender1",
    "libxi-dev", "libxi6", "libxfixes-dev", "libxfixes3", "libxinerama-dev", "libxinerama1",
    "libxcursor-dev", "libxcursor1", "libxrandr-dev", "libxrandr2", "libxcb1-dev", "libxcb1",
    "libxau-dev", "libxau6", "libxdmcp-dev", "libxdmcp6", "libbsd-dev", "libbsd0",
    "libmd-dev", "libexpat1-dev", "libexpat1", "libuuid1", "libblkid1",
    "libbrotli-dev", "libbrotli1", "zlib1g-dev", "zlib1g", "liblzma-dev", "liblzma5",
    "libselinux1-dev", "libselinux1", "libpcre2-dev", "libpcre2-8-0",
    "libffi-dev", "libffi8", "libmount-dev", "libmount1", "libblkid-dev",
    "libwayland-dev", "libwayland-client0", "libwayland-server0",
    "libthai-dev", "libthai0", "libdatrie-dev", "libdatrie1",
    "libicu-dev", "libicu72", "libxml2-dev", "libxml2",
    "libgssapi-krb5-2", "libkrb5-3", "libk5crypto3", "libkrb5support0", "libkeyutils1",
    "libcom-err2", "libsqlite3-0", "libgcrypt20", "libgpg-error0", "liblz4-1",
    "libwayland-egl1", "libgl1", "libglx0", "libglvnd0", "libglapi-mesa",
]


def fetch(url: str) -> bytes:
    with urllib.request.urlopen(url, timeout=180) as response:
        return response.read()


def load_index() -> dict:
    cache = f"/tmp/Packages-{DIST}-{ARCH}.gz"
    if not os.path.exists(cache):
        url = f"{MIRROR}/dists/{DIST}/main/binary-{ARCH}/Packages.gz"
        print("downloading package index …", flush=True)
        with open(cache, "wb") as handle:
            handle.write(gzip.decompress(fetch(url)))
    entries: dict[str, str] = {}
    with open(cache, encoding="utf-8", errors="replace") as handle:
        name = None
        for line in handle:
            if line.startswith("Package: "):
                name = line[9:].strip()
            elif line.startswith("Filename: ") and name:
                entries.setdefault(name, line[10:].strip())
    return entries


AR = os.environ.get("AR", "/Library/Developer/CommandLineTools/usr/bin/ar")
if not os.path.exists(AR):
    AR = "ar"


def main() -> int:
    index = load_index()
    os.makedirs(SYSROOT, exist_ok=True)
    os.makedirs("/tmp/debs", exist_ok=True)

    missing, fetched = [], 0
    for package in PACKAGES:
        filename = index.get(package)
        if filename is None:
            missing.append(package)
            continue
        deb = os.path.join("/tmp/debs", os.path.basename(filename))
        if not os.path.exists(deb):
            with open(deb, "wb") as handle:
                handle.write(fetch(f"{MIRROR}/{filename}"))
        work = "/tmp/debwork"
        subprocess.run(["rm", "-rf", work], check=False)
        os.makedirs(work, exist_ok=True)
        subprocess.run([AR, "x", deb], cwd=work, check=True)
        data = next((os.path.join(work, n) for n in os.listdir(work) if n.startswith("data.tar")), None)
        if data is None:
            print(f"  ! no data tarball in {deb}", file=sys.stderr)
            continue
        subprocess.run(["tar", "-xf", data, "-C", SYSROOT], check=True)
        fetched += 1
        print(f"  ✓ {package}", flush=True)

    print(f"\nextracted {fetched} packages into {SYSROOT}")
    if missing:
        print("not found in index: " + ", ".join(missing))
    return 0


if __name__ == "__main__":
    sys.exit(main())
