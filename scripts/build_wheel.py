"""Pack build/eva into a platform wheel: python scripts/build_wheel.py PLATFORM_TAG.

PLATFORM_TAG is a wheel platform tag such as macosx_13_0_arm64 or
manylinux_2_34_x86_64. The version comes from pixi.toml. No build backend is
involved: a wheel is a zip with three metadata files.

The wheel holds no Python. The binary goes in the wheel's .data/scripts, which
installers put straight into the environment's bin/, and the libraries in
.data/data/lib/evateam-cli, which lands in <prefix>/lib/evateam-cli: the
binary's rpath is ../lib/evateam-cli and its TLS layer looks there for libssl.
A subdirectory keeps them clear of a conda env's own libssl.
"""

import base64
import hashlib
import stat
import sys
import tempfile
import zipfile
from pathlib import Path

from bundle import libraries, licenses, version
from relocate import ROOT, relocated_binary

NAME = "evateam_cli"


def record_line(path: str, data: bytes) -> str:
    digest = base64.urlsafe_b64encode(hashlib.sha256(data).digest()).rstrip(b"=").decode()
    return f"{path},sha256={digest},{len(data)}"


def main() -> None:
    tag = sys.argv[1]
    ver = version()
    dist_info = f"{NAME}-{ver}.dist-info"
    data = f"{NAME}-{ver}.data"
    readme = (ROOT / "README.md").read_text()
    files: dict[str, tuple[bytes, int]] = {}

    with tempfile.TemporaryDirectory() as tmp:
        eva = relocated_binary(Path(tmp) / "eva", "../lib/evateam-cli")
        files[f"{data}/scripts/eva"] = (eva.read_bytes(), 0o755)
    for lib in libraries():
        files[f"{data}/data/lib/evateam-cli/{lib.name}"] = (lib.read_bytes(), 0o755)
    license_files = licenses()
    for shipped, src in license_files.items():
        files[f"{dist_info}/licenses/{shipped}"] = (src.read_bytes(), 0o644)
    license_headers = "".join(f"License-File: {name}\n" for name in license_files)
    files[f"{dist_info}/METADATA"] = (
        f"""Metadata-Version: 2.4
Name: evateam-cli
Version: {ver}
Summary: EvaTeam from the command line, written in Mojo
Author: Ilya Lubenets
License-Expression: MIT
{license_headers}Project-URL: Source, https://github.com/ormeilu/evateam-cli
Description-Content-Type: text/markdown

{readme}""".encode(),
        0o644,
    )
    files[f"{dist_info}/WHEEL"] = (
        f"Wheel-Version: 1.0\nGenerator: evateam-cli build_wheel.py\nRoot-Is-Purelib: false\nTag: py3-none-{tag}\n".encode(),
        0o644,
    )

    record = [record_line(p, d) for p, (d, _) in files.items()]
    record.append(f"{dist_info}/RECORD,,")
    files[f"{dist_info}/RECORD"] = (("\n".join(record) + "\n").encode(), 0o644)

    out = ROOT / "dist" / f"{NAME}-{ver}-py3-none-{tag}.whl"
    out.parent.mkdir(exist_ok=True)
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as zf:
        for path, (blob, mode) in files.items():
            info = zipfile.ZipInfo(path, date_time=(1980, 1, 1, 0, 0, 0))
            info.external_attr = (stat.S_IFREG | mode) << 16
            info.compress_type = zipfile.ZIP_DEFLATED
            zf.writestr(info, blob)
    print(out)


if __name__ == "__main__":
    main()
