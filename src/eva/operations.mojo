"""Confirmation-gated trash recovery and bounded bulk task operations."""
from eva.args import Args
from eva.client import Client
from eva.common import get_by_code, quote_str, split_csv, simple_list, want_json
from eva.resources import filter_eq
from eva.selection import collect_rows
from eva.task import task_filter, task_update
from eva.workflow import move_task
from eva.writes import preview_write
from eva.json import JsonDoc, J_OBJ
from eva.render import Out
from eva.term import stdin_is_tty, prompt_line


def trash_command(client: Client, args: Args, ui: Out) raises:
    var sub = args.pos(1)
    if sub == "list" or sub == "":
        args.check_known(
            [
                "project",
                "p",
                "limit",
                "n",
                "page",
                "json",
                "format",
                "verbose",
                "v",
            ]
        )
        var filter = String('["cmf_deleted","==",true]')
        if args.get("project", "p") != "":
            filter = "[" + filter + "," + filter_eq("project.code", args.get("project", "p")) + "]"
        simple_list(
            client,
            args,
            ui,
            "CmfTask",
            split_csv("code,name,cmf_modified_at"),
            filter,
            "code",
            split_csv("name,cmf_modified_at"),
        )
        if not want_json(args):
            print("timestamp is last modified, not a promised deletion date; retention is server-configured")
        return
    if sub != "restore":
        raise Error("usage: eva trash list | restore CODE [--yes]")
    args.check_known(["yes", "y", "dry-run", "verbose", "v"])
    var code = args.need(2, "task code")
    var r = get_by_code(client, "CmfTask", code, split_csv("id,code,name,cmf_deleted"))
    if r.doc.text_at(r.result, "cmf_deleted") == "false":
        print(code + " is already outside the trash")
        return
    if r.doc.text_at(r.result, "cmf_deleted") != "true":
        raise Error(code + ": deletion state is not readable; refusing to restore blindly")
    var id = r.doc.text_at(r.result, "id")
    if preview_write(args.has("dry-run"), "CmfTask.restore", "", "[" + quote_str(id) + "]"):
        return
    var what = code + "  " + r.doc.text_at(r.result, "name")
    if not args.has("yes", "y"):
        if not stdin_is_tty():
            raise Error("restoring " + what + " needs confirmation: run it in a terminal, or pass --yes")
        var answer = prompt_line("restore " + what + "? [y/N] ").lower()
        if answer != "y" and answer != "yes" and answer != "д" and answer != "да":
            print("not restored")
            return
    _ = client.call("CmfTask.restore", "", "[" + quote_str(id) + "]")
    var after = get_by_code(client, "CmfTask", code, split_csv("cmf_deleted"))
    if after.doc.text_at(after.result, "cmf_deleted") != "false":
        raise Error(code + ": restore was not confirmed by readback")
    print("restored " + ui.bold(code))


def task_bulk(client: Client, args: Args, ui: Out) raises:
    args.check_known(
        [
            "filter",
            "project",
            "p",
            "assignee",
            "a",
            "status",
            "s",
            "query",
            "q",
            "author",
            "watching",
            "waiting-for",
            "archived",
            "tag",
            "set",
            "resolution",
            "r",
            "comment",
            "m",
            "path",
            "dry-run",
            "yes",
            "y",
            "verbose",
            "v",
        ]
    )
    var action = args.need(2, "bulk operation: set or move")
    if action != "set" and action != "move":
        raise Error("bulk supports set and move")
    if args.get("filter") == "" and args.get("project", "p") == "":
        raise Error("bulk needs an explicit --filter or --project selector")
    if action == "set" and args.get("set") == "":
        raise Error("bulk set requires --set JSON")
    if action == "set" and (args.has("resolution", "r") or args.has("comment", "m") or args.has("path")):
        raise Error("--resolution, -m and --path go with bulk move, not set")
    var target = args.need(3, "target status") if action == "move" else String("")
    # Parse the payload before even resolving the selected set.
    var check = JsonDoc()
    if args.get("set") != "":
        var values = check.parse(args.get("set"))
        if check.kind(values) != J_OBJ:
            raise Error("--set expects a JSON object")
        if action == "set" and check.len(values) == 0:
            raise Error("nothing to change: --set is empty")
    var d = JsonDoc()
    var filter = task_filter(client, d, args)
    var rows = collect_rows(client, "CmfTask", d.dump(filter), "code,name", 1000)
    var n = rows.doc.len(rows.result)
    print("resolved " + String(n) + " tasks (snapshot; not an atomic transaction)")
    var dry = args.has("dry-run") or not args.has("yes", "y")
    if dry:
        print("dry run; --yes applies this operation to a freshly resolved set; server acceptance is not validated")
    var failures = 0
    for i in range(n):
        var row = rows.doc.at(rows.result, i)
        var code = rows.doc.text_at(row, "code")
        if code == "":
            raise Error("selected task has no readable code; refusing to apply an unnamed change")
        print("  " + code + "  " + rows.doc.text_at(row, "name"))
    for i in range(n):
        var row = rows.doc.at(rows.result, i)
        var code = rows.doc.text_at(row, "code")
        try:
            if action == "move":
                move_task(
                    client,
                    code,
                    target,
                    args.get("comment", "m"),
                    args.get("set"),
                    args.get("resolution", "r"),
                    ui,
                    args.has("path"),
                    dry,
                )
            else:
                var raw: List[String] = [
                    "task",
                    "update",
                    code,
                    "--set",
                    args.get("set"),
                ]
                if dry:
                    raw.append("--dry-run")
                var one = Args(raw)
                task_update(client, one, ui)
        except e:
            failures += 1
            print("failed " + code + ": " + String(e))
    print(
        String(n - failures)
        + (" previews succeeded, " if dry else " changes succeeded, ")
        + String(failures)
        + " failed"
    )
    if failures > 0:
        raise Error("bulk operation had failures; successful changes were kept, no rollback was attempted")
