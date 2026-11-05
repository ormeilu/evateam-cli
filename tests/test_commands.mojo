from std.testing import assert_equal, assert_true, assert_raises, TestSuite

from eva.args import Args
from eva.commands import (
    code_kwargs,
    fields_from,
    like_filter,
    local_now,
    page_slice,
    parse_minutes,
    person,
    quote_str,
    split_csv,
    status_condition,
    want_json,
)
from eva.json import JsonDoc
from eva.upgrade import dirname, shell_quote


def test_parse_minutes() raises:
    assert_equal(parse_minutes("90"), 90)
    assert_equal(parse_minutes("90m"), 90)
    assert_equal(parse_minutes("1h30m"), 90)
    assert_equal(parse_minutes("2H"), 120)
    assert_equal(parse_minutes("1h"), 60)
    for bad in ["1.5h", "", "0", "h", "-5", "1d", "10 m"]:
        with assert_raises():
            _ = parse_minutes(String(bad))


def test_status_condition() raises:
    var d = JsonDoc()
    assert_equal(d.dump(status_condition(d, "open")), '["cache_status_type","!=","CLOSED"]')
    assert_equal(d.dump(status_condition(d, "Closed")), '["cache_status_type","==","CLOSED"]')
    assert_equal(d.dump(status_condition(d, "in_progress")), '["cache_status_type","==","IN_PROGRESS"]')
    assert_equal(d.dump(status_condition(d, "in_review")), '["cache_status_type","==","IN_REVIEW"]')
    assert_equal(d.dump(status_condition(d, "s7.in-dev")), '["status.code","==","s7.in-dev"]')


def test_like_filter() raises:
    assert_equal(like_filter("name", "", ""), "")
    assert_equal(like_filter("name", "Bot", ""), '["name","ILIKE","%Bot%"]')
    assert_equal(
        like_filter("name", "x", '["system", "==", false]'),
        '[["system","==",false],["name","ILIKE","%x%"]]',
    )
    assert_equal(like_filter("name", "", '["system", "==", false]'), '["system","==",false]')


def test_like_filter_quotes_input() raises:
    # A quote in the search text stays inside the JSON string.
    assert_equal(like_filter("name", 'a"],["x', ""), '["name","ILIKE","%a\\"],[\\"x%"]')


def test_split_csv_and_fields() raises:
    var parts = split_csv(" a, b ,,c ")
    assert_equal(len(parts), 3)
    assert_equal(parts[1], "b")
    var none = Args([])
    assert_equal(len(fields_from(none, "x,y")), 2)
    var some = Args(["--fields", "name"])
    assert_equal(fields_from(some, "x,y")[0], "name")


def test_code_kwargs_escapes() raises:
    assert_equal(code_kwargs("DEV-1", [String("code")]), '{"filter":["code","==","DEV-1"],"fields":["code"]}')
    assert_equal(code_kwargs('X"Y', List[String]()), '{"filter":["code","==","X\\"Y"]}')


def test_page_slice() raises:
    var d = JsonDoc()
    assert_equal(d.dump(page_slice(d, Args(["-n", "10", "--page", "3"]))), "[20,30]")
    assert_equal(d.dump(page_slice(d, Args([]))), "[0,25]")
    with assert_raises(contains="start at 1"):
        _ = page_slice(d, Args(["--page", "0"]))


def test_person_prefers_login() raises:
    var d = JsonDoc()
    var r = d.parse('{"a": {"login": "l", "name": "N"}, "b": {"name": "Only"}, "c": null}')
    assert_equal(person(d, r, "a"), "l")
    assert_equal(person(d, r, "b"), "Only")
    assert_equal(person(d, r, "c"), "-")


def test_want_json() raises:
    assert_true(want_json(Args(["--json"])))
    assert_true(want_json(Args(["--format", "json"])))
    assert_true(not want_json(Args([])))


def test_quote_str() raises:
    assert_equal(quote_str('CmfTask:1"'), '"CmfTask:1\\""')


def test_local_now_format() raises:
    var t = local_now()
    assert_equal(t.byte_length(), 19)
    assert_equal(String(t[byte=4:5]), "-")
    assert_equal(String(t[byte=10:11]), " ")
    assert_equal(String(t[byte=13:14]), ":")


def test_shell_quote_and_dirname() raises:
    assert_equal(shell_quote("a b"), "'a b'")
    assert_equal(shell_quote("it's"), "'it'\\''s'")
    assert_equal(shell_quote("$(rm -rf ~)"), "'$(rm -rf ~)'")
    assert_equal(dirname("/a/b/c"), "/a/b")
    assert_equal(dirname("c"), "/")


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
