"""The update check's version parsing, throttle and once-a-day notice. The
cache tests point XDG_CACHE_HOME at a fresh directory and record a recent check
first, so no background check starts and nothing goes to the network."""

from std.ffi import external_call
from std.os import setenv, unsetenv
from std.testing import assert_equal, assert_true, assert_false, TestSuite

from eva.dates import now_epoch
from eva.state import PrivateCache
from eva.update_check import (
    DAY,
    LATEST_FILE,
    STATE_FILE,
    UpdateState,
    check_due,
    check_for_update,
    check_interval,
    is_newer,
    notice_due,
    update_check_disabled,
    update_line,
)
from eva.upgrade import clean_version, version_from_location
from requests._dns import _cstr


def fresh_cache() raises -> PrivateCache:
    var template = _cstr("/tmp/eva-update-XXXXXX")
    var made = external_call["mkdtemp", Int](template)
    var path = String()
    var i = 0
    while template[unsafe_offset=i] != 0:
        path += chr(Int(template[unsafe_offset=i]))
        i += 1
    template.unsafe_free()
    if made == 0:
        raise Error("mkdtemp failed")
    _ = setenv("XDG_CACHE_HOME", path)
    for name in ["EVA_NO_UPDATE_CHECK", "CI", "EVA_UPDATE_CHECK_HOURS"]:
        _ = unsetenv(name)
    return PrivateCache()


def recently_checked(cache: PrivateCache, latest: String) raises:
    var state = UpdateState("")
    state.checked = now_epoch()
    _ = cache.write(STATE_FILE, state.text())
    _ = cache.write(LATEST_FILE, latest + "\n")


def test_versions_from_the_redirect() raises:
    assert_equal(
        version_from_location("https://github.com/ormeilu/evateam-cli/releases/tag/v0.10.0"),
        "0.10.0",
    )
    assert_equal(version_from_location("/releases/tag/v1.2.3-rc.1"), "1.2.3-rc.1")
    # No release yet: /releases/latest goes to /releases.
    assert_equal(
        version_from_location("https://github.com/ormeilu/evateam-cli/releases"),
        "",
    )
    assert_equal(version_from_location("/releases/tag/vnext"), "")
    assert_equal(version_from_location(""), "")


def test_clean_version_keeps_the_terminal_safe() raises:
    assert_equal(clean_version(" v0.9.0\n"), "0.9.0")
    assert_equal(clean_version("0.9.0"), "0.9.0")
    assert_equal(clean_version("0.9.0\x1b[2J"), "")
    assert_equal(clean_version("0.9.0 is fine"), "")
    assert_equal(clean_version("1" * 33), "")
    assert_equal(clean_version("v"), "")
    assert_equal(clean_version(""), "")


def test_is_newer() raises:
    assert_true(is_newer("0.10.0", "0.9.0"))
    assert_true(is_newer("1.0.0", "0.99.99"))
    assert_true(is_newer("0.9.1", "0.9.0"))
    assert_true(is_newer("0.9.0.1", "0.9.0"))
    assert_true(is_newer("0.9.0", "0.9.0-rc.1"))
    assert_false(is_newer("0.9.0", "0.9.0"))
    assert_false(is_newer("0.9.0", "0.10.0"))
    assert_false(is_newer("0.9.0-rc.1", "0.9.0"))
    assert_false(is_newer("0.9", "0.9.0"))
    assert_false(is_newer("", "0.9.0"))
    assert_false(is_newer("0.x.0", "0.9.0"))
    assert_false(is_newer("0.10.0", ""))


def test_throttle() raises:
    var hour = 3600
    assert_true(check_due(0, 1000 * DAY, 24 * hour))
    assert_false(check_due(1000, 1000 + 24 * hour - 1, 24 * hour))
    assert_true(check_due(1000, 1000 + 24 * hour, 24 * hour))
    assert_true(check_due(5000, 4000, 24 * hour))  # clock set back


def test_interval_from_the_environment() raises:
    assert_equal(check_interval(""), 24 * 3600)
    assert_equal(check_interval("6"), 6 * 3600)
    assert_equal(check_interval("0"), 24 * 3600)
    assert_equal(check_interval("-3"), 24 * 3600)
    assert_equal(check_interval("1.5"), 24 * 3600)
    assert_equal(check_interval("soon"), 24 * 3600)


def test_notice_once_a_day_per_version() raises:
    var now = 1000 * DAY
    assert_true(notice_due("0.10.0", "", 0, now))
    assert_false(notice_due("0.10.0", "0.10.0", now - DAY + 1, now))
    assert_true(notice_due("0.10.0", "0.10.0", now - DAY, now))
    assert_true(notice_due("0.11.0", "0.10.0", now - 60, now))
    assert_true(notice_due("0.10.0", "0.10.0", now + 60, now))  # clock set back


def test_opt_out() raises:
    assert_false(update_check_disabled("", ""))
    assert_true(update_check_disabled("1", ""))
    assert_true(update_check_disabled("true", ""))
    assert_false(update_check_disabled("0", ""))
    assert_true(update_check_disabled("", "true"))
    assert_true(update_check_disabled("", "1"))
    assert_false(update_check_disabled("", "false"))
    assert_false(update_check_disabled("", "0"))


def test_state_round_trip_and_junk() raises:
    var state = UpdateState("checked=17\nnotified=0.10.0\nnotified_at=42\n")
    assert_equal(state.checked, 17)
    assert_equal(state.notified, "0.10.0")
    assert_equal(state.notified_at, 42)
    var again = UpdateState(state.text())
    assert_equal(again.checked, 17)
    assert_equal(again.notified, "0.10.0")
    var junk = UpdateState("checked=soon\nnotified=\x1b[31m\ngarbage\n")
    assert_equal(junk.checked, 0)
    assert_equal(junk.notified, "")
    assert_equal(junk.notified_at, 0)


def test_notice_shows_once_then_waits() raises:
    var cache = fresh_cache()
    recently_checked(cache, "0.10.0")
    var line = update_line("0.10.0", "0.9.0")
    assert_equal(line, "eva 0.10.0 is out (you have 0.9.0); update with: eva upgrade")
    assert_equal(check_for_update("0.9.0", False), line)
    assert_equal(check_for_update("0.9.0", False), "")
    # eva --version and eva context show it whenever it is known.
    assert_equal(check_for_update("0.9.0", True), line)
    var state = UpdateState(cache.read(STATE_FILE))
    assert_equal(state.notified, "0.10.0")


def test_a_newer_release_is_announced_at_once() raises:
    var cache = fresh_cache()
    recently_checked(cache, "0.10.0")
    assert_true(check_for_update("0.9.0", False) != "")
    _ = cache.write(LATEST_FILE, "0.11.0\n")
    assert_equal(check_for_update("0.9.0", False), update_line("0.11.0", "0.9.0"))


def test_nothing_for_the_current_or_an_older_release() raises:
    var cache = fresh_cache()
    recently_checked(cache, "0.9.0")
    assert_equal(check_for_update("0.9.0", True), "")
    _ = cache.write(LATEST_FILE, "0.8.1\n")
    assert_equal(check_for_update("0.9.0", True), "")
    _ = cache.write(LATEST_FILE, "garbage\x1b]\n")
    assert_equal(check_for_update("0.9.0", True), "")


def test_opt_out_reads_nothing() raises:
    var cache = fresh_cache()
    recently_checked(cache, "0.10.0")
    _ = setenv("EVA_NO_UPDATE_CHECK", "1")
    assert_equal(check_for_update("0.9.0", True), "")
    _ = unsetenv("EVA_NO_UPDATE_CHECK")
    _ = setenv("CI", "true")
    assert_equal(check_for_update("0.9.0", True), "")
    _ = unsetenv("CI")
    assert_equal(UpdateState(cache.read(STATE_FILE)).notified, "")


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
