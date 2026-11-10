from std.testing import (
    TestSuite,
    assert_equal,
    assert_true,
    assert_false,
    assert_raises,
)
from eva.args import Args
from eva.json import JsonDoc
from eva.projection import project_json, column_text, tsv_cell
from eva.validation import field_confirmed
from eva.task_options import priority_value, priority_caption, valid_datetime
from eva.filters import validate_bql


def test_projection_nested_arrays_and_missing_fields() raises:
    var src = JsonDoc()
    var root = src.parse('{"code":"X","people":[{"login":"a","id":"1"},{"login":null,"id":"2"}],"extra":3}')
    var got = JsonDoc()
    var value = got.parse(
        project_json(
            src,
            root,
            [String("code"), String("people.login"), String("missing")],
        )
    )
    assert_equal(got.len(value), 2)
    var people = got.get(value, "people")
    assert_equal(got.len(people), 2)
    assert_equal(got.len(got.at(people, 0)), 1)
    assert_true(got.is_null(got.get(got.at(people, 1), "login")))
    assert_equal(column_text(src, root, "people.login"), "a, ")
    assert_equal(tsv_cell("a\tb\n\\x"), "a\\tb\\n\\\\x")
    with assert_raises():
        _ = project_json(src, root, [String("a..b")])


def test_projection_empty_and_repeated_paths() raises:
    var src = JsonDoc()
    var empty = src.parse("[]")
    assert_equal(project_json(src, empty, [String("code")]), "[]")
    var root = src.parse('{"r":{"a":1,"b":2}}')
    var once = project_json(src, root, [String("r.a")])
    assert_equal(project_json(src, root, [String("r.a"), String("r.a")]), once)


def test_readback_normalized_relations_numbers_and_missing_null() raises:
    var e = JsonDoc()
    var a = JsonDoc()
    assert_true(
        field_confirmed(
            e,
            e.parse('["Person:1","Person:2"]'),
            a,
            a.parse('[{"id":"Person:2"},{"id":"Person:1"}]'),
        )
    )
    assert_false(
        field_confirmed(
            e,
            e.parse('["Person:1","Person:1"]'),
            a,
            a.parse('[{"id":"Person:1"},{"id":"Person:2"}]'),
        )
    )
    assert_true(field_confirmed(e, e.parse("5.5"), a, a.parse("5.500")))
    assert_false(field_confirmed(e, e.null(), a, -1))
    assert_true(field_confirmed(e, e.null(), a, a.null()))


def test_priority_codes_captions_and_aliases() raises:
    var names: List[String] = [
        "Минимальный",
        "Низкий",
        "Обычный",
        "Высокий",
        "Критичный",
        "Блокирующий",
    ]
    var aliases: List[String] = [
        "lowest",
        "low",
        "normal",
        "high",
        "critical",
        "blocker",
    ]
    for i in range(len(names)):
        assert_equal(priority_value(names[i]), i - 2)
        assert_equal(priority_value(aliases[i]), i - 2)
        assert_equal(priority_value(String(i - 2)), i - 2)
        assert_equal(priority_caption(String(i - 2)), names[i])
    for bad in ["hihg", "4", "", "-3"]:
        with assert_raises():
            _ = priority_value(String(bad))


def test_shared_date_validation() raises:
    valid_datetime("2028-02-29 23:59")
    for bad in [
        "2026-02-29",
        "2026-02-30",
        "2026-11-10 24:00",
        "2026-11-10 9:00",
        "today",
    ]:
        with assert_raises():
            valid_datetime(String(bad))


def test_bql_shapes_are_data_not_code() raises:
    var d = JsonDoc()
    for good in [
        '["code","==","X"]',
        '["OR",["name","ILIKE","%x%"],["text","ILIKE","%x%"]]',
    ]:
        validate_bql(d, d.parse(String(good)))
    # [] would match every task, so a saved filter of [] must not reach a bulk.
    for bad in [
        '{"code":"X"}',
        '["OR"]',
        '["code"]',
        "[1,2,3]",
        "[]",
        '["AND",[]]',
    ]:
        with assert_raises():
            validate_bql(d, d.parse(String(bad)))


def test_version_flag_context_and_repeated_flags() raises:
    assert_equal(Args(["--version"]).get("version"), "true")
    assert_equal(Args(["--version", "--md"]).get("md"), "true")
    assert_equal(
        Args(["doc", "get", "DOC-1", "--version", "00170000000000000"]).get("version"),
        "00170000000000000",
    )
    var repeated = Args(["task", "update", "X", "--tag", "a", "--tag", "b"])
    assert_equal(len(repeated.keys), 2)
    assert_equal(repeated.get("tag"), "b")


def test_reverse_array_empty_repeated_and_wrong_kind() raises:
    var d = JsonDoc()
    var empty = d.parse("[]")
    d.reverse_array(empty)
    assert_equal(d.dump(empty), "[]")
    var values = d.parse("[1,2,3]")
    d.reverse_array(values)
    assert_equal(d.dump(values), "[3,2,1]")
    d.reverse_array(values)
    assert_equal(d.dump(values), "[1,2,3]")
    with assert_raises():
        d.reverse_array(d.object())


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
