"""EvaTeam JSON-RPC 2.2 client.

Mojo's standard library has no TLS, so the HTTPS POST itself goes through
Python's urllib. Building the request and reading the reply stay in Mojo.
"""

from std.os import getenv
from std.sys import stderr
from std.os.path import exists, expanduser
from std.python import Python, PythonObject

from eva.json import JsonDoc, NO_NODE, quote
from eva.pyfind import ensure_python

comptime HTTP_HELPER = """
import ssl, urllib.request, urllib.error

def post(url, token, body, timeout, insecure):
    req = urllib.request.Request(
        url,
        data=body.encode("utf-8"),
        method="POST",
        headers={
            "Content-Type": "application/json",
            "Authorization": "Bearer " + token,
            "User-Agent": "eva-cli",
        },
    )
    ctx = ssl._create_unverified_context() if insecure else None
    try:
        with urllib.request.urlopen(req, timeout=timeout, context=ctx) as r:
            return r.status, r.read().decode("utf-8", "replace")
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode("utf-8", "replace")
    except (urllib.error.URLError, OSError) as e:
        return 0, str(getattr(e, "reason", e))
"""


struct Config(Copyable, Movable):
    var url: String
    var token: String
    var insecure: Bool
    # Where the settings came from, for `eva config`.
    var source: String

    def __init__(out self):
        self.url = ""
        self.token = ""
        self.insecure = False
        self.source = ""


def strip_quotes(v: String) -> String:
    var s = String(v.strip())
    if s.byte_length() >= 2:
        var first = s[byte=0:1]
        var last = s[byte = s.byte_length() - 1 : s.byte_length()]
        if (first == '"' and last == '"') or (first == "'" and last == "'"):
            return String(s[byte = 1 : s.byte_length() - 1])
    return s


def read_env_file(path: String, mut cfg: Config) raises -> Bool:
    """Fill unset fields from a KEY=VALUE file. True if it set anything."""
    if not exists(path):
        return False
    var text: String
    with open(path, "r") as f:
        text = f.read()
    var touched = False
    for raw in text.split("\n"):
        var line = String(raw.strip())
        if line.byte_length() == 0 or line.startswith("#"):
            continue
        if line.startswith("export "):
            var rest = String(line[byte=7:])
            line = rest^
        var eq = line.find("=")
        if eq < 0:
            continue
        var key = String(line[byte=0:eq].strip())
        var val = strip_quotes(String(line[byte = eq + 1 :]))
        if key == "EVA_URL" and cfg.url == "":
            cfg.url = val
            touched = True
        elif (key == "EVA_API_KEY" or key == "EVA_TOKEN") and cfg.token == "":
            cfg.token = val
            touched = True
        elif key == "EVA_INSECURE" and is_truthy(val):
            cfg.insecure = True
    return touched


def is_truthy(v: String) -> Bool:
    var s = v.lower()
    return s == "1" or s == "true" or s == "yes"


def load_config() raises -> Config:
    """Environment first, then ./.env, then ~/.config/eva-cli/env."""
    var cfg = Config()
    cfg.url = getenv("EVA_URL")
    cfg.token = getenv("EVA_API_KEY")
    if cfg.token == "":
        cfg.token = getenv("EVA_TOKEN")
    cfg.insecure = is_truthy(getenv("EVA_INSECURE"))
    var sources = List[String]()
    if cfg.url != "" or cfg.token != "":
        sources.append("env")
    if read_env_file(".env", cfg):
        sources.append("./.env")
    var home_file = expanduser("~/.config/eva-cli/env")
    if read_env_file(home_file, cfg):
        sources.append(home_file)
    cfg.source = ", ".join(sources) if len(sources) > 0 else "nothing"
    while cfg.url.endswith("/"):
        var trimmed = String(cfg.url[byte = 0 : cfg.url.byte_length() - 1])
        cfg.url = trimmed^
    if cfg.url.endswith("/api"):
        var base = String(cfg.url[byte = 0 : cfg.url.byte_length() - 4])
        cfg.url = base^
    if cfg.url != "" and not cfg.url.startswith("http"):
        cfg.url = "https://" + cfg.url
    return cfg^


struct Reply(Movable):
    var doc: JsonDoc
    var result: Int

    def __init__(out self, var doc: JsonDoc, result: Int):
        self.doc = doc^
        self.result = result


struct Client(Movable):
    var cfg: Config
    var verbose: Bool
    var _post: PythonObject

    def __init__(out self, var cfg: Config, verbose: Bool) raises:
        if cfg.url == "":
            raise Error(
                "EVA_URL is not set: export EVA_URL=https://eva.example.ru"
                " or put it in ./.env"
            )
        if cfg.token == "":
            raise Error(
                "EVA_API_KEY is not set: create a token on your EvaTeam page,"
                " Безопасность → Сгенерировать API токен"
            )
        self.cfg = cfg^
        self.verbose = verbose
        ensure_python()
        var ns = Python.dict()
        var builtins = Python.import_module("builtins")
        _ = builtins.exec(HTTP_HELPER, ns)
        self._post = ns["post"]

    def call(
        self,
        method: String,
        kwargs: String = "",
        args: String = "",
        flags: String = "",
    ) raises -> Reply:
        """Call `method`. kwargs, args and flags are JSON text or ""."""
        var uuid = Python.import_module("uuid")
        var body = String('{"jsonrpc":"2.2","no_meta":true,"callid":')
        body += quote(String(uuid.uuid4()))
        body += ',"method":'
        body += quote(method)
        if kwargs != "":
            body += ',"kwargs":' + kwargs
        if args != "":
            body += ',"args":' + args
        if flags != "":
            body += ',"flags":' + flags
        body += "}"
        if self.verbose:
            print("→ POST", self.cfg.url + "/api/", body, file=stderr)

        var resp = self._post(
            self.cfg.url + "/api/", self.cfg.token, body, 30, self.cfg.insecure
        )
        var status = Int(py=resp[0])
        var text = String(resp[1])
        if self.verbose:
            print("← HTTP", status, text[byte = 0 : min(text.byte_length(), 600)], file=stderr)
        if status == 0:
            raise Error("cannot reach " + self.cfg.url + ": " + text)
        if status == 401:
            raise Error("401 unauthorized: the token in EVA_API_KEY was rejected")

        var doc = JsonDoc()
        var root: Int
        try:
            root = doc.parse(text)
        except e:
            raise Error(
                "HTTP "
                + String(status)
                + ", reply is not JSON: "
                + String(text[byte = 0 : min(text.byte_length(), 200)])
            )
        var err = doc.get(root, "error")
        if err != NO_NODE and not doc.is_null(err):
            var msg = doc.text_at(err, "message")
            if msg == "":
                msg = doc.text(err)
            raise Error(method + ": " + msg + " (code " + doc.text_at(err, "code") + ")")
        # A business rule that refuses the call (a required field, a closed
        # task) comes back as HTTP 200 with "abort" and no "error".
        var abort = doc.get(root, "abort")
        if abort != NO_NODE and doc.text(abort) != "":
            raise Error(method + " refused: " + doc.text(abort))
        if status != 200:
            raise Error("HTTP " + String(status) + " from " + method)
        var result = doc.get(root, "result")
        return Reply(doc^, result)

