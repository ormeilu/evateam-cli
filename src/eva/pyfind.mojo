"""Find a libpython for Mojo's Python interop before it starts.

eva makes its HTTPS calls through Python, and Mojo's own lookup gives up on
some interpreters (Apple's Python3.framework, venvs). When MOJO_PYTHON_LIBRARY
is unset, ask the first Python 3.10+ on PATH where its library is.
"""

from std.os import getenv, setenv
from std.subprocess import run

# Runs under /bin/sh; the Python program must not contain single quotes.
comptime FIND_SCRIPT = """for py in python3.14 python3.13 python3.12 python3.11 python3.10 python3; do
  command -v "$py" >/dev/null 2>&1 && "$py" -c '
import os, sys, sysconfig
if sys.version_info < (3, 10):
    raise SystemExit(1)
v = sysconfig.get_config_var
ver = "%d.%d" % sys.version_info[:2]
names = [v("LDLIBRARY") or "", v("INSTSONAME") or "", "libpython" + ver + ".dylib",
         "libpython" + ver + ".so.1.0", "libpython" + ver + ".so"]
dirs = [v("LIBDIR") or "", os.path.join(sys.base_prefix, "lib"), v("PYTHONFRAMEWORKPREFIX") or ""]
found = ""
for d in dirs:
    for n in names:
        if d and n and not n.endswith(".a") and os.path.isfile(os.path.join(d, n)):
            found = found or os.path.join(d, n)
if not found and os.path.isfile(os.path.join(sys.base_prefix, "Python")):
    found = os.path.join(sys.base_prefix, "Python")
if not found:
    raise SystemExit(1)
print(found)
print(sys.base_prefix if sys.prefix != sys.base_prefix else "")
' 2>/dev/null && exit 0
done
exit 0"""


def ensure_python() raises:
    if getenv("MOJO_PYTHON_LIBRARY") != "":
        return
    var lines = run(FIND_SCRIPT).split("\n")
    var lib = String(lines[0].strip()) if len(lines) > 0 else String("")
    if lib == "":
        raise Error(
            "eva needs Python 3.10 or newer on PATH for its HTTPS calls"
            " (brew install python3, apt install python3), or MOJO_PYTHON_LIBRARY"
            " set to a libpython"
        )
    _ = setenv("MOJO_PYTHON_LIBRARY", lib)
    # A venv's interpreter, embedded, cannot find its prefix on its own.
    var home = String(lines[1].strip()) if len(lines) > 1 else String("")
    if home != "" and getenv("PYTHONHOME") == "":
        _ = setenv("PYTHONHOME", home)
