"""Pack build/eva into a platform wheel: python scripts/build_wheel.py PLATFORM_TAG.

PLATFORM_TAG is a wheel platform tag such as macosx_13_0_arm64 or
manylinux_2_34_x86_64. The version comes from pixi.toml. No build backend is
involved: a wheel is a zip with three metadata files.
"""

import base64
import hashlib
import re
import stat
import sys
import tempfile
import zipfile
from pathlib import Path

from relocate import relocated_binary

ROOT = Path(__file__).resolve().parent.parent
NAME = "evateam_cli"
MOJO_VERSION = "1.2.0"


def version() -> str:
    text = (ROOT / "pixi.toml").read_text()
    return re.search(r'^version = "([^"]+)"', text, re.M).group(1)


def record_line(path: str, data: bytes) -> str:
    digest = base64.urlsafe_b64encode(hashlib.sha256(data).digest()).rstrip(b"=").decode()
    return f"{path},sha256={digest},{len(data)}"


def main() -> None:
    tag = sys.argv[1]
    ver = version()
    dist_info = f"{NAME}-{ver}.dist-info"
    readme = (ROOT / "README.md").read_text()
    files: dict[str, tuple[bytes, int]] = {}

    for src in sorted((ROOT / "python" / NAME).glob("*.py")):
        files[f"{NAME}/{src.name}"] = (src.read_bytes(), 0o644)
    with tempfile.TemporaryDirectory() as tmp:
        # The wheel puts eva in site-packages/evateam_cli/bin/ and mojo-compiler
        # puts the runtime in site-packages/modular/lib/.
        eva = relocated_binary(Path(tmp) / "eva", "../../modular/lib")
        files[f"{NAME}/bin/eva"] = (eva.read_bytes(), 0o755)
    files[f"{dist_info}/licenses/LICENSE"] = ((ROOT / "LICENSE").read_bytes(), 0o644)
    files[f"{dist_info}/METADATA"] = (
        f"""Metadata-Version: 2.4
Name: evateam-cli
Version: {ver}
Summary: EvaTeam from the command line, written in Mojo
Author: Ilya Lubenets
License-Expression: MIT
License-File: LICENSE
Project-URL: Source, https://github.com/ormeilu/evateam-cli
Requires-Python: >=3.10
Requires-Dist: mojo-compiler=={MOJO_VERSION}
Description-Content-Type: text/markdown

{readme}""".encode(),
        0o644,
    )
    files[f"{dist_info}/WHEEL"] = (
        f"Wheel-Version: 1.0\nGenerator: evateam-cli build_wheel.py\nRoot-Is-Purelib: false\nTag: py3-none-{tag}\n".encode(),
        0o644,
    )
    files[f"{dist_info}/entry_points.txt"] = (b"[console_scripts]\neva = evateam_cli:main\n", 0o644)

    record = [record_line(p, d) for p, (d, _) in files.items()]
    record.append(f"{dist_info}/RECORD,,")
    files[f"{dist_info}/RECORD"] = (("\n".join(record) + "\n").encode(), 0o644)

    out = ROOT / "dist" / f"{NAME}-{ver}-py3-none-{tag}.whl"
    out.parent.mkdir(exist_ok=True)
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as zf:
        for path, (data, mode) in files.items():
            info = zipfile.ZipInfo(path, date_time=(1980, 1, 1, 0, 0, 0))
            info.external_attr = (stat.S_IFREG | mode) << 16
            info.compress_type = zipfile.ZIP_DEFLATED
            zf.writestr(info, data)
    print(out)


if __name__ == "__main__":
    main()
