"""Pack build/eva into a self-contained release archive:
python scripts/build_archive.py TARGET, e.g. aarch64-apple-darwin.

The archive holds bin/eva, Mojo's runtime libraries and OpenSSL in lib/ (the
binary's rpath is ../lib, and its TLS layer looks for libssl there too), and
the licences. It needs nothing from the system but a CA bundle.
"""

import hashlib
import shutil
import sys
import tarfile
import tempfile
from pathlib import Path

from bundle import libraries, licenses, version
from relocate import ROOT, relocated_binary


def main() -> None:
    target = sys.argv[1]
    top = f"eva-v{version()}-{target}"

    with tempfile.TemporaryDirectory() as tmp:
        stage = Path(tmp) / top
        (stage / "bin").mkdir(parents=True)
        (stage / "lib").mkdir()
        relocated_binary(stage / "bin" / "eva", "../lib")
        for lib in libraries():
            shutil.copy(lib, stage / "lib" / lib.name)
        for shipped, src in licenses().items():
            shutil.copy(src, stage / shipped)
        shutil.copy(ROOT / "README.md", stage / "README.md")

        out = ROOT / "dist" / f"{top}.tar.gz"
        out.parent.mkdir(exist_ok=True)
        with tarfile.open(out, "w:gz") as tar:
            tar.add(stage, arcname=top)
    digest = hashlib.sha256(out.read_bytes()).hexdigest()
    out.with_name(out.name + ".sha256").write_text(f"{digest}  {out.name}\n")
    print(out)


if __name__ == "__main__":
    main()
