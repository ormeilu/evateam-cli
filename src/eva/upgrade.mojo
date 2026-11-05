"""`eva upgrade`: update eva the same way it was installed.

The install method shows in where the binary lives: a release archive
unpacked by install.sh, a pixi global environment, a uv or pipx tool venv, or
a source checkout.
"""

from std.python import Python

from eva.pyfind import ensure_python

comptime UPGRADE_HELPER = """
import os, shutil, subprocess, sys

INSTALL_URL = "https://raw.githubusercontent.com/ormeilu/evateam-cli/main/install.sh"

def upgrade(argv0):
    exe = os.path.realpath(shutil.which(argv0) or argv0)
    cmd = None
    if os.sep + os.path.join("envs", "evateam-cli") + os.sep in exe:
        pixi = shutil.which("pixi") or os.path.expanduser("~/.pixi/bin/pixi")
        cmd = [pixi, "global", "update", "evateam-cli"]
    elif os.sep + "site-packages" + os.sep in exe:
        if os.sep + os.path.join("uv", "tools") + os.sep in exe:
            cmd = ["uv", "tool", "upgrade", "evateam-cli"]
        elif os.sep + "pipx" + os.sep in exe:
            cmd = ["pipx", "upgrade", "evateam-cli"]
        elif os.sep + os.path.join("uv", "archive") in exe:
            print("eva runs through uvx; `uvx --refresh --from evateam-cli eva` fetches the latest", flush=True)
            return 0
        else:
            print("eva was installed with pip: pip install -U evateam-cli", flush=True)
            return 0
    elif os.path.isfile(os.path.join(os.path.dirname(os.path.dirname(exe)), "LICENSE-MODULAR")):
        # A release archive unpacked by install.sh into <install dir>/<version>/.
        install_dir = os.path.dirname(os.path.dirname(os.path.dirname(exe)))
        cmd = ["sh", "-c", "curl -fsSL " + INSTALL_URL + ' | EVA_INSTALL_DIR="$0" sh', install_dir]
    else:
        print("eva at " + exe + " looks built from source: git pull && pixi run build", flush=True)
        return 0
    print("-> " + " ".join(cmd), file=sys.stderr, flush=True)
    # The wheel's launcher sets these for eva's embedded Python; a Python tool
    # such as pipx must not inherit them.
    env = {k: v for k, v in os.environ.items() if k not in ("PYTHONHOME", "MOJO_PYTHON_LIBRARY")}
    try:
        return subprocess.call(cmd, env=env)
    except FileNotFoundError:
        print("eva: " + cmd[0] + " is not on PATH", file=sys.stderr, flush=True)
        return 1
"""


def upgrade(argv0: String) raises -> Int:
    ensure_python()
    var ns = Python.dict()
    var builtins = Python.import_module("builtins")
    _ = builtins.exec(UPGRADE_HELPER, ns)
    return Int(py=ns["upgrade"](argv0))
