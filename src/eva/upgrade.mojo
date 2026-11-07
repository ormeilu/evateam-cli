"""`eva upgrade`: update eva the same way it was installed.

The install method shows in where the binary lives: a release archive
unpacked by install.sh, a pixi global environment, a uv or pipx tool venv, or
a source checkout.
"""

from std.ffi import external_call, c_int
from std.os.path import exists

import requests
from requests._dns import _cstr

from eva.client import ca_bundle
from requests._tls import _self_exe

comptime INSTALL_URL = "https://raw.githubusercontent.com/ormeilu/evateam-cli/main/install.sh"
# install.sh finds the newest release the same way: /releases/latest redirects
# to /releases/tag/vX.Y.Z, and reading the redirect needs no API token.
comptime LATEST_URL = "https://github.com/ormeilu/evateam-cli/releases/latest"


def clean_version(raw: String) -> String:
    """A version string from the network, or "" when it does not look like one.
    It ends up on the terminal, so only digits, letters, dots and dashes pass.
    """
    var v = String(raw.strip())
    if v.startswith("v"):
        var rest = String(v[byte=1:])
        v = rest
    if v.byte_length() == 0 or v.byte_length() > 32:
        return ""
    var bytes = v.as_bytes()
    if Int(bytes[0]) < ord("0") or Int(bytes[0]) > ord("9"):
        return ""
    for byte in bytes:
        var b = Int(byte)
        var ok = (
            (b >= ord("0") and b <= ord("9"))
            or (b >= ord("a") and b <= ord("z"))
            or (b >= ord("A") and b <= ord("Z"))
            or b == ord(".")
            or b == ord("-")
        )
        if not ok:
            return ""
    return v


def version_from_location(location: String) -> String:
    """The version in a `.../releases/tag/vX.Y.Z` redirect target, or ""."""
    var slash = location.rfind("/")
    var tag = String(location[byte = slash + 1 :])
    if not tag.startswith("v"):
        return ""
    return clean_version(tag)


def latest_release(url: String, timeout: Float64) raises -> String:
    """The newest release's version from where `url` redirects, or "" when the
    reply names none. No credentials go out and no redirect is followed."""
    var headers = Dict[String, String]()
    headers["User-Agent"] = "eva-cli"
    # A release build bundles OpenSSL, whose default CA path is the build
    # machine's; without the system bundle every handshake fails.
    var ca: Optional[String] = None
    var bundle = ca_bundle()
    if bundle != "":
        ca = bundle
    var resp = requests.get(
        url,
        headers=headers^,
        timeout=timeout,
        allow_redirects=False,
        ca_bundle=ca,
    )
    if resp.status_code < 300 or resp.status_code >= 400:
        return ""
    if not resp.headers.contains("location"):
        return ""
    return version_from_location(resp.headers["location"])


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
