from std.testing import assert_equal, assert_true, TestSuite

from eva.json import JsonDoc, J_OBJ, J_ARR, J_STR, J_NUM, J_BOOL, NO_NODE, clean, quote


def test_roundtrip_compact() raises:
    var d = JsonDoc()
    var r = d.parse('{"a": [1, -2.5e3, true, null], "b": "q\\"\\u044f\\ud83d\\udd25\\n", "c": {}}')
    assert_equal(d.kind(r), J_OBJ)
    assert_equal(d.dump(r), '{"a":[1,-2.5e3,true,null],"b":"q\\"я🔥\\n","c":{}}')


def test_string_escapes() raises:
    var d = JsonDoc()
    var r = d.parse('"\\b\\f\\n\\r\\t\\/\\\\\\""')
    assert_equal(d.nodes[r].text, String(chr(8)) + chr(12) + '\n\r\t/\\"')


def test_numbers_keep_their_text() raises:
    var d = JsonDoc()
    var r = d.parse("[0, -0, 12345678901234567890, 1.5E-7, 3e+2]")
    assert_equal(d.dump(r), "[0,-0,12345678901234567890,1.5E-7,3e+2]")
    assert_equal(d.kind(d.at(r, 2)), J_NUM)


def test_kinds() raises:
    var d = JsonDoc()
    var r = d.parse('[true, false, null, "s", 1, [], {}]')
    assert_equal(d.kind(d.at(r, 0)), J_BOOL)
    assert_equal(d.text(d.at(r, 1)), "false")
    assert_true(d.is_null(d.at(r, 2)))
    assert_equal(d.kind(d.at(r, 3)), J_STR)
    assert_equal(d.kind(d.at(r, 5)), J_ARR)
    assert_equal(d.len(d.at(r, 6)), 0)


def test_whitespace_everywhere() raises:
    var d = JsonDoc()
    var r = d.parse(' \n\t{ "a" : [ 1 , 2 ] }\r\n ')
    assert_equal(d.dump(r), '{"a":[1,2]}')


def test_path_and_text_at() raises:
    var d = JsonDoc()
    var r = d.parse('{"result": {"responsible": {"name": "Ilya"}, "x": null, "n": 3}}')
    assert_equal(d.text_at(r, "result.responsible.name"), "Ilya")
    assert_equal(d.text_at(r, "result.x"), "")
    assert_equal(d.text_at(r, "result.n"), "3")
    assert_equal(d.text_at(r, "result.nope.deeper"), "")
    assert_equal(d.path(r, "result.responsible.name.more"), NO_NODE)


def test_object_as_text_is_json() raises:
    var d = JsonDoc()
    var r = d.parse('{"o": {"k": [1]}}')
    assert_equal(d.text_at(r, "o"), '{"k":[1]}')


def test_get_on_non_object() raises:
    var d = JsonDoc()
    var r = d.parse("[1]")
    assert_equal(d.get(r, "a"), NO_NODE)
    assert_equal(d.get(NO_NODE, "a"), NO_NODE)
    assert_equal(d.len(NO_NODE), 0)
    assert_equal(d.text(NO_NODE), "")


def test_build_and_replace() raises:
    var d = JsonDoc()
    var o = d.object()
    d.set_str(o, "method", "CmfTask.list")
    var v = d.string("DEV-1")
    var f = d.triple("code", "==", v)
    d.set(o, "filter", f)
    d.set_str(o, "method", "CmfTask.get")
    var arr = d.str_array([String("a"), String("b")])
    d.set(o, "fields", arr)
    var t = d.boolean(True)
    d.set(o, "flag", t)
    var n = d.null()
    d.set(o, "none", n)
    assert_equal(
        d.dump(o),
        '{"method":"CmfTask.get","filter":["code","==","DEV-1"],"fields":["a","b"],"flag":true,"none":null}',
    )


def test_pretty() raises:
    var d = JsonDoc()
    var r = d.parse('{"a":[1,{"b":null}],"c":{}}')
    assert_equal(d.dump_pretty(r), '{\n  "a": [\n    1,\n    {\n      "b": null\n    }\n  ],\n  "c": {}\n}')


def test_quote_escapes_controls() raises:
    assert_equal(quote('a"b\\c\n\t' + chr(1)), '"a\\"b\\\\c\\n\\t\\u0001"')


def test_parse_into_same_doc() raises:
    var d = JsonDoc()
    var a = d.parse("[1]")
    var b = d.parse('{"x": 2}')
    assert_equal(d.dump(a), "[1]")
    assert_equal(d.dump(b), '{"x":2}')


def test_errors() raises:
    var bad = [
        '{"a": }',
        "[1, 2",
        '"abc',
        "{1: 2}",
        "tru",
        "nul",
        "[1,]x",
        '{"a" 1}',
        '"\\x"',
        '"\\u12"',
        "",
        "[1] [2]",
    ]
    for s in bad:
        var d = JsonDoc()
        var raised = False
        try:
            _ = d.parse(String(s))
        except:
            raised = True
        assert_true(raised, "should not parse: " + String(s))


def test_clean_strips_terminal_controls() raises:
    var esc = String(chr(27))
    assert_equal(clean("ok" + esc + "[31mred" + esc + "[0m"), "ok[31mred[0m")
    assert_equal(clean("a\tb\nc"), "a\tb\nc")
    assert_equal(clean("bell" + chr(7) + "del" + chr(127)), "belldel")
    assert_equal(clean("c1" + chr(0x9B) + "x"), "c1x")
    assert_equal(clean("кириллица ✓"), "кириллица ✓")


def test_text_is_cleaned_but_dump_is_not() raises:
    var d = JsonDoc()
    var r = d.parse('{"n": "a\\u001b[2Jb"}')
    assert_equal(d.text_at(r, "n"), "a[2Jb")
    assert_equal(d.dump(r), '{"n":"a\\u001b[2Jb"}')


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
