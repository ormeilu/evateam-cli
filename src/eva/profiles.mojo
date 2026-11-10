"""Profile names and the default, in ~/.config/eva-cli/profiles.

The file holds no secrets, only which profiles exist and which one is used when
none is named; the address and token of each live in the OS keychain.

    default=s7
    profile=s7
    profile=sandbox
"""

from std.os import makedirs
from std.os.path import exists, expanduser

comptime PROFILES_FILE = "~/.config/eva-cli/profiles"


def valid_profile_name(name: String) -> Bool:
    """1-64 of [A-Za-z0-9._-]: safe in a keychain label, a file and a shell."""
    var n = name.byte_length()
    if n == 0 or n > 64:
        return False
    for b in name.as_bytes():
        var c = Int(b)
        var ok = (
            (c >= 0x30 and c <= 0x39)
            or (c >= 0x41 and c <= 0x5A)
            or (c >= 0x61 and c <= 0x7A)
            or c == 0x2E
            or c == 0x5F
            or c == 0x2D
        )
        if not ok:
            return False
    return True


def check_profile_name(name: String) raises:
    if not valid_profile_name(name):
        raise Error("profile name '" + name + "' is not allowed: use 1-64 letters, digits, '.', '_' or '-'")


struct Profiles(Movable):
    var default: String
    var names: List[String]

    def __init__(out self):
        self.default = ""
        self.names = List[String]()

    def has(self, name: String) -> Bool:
        for n in self.names:
            if n == name:
                return True
        return False

    def add(mut self, name: String):
        if not self.has(name):
            self.names.append(name)
        if self.default == "":
            self.default = name

    def remove(mut self, name: String):
        var kept = List[String]()
        for n in self.names:
            if n != name:
                kept.append(n)
        self.names = kept^
        if self.default == name:
            self.default = self.names[0] if len(self.names) > 0 else String("")


def profiles_path() raises -> String:
    return expanduser(PROFILES_FILE)


def load_profiles() raises -> Profiles:
    var p = Profiles()
    var path = profiles_path()
    if not exists(path):
        return p^
    var text: String
    with open(path, "r") as f:
        text = f.read()
    for raw in text.split("\n"):
        var line = String(raw.strip())
        var eq = line.find("=")
        if eq < 0:
            continue
        var key = String(line[byte=0:eq])
        var val = String(line[byte = eq + 1 :])
        if not valid_profile_name(val):
            continue
        if key == "default":
            p.default = val
        elif key == "profile":
            p.add(val)
    return p^


def save_profiles(p: Profiles) raises:
    var path = profiles_path()
    var slash = path.rfind("/")
    makedirs(String(path[byte=0:slash]), exist_ok=True)
    var text = String()
    if p.default != "":
        text += "default=" + p.default + "\n"
    for n in p.names:
        text += "profile=" + n + "\n"
    with open(path, "w") as f:
        f.write(text)
