"""The multi-select field cache and how values print."""

from std.testing import assert_equal, assert_true, assert_false, TestSuite

from eva.fields import from_meta, kind_of, value_names
from eva.state import server_key
from eva.json import JsonDoc


def test_cache_identity_is_stable_opaque_component() raises:
    var key = server_key("https://eva.example.invalid:8443/../x")
    assert_equal(key, server_key("https://eva.example.invalid:8443/../x"))
    assert_false(key == server_key("https://other.example.invalid"))
    assert_false(key.find("/") >= 0)
    assert_false(key.find(":") >= 0)
    assert_false(key.find("eva") >= 0)


def test_from_meta_keeps_custom_fields() raises:
    var d = JsonDoc()
    var m = d.parse(
        '{"fields": {"name": {"widget": "CmfM2M"}, "cf_a": {"widget": "CmfM2M",'
        ' "caption": "A\\tB\\nC"}, "cf_b": {"widget": "CmfChoice", "caption":'
        ' "B"}, "cf_c": {"widget": "CmfM2M"}}}'
    )
    var got = from_meta(d, m)
    assert_equal(len(got), 3)
    assert_equal(got[0].name, "cf_a")
    assert_equal(got[0].caption, "A B C")
    assert_equal(got[1].widget, "CmfChoice")
    assert_equal(got[1].model, "")
    assert_equal(got[2].caption, "cf_c")  # no caption: the name stands in


def test_value_names() raises:
    var d = JsonDoc()
    var r = d.parse('{"a": [{"name": "iOS"}, {"name": "BE"}], "b": [], "c": "plain", "d": ["x", "y"]}')
    assert_equal(value_names(d, d.get(r, "a")), "iOS, BE")
    assert_equal(value_names(d, d.get(r, "b")), "")
    assert_equal(value_names(d, d.get(r, "c")), "plain")
    assert_equal(value_names(d, d.get(r, "d")), "x, y")
    assert_equal(value_names(d, d.get(r, "missing")), "")


def test_kind_of() raises:
    assert_equal(kind_of("CmfM2M"), "multi-select")
    assert_equal(kind_of("CmfChoice"), "choice")
    assert_equal(kind_of("CmfSomethingNew"), "CmfSomethingNew")


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
