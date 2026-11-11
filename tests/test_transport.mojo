"""How a call that got no reply is reported: a lost reply to a write must not
read as a failed connect, or a retry can apply the write twice."""

from std.testing import assert_equal, assert_true, assert_false, TestSuite

from eva.client import is_read_method, reply_lost, timed_out, transport_failure
from requests.exceptions import NO_RESPONSE

comptime URL = "https://eva.example.ru"
comptime LOST = "ConnectionError: " + NO_RESPONSE + ": the connection closed or timed out before any reply"


def test_read_methods() raises:
    for m in ["CmfTask.get", "CmfList.list", "CmfTask.count", "CmfTask.get_meta", "CmfPerson.get_current_user"]:
        assert_true(is_read_method(m), m)
    for m in [
        "CmfList.create",
        "CmfList.update",
        "CmfTask.fix_versions.append",
        "CmfTask.fix_versions.remove",
        "CmfTask.task_transition_run",
        "CmfTask.getter",
        "get",
        "",
    ]:
        assert_false(is_read_method(m), m)


def test_reply_lost_only_after_the_request_went_out() raises:
    assert_true(reply_lost(LOST))
    assert_true(reply_lost("ReadTimeout: recv timed out"))
    assert_false(reply_lost("ConnectionError: connect() to port 443 failed"))
    assert_false(reply_lost("ConnectTimeout: connect() to port 443 failed"))
    assert_false(reply_lost("SSLError: certificate verify failed"))
    assert_false(reply_lost("ConnectionError: send failed before the whole request went out"))


def test_lost_write_says_it_may_be_applied() raises:
    var msg = transport_failure(URL, "CmfList.create", LOST, 0.4, 1)
    assert_true(msg.startswith("CmfList.create was sent to " + URL + ", but the connection closed"), msg)
    assert_true(msg.find("may have been applied") >= 0, msg)
    assert_true(msg.find("cannot reach") < 0, msg)
    msg = transport_failure(URL, "CmfList.create", LOST, 30.2, 1)
    assert_true(msg.find("no reply within 30 s") >= 0, msg)


def test_lost_read_and_failed_connect() raises:
    var msg = transport_failure(URL, "CmfList.get", LOST, 0.4, 2)
    assert_equal(msg, "CmfList.get got no reply from " + URL + ": the connection closed without a reply (tried twice)")
    msg = transport_failure(URL, "CmfList.create", "ConnectionError: connect() to port 443 failed", 0.1, 1)
    assert_equal(msg, "cannot reach " + URL + ": ConnectionError: connect() to port 443 failed")


def test_timed_out() raises:
    assert_false(timed_out(0.5))
    assert_false(timed_out(28.0))
    assert_true(timed_out(29.5))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
