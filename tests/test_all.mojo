from std.testing import assert_equal, assert_true, assert_raises
from eva.json import JsonDoc, J_OBJ, J_ARR
from eva.render import html_to_text, text_to_html, clip, pad
from eva.commands import parse_minutes
from eva.args import Args


def test_roundtrip() raises:
    var d = JsonDoc()
    var r = d.parse('{"a": [1, -2.5e3, true, null], "b": "q\\"\\u044f\\ud83d\\udd25\\n", "c": {}}')
    assert_equal(d.kind(r), J_OBJ)
    assert_equal(d.dump(r), '{"a":[1,-2.5e3,true,null],"b":"q\\"я🔥\\n","c":{}}')
    assert_equal(d.text_at(r, "b"), 'q"я🔥\n')
    assert_equal(d.len(d.get(r, "a")), 4)


def test_path() raises:
    var d = JsonDoc()
    var r = d.parse('{"result": {"responsible": {"name": "Ilya"}, "x": null}}')
    assert_equal(d.text_at(r, "result.responsible.name"), "Ilya")
    assert_equal(d.text_at(r, "result.x"), "")
    assert_equal(d.text_at(r, "result.nope.deeper"), "")


def test_build() raises:
    var d = JsonDoc()
    var o = d.object()
    d.set_str(o, "method", "CmfTask.list")
    var v = d.string("DEV-1")
    var f = d.triple("code", "==", v)
    d.set(o, "filter", f)
    d.set_str(o, "method", "CmfTask.get")
    assert_equal(d.dump(o), '{"method":"CmfTask.get","filter":["code","==","DEV-1"]}')


def test_errors() raises:
    var d = JsonDoc()
    with assert_raises():
        _ = d.parse('{"a": }')
    with assert_raises():
        _ = d.parse('[1, 2')
    with assert_raises():
        _ = d.parse('"abc')


def test_render() raises:
    assert_equal(html_to_text("<p>a&amp;b</p><ul><li>x</li><li>y</li></ul><p>z</p>"), "a&b\n\n- x\n- y\n\nz")
    assert_equal(text_to_html("a<b\n\nc\nd"), "<p>a&lt;b</p><p>c<br>d</p>")
    assert_equal(clip("абвгдеё", 4), "абв…")
    assert_equal(clip("абв", 4), "абв")
    assert_equal(pad("я", 3), "я  ")


def test_minutes() raises:
    assert_equal(parse_minutes("90"), 90)
    assert_equal(parse_minutes("1h30m"), 90)
    assert_equal(parse_minutes("2H"), 120)
    with assert_raises():
        _ = parse_minutes("1.5h")


def test_args() raises:
    var a = Args(["task", "list", "-p", "DEV", "--json", "--limit=5", "--", "-x"])
    assert_equal(a.pos(1), "list")
    assert_equal(a.get("project", "p"), "DEV")
    assert_true(a.has("json"))
    assert_equal(a.int_or("limit", "n", 25), 5)
    assert_equal(a.pos(2), "-x")
    with assert_raises():
        _ = Args(["task", "get", "-p"])


def main() raises:
    test_render()
    test_minutes()
    test_args()
    test_roundtrip()
    test_path()
    test_build()
    test_errors()
    print("unit tests: ok")
