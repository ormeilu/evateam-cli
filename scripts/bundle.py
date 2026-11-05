"""What a self-contained eva carries next to its binary.

Mojo's runtime libraries and OpenSSL come from the pixi env, so they are the
exact builds eva was compiled and tested with. Their licences come from the
same conda packages in rattler's cache: Modular requires its terms to travel
with its libraries, and OpenSSL's Apache-2.0 asks for its licence too.
"""

import json
import os
import re
import subprocess
import sys
from pathlib import Path

from relocate import ROOT

ENV = ROOT / ".pixi" / "envs" / "default"
DARWIN = sys.platform == "darwin"

# Loaded by the binary, by libKGENCompilerRTShared at run time, or (libssl,
# libcrypto) by eva's TLS layer with dlopen.
LIBS = (
    ["libKGENCompilerRTShared.dylib", "libAsyncRTRuntimeGlobals.dylib", "libMSupportGlobals.dylib",
     "libssl.3.dylib", "libcrypto.3.dylib"]
    if DARWIN
    else ["libKGENCompilerRTShared.so", "libAsyncRTRuntimeGlobals.so", "libMSupportGlobals.so",
          "libssl.so.3", "libcrypto.so.3"]
)

# Shipped licence file name -> (conda package, file in its info/licenses).
LICENSES = {
    "LICENSE-MODULAR": ("mojo-compiler", "LICENSE"),
    "THIRD-PARTY-NOTICES-MODULAR": ("mojo-compiler", "Third-Party-Notices"),
    "LICENSE-OPENSSL": ("openssl", "LICENSE.txt"),
}

CHANNELS = {"mojo-compiler": "https://conda.modular.com/max", "openssl": "conda-forge"}


def version() -> str:
    text = (ROOT / "pixi.toml").read_text()
    return re.search(r'^version = "([^"]+)"', text, re.M).group(1)


def libraries() -> list[Path]:
    libs = {ENV / "lib" / name for name in LIBS}
    if not DARWIN:
        # Anything else the binary links from the env.
        out = subprocess.run(["ldd", str(ROOT / "build" / "eva")], capture_output=True, text=True).stdout
        libs |= {Path(m) for m in re.findall(r"=> (\S+)", out) if str(ENV / "lib") in m}
    missing = [p for p in libs if not p.exists()]
    if missing:
        raise SystemExit(f"missing in the pixi env: {', '.join(map(str, missing))}")
    return sorted(libs)


def _package_licenses(package: str) -> Path:
    """info/licenses of `package` as installed in the env.

    It sits in rattler's package cache. An env restored from a CI cache never
    went through it, so fetch that exact build with `pixi exec` if needed.
    """
    meta_file = next(p for p in (ENV / "conda-meta").glob(f"{package}-*.json")
                     if json.loads(p.read_text())["name"] == package)
    meta = json.loads(meta_file.read_text())
    cache = os.environ.get("RATTLER_CACHE_DIR")
    roots = [Path(cache)] if cache else []
    roots += [Path.home() / "Library/Caches/rattler/cache", Path.home() / ".cache/rattler/cache"]

    def find() -> Path | None:
        for root in roots:
            lic = root / "pkgs" / meta_file.stem / "info" / "licenses"
            if lic.is_dir() and any(lic.iterdir()):
                return lic
        return None

    lic = find()
    if lic is None:
        spec = f"{package}=={meta['version']}={meta['build']}"
        subprocess.run(["pixi", "exec", "-c", CHANNELS[package], "-c", "conda-forge", "-s", spec, "--", "true"],
                       check=True)
        lic = find()
    if lic is None:
        raise SystemExit(f"no info/licenses for {meta_file.stem} in the rattler cache")
    return lic


def licenses() -> dict[str, Path]:
    """Shipped name -> source file, eva's own licence included."""
    out = {"LICENSE": ROOT / "LICENSE"}
    for shipped, (package, name) in LICENSES.items():
        path = _package_licenses(package) / name
        if path.exists():
            out[shipped] = path
    return out
