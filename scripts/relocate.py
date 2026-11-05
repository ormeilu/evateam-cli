"""Copy build/eva with its rpath pointed somewhere other than the pixi env."""

import re
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def relocated_binary(out: Path, rpath: str) -> Path:
    """Write build/eva to `out` with `rpath` as its only rpath.

    `rpath` is relative to the binary: "../lib" becomes @loader_path/../lib on
    macOS and $ORIGIN/../lib on Linux.
    """
    shutil.copy(ROOT / "build" / "eva", out)
    if sys.platform == "darwin":
        load = subprocess.run(["otool", "-l", str(out)], capture_output=True, text=True, check=True).stdout
        for old in re.findall(r"cmd LC_RPATH\n\s+cmdsize \d+\n\s+path (\S+)", load):
            subprocess.run(["install_name_tool", "-delete_rpath", old, str(out)], check=True)
        subprocess.run(["install_name_tool", "-add_rpath", f"@loader_path/{rpath}", str(out)], check=True)
        # Editing load commands breaks the ad-hoc signature arm64 requires.
        subprocess.run(["codesign", "--force", "--sign", "-", str(out)], check=True, capture_output=True)
    else:
        subprocess.run(["patchelf", "--set-rpath", f"$ORIGIN/{rpath}", str(out)], check=True)
    return out
