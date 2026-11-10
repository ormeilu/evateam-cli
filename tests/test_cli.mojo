from std.testing import (
    assert_equal,
    assert_true,
    assert_false,
    assert_raises,
    TestSuite,
)

from eva.args import Args, closest, edit_distance
from eva.cli import (
    ANY,
    canonical_group,
    commands,
    completion,
    groups,
    help_text,
    resolve,
    subcommands,
)


def test_edit_distance() raises:
    assert_equal(edit_distance("task", "task"), 0)
    assert_equal(edit_distance("tsak", "task"), 1)
    assert_equal(edit_distance("ab", "ba"), 1)
    assert_equal(edit_distance("gett", "get"), 1)
    assert_equal(edit_distance("", "abc"), 3)


def test_closest() raises:
    var names: List[String] = ["get", "list", "statuses", "status-x"]
    assert_equal(closest("gte", names), "get")
    assert_equal(closest("lsit", names), "list")
    assert_equal(closest("zzzzzz", names), "")
    assert_equal(closest("g", names), "")
    # A prefix counts only when it is unique.
    assert_equal(closest("statu", names), "")
    var one: List[String] = ["get", "statuses"]
    assert_equal(closest("stat", one), "statuses")


def test_aliases_become_canonical() raises:
    var a = Args(["docs", "show", "DOC-1"])
    var c = resolve(a)
    assert_equal(c.group, "doc")
    assert_equal(c.sub, "get")
    assert_equal(a.pos(0), "doc")
    assert_equal(a.pos(1), "get")
    assert_equal(a.pos(2), "DOC-1")
    var t = Args(["t", "uncomment", "5"])
    assert_equal(resolve(t).sub, "comment-delete")


def test_default_subcommand_adds_no_positional() raises:
    var a = Args(["time", "--from", "2026-11-01"])
    assert_equal(resolve(a).sub, "list")
    assert_equal(len(a.positionals), 1)


def test_any_keeps_the_argument() raises:
    var a = Args(["search", "gett"])
    assert_equal(resolve(a).sub, ANY)
    assert_equal(a.pos(1), "gett")


def test_unknown_commands_suggest() raises:
    with assert_raises(contains="unknown command 'tsak'; did you mean 'task'?"):
        var a = Args(["tsak", "list"])
        _ = resolve(a)
    with assert_raises(contains="unknown command 'zzz', see eva --help"):
        var a = Args(["zzz"])
        _ = resolve(a)
    with assert_raises(contains="unknown task command 'gett'; did you mean 'get'?"):
        var a = Args(["task", "gett"])
        _ = resolve(a)
    with assert_raises(contains="unknown auth command 'x': login, status, use or logout"):
        var a = Args(["auth", "x"])
        _ = resolve(a)
    with assert_raises(contains="eva task needs a command: get, list"):
        var a = Args(["task"])
        _ = resolve(a)


def test_unknown_option_suggests() raises:
    with assert_raises(contains="unknown option --projet; did you mean --project?"):
        Args(["--projet", "X"]).check_known(["project", "p", "json"])
    with assert_raises(contains="unknown option --bogus"):
        Args(["--bogus", "1"]).check_known(["json"])


def test_table_is_consistent() raises:
    # Every command belongs to a known group, and no name is taken twice.
    var seen = List[String]()
    for c in commands():
        assert_equal(canonical_group(c.group), c.group, c.group)
        var names = List[String]()
        names.append(c.sub)
        for a in c.aliases:
            names.append(a)
        for n in names:
            var key = c.group + " " + n
            for s in seen:
                assert_true(s != key, "duplicate " + key)
            seen.append(key)
    for g in groups():
        var has = False
        for c in commands():
            has = has or c.group == g.name
        assert_true(has, "group without commands: " + g.name)


comptime USAGE = """eva — test

usage: eva <command> [options]

  task get CODE
      card
  task create -p PROJ
      create
  time list
      days

shared task create/update flags
  --priority N

once a day eva checks the latest release
and names it.

options
  --json            API result
"""


def test_help_text() raises:
    var t = help_text(USAGE, "task", "")
    assert_true("task get CODE" in t and "task create" in t)
    assert_false("time list" in t)
    assert_true("--priority" in t and "--json" in t)
    var g = help_text(USAGE, "task", "get")
    assert_true(g.startswith("usage: eva task get"))
    assert_false("task create" in g or "--priority" in g)
    assert_true("--priority" in help_text(USAGE, "task", "create"))
    # A paragraph that mentions a group is not a section about it.
    assert_false("once a day" in help_text(USAGE, "time", ""))


def test_completion_scripts() raises:
    var fish = completion("fish")
    assert_true("complete -c eva" in fish and "contains -- $w[2] task tasks t" in fish)
    var bash = completion("bash")
    assert_true("task|tasks|t)" in bash and "complete -o default -F _eva eva" in bash)
    assert_true("compdef _eva eva" in completion("zsh"))
    for s in subcommands("doc"):
        assert_true(s in fish, s)
    with assert_raises(contains="fish, bash or zsh"):
        _ = completion("pwsh")


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
