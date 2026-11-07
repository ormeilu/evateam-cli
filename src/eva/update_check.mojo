"""Periodic check for a newer eva release.

At most once per EVA_UPDATE_CHECK_HOURS (24 by default) a run starts a detached
`eva __update-check`, which asks the release source the way `eva upgrade` and
install.sh do and saves the answer in the private cache. Commands never wait
for it: they read what an earlier check saved. EVA_NO_UPDATE_CHECK=1 or a CI
environment turns the whole thing off.
"""

from std.ffi import external_call, c_int
from std.os import getenv

from eva.client import is_truthy
from eva.dates import now_epoch
from eva.state import PrivateCache
from eva.upgrade import LATEST_URL, clean_version, latest_release, shell_quote
from requests._dns import _cstr
from requests._tls import _self_exe

comptime FETCH_ARG = "__update-check"
# The parent writes when it last started a check and which version it last
# announced; the detached check writes only the version it found.
comptime STATE_FILE = "update-check"
comptime LATEST_FILE = "update-latest"
comptime DEFAULT_HOURS = 24
comptime DAY = 86400
comptime FETCH_TIMEOUT = 5.0


def update_check_disabled(no_check: String, ci: String) -> Bool:
    if is_truthy(no_check):
        return True
    var c = ci.lower()
    return c != "" and c != "0" and c != "false"


def check_interval(hours: String) -> Int:
    """Seconds between checks: EVA_UPDATE_CHECK_HOURS when it is a whole number
    of hours from 1 to a year, 24 hours otherwise."""
    try:
        var n = Int(hours)
        if n >= 1 and n <= 24 * 366:
            return n * 3600
    except:
        pass
    return DEFAULT_HOURS * 3600


def check_due(checked: Int, now: Int, interval: Int) -> Bool:
    # A clock set back past the last check starts a new interval.
    return now - checked >= interval or now < checked


def notice_due(latest: String, notified: String, notified_at: Int, now: Int) -> Bool:
    """Once a day per version; a version not announced yet is due at once."""
    return latest != notified or now - notified_at >= DAY or now < notified_at


def _numbers(version: String) -> List[Int]:
    """X.Y.Z of a version as numbers, empty when a part is not a number."""
    var core = version
    var dash = core.find("-")
    if dash >= 0:
        var head = String(core[byte=0:dash])
        core = head
    var out = List[Int]()
    for part in core.split("."):
        try:
            var n = Int(String(part))
            if n < 0:
                return List[Int]()
            out.append(n)
        except:
            return List[Int]()
    return out^


def is_newer(latest: String, current: String) -> Bool:
    """Whether release `latest` comes after `current`; False when either does
    not parse. A release beats a pre-release of the same numbers."""
    if latest == "" or current == "":
        return False
    var a = _numbers(latest)
    var b = _numbers(current)
    if len(a) == 0 or len(b) == 0:
        return False
    for i in range(max(len(a), len(b))):
        var x = a[i] if i < len(a) else 0
        var y = b[i] if i < len(b) else 0
        if x != y:
            return x > y
    return latest.find("-") < 0 and current.find("-") >= 0


def update_line(latest: String, current: String) -> String:
    return (
        "eva "
        + latest
        + " is out (you have "
        + current
        + "); update with: eva upgrade"
    )


def _epoch(text: String) -> Int:
    try:
        return Int(text)
    except:
        return 0


struct UpdateState(Movable):
    var checked: Int
    var notified: String
    var notified_at: Int

    def __init__(out self, text: String):
        self.checked = 0
        self.notified = ""
        self.notified_at = 0
        for raw in text.splitlines():
            var line = String(raw)
            var eq = line.find("=")
            if eq < 0:
                continue
            var key = String(line[byte=0:eq])
            var value = String(line[byte = eq + 1 :])
            if key == "checked":
                self.checked = _epoch(value)
            elif key == "notified":
                self.notified = clean_version(value)
            elif key == "notified_at":
                self.notified_at = _epoch(value)

    def text(self) -> String:
        return (
            "checked="
            + String(self.checked)
            + "\nnotified="
            + self.notified
            + "\nnotified_at="
            + String(self.notified_at)
            + "\n"
        )


def _start_check():
    """Start `eva __update-check` detached; this run does not wait for it."""
    var exe = _self_exe()
    if exe == "":
        return
    var c = _cstr(
        shell_quote(exe) + " " + FETCH_ARG + " </dev/null >/dev/null 2>&1 &"
    )
    _ = external_call["system", c_int](c)
    c.unsafe_free()


def fetch_latest():
    """`eva __update-check`: ask the release source, save what it names.
    Errors are dropped; the next attempt is an interval away either way."""
    try:
        var url = getenv("EVA_UPDATE_URL")
        if url == "":
            url = LATEST_URL
        var latest = latest_release(url, FETCH_TIMEOUT)
        if latest != "":
            var cache = PrivateCache()
            _ = cache.write(LATEST_FILE, latest + "\n")
    except:
        pass


def check_for_update(current: String, always: Bool) -> String:
    """The update line for this run, or "".

    Other commands get it at most once a day per version; with `always`
    (eva --version, eva context) it comes whenever an earlier check found a
    newer release. Starts a background check when one is due. Never raises and
    never waits on the network.
    """
    if update_check_disabled(getenv("EVA_NO_UPDATE_CHECK"), getenv("CI")):
        return ""
    try:
        var cache = PrivateCache()
        var now = now_epoch()
        var state = UpdateState(cache.read(STATE_FILE))
        var start = check_due(
            state.checked, now, check_interval(getenv("EVA_UPDATE_CHECK_HOURS"))
        )
        if start:
            state.checked = now
        var latest = clean_version(cache.read(LATEST_FILE))
        var known = is_newer(latest, current)
        var due = known and notice_due(
            latest, state.notified, state.notified_at, now
        )
        if due:
            state.notified = latest
            state.notified_at = now
        if start or due:
            # Saved before the check starts, so runs in parallel start one.
            _ = cache.write(STATE_FILE, state.text())
        if start:
            _start_check()
        if due or (always and known):
            return update_line(latest, current)
    except:
        pass
    return ""
