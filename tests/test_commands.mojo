from std.testing import assert_equal, assert_true, assert_raises, TestSuite
from std.os import getenv

from eva.args import Args
from eva.common import (
    body_html,
    code_kwargs,
    fields_from,
    like_filter,
    page_slice,
    person,
    quote_str,
    split_csv,
    text_from,
    want_json,
)
from eva.collaboration import comments_kwargs
from eva.dates import local_now, parse_minutes
from eva.task import status_condition
from eva.resources import check_dates
from eva.workflow import FROM_ANY, Transitions, shell_word
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
    assert_equal(
        d.dump(status_condition(d, "open")),
        '["cache_status_type","!=","CLOSED"]',
    )
    assert_equal(
        d.dump(status_condition(d, "Closed")),
        '["cache_status_type","==","CLOSED"]',
    )
    assert_equal(
        d.dump(status_condition(d, "in_progress")),
        '["cache_status_type","==","IN_PROGRESS"]',
    )
    assert_equal(
        d.dump(status_condition(d, "in_review")),
        '["cache_status_type","==","IN_REVIEW"]',
    )
    assert_equal(
        d.dump(status_condition(d, "s7.in-dev")),
        '["status.code","==","s7.in-dev"]',
    )


def test_like_filter() raises:
    assert_equal(like_filter("name", "", ""), "")
    assert_equal(like_filter("name", "Bot", ""), '["name","ILIKE","%Bot%"]')
    assert_equal(
        like_filter("name", "x", '["system", "==", false]'),
        '[["system","==",false],["name","ILIKE","%x%"]]',
    )
    assert_equal(
        like_filter("name", "", '["system", "==", false]'),
        '["system","==",false]',
    )


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
    assert_equal(
        code_kwargs("DEV-1", [String("code")]),
        '{"filter":["code","==","DEV-1"],"fields":["code"]}',
    )
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


def test_body_html_modes() raises:
    assert_equal(body_html(Args(["x"]), "<b>a</b>"), "<p>&lt;b&gt;a&lt;/b&gt;</p>")
    assert_equal(body_html(Args(["--html"]), "<b>a</b>"), "<b>a</b>")
    assert_equal(body_html(Args(["--md"]), "**a**"), "<p><strong>a</strong></p>")
    with assert_raises(contains="exclude each other"):
        _ = body_html(Args(["--md", "--html"]), "a")


def test_text_from_file() raises:
    var path = String(getenv("TMPDIR", "/tmp")) + "/eva-text-from-test.md"
    with open(path, "w") as f:
        f.write("line one\n\nline 'two' \"quoted\"\n\n")
    assert_equal(
        text_from(Args(["-F", path]), "", "the comment"),
        "line one\n\nline 'two' \"quoted\"",
    )
    assert_equal(text_from(Args(["x"]), "inline", "the comment"), "inline")
    with assert_raises(contains="not both"):
        _ = text_from(Args(["-F", path]), "inline", "the comment")
    with assert_raises(contains="cannot read"):
        _ = text_from(Args(["-F", path + ".missing"]), "", "the comment")
    with open(path, "w") as f:
        f.write("  \n")
    with assert_raises(contains="is empty"):
        _ = text_from(Args(["--file", path]), "", "the comment")


def test_comments_kwargs() raises:
    var all = comments_kwargs("CmfTask:1", False, [String("id")])
    assert_true(all.find('"filter":[["parent_id","==","CmfTask:1"]]') >= 0, all)
    assert_true(all.find('"order_by":["cmf_created_at"]') >= 0, all)
    var people = comments_kwargs("CmfTask:1", True, [String("id")])
    assert_true(people.find('["log_level","==",0]') >= 0, people)
    # The count call sends the filter alone.
    assert_equal(
        comments_kwargs("CmfTask:1", False, List[String]()),
        '{"filter":[["parent_id","==","CmfTask:1"]]}',
    )


def add(mut tr: Transitions, to: String, froms: String, limit: String = ""):
    tr.trans_ids.append("T" + to)
    tr.trans_names.append(to)
    tr.to_ids.append(to)
    tr.to_codes.append(to.lower())
    tr.to_names.append(to)
    tr.froms.append(froms)
    tr.limits.append(limit)


def workflow() -> Transitions:
    """A -> B -> C -> D forward, Hold reachable from all and leading to D."""
    var tr = Transitions()
    tr.current_id = "A"
    tr.current = "A"
    add(tr, "B", "A,Hold")
    add(tr, "C", "B,Hold")
    add(tr, "D", "C")
    add(tr, "Hold", "A,B,C")
    add(tr, "D", "Hold")
    add(tr, "X", "A", "automatic")
    return tr^


def names(tr: Transitions, steps: List[Int]) -> String:
    var out = List[String]()
    for i in steps:
        out.append(tr.to_names[i])
    return ",".join(out)


def test_path_goes_forward_not_through_hold() raises:
    var tr = workflow()
    assert_true(tr.is_hub("Hold"))
    assert_true(not tr.is_hub("C"))
    assert_equal(names(tr, tr.path_to("d")), "B,C,D")
    assert_equal(names(tr, tr.path_to("Hold")), "Hold")


def test_path_uses_hub_when_nothing_else_works() raises:
    var tr = workflow()
    tr.limits[2] = "automatic"  # C -> D only automatic now
    assert_equal(names(tr, tr.path_to("D")), "Hold,D")


def test_path_skips_automatic_and_unknown() raises:
    var tr = workflow()
    assert_equal(len(tr.path_to("X")), 0)
    assert_equal(len(tr.path_to("nowhere")), 0)
    assert_equal(len(tr.path_to("A")), 0)
    var here = tr.from_here()
    assert_equal(len(here), 2)  # B and Hold, not the automatic X


def test_from_any_status_runs_from_every_status() raises:
    """EvaTeam reads an empty status_from as any status, so a system
    transition to Done gives a way out of a status the workflow has none from.
    """
    var tr = workflow()
    add(tr, "Done", FROM_ANY)
    tr.current_id = "D"
    tr.current = "D"
    assert_equal(names(tr, tr.from_here()), "Done")
    assert_equal(names(tr, tr.path_to("done")), "Done")
    tr.current_id = "B"
    assert_equal(names(tr, tr.from_here()), "C,Hold,Done")
    # Not from Done to itself.
    tr.current_id = "Done"
    assert_equal(len(tr.from_here()), 0)


def test_status_own_transition_wins_over_from_any() raises:
    var tr = Transitions()
    tr.current_id = "A"
    tr.current = "A"
    add(tr, "B", FROM_ANY)  # listed first, as the server may
    add(tr, "B", "A")
    var here = tr.from_here()
    assert_equal(len(here), 1)
    assert_equal(tr.froms[here[0]], "A")
    var steps = tr.path_to("B")
    assert_equal(len(steps), 1)
    assert_equal(tr.froms[steps[0]], "A")


def test_from_any_target_counts_as_side_status() raises:
    var tr = workflow()
    add(tr, "A", FROM_ANY)  # reset to the start from anywhere
    assert_true(tr.is_hub("A"))
    assert_true(not tr.is_hub("C"))
    # Out of the dead end D, the reset is the only way back.
    tr.current_id = "D"
    tr.current = "D"
    assert_equal(names(tr, tr.path_to("C")), "A,B,C")


def test_shell_word() raises:
    assert_equal(shell_word("closed"), "closed")
    assert_equal(shell_word("In Review"), "'In Review'")
    assert_equal(shell_word("it's"), "'it'\\''s'")


def test_check_dates() raises:
    check_dates("2026-12-01", "2026-12-20")
    check_dates("2026-12-01", "2026-12-01")
    check_dates("2026-12-01T10:00:00+03:00", "2026-12-01")
    check_dates("", "2026-12-01")
    var raised = False
    try:
        check_dates("2026-12-20", "2026-12-01T00:00:00+03:00")
    except e:
        raised = String(e).find("is after") >= 0
    assert_true(raised)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
