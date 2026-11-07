"""Readback: server-normalized dates, numbers and markup still confirm."""

from std.testing import assert_equal, assert_true, assert_false, TestSuite

from eva.json import JsonDoc
from eva.validation import date_key, markup_key, field_confirmed, text_confirmed


def _confirmed(expected: String, actual: String) raises -> Bool:
    var e = JsonDoc()
    var a = JsonDoc()
    var en = e.parse(expected)
    var an = a.parse(actual)
    return field_confirmed(e, en, a, an)


def test_date_key() raises:
    assert_equal(date_key("2026-11-10"), "2026-11-10")
    assert_equal(date_key("2026-11-10 09:00"), "2026-11-10 09:00")
    assert_equal(date_key("2026-11-10T09:00:00.123+03:00"), "2026-11-10 09:00")
    assert_equal(date_key("Высокий"), "")
    assert_equal(date_key("2026/11/10"), "")
    assert_equal(date_key("2026-11-10T9"), "")


def test_dates_confirm_in_server_form() raises:
    assert_true(_confirmed('"2026-11-10"', '"2026-11-10T00:00:00+03:00"'))
    assert_true(_confirmed('"2026-11-10 18:00"', '"2026-11-10T18:00:00+03:00"'))
    assert_false(_confirmed('"2026-11-10 18:00"', '"2026-11-10T19:00:00+03:00"'))
    assert_false(_confirmed('"2026-11-10"', '"2026-11-11T00:00:00+03:00"'))
    assert_false(_confirmed('"2026-11-10"', "null"))


def test_numbers_and_references() raises:
    assert_true(_confirmed("3", '"3.00"'))
    assert_true(_confirmed("5.5", "5.5"))
    assert_false(_confirmed("3", '"three"'))
    assert_true(_confirmed('"CmfPerson:1"', '{"id": "CmfPerson:1"}'))
    assert_false(_confirmed('"plain"', '"Plain"'))


def test_markup_compares_visible_text() raises:
    assert_equal(markup_key("<p>a &amp; b</p>\r\n<p>c</p>"), "a & b c")
    assert_true(_confirmed('"<p>Hello <b>you</b></p>"', '"<p class=\\"x\\">Hello <strong>you</strong></p>"'))
    assert_true(text_confirmed("<p>one\r\ntwo</p>", "<p>one\ntwo</p>"))
    assert_false(text_confirmed("<p>one</p>", "<p>two</p>"))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
