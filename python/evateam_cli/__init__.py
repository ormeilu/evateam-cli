"""Launcher for the `eva` binary shipped in this wheel.

The binary is compiled Mojo. It needs Mojo's runtime libraries, which come
from the mojo-compiler package on PyPI, and a libpython for its HTTPS calls,
which is the interpreter running this launcher.
"""

import os
import sys
import sysconfig
from importlib import metadata
from pathlib import Path


def _mojo_lib_dir() -> str:
    dist = metadata.distribution("mojo-compiler")
    return str(Path(dist.locate_file("modular/lib")).resolve())


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
    libs = _mojo_lib_dir()
    var = "DYLD_LIBRARY_PATH" if sys.platform == "darwin" else "LD_LIBRARY_PATH"
    env[var] = libs + (os.pathsep + env[var] if env.get(var) else "")
    if "MOJO_PYTHON_LIBRARY" not in env:
        lib = _libpython()
        if lib:
            env["MOJO_PYTHON_LIBRARY"] = lib
    os.execve(binary, [str(binary), *sys.argv[1:]], env)
