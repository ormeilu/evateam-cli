from std.testing import assert_equal, assert_true, assert_false, assert_raises, TestSuite

from eva.args import Args


def test_positionals_and_options() raises:
    var a = Args(["task", "list", "-p", "DEV", "--json", "--limit=5", "--", "-x"])
    assert_equal(a.pos(0), "task")
    assert_equal(a.pos(1), "list")
    assert_equal(a.get("project", "p"), "DEV")
    assert_true(a.has("json"))
    assert_equal(a.int_or("limit", "n", 25), 5)
    assert_equal(a.pos(2), "-x")
    assert_equal(a.pos(9), "")


def test_last_value_wins() raises:
    var a = Args(["--page", "2", "--page", "3"])
    assert_equal(a.get("page"), "3")


def test_bool_flags_take_no_value() raises:
    var a = Args(["--full", "CODE", "-v", "--insecure", "--version", "--md", "--html", "--human", "--ids"])
    assert_true(a.has("full"))
    for f in ["md", "html", "human", "ids"]:
        assert_true(a.has(String(f)), String(f))
    assert_true(a.has("verbose", "v"))
    assert_true(a.has("insecure"))
    assert_equal(a.pos(0), "CODE")


def test_missing_value() raises:
    with assert_raises(contains="needs a value"):
        _ = Args(["task", "get", "-p"])


def test_dash_alone_is_positional() raises:
    var a = Args(["-"])
    assert_equal(a.pos(0), "-")


def test_int_or() raises:
    var a = Args(["-n", "abc"])
    with assert_raises(contains="expects a number"):
        _ = a.int_or("limit", "n", 1)
    assert_equal(Args([]).int_or("limit", "n", 25), 25)


def test_need() raises:
    var a = Args(["task"])
    assert_equal(a.need(0, "group"), "task")
    with assert_raises(contains="missing task code"):
        _ = a.need(2, "task code")


def test_check_known() raises:
    var a = Args(["--json", "--bogus", "1"])
    with assert_raises(contains="unknown option --bogus"):
        a.check_known(["json"])
    var b = Args(["-z", "1"])
    with assert_raises(contains="unknown option -z"):
        b.check_known(["json"])
    Args(["--json"]).check_known(["json"])


def test_take_removes_global_option() raises:
    var a = Args(["--profile", "work", "task", "get", "X", "--json"])
    assert_equal(a.take("profile"), "work")
    assert_false(a.has("profile"))
    assert_true(a.has("json"))
    a.check_known(["json"])
    assert_equal(a.take("profile"), "")


def test_unicode_values() raises:
    var a = Args(["-q", "Иванов", '--set={"a": "б"}'])
    assert_equal(a.get("query", "q"), "Иванов")
    assert_equal(a.get("set"), '{"a": "б"}')


def test_values_and_switches_do_not_swallow_each_other() raises:
    with assert_raises(contains="needs a value"):
        _ = Args(["task", "log", "DEV-1", "1h", "-m", "--dry-run"])
    var a = Args(["-m=--literal", "--order", "-cmf_created_at", "-F", "-"])
    assert_equal(a.get("m"), "--literal")
    assert_equal(a.get("order"), "-cmf_created_at")
    assert_equal(a.get("F"), "-")
    with assert_raises(contains="is a switch"):
        _ = Args(["trash", "restore", "DEV-9", "--yes=false"])
    assert_true(Args(["--yes=true"]).has("yes"))
    var off = Args(["doc", "watch", "DOC-1", "--off", "--children"])
    assert_true(off.has("off") and off.has("children"))
    assert_equal(off.pos(2), "DOC-1")
    var v = Args(["doc", "get", "DOC-1", "--version=20261106"])
    assert_equal(v.get("version"), "20261106")


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
