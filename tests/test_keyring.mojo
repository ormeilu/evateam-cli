"""The real OS keychain. Opt-in with EVA_TEST_KEYRING=1: it writes and deletes
an item named eva-cli / eva-test-<pid> in the user's keychain."""

from std.ffi import external_call, c_int
from std.os import getenv
from std.testing import assert_equal, assert_true, assert_false, TestSuite

from eva.keyring import keyring_delete, keyring_get, keyring_set


def enabled() -> Bool:
    return getenv("EVA_TEST_KEYRING") == "1"


def profile() -> String:
    return "eva-test-" + String(external_call["getpid", c_int]())


def test_roundtrip_update_delete() raises:
    if not enabled():
        return
    var p = profile()
    keyring_set(p, "first")
    assert_equal(keyring_get(p).value(), "first")
    keyring_set(p, '{"url":"https://e","token":"т"}')
    assert_equal(keyring_get(p).value(), '{"url":"https://e","token":"т"}')
    assert_true(keyring_delete(p))
    assert_false(Bool(keyring_get(p)))
    assert_false(keyring_delete(p))


def test_missing_is_none_not_error() raises:
    if not enabled():
        return
    assert_false(Bool(keyring_get(profile() + "-never")))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
