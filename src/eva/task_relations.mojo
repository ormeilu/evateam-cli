"""Relations, checklists and creation from task templates."""
from eva.args import Args
from eva.writes import preview_write
from eva.client import Client
from eva.common import (
    get_by_code,
    id_of,
    quote_str,
    split_csv,
    simple_list,
    want_json,
)
from eva.task import build_update, task_by_id
from eva.validation import require_fields
from eva.json import JsonDoc
from eva.render import Out
from eva.resources import filter_eq, page_rows, page_footer


def relation_type(client: Client, want: String) raises -> String:
    var name = want if want != "" and want != "relates" else String(
        "system.link"
    )
    var r = client.call(
        "CmfRelationType.list",
        '{"fields":["id","code","name"],"slice":[0,5000]}',
    )
    if r.doc.len(r.result) >= 5000:
        raise Error("too many relation types to resolve safely")
    var code = String()
    for i in range(r.doc.len(r.result)):
        var row = r.doc.at(r.result, i)
        if r.doc.text_at(row, "code").lower() == name.lower():
            return r.doc.text_at(row, "code")
        if r.doc.text_at(row, "name").lower() == name.lower():
            if code != "":
                raise Error(
                    "ambiguous relation type " + name + "; use its code"
                )
            code = r.doc.text_at(row, "code")
    if code == "":
        raise Error(
            "unknown relation type " + name + "; eva relation types shows them"
        )
    return code


def relation_types(client: Client, args: Args, ui: Out) raises:
    args.check_known(["limit", "n", "page", "json", "format", "verbose", "v"])
    simple_list(
        client,
        args,
        ui,
        "CmfRelationType",
        split_csv("code,name"),
        "",
        "code",
        [String("name")],
    )


def task_link(client: Client, args: Args, ui: Out) raises:
    args.check_known(["type", "verbose", "v"])
    var src = args.need(2, "source task")
    var dst = args.need(3, "target task")
    if src == dst:
        raise Error("a task cannot be linked to itself")
    _ = id_of(client, "CmfTask", "code", src)
    _ = id_of(client, "CmfTask", "code", dst)
    var kind = relation_type(client, args.get("type"))
    var filter = (
        "["
        + filter_eq("out_link.code", src)
        + ","
        + filter_eq("in_link.code", dst)
        + ","
        + filter_eq("relation_type.code", kind)
        + "]"
    )
    var kw = '{"filter":' + filter + ',"fields":["id"],"slice":[0,1000]}'
    var r = client.call("CmfRelationOption.list", kw)
    if r.doc.len(r.result) >= 1000:
        raise Error("too many matching links to modify safely")
    if args.pos(1) == "link":
        if r.doc.len(r.result) > 0:
            print("already linked " + src + " → " + dst + "  " + kind)
            return
        if r.doc.len(r.result) == 0:
            var d = JsonDoc()
            var fields = d.object()
            d.set_str(fields, "out_link", src)
            d.set_str(fields, "in_link", dst)
            d.set_str(fields, "relation_type", kind)
            _ = client.call("CmfRelationOption.create", d.dump(fields))
        var after = client.call("CmfRelationOption.list", kw)
        if after.doc.len(after.result) == 0:
            raise Error("link creation was not confirmed")
        print("linked " + src + " → " + dst + "  " + kind)
    else:
        if r.doc.len(r.result) == 0:
            print(
                "no "
                + kind
                + " link "
                + src
                + " → "
                + dst
                + "; nothing to remove"
            )
            return
        for i in range(r.doc.len(r.result)):
            var id = r.doc.text_at(r.doc.at(r.result, i), "id")
            _ = client.call(
                "CmfRelationOption.delete", "", "[" + quote_str(id) + "]"
            )
        var after = client.call("CmfRelationOption.list", kw)
        if after.doc.len(after.result) != 0:
            raise Error("link removal was not confirmed")
        print("unlinked " + src + " → " + dst + "  " + kind)


def task_checklist(client: Client, args: Args, ui: Out) raises:
    args.check_known(
        ["limit", "n", "page", "json", "format", "verbose", "v", "full"]
    )
    var code = args.need(2, "task code")
    var filter = filter_eq("parent_id", id_of(client, "CmfTask", "code", code))
    var lists = page_rows(
        client, args, "CmfChecklist", filter, "id,code,name", "id"
    )
    var d = JsonDoc()
    var result = d.array()
    for i in range(lists.doc.len(lists.result)):
        var row = lists.doc.at(lists.result, i)
        var id = lists.doc.text_at(row, "id")
        var f = filter_eq("parent_id", id)
        var items = page_rows(
            client,
            args,
            "CmfChecklistItem",
            f,
            "id,code,name,status,orderno",
            "orderno",
        )
        if want_json(args):
            var obj = d.parse(lists.doc.dump(row))
            var it = d.parse(items.doc.dump(items.result))
            d.set(obj, "items", it)
            d.push(result, obj)
        else:
            print(
                lists.doc.text_at(row, "code")
                + "  "
                + lists.doc.text_at(row, "name")
            )
            for j in range(items.doc.len(items.result)):
                var item = items.doc.at(items.result, j)
                var status = items.doc.text_at(item, "status")
                print(
                    "  "
                    + ("[x] " if status == "DONE" else "[ ] ")
                    + items.doc.text_at(item, "code")
                    + "  "
                    + status
                    + "  "
                    + items.doc.text_at(item, "name")
                )
            page_footer(
                client,
                args,
                ui,
                "CmfChecklistItem",
                f,
                items.doc.len(items.result),
            )
    if want_json(args):
        print(d.dump_pretty(result))
    else:
        page_footer(
            client,
            args,
            ui,
            "CmfChecklist",
            filter,
            lists.doc.len(lists.result),
        )


def task_check(client: Client, args: Args, ui: Out) raises:
    args.check_known(["undo", "verbose", "v"])
    var code = args.need(2, "checklist item code")
    var r = get_by_code(
        client, "CmfChecklistItem", code, split_csv("id,status")
    )
    var want = "OPEN" if args.has("undo") else "DONE"
    if r.doc.text_at(r.result, "status") != want:
        _ = client.call(
            "CmfChecklistItem.update",
            '{"status":' + quote_str(want) + "}",
            "[" + quote_str(r.doc.text_at(r.result, "id")) + "]",
        )
        var got = get_by_code(
            client, "CmfChecklistItem", code, split_csv("id,status")
        )
        if got.doc.text_at(got.result, "status") != want:
            raise Error(code + ": checklist update was not confirmed")
    print(code + "  " + want)


def task_template(client: Client, args: Args, ui: Out) raises:
    args.check_known(
        [
            "dry-run",
            "template",
            "project",
            "p",
            "name",
            "title",
            "t",
            "description",
            "d",
            "file",
            "F",
            "md",
            "html",
            "assignee",
            "a",
            "set",
            "priority",
            "story-points",
            "plan-start",
            "plan-end",
            "alarm",
            "co-assignee",
            "waiting-for",
            "tag",
            "verbose",
            "v",
        ]
    )
    var project = args.get("project", "p")
    if project == "":
        raise Error("--template requires -p PROJECT")
    var before = get_by_code(
        client, "CmfTask", args.get("template"), split_csv("id,is_template")
    )
    if before.doc.text_at(before.result, "is_template") != "true":
        raise Error(args.get("template") + " is not a task template")
    var d = JsonDoc()
    var override = d.object()
    _ = build_update(client, args, d, override)
    var kw = d.object()
    var params = d.object()
    d.set_str(params, "parent", project)
    d.set(kw, "params", params)
    if preview_write(
        args.has("dry-run"),
        "CmfTask.create_task_from_template",
        d.dump(kw),
        "[" + quote_str(before.doc.text_at(before.result, "id")) + "]",
    ):
        if d.len(override) > 0:
            print(
                "field overrides follow after the server assigns a task id: "
                + d.dump(override)
            )
        return
    var r = client.call(
        "CmfTask.create_task_from_template",
        d.dump(kw),
        "[" + quote_str(before.doc.text_at(before.result, "id")) + "]",
    )
    var id = r.doc.text(r.result)
    var got = task_by_id(client, id, "id,code")
    var code = got.doc.text_at(got.result, "code")
    if code == "":
        raise Error(
            "template returned " + id + ", but the new task code is unreadable"
        )
    print("created " + ui.bold(code) + " from " + args.get("template"))
    if d.len(override) > 0:
        try:
            _ = client.call(
                "CmfTask.update", d.dump(override), "[" + quote_str(id) + "]"
            )
            var fields = List[String]()
            for i in range(d.len(override)):
                fields.append(d.key_at(override, i))
            var after = task_by_id(client, id, ",".join(fields))
            require_fields(d, override, after.doc, after.result, code)
        except e:
            raise Error(
                code + " is kept, but applying overrides failed: " + String(e)
            )
