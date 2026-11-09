"""The command table behind `eva GROUP SUB`: names, aliases and handlers.
Dispatch, per-command help, typo suggestions and shell completion all read it.
"""

from eva.args import Args, closest
from eva.client import Client
from eva.render import Out
from eva.task import (
    task_get,
    task_list,
    task_create,
    task_update,
    task_delete,
    task_links,
)
from eva.workflow import task_move, task_statuses, task_path, resolution_list
from eva.resources import project_list, person_list
from eva.documents import doc_get, doc_list, doc_write, doc_publish
from eva.collaboration import (
    task_comments,
    task_comment_delete,
    comment_write,
    comment_edit,
    task_watch,
)
from eva.commands import raw_call
from eva.common import simple_list, like_filter
from eva.fields import field_get, field_list
from eva.timelog import task_log, time_delete, time_list
from eva.attachments import (
    attachment_delete,
    attachment_download,
    attachment_get,
    doc_download_all,
    task_attach,
    task_attachments,
)
from eva.diagnostics import schema
from eva.resources import (
    filter_eq,
    list_command,
    task_history,
    task_time,
    task_dev,
    notify_list,
    repo_list,
    search,
)
from eva.subscriptions import doc_followers, doc_watch
from eva.task_card import task_card
from eva.reports import time_report
from eva.filters import filter_list
from eva.operations import trash_command, task_bulk
from eva.knowledge import (
    doc_children,
    doc_history,
    doc_version,
    project_get,
    test_command,
    ticket_get,
)
from eva.task_relations import (
    task_link,
    relation_types,
    task_checklist,
    task_check,
    task_template,
)

comptime Handler = def(client: Client, args: Args, ui: Out) raises thin -> None

comptime ANY = "*"
"""A `sub` that means the group has no subcommands: position 1 is an argument."""


@fieldwise_init
struct Group(Copyable, Movable):
    var name: String
    var aliases: List[String]


@fieldwise_init
struct Command(Copyable, Movable):
    var group: String
    var sub: String
    """The canonical subcommand, or ANY."""
    var aliases: List[String]
    """Other names for `sub`; "" makes it the default when none is given."""
    var run: Handler


def groups() -> List[Group]:
    """Command groups in --help order; the first name is canonical."""
    return [
        Group("task", ["tasks", "t"]),
        Group("time", ["worklog"]),
        Group("attachment", ["attachments", "file"]),
        Group("project", ["projects"]),
        Group("person", ["people", "user"]),
        Group("doc", ["docs"]),
        Group("sprint", []),
        Group("release", []),
        Group("relation", []),
        Group("tag", []),
        Group("component", []),
        Group("filter", []),
        Group("notify", []),
        Group("repo", []),
        Group("search", []),
        Group("testcase", []),
        Group("testplan", []),
        Group("ticket", []),
        Group("trash", []),
        Group("field", ["fields"]),
        Group("resolution", ["resolutions"]),
        Group("schema", []),
        Group("context", []),
        Group("cheatsheet", []),
        Group("call", []),
        Group("auth", []),
        Group("config", []),
        Group("upgrade", ["self-update"]),
        Group("completion", []),
    ]


def commands() -> List[Command]:
    """Every command. Groups that main.run handles itself (auth, config,
    context, cheatsheet, upgrade, completion) point at `in_run`."""
    var none = List[String]()
    var dflt: List[String] = [""]
    return [
        Command("task", "get", ["show"], _task_get),
        Command("task", "list", ["ls", "find"], task_list),
        Command("task", "create", ["new"], _task_create),
        Command("task", "update", ["edit"], task_update),
        Command("task", "delete", ["rm"], task_delete),
        Command("task", "move", none.copy(), task_move),
        Command("task", "statuses", none.copy(), task_statuses),
        Command("task", "path", none.copy(), task_path),
        Command("task", "comment", none.copy(), comment_write),
        Command("task", "comments", none.copy(), task_comments),
        Command("task", "comment-edit", none.copy(), comment_edit),
        Command("task", "comment-delete", ["uncomment"], task_comment_delete),
        Command("task", "log", none.copy(), task_log),
        Command("task", "history", none.copy(), task_history),
        Command("task", "time", none.copy(), task_time),
        Command("task", "dev", none.copy(), task_dev),
        Command("task", "links", none.copy(), task_links),
        Command("task", "link", none.copy(), task_link),
        Command("task", "unlink", none.copy(), task_link),
        Command("task", "checklist", none.copy(), task_checklist),
        Command("task", "check", none.copy(), task_check),
        Command("task", "watch", none.copy(), task_watch),
        Command("task", "unwatch", none.copy(), task_watch),
        Command("task", "attachments", ["files"], task_attachments),
        Command("task", "attach", none.copy(), task_attach),
        Command("task", "bulk", none.copy(), task_bulk),
        Command("time", "list", ["ls", ""], time_list),
        Command("time", "report", none.copy(), time_report),
        Command("time", "log", none.copy(), task_log),
        Command("time", "delete", ["rm"], time_delete),
        Command("attachment", "get", ["show"], attachment_get),
        Command("attachment", "download", ["dl"], attachment_download),
        Command("attachment", "delete", ["rm"], attachment_delete),
        Command("project", "list", ["ls", ""], project_list),
        Command("project", "get", none.copy(), project_get),
        Command("person", "list", ["ls", ""], person_list),
        Command("doc", "list", ["ls", ""], doc_list),
        Command("doc", "get", ["show"], _doc_get),
        Command("doc", "create", none.copy(), doc_write),
        Command("doc", "update", none.copy(), doc_write),
        Command("doc", "publish", none.copy(), doc_publish),
        Command("doc", "comment", none.copy(), comment_write),
        Command("doc", "comment-edit", none.copy(), comment_edit),
        Command("doc", "comments", none.copy(), task_comments),
        Command("doc", "attachments", none.copy(), task_attachments),
        Command("doc", "attach", none.copy(), task_attach),
        Command("doc", "download-all", none.copy(), doc_download_all),
        Command("doc", "children", none.copy(), doc_children),
        Command("doc", "history", none.copy(), doc_history),
        Command("doc", "followers", none.copy(), doc_followers),
        Command("doc", "watch", none.copy(), doc_watch),
        Command("sprint", "list", dflt.copy(), list_command),
        Command("sprint", "get", none.copy(), list_command),
        Command("sprint", "add", none.copy(), list_command),
        Command("release", "list", dflt.copy(), list_command),
        Command("release", "get", none.copy(), list_command),
        Command("release", "add", none.copy(), list_command),
        Command("relation", "types", dflt.copy(), relation_types),
        Command("tag", "list", dflt.copy(), _tag_list),
        Command("component", "list", dflt.copy(), _component_list),
        Command("filter", "list", dflt.copy(), filter_list),
        Command("notify", "list", dflt.copy(), notify_list),
        Command("repo", "list", dflt.copy(), repo_list),
        Command("search", ANY, none.copy(), search),
        Command("testcase", "list", dflt.copy(), test_command),
        Command("testcase", "get", none.copy(), test_command),
        Command("testplan", "list", dflt.copy(), test_command),
        Command("testplan", "get", none.copy(), test_command),
        Command("ticket", "get", none.copy(), ticket_get),
        Command("trash", "list", dflt.copy(), trash_command),
        Command("trash", "restore", none.copy(), trash_command),
        Command("field", "list", ["ls", ""], field_list),
        Command("field", "get", ["show"], field_get),
        Command("resolution", "list", dflt.copy(), resolution_list),
        Command("schema", ANY, none.copy(), schema),
        Command("context", ANY, none.copy(), in_run),
        Command("cheatsheet", ANY, none.copy(), in_run),
        Command("call", ANY, none.copy(), raw_call),
        Command("auth", "login", none.copy(), in_run),
        Command("auth", "status", none.copy(), in_run),
        Command("auth", "use", none.copy(), in_run),
        Command("auth", "logout", none.copy(), in_run),
        Command("config", ANY, none.copy(), in_run),
        Command("upgrade", ANY, none.copy(), in_run),
        Command("completion", ANY, none.copy(), in_run),
    ]


def in_run(client: Client, args: Args, ui: Out) raises:
    raise Error("internal: eva " + args.pos(0) + " is dispatched by main.run")


def _task_get(client: Client, args: Args, ui: Out) raises:
    if args.has("with"):
        task_card(client, args, ui)
    else:
        task_get(client, args, ui)


def _task_create(client: Client, args: Args, ui: Out) raises:
    if args.has("template"):
        task_template(client, args, ui)
    else:
        task_create(client, args, ui)


def _doc_get(client: Client, args: Args, ui: Out) raises:
    if args.has("version"):
        doc_version(client, args, ui)
    else:
        doc_get(client, args, ui)


def _component_list(client: Client, args: Args, ui: Out) raises:
    args.check_known(
        [
            "project",
            "p",
            "query",
            "q",
            "limit",
            "n",
            "page",
            "json",
            "format",
            "verbose",
            "v",
        ]
    )
    var base = String("")
    if args.get("project", "p") != "":
        base = filter_eq("project.code", args.get("project", "p"))
    simple_list(
        client,
        args,
        ui,
        "CmfComponent",
        [String("code"), String("name"), String("project.code")],
        like_filter("name", args.get("query", "q"), base),
        "code",
        [String("name"), String("project.code")],
    )


def _tag_list(client: Client, args: Args, ui: Out) raises:
    args.check_known(
        ["query", "q", "limit", "n", "page", "json", "verbose", "v"]
    )
    simple_list(
        client,
        args,
        ui,
        "CmfTag",
        [String("id"), String("name")],
        like_filter("name", args.get("query", "q"), ""),
        "id",
        [String("name")],
    )


def canonical_group(name: String) -> String:
    """The canonical group for a name or alias, or ""."""
    for g in groups():
        if g.name == name:
            return g.name
        for a in g.aliases:
            if a == name:
                return g.name
    return ""


def group_names() -> List[String]:
    var out = List[String]()
    for g in groups():
        out.append(g.name)
    return out^


def subcommands(group: String) -> List[String]:
    """Canonical subcommands of a group, in table order; empty for ANY."""
    var out = List[String]()
    for c in commands():
        if c.group == group and c.sub != ANY:
            out.append(c.sub)
    return out^


def _join_or(names: List[String]) -> String:
    var out = String("")
    for i in range(len(names)):
        if i > 0:
            out += " or " if i == len(names) - 1 else ", "
        out += names[i]
    return out


def find_group(name: String) raises -> String:
    var g = canonical_group(name)
    if g != "":
        return g
    var msg = "unknown command '" + name + "'"
    var near = closest(name, group_names())
    if near != "":
        raise Error(msg + "; did you mean '" + near + "'?")
    raise Error(msg + ", see eva --help")


def resolve(mut args: Args) raises -> Command:
    """Find the command for positions 0 and 1, rewriting aliases there to
    canonical names, so handlers see `doc`, never `docs`."""
    var group = find_group(args.pos(0))
    args.positionals[0] = group
    var sub = args.pos(1)
    for c in commands():
        if c.group != group:
            continue
        if c.sub == ANY:
            return c.copy()
        var hit = c.sub == sub
        for a in c.aliases:
            hit = hit or a == sub
        if hit:
            if len(args.positionals) > 1:
                args.positionals[1] = c.sub
            return c.copy()
    var subs = subcommands(group)
    if sub == "":
        raise Error("eva " + group + " needs a command: " + _join_or(subs))
    var msg = "unknown " + group + " command '" + sub + "'"
    var near = closest(sub, subs)
    if near != "":
        msg += "; did you mean '" + near + "'?"
    else:
        msg += ": " + _join_or(subs)
    raise Error(msg)


def _entry_matches(line: String, group: String, sub: String) -> Bool:
    """Whether a usage entry line (`  task get CODE ...`) is GROUP [SUB]."""
    var head = String(line[byte=2:])
    var words = head.split(" ")
    if len(words) == 0 or String(words[0]) != group:
        return False
    return sub == "" or (len(words) > 1 and String(words[1]) == sub)


def help_text(usage: String, group: String, sub: String) -> String:
    """The --help entries for one group (or one subcommand), the trailing
    sections that name the group, and the global options."""
    var lines = usage.split("\n")
    var entries = String("")
    var sections = String("")
    var i = 0
    var in_entry = False
    var in_section = False
    while i < len(lines):
        var line = String(lines[i])
        i += 1
        if line == "":
            in_entry = False
            in_section = False
            continue
        if line.startswith("      "):
            if in_entry:
                entries += line + "\n"
            elif in_section:
                sections += line + "\n"
            continue
        if line.startswith("  "):
            if in_section:
                sections += line + "\n"
                continue
            in_entry = _entry_matches(line, group, sub)
            if in_entry:
                entries += line + "\n"
            continue
        # A section header (followed by indented lines): keep it when it is
        # about this group, or global.
        in_entry = False
        if i >= len(lines) or not String(lines[i]).startswith("  "):
            in_section = False
            continue
        var words = line.replace("/", " ").split(" ")
        var about = line == "options"
        var names_group = False
        var names_sub = sub == ""
        for w in words:
            names_group = names_group or String(w) == group
            names_sub = names_sub or String(w) == sub
        about = about or (names_group and names_sub)
        in_section = about and not line.startswith("eva ")
        in_section = in_section and not line.startswith("usage:")
        if in_section:
            sections += "\n" + line + "\n"
    if entries == "" and sub != "":
        return help_text(usage, group, "")
    var head = "usage: eva " + group + (" " + sub if sub != "" else "")
    return head + " [options]\n\n" + entries + sections


def completion(shell: String) raises -> String:
    """A completion script for groups and their subcommands."""
    var gs = groups()
    var all_groups = String(" ").join(group_names())
    if shell == "fish":
        var out = String(
            "# eva completion fish | source\n"
            + "complete -c eva -n __fish_use_subcommand -f -a '"
            + all_groups
            + "'\n"
        )
        for g in gs:
            var subs = String(" ").join(subcommands(g.name))
            if subs == "":
                continue
            var names = g.name
            for a in g.aliases:
                names += " " + a
            # Only right after the group: `time` is also a task subcommand.
            out += (
                "complete -c eva -n 'set -l w (commandline -opc);"
                + " test (count $w) -eq 2; and contains -- $w[2] "
                + names
                + "' -f -a '"
                + subs
                + "'\n"
            )
        out += "complete -c eva -l help -s h -d 'help for this command'\n"
        out += "complete -c eva -l json -d 'API result'\n"
        out += "complete -c eva -l full -d 'no truncation'\n"
        out += "complete -c eva -l verbose -s v -d 'requests on stderr'\n"
        out += "complete -c eva -l profile -x -d 'saved profile'\n"
        return out
    var cases = String("")
    for g in gs:
        var subs = String(" ").join(subcommands(g.name))
        if subs == "":
            continue
        var names = g.name
        for a in g.aliases:
            names += "|" + a
        if shell == "bash":
            cases += (
                "      "
                + names
                + ') COMPREPLY=($(compgen -W "'
                + subs
                + '" -- "$cur")) ;;\n'
            )
        else:
            cases += "      " + names + ") compadd -- " + subs + " ;;\n"
    if shell == "bash":
        return (
            "# source <(eva completion bash)\n"
            + "_eva() {\n"
            + "  local cur=${COMP_WORDS[COMP_CWORD]}\n"
            + '  if [ "$COMP_CWORD" -eq 1 ]; then\n'
            + '    COMPREPLY=($(compgen -W "'
            + all_groups
            + '" -- "$cur"))\n'
            + '  elif [ "$COMP_CWORD" -eq 2 ]; then\n'
            + "    case ${COMP_WORDS[1]} in\n"
            + cases
            + "    esac\n"
            + "  fi\n"
            + "}\n"
            + "complete -o default -F _eva eva\n"
        )
    if shell == "zsh":
        return (
            "#compdef eva\n"
            + "# source <(eva completion zsh), or save as _eva in $fpath\n"
            + "_eva() {\n"
            + "  if (( CURRENT == 2 )); then\n"
            + "    compadd -- "
            + all_groups
            + "\n"
            + "  elif (( CURRENT == 3 )); then\n"
            + "    case $words[2] in\n"
            + cases
            + "      *) _files ;;\n"
            + "    esac\n"
            + "  else\n"
            + "    _files\n"
            + "  fi\n"
            + "}\n"
            + 'if [ "$funcstack[1]" = "_eva" ]; then\n'
            + '  _eva "$@"\n'
            + "else\n"
            + "  compdef _eva eva\n"
            + "fi\n"
        )
    raise Error("eva completion takes fish, bash or zsh, not '" + shell + "'")
