"""`eva upgrade`: update eva the same way it was installed.

The install method shows in where the binary lives: a release archive
unpacked by install.sh, a pixi global environment, a uv or pipx tool venv, or
a source checkout.
"""

from std.ffi import external_call, c_int
from std.os.path import exists

from requests._dns import _cstr
from requests._tls import _self_exe

comptime INSTALL_URL = "https://raw.githubusercontent.com/ormeilu/evateam-cli/main/install.sh"


def dirname(path: String) -> String:
    var slash = path.rfind("/")
    return String(path[byte=0:slash]) if slash > 0 else String("/")


def shell_quote(s: String) -> String:
    return "'" + s.replace("'", "'\\''") + "'"


def run_shell(cmd: String) -> Int:
    """Run `cmd` with /bin/sh, output going straight to the terminal."""
    print("-> " + cmd)
    var c = _cstr(cmd)
    var status = Int(external_call["system", c_int](c))
    c.unsafe_free()
    if status < 0:
        return 1
    return (status >> 8) & 0xFF


def upgrade() -> Int:
    var exe = _self_exe()
    if exe.find("/envs/evateam-cli/") >= 0:
        return run_shell('PATH="$PATH:$HOME/.pixi/bin" pixi global update evateam-cli')
    var root = dirname(dirname(exe))
    if exists(root + "/lib/evateam-cli"):
        # The PyPI wheel: <prefix>/bin/eva with its libraries in <prefix>/lib/evateam-cli.
        if exe.find("/uv/tools/") >= 0:
            return run_shell("uv tool upgrade evateam-cli")
        if exe.find("/pipx/") >= 0:
            return run_shell("pipx upgrade evateam-cli")
        if exe.find("/uv/archive") >= 0:
            print("eva runs through uvx; `uvx --refresh --from evateam-cli eva` fetches the latest")
            return 0
        print("eva was installed with pip: pip install -U evateam-cli")
        return 0
    if exists(root + "/LICENSE-MODULAR"):
        # A release archive unpacked by install.sh into <install dir>/<version>/.
        return run_shell(
            "curl -fsSL " + INSTALL_URL + " | EVA_INSTALL_DIR=" + shell_quote(dirname(root)) + " sh"
        )
    print("eva at " + exe + " looks built from source: git pull && pixi run build")
    return 0
