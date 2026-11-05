"""Pack build/eva into a self-contained release archive:
python scripts/build_archive.py TARGET, e.g. aarch64-apple-darwin.

The archive holds bin/eva, Mojo's runtime libraries in lib/ (the binary's
rpath is ../lib), and the licences: eva's, and Modular's licence and
third-party notices, which Modular requires alongside its libraries. Those two
come from the mojo-compiler conda package in pixi's cache, so they match the
libraries shipped. eva still needs a Python 3 on PATH for its HTTPS calls.
"""

import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tarfile
import tempfile
from pathlib import Path

from relocate import ROOT, relocated_binary

# Loaded by the binary or, at run time, by libKGENCompilerRTShared.
RUNTIME_LIBS = ["libKGENCompilerRTShared", "libAsyncRTRuntimeGlobals", "libMSupportGlobals"]


def version() -> str:
    text = (ROOT / "pixi.toml").read_text()
    return re.search(r'^version = "([^"]+)"', text, re.M).group(1)


def env_lib() -> Path:
    return ROOT / ".pixi" / "envs" / "default" / "lib"


def modular_licenses() -> Path:
    """info/licenses of the mojo-compiler package the env was built from.

    It sits in rattler's package cache. An env restored from a CI cache never
    went through it, so fetch that exact build with `pixi exec` if needed.
    """
    meta_file = next((ROOT / ".pixi/envs/default/conda-meta").glob("mojo-compiler-*.json"))
    meta = json.loads(meta_file.read_text())
    name = meta_file.stem
    cache = os.environ.get("RATTLER_CACHE_DIR")
    roots = [Path(cache)] if cache else []
    roots += [Path.home() / "Library/Caches/rattler/cache", Path.home() / ".cache/rattler/cache"]

    def find() -> Path | None:
        for root in roots:
            lic = root / "pkgs" / name / "info" / "licenses"
            if (lic / "LICENSE").exists():
                return lic
        return None

    lic = find()
    if lic is None:
        spec = f"mojo-compiler=={meta['version']}={meta['build']}"
        subprocess.run(
            ["pixi", "exec", "-c", "https://conda.modular.com/max", "-c", "conda-forge", "-s", spec, "--", "true"],
            check=True,
        )
        lic = find()
    if lic is None:
        raise SystemExit(f"no info/licenses for {name} in the rattler cache")
    return lic


def linked_env_libs(binary: Path) -> set[str]:
    """Libraries the binary links that resolve into the pixi env (Linux only)."""
    if sys.platform == "darwin":
        return set()
    out = subprocess.run(["ldd", str(ROOT / "build" / "eva")], capture_output=True, text=True).stdout
    return {Path(m).name for m in re.findall(r"=> (\S+)", out) if str(env_lib()) in m}


def main() -> None:
    target = sys.argv[1]
    ver = version()
    ext = ".dylib" if sys.platform == "darwin" else ".so"
    top = f"eva-v{ver}-{target}"
    lic = modular_licenses()

    with tempfile.TemporaryDirectory() as tmp:
        stage = Path(tmp) / top
        (stage / "bin").mkdir(parents=True)
        (stage / "lib").mkdir()
        relocated_binary(stage / "bin" / "eva", "../lib")
        libs = {name + ext for name in RUNTIME_LIBS} | linked_env_libs(stage / "bin" / "eva")
        for lib in sorted(libs):
            shutil.copy(env_lib() / lib, stage / "lib" / lib)
        shutil.copy(ROOT / "LICENSE", stage / "LICENSE")
        shutil.copy(ROOT / "README.md", stage / "README.md")
        shutil.copy(lic / "LICENSE", stage / "LICENSE-MODULAR")
        if (lic / "Third-Party-Notices").exists():
            shutil.copy(lic / "Third-Party-Notices", stage / "THIRD-PARTY-NOTICES-MODULAR")

        out = ROOT / "dist" / f"{top}.tar.gz"
        out.parent.mkdir(exist_ok=True)
        with tarfile.open(out, "w:gz") as tar:
            tar.add(stage, arcname=top)
    digest = hashlib.sha256(out.read_bytes()).hexdigest()
    out.with_name(out.name + ".sha256").write_text(f"{digest}  {out.name}\n")
    print(out)


if __name__ == "__main__":
    main()
