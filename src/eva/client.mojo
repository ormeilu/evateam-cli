"""EvaTeam JSON-RPC 2.2 client.

HTTPS goes through the vendored `requests` package (src/requests): sockets via
libc and TLS via OpenSSL, loaded at run time. A release ships its own
libssl/libcrypto next to the binary, so eva needs nothing from the system but a
CA bundle, which it looks up in the usual places.
"""

from std.ffi import external_call, c_int
from std.os import getenv
from std.os.path import exists, expanduser
from std.sys import stderr
from std.memory.alloc import unsafe_alloc
from std.random import random_ui64
from std.sys import CompilationTarget
from std.time import perf_counter_ns

import requests

from eva.json import JsonDoc, NO_NODE, clean, quote
from eva.keyring import keyring_get, keyring_name
from eva.profiles import check_profile_name, load_profiles
from requests._dns import _cstr

# Where systems keep the PEM bundle of trusted CAs, most common first.
comptime CA_BUNDLES = (
    "/etc/ssl/cert.pem,"  # macOS, Alpine, Arch
    "/etc/ssl/certs/ca-certificates.crt,"  # Debian, Ubuntu
    "/etc/pki/tls/certs/ca-bundle.crt,"  # Fedora, RHEL
    "/etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem,"
    "/etc/ssl/ca-bundle.pem"  # openSUSE
)


def ca_bundle() -> String:
    """The CA bundle to verify servers with, or "" for OpenSSL's defaults.

    EVA_CA_BUNDLE wins, then REQUESTS_CA_BUNDLE and SSL_CERT_FILE, then the
    system's own bundle. A bundled OpenSSL's compiled-in default points at the
    machine it was built on, so falling back to it would fail every handshake.
    """
    for var_name in ["EVA_CA_BUNDLE", "REQUESTS_CA_BUNDLE", "SSL_CERT_FILE"]:
        var v = getenv(var_name)
        if v != "":
            return v
    for path in CA_BUNDLES.split(","):
        if exists(String(path)):
            return String(path)
    return ""


def new_callid() -> String:
    """Unique per call; the server echoes it back and warns when it is missing."""
    var pid = external_call["getpid", c_int]()
    return "eva-" + String(pid) + "-" + String(perf_counter_ns()) + "-" + String(random_ui64(0, 1 << 32))


struct Config(Copyable, Movable):
    var url: String
    var token: String
    var insecure: Bool
    # Where the settings came from, for `eva config` and `eva auth status`.
    var source: String
    # The keychain profile in use, or "".
    var profile: String

    def __init__(out self):
        self.url = ""
        self.token = ""
        self.insecure = False
        self.source = ""
        self.profile = ""


def strip_quotes(v: String) -> String:
    var s = String(v.strip())
    if s.byte_length() >= 2:
        var first = s[byte=0:1]
        var last = s[byte = s.byte_length() - 1 : s.byte_length()]
        if (first == '"' and last == '"') or (first == "'" and last == "'"):
            return String(s[byte = 1 : s.byte_length() - 1])
    return s


def is_truthy(v: String) -> Bool:
    var s = v.lower()
    return s == "1" or s == "true" or s == "yes"


def _take_pair(mut cfg: Config, url: String, token: String, source: String) raises -> Bool:
    """Use `url` and `token` if `source` has them. One without the other is an
    error rather than a gap to fill from elsewhere: a stray EVA_URL in a .env
    must not receive the token kept somewhere else."""
    if url == "" and token == "":
        return False
    if url == "" or token == "":
        var has = "EVA_URL" if url != "" else "EVA_API_KEY"
        var lacks = "EVA_API_KEY" if url != "" else "EVA_URL"
        raise Error(
            source + " sets " + has + " but not " + lacks + "; eva takes both from"
            " one place, so that a token is never sent to an address from somewhere else"
        )
    cfg.url = url
    cfg.token = token
    cfg.source = source
    return True


def _file_pair(mut cfg: Config, path: String, label: String) raises -> Bool:
    if not exists(path):
        return False
    var text: String
    with open(path, "r") as f:
        text = f.read()
    var url = String()
    var token = String()
    var insecure = False
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
        if key == "EVA_URL":
            url = val
        elif key == "EVA_API_KEY" or key == "EVA_TOKEN":
            token = val
        elif key == "EVA_INSECURE":
            insecure = is_truthy(val)
    if not _take_pair(cfg, url, token, label):
        return False
    cfg.insecure = cfg.insecure or insecure
    if token != "" and _group_or_world_readable(path):
        print(
            "eva: warning: " + label + " holds a token and other users can read it;"
            " chmod 600 it, or move the token to the keychain with `eva auth login`",
            file=stderr,
        )
    return True


def _group_or_world_readable(path: String) -> Bool:
    """stat(2) the file; True if group or others may read or write it."""
    var buf = unsafe_alloc[UInt8](512)
    var c = _cstr(path)
    var rc = external_call["stat", c_int](c, buf)
    c.unsafe_free()
    var mode = 0
    if rc == 0:
        # Where struct stat keeps st_mode: after a 4-byte st_dev on macOS; after
        # st_dev, st_ino and st_nlink (8 bytes each) on x86_64 Linux; after
        # st_dev and st_ino on the generic layout aarch64 Linux uses.
        comptime if CompilationTarget.is_macos():
            mode = Int(buf[unsafe_offset=4]) | (Int(buf[unsafe_offset=5]) << 8)
        elif CompilationTarget.is_x86():
            mode = Int(buf[unsafe_offset=24]) | (Int(buf[unsafe_offset=25]) << 8)
        else:
            mode = Int(buf[unsafe_offset=16]) | (Int(buf[unsafe_offset=17]) << 8)
    buf.unsafe_free()
    return rc == 0 and (mode & 0o077) != 0


def secret_json(url: String, token: String, insecure: Bool) -> String:
    var d = JsonDoc()
    var o = d.object()
    d.set_str(o, "url", url)
    d.set_str(o, "token", token)
    if insecure:
        var t = d.boolean(True)
        d.set(o, "insecure", t)
    return d.dump(o)


def _keychain_pair(mut cfg: Config, profile: String, required: Bool) raises -> Bool:
    var secret: Optional[String]
    try:
        secret = keyring_get(profile)
    except e:
        if required:
            raise Error("profile '" + profile + "': " + String(e))
        return False
    if not secret:
        if required:
            raise Error(
                "no profile '" + profile + "' in " + keyring_name()
                + "; `eva auth login --profile " + profile + "` creates it"
            )
        return False
    var d = JsonDoc()
    var root = d.parse(secret.value())
    var ok = _take_pair(
        cfg, d.text_at(root, "url"), d.text_at(root, "token"),
        "profile '" + profile + "' in " + keyring_name(),
    )
    if ok:
        cfg.profile = profile
        cfg.insecure = cfg.insecure or d.text_at(root, "insecure") == "true"
    return ok


def url_host(url: String) -> String:
    """The host of scheme://[user@]host[:port]/..., lower-cased; "" if none."""
    var start = url.find("://")
    var rest = String(url[byte = start + 3 :]) if start >= 0 else url
    var end = rest.byte_length()
    for sep in ["/", "?", "#"]:
        var k = rest.find(sep)
        if k >= 0 and k < end:
            end = k
    var authority = String(rest[byte=0:end])
    var at = authority.rfind("@")
    if at >= 0:
        var after = String(authority[byte = at + 1 :])
        authority = after^
    if authority.startswith("["):
        var close = authority.find("]")
        return String(authority[byte = 0 : close + 1]).lower() if close > 0 else authority.lower()
    var colon = authority.find(":")
    if colon >= 0:
        var host_only = String(authority[byte=0:colon])
        authority = host_only^
    return authority.lower()


def normalize_url(raw: String, insecure: Bool) raises -> String:
    """https://host[/path] without a trailing / or /api. A token travels over
    plain http only to this machine, or when EVA_INSECURE says so."""
    var url = String(raw.strip())
    while url.endswith("/"):
        var trimmed = String(url[byte = 0 : url.byte_length() - 1])
        url = trimmed^
    if url.endswith("/api"):
        var base = String(url[byte = 0 : url.byte_length() - 4])
        url = base^
    if url == "":
        return url
    if not url.startswith("http://") and not url.startswith("https://"):
        url = "https://" + url
    if url.startswith("http://") and not insecure:
        var host = url_host(url)
        var local = host == "localhost" or host == "127.0.0.1" or host == "[::1]"
        if not local:
            raise Error(
                url + " is plain http, which would send the token unencrypted; use https,"
                " or set EVA_INSECURE=1 if this server really has no TLS"
            )
    return url


def load_config(profile_flag: String = "") raises -> Config:
    """Where the address and token come from, first match wins:

    1. --profile or EVA_PROFILE: that keychain profile and nothing else;
    2. EVA_URL and EVA_API_KEY in the environment;
    3. ./.env;
    4. the default keychain profile;
    5. ~/.config/eva-cli/env.

    Each source must supply both values.
    """
    var cfg = Config()
    cfg.insecure = is_truthy(getenv("EVA_INSECURE"))
    var profile = profile_flag if profile_flag != "" else getenv("EVA_PROFILE")
    var found: Bool
    if profile != "":
        check_profile_name(profile)
        found = _keychain_pair(cfg, profile, True)
    else:
        var env_token = getenv("EVA_API_KEY")
        if env_token == "":
            env_token = getenv("EVA_TOKEN")
        found = _take_pair(cfg, getenv("EVA_URL"), env_token, "the environment")
        if not found:
            found = _file_pair(cfg, ".env", "./.env")
        if not found:
            var profiles = load_profiles()
            var name = profiles.default if profiles.default != "" else String("default")
            found = _keychain_pair(cfg, name, profiles.default != "")
        if not found:
            found = _file_pair(cfg, expanduser("~/.config/eva-cli/env"), "~/.config/eva-cli/env")
    if not found:
        cfg.source = "nothing"
    cfg.url = normalize_url(cfg.url, cfg.insecure)
    return cfg^


struct Reply(Movable):
    var doc: JsonDoc
    var result: Int

    def __init__(out self, var doc: JsonDoc, result: Int):
        self.doc = doc^
        self.result = result


def check_files_path(path: String, what: String) raises:
    """Only a server-relative /files/ address, so the token stays on this server."""
    if not path.startswith("/files/") or path.find("..") >= 0 or path.find("//") >= 0:
        raise Error("refusing to " + what + " " + clean(path) + ": not a /files/ address on this server")


struct Client(Movable):
    var cfg: Config
    var verbose: Bool
    var ca: String

    def __init__(out self, var cfg: Config, verbose: Bool) raises:
        if cfg.url == "" or cfg.token == "":
            raise Error(
                "not signed in: run `eva auth login`, or set EVA_URL and EVA_API_KEY"
                " in the environment"
            )
        self.cfg = cfg^
        self.verbose = verbose
        self.ca = ca_bundle()

    def download(self, path: String) raises -> List[UInt8]:
        """The bytes at `path`, a server-relative /files/... address from an
        attachment. Only such paths are fetched, so the token goes to this
        EvaTeam and nowhere else."""
        check_files_path(path, "download")
        if self.verbose:
            print("→ GET", self.cfg.url + path, file=stderr)
        var headers = Dict[String, String]()
        headers["Authorization"] = "Bearer " + self.cfg.token
        headers["User-Agent"] = "eva-cli"
        var ca: Optional[String] = None
        if self.ca != "":
            ca = self.ca
        var status: Int
        var kind = String()
        var body: List[UInt8]
        try:
            var session = requests.Session()
            var resp = session.get(
                self.cfg.url + path,
                headers=headers^,
                timeout=300.0,
                verify=not self.cfg.insecure,
                ca_bundle=ca,
                allow_redirects=False,
            )
            status = resp.status_code
            if resp.headers.contains("content-type"):
                kind = resp.headers["content-type"]
            body = resp.content.copy()
        except e:
            raise Error("cannot reach " + self.cfg.url + ": " + String(e))
        if self.verbose:
            print("← HTTP", status, kind, len(body), "bytes", file=stderr)
        if status >= 300 and status < 400:
            raise Error("the file address redirects (HTTP " + String(status) + "); eva does not follow it with your token")
        if status == 401 or status == 403:
            raise Error("HTTP " + String(status) + ": the token was rejected; sign in again with `eva auth login`")
        if status != 200:
            raise Error("HTTP " + String(status) + " for " + clean(path))
        return body^

    def upload(self, path: String, file_name: String, content: List[UInt8]) raises:
        """POST `content` as multipart form field "file" to `path`, the /files/
        address of an attachment created for it."""
        check_files_path(path, "upload")
        var boundary = "eva-" + String(random_ui64(0, 0xFFFFFFFFFFFF)) + String(random_ui64(0, 0xFFFFFFFFFFFF))
        # A file name cannot end the header line or its quoted value early.
        var name = String(clean(file_name).replace('"', "'").replace("\n", " ").replace("\r", " "))
        var head = (
            "--" + boundary + "\r\n"
            + 'Content-Disposition: form-data; name="file"; filename="' + name + '"\r\n'
            + "Content-Type: application/octet-stream\r\n\r\n"
        )
        var bytes = List[UInt8]()
        for b in head.as_bytes():
            bytes.append(b)
        for b in content:
            bytes.append(b)
        for b in String("\r\n--" + boundary + "--\r\n").as_bytes():
            bytes.append(b)
        # The request body is a String; the file's bytes go through it as they are.
        var body = String(unsafe_from_utf8=Span(bytes))
        if self.verbose:
            print("→ POST", self.cfg.url + path, len(content), "bytes as", name, file=stderr)
        var headers = Dict[String, String]()
        headers["Authorization"] = "Bearer " + self.cfg.token
        headers["User-Agent"] = "eva-cli"
        headers["Content-Type"] = "multipart/form-data; boundary=" + boundary
        var ca: Optional[String] = None
        if self.ca != "":
            ca = self.ca
        var status: Int
        var text: String
        try:
            var session = requests.Session()
            var resp = session.post(
                self.cfg.url + path,
                data=body,
                headers=headers^,
                timeout=300.0,
                verify=not self.cfg.insecure,
                ca_bundle=ca,
                allow_redirects=False,
            )
            status = resp.status_code
            text = resp.text()
        except e:
            raise Error("cannot reach " + self.cfg.url + ": " + String(e))
        if self.verbose:
            print("← HTTP", status, clean(String(text[byte = 0 : min(text.byte_length(), 300)])), file=stderr)
        if status >= 300 and status < 400:
            raise Error("the upload address redirects (HTTP " + String(status) + "); eva does not follow it with your token")
        if status == 401 or status == 403:
            raise Error("HTTP " + String(status) + ": the server refused the upload: " + clean(String(text[byte = 0 : min(text.byte_length(), 200)])))
        if status != 200:
            raise Error(
                "HTTP " + String(status) + " for the upload: " + clean(String(String(text[byte = 0 : min(text.byte_length(), 200)]).strip()))
            )

    def call(
        self,
        method: String,
        kwargs: String = "",
        args: String = "",
        flags: String = "",
    ) raises -> Reply:
        """Call `method`. kwargs, args and flags are JSON text or ""."""
        var body = String('{"jsonrpc":"2.2","no_meta":true,"callid":')
        body += quote(new_callid())
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

        var headers = Dict[String, String]()
        headers["Authorization"] = "Bearer " + self.cfg.token
        headers["User-Agent"] = "eva-cli"
        var ca: Optional[String] = None
        if self.ca != "":
            ca = self.ca
        var status: Int
        var text: String
        var location = String()
        try:
            # Redirects are not followed: the token is meant for this address
            # alone, and a JSON-RPC endpoint has no reason to move.
            var session = requests.Session()
            var resp = session.post(
                self.cfg.url + "/api/",
                json=body,
                headers=headers^,
                timeout=30.0,
                verify=not self.cfg.insecure,
                ca_bundle=ca,
                allow_redirects=False,
            )
            status = resp.status_code
            if resp.headers.contains("location"):
                location = resp.headers["location"]
            text = resp.text()
        except e:
            raise Error("cannot reach " + self.cfg.url + ": " + String(e))
        if status >= 300 and status < 400:
            raise Error(
                self.cfg.url + "/api/ redirects (HTTP " + String(status) + ") to " + clean(location)
                + "; eva does not follow it with your token. If that is the real address,"
                " sign in to it with `eva auth login`"
            )
        if self.verbose:
            print("← HTTP", status, clean(String(text[byte = 0 : min(text.byte_length(), 600)])), file=stderr)
        if status == 401 or status == 403:
            raise Error(
                "HTTP " + String(status) + ": the token was rejected ("
                + clean(String(text[byte = 0 : min(text.byte_length(), 120)].strip()))
                + "); sign in again with `eva auth login`"
            )

        var doc = JsonDoc()
        var root: Int
        try:
            root = doc.parse(text)
        except e:
            raise Error(
                "HTTP "
                + String(status)
                + ", reply is not JSON: "
                + clean(String(text[byte = 0 : min(text.byte_length(), 200)]))
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
