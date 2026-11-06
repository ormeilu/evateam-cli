"""The multi-select field cache and how values print."""

from std.testing import assert_equal, assert_true, assert_false, TestSuite

from eva.fields import cache_file, from_meta, parse_cache, value_names
from eva.json import JsonDoc


def test_cache_fresh_stale_malformed() raises:
    var text = "# 1000\ncf_a\tНаправление\ncf_b\tДругое\njunk line\nname\tnot custom\n"
    var fresh = parse_cache(text, 1000 + 3600)
    assert_true(Bool(fresh))
    assert_equal(len(fresh.value()), 2)
    assert_equal(fresh.value()[0].caption, "Направление")
    assert_false(Bool(parse_cache(text, 1000 + 86401)))  # older than a day
    assert_false(Bool(parse_cache(text, 999)))  # from the future
    assert_false(Bool(parse_cache("cf_a\tx\n", 1000)))  # no stamp
    assert_false(Bool(parse_cache("# soon\n", 1000)))


def test_cache_file_is_one_component() raises:
    var p = cache_file("https://eva.example.ru:8443/../x")
    assert_true(p.endswith("/eva-cli/task-multiselects-https___eva_example_ru_8443____x"), p)


def test_from_meta_keeps_custom_multiselects() raises:
    var d = JsonDoc()
    var m = d.parse(
        '{"fields": {"name": {"widget": "CmfM2M"}, "cf_a": {"widget": "CmfM2M", "caption": "A\\tB\\nC"},'
        ' "cf_b": {"widget": "CmfChoice", "caption": "B"}, "cf_c": {"widget": "CmfM2M"}}}'
    )
    var got = from_meta(d, m)
    assert_equal(len(got), 2)
    assert_equal(got[0].name, "cf_a")
    assert_equal(got[0].caption, "A B C")
    assert_equal(got[1].caption, "cf_c")  # no caption: the name stands in


def test_value_names() raises:
    var d = JsonDoc()
    var r = d.parse('{"a": [{"name": "iOS"}, {"name": "BE"}], "b": [], "c": "plain", "d": ["x", "y"]}')
    assert_equal(value_names(d, d.get(r, "a")), "iOS, BE")
    assert_equal(value_names(d, d.get(r, "b")), "")
    assert_equal(value_names(d, d.get(r, "c")), "plain")
    assert_equal(value_names(d, d.get(r, "d")), "x, y")
    assert_equal(value_names(d, d.get(r, "missing")), "")


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
