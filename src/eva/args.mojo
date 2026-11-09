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
        or name == "classes"
        or name == "relations"
        or name == "refresh"
        or name == "dry-run"
        or name == "undo"
        or name == "all"
        or name == "archived"
        or name == "publish"
        or name == "yes"
        or name == "y"
        or name == "off"
        or name == "children"
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
            var name = String(a[byte=2:]) if a.startswith("--") else String(
                a[byte=1:]
            )
            var eq = name.find("=")
            var key = String(name[byte=0:eq]) if eq >= 0 else name
            var doc_version = (
                key == "version"
                and len(self.positionals) >= 2
                and (self.pos(0) == "doc" or self.pos(0) == "docs")
                and (self.pos(1) == "get" or self.pos(1) == "show")
            )
            var switch = is_bool_flag(key) and not doc_version
            if eq >= 0:
                var value = String(name[byte = eq + 1 :])
                # --yes=false must not read as yes.
                if switch and value != "true":
                    raise Error(
                        "option --" + key + " is a switch; drop =" + value
                    )
                self.keys.append(key)
                self.values.append(value)
                continue
            if switch:
                self.keys.append(name)
                self.values.append("true")
                continue
            if i >= len(argv):
                raise Error("option " + a + " needs a value")
            # `-m $EMPTY --dry-run` must not turn --dry-run into the comment.
            if argv[i].startswith("--") and argv[i].byte_length() > 2:
                raise Error(
                    "option "
                    + a
                    + " needs a value, not "
                    + argv[i]
                    + "; write "
                    + a
                    + "=VALUE for a value that starts with --"
                )
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
                var msg = "unknown option " + dash + k
                if k.byte_length() > 1:
                    var longs = List[String]()
                    for a in allowed:
                        if a.byte_length() > 1:
                            longs.append(a)
                    var near = closest(k, longs)
                    if near != "":
                        msg += "; did you mean --" + near + "?"
                raise Error(msg)


def edit_distance(a: String, b: String) -> Int:
    """Edits between two names, a swap of neighbours counting as one
    (optimal string alignment over bytes; names are ASCII)."""
    var x = a.as_bytes()
    var y = b.as_bytes()
    var before = List[Int]()
    var prev = List[Int]()
    for j in range(len(y) + 1):
        prev.append(j)
    for i in range(1, len(x) + 1):
        var cur = List[Int]()
        cur.append(i)
        for j in range(1, len(y) + 1):
            var cost = 0 if x[i - 1] == y[j - 1] else 1
            var d = min(min(prev[j] + 1, cur[j - 1] + 1), prev[j - 1] + cost)
            if (
                i > 1
                and j > 1
                and x[i - 1] == y[j - 2]
                and x[i - 2] == y[j - 1]
            ):
                d = min(d, before[j - 2] + 1)
            cur.append(d)
        before = prev^
        prev = cur^
    return prev[len(y)]


def closest(word: String, candidates: List[String]) -> String:
    """The candidate a typo most likely meant, or "" when none is close:
    at most two edits away (one for short words), or a unique prefix."""
    if word.byte_length() < 2:
        return ""
    var best = String("")
    var best_d = 3 if word.byte_length() > 3 else 2
    var prefixed = List[String]()
    for c in candidates:
        if c == word:
            return c
        if word.byte_length() >= 3 and c.startswith(word):
            prefixed.append(c)
        var d = edit_distance(word, c)
        if d < best_d:
            best = c
            best_d = d
    if best == "" and len(prefixed) == 1:
        return prefixed[0]
    return best
