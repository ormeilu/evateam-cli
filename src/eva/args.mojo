"""Command-line parsing: positionals plus `--name value`, `-n value`,
`--name=value`, and boolean switches."""

def is_bool_flag(name: String) -> Bool:
    """Switches that never take a value."""
    return (
        name == "help"
        or name == "h"
        or name == "json"
        or name == "full"
        or name == "verbose"
        or name == "v"
        or name == "version"
        or name == "insecure"
        or name == "md"
        or name == "html"
        or name == "human"
        or name == "ids"
        or name == "path"
        or name == "force"
        or name == "yes"
        or name == "y"
    )


struct Args(Movable):
    var positionals: List[String]
    var keys: List[String]
    var values: List[String]

    def __init__(out self, argv: List[String]) raises:
        self.positionals = List[String]()
        self.keys = List[String]()
        self.values = List[String]()
        var i = 0
        var only_positionals = False
        while i < len(argv):
            var a = argv[i]
            i += 1
            if only_positionals or not a.startswith("-") or a == "-":
                self.positionals.append(a)
                continue
            if a == "--":
                only_positionals = True
                continue
            var name = String(a[byte=2:]) if a.startswith("--") else String(a[byte=1:])
            var eq = name.find("=")
            if eq >= 0:
                self.keys.append(String(name[byte=0:eq]))
                self.values.append(String(name[byte = eq + 1 :]))
                continue
            if is_bool_flag(name):
                self.keys.append(name)
                self.values.append("true")
                continue
            if i >= len(argv):
                raise Error("option " + a + " needs a value")
            self.keys.append(name)
            self.values.append(argv[i])
            i += 1

    def get(self, long: String, short: String = "") -> String:
        """Last value given for --long or -short, or ""."""
        var out = String()
        for i in range(len(self.keys)):
            if self.keys[i] == long or (short != "" and self.keys[i] == short):
                out = self.values[i]
        return out

    def take(mut self, long: String) -> String:
        """Remove --long from the options and return its last value, or ""."""
        var value = String()
        var keys = List[String]()
        var values = List[String]()
        for i in range(len(self.keys)):
            if self.keys[i] == long:
                value = self.values[i]
            else:
                keys.append(self.keys[i])
                values.append(self.values[i])
        self.keys = keys^
        self.values = values^
        return value

    def has(self, long: String, short: String = "") -> Bool:
        for i in range(len(self.keys)):
            if self.keys[i] == long or (short != "" and self.keys[i] == short):
                return True
        return False

    def pos(self, i: Int) -> String:
        if i < len(self.positionals):
            return self.positionals[i]
        return ""

    def need(self, i: Int, what: String) raises -> String:
        if i >= len(self.positionals):
            raise Error("missing " + what)
        return self.positionals[i]

    def int_or(self, long: String, short: String, default: Int) raises -> Int:
        var v = self.get(long, short)
        if v == "":
            return default
        try:
            return Int(v)
        except:
            raise Error("--" + long + " expects a number, got " + v)

    def check_known(self, allowed: List[String]) raises:
        """Reject options this command does not take."""
        for k in self.keys:
            var ok = False
            for a in allowed:
                if k == a:
                    ok = True
                    break
            if not ok:
                var dash = "--" if k.byte_length() > 1 else "-"
                raise Error("unknown option " + dash + k)
