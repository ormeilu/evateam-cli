"""Launcher for the `eva` binary shipped in this wheel.

The binary is compiled Mojo. Its rpath finds Mojo's runtime libraries in the
mojo-compiler package next to this one in site-packages. For its HTTPS calls
it embeds a libpython, and this launcher points it at the interpreter that is
running here.
"""

import os
import sys
import sysconfig
from pathlib import Path


def _libpython() -> str | None:
    libdir = sysconfig.get_config_var("LIBDIR") or ""
    names = [
        sysconfig.get_config_var("LDLIBRARY") or "",
        sysconfig.get_config_var("INSTSONAME") or "",
        f"libpython{sysconfig.get_python_version()}.dylib",
        f"libpython{sysconfig.get_python_version()}.so.1.0",
        f"libpython{sysconfig.get_python_version()}.so",
    ]
    for name in names:
        if name and not name.endswith(".a"):
            path = Path(libdir) / name
            if path.exists():
                return str(path)
    framework = sysconfig.get_config_var("PYTHONFRAMEWORKPREFIX")
    if framework:
        path = Path(framework) / "Python.framework" / "Versions" / sysconfig.get_python_version() / "Python"
        if path.exists():
            return str(path)
    return None


def main() -> None:
    binary = Path(__file__).parent / "bin" / "eva"
    env = dict(os.environ)
    if "MOJO_PYTHON_LIBRARY" not in env:
        lib = _libpython()
        if lib:
            env["MOJO_PYTHON_LIBRARY"] = lib
            # From a venv the embedded interpreter cannot find its own prefix.
            env.setdefault("PYTHONHOME", sys.base_prefix)
    os.execve(binary, [str(binary), *sys.argv[1:]], env)
