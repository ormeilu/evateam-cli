"""Comments share the same parent model for tasks and documents."""
from eva.args import Args
from eva.writes import preview_write
from eva.client import Client, Reply
from eva.common import (
    body_html,
    get_by_code,
    id_of,
    quote_str,
    split_csv,
    text_from,
    print_json,
    want_json,
)
from eva.task_options import person_id
from eva.selection import collect_rows
from std.sys import stderr

from eva.attachments import task_attach
from eva.validation import text_confirmed
from eva.json import JsonDoc, J_OBJ
from eva.render import Out


def has_person(r: Reply, id: String) raises -> Bool:
    var rows = r.doc.get(r.result, "spectators")
    for i in range(r.doc.len(rows)):
        if r.doc.text_at(r.doc.at(rows, i), "id") == id:
            return True
    return False


def task_watch(client: Client, args: Args, ui: Out) raises:
    args.check_known(["login", "verbose", "v"])
    var code = args.need(2, "task code")
    var login = args.get("login")
    var id = person_id(client, login if login != "" else String("me"))
    var r = get_by_code(client, "CmfTask", code, split_csv("id,spectators.id"))
    var adding = args.pos(1) == "watch"
    if has_person(r, id) != adding:
        var method = "CmfTask.spectators." + ("append" if adding else "remove")
        _ = client.call(
            method,
            "",
            "[" + quote_str(r.doc.text_at(r.result, "id")) + "," + quote_str(id) + "]",
        )
        var got = get_by_code(client, "CmfTask", code, split_csv("id,spectators.id"))
        if has_person(got, id) != adding:
            raise Error(code + ": watcher write returned, but readback did not confirm it")
    print(("watching " if adding else "not watching ") + ui.bold(code) + " as " + id)


def comment_by_id(client: Client, id: String) raises -> Reply:
    if not id.startswith("CmfComment:"):
        raise Error(id + " is not a comment id (CmfComment:…)")
    var r = client.call(
        "CmfComment.get",
        '{"filter":["id","==",' + quote_str(id) + '],"fields":["id","parent_id","tree_parent_id","text"]}',
    )
    if r.doc.kind(r.result) != J_OBJ:
        raise Error(id + ": comment not found")
    return r^


def comment_write(client: Client, args: Args, ui: Out) raises:
    args.check_known(
        [
            "dry-run",
            "file",
            "F",
            "md",
            "html",
            "verbose",
            "v",
            "json",
            "format",
            "attach",
            "reply-to",
        ]
    )
    var code = args.need(2, "task or document code")
    var text = text_from(args, args.pos(3), "the comment")
    if text == "":
        raise Error("missing comment text: eva task comment CODE TEXT, or -F FILE (- for stdin)")
    var html = body_html(args, text)
    var paths = List[String]()
    var names = Dict[String, Bool]()
    for i in range(len(args.keys)):
        if args.keys[i] == "attach":
            var path = args.values[i]
            try:
                with open(path, "r") as f:
                    _ = f.read_bytes()
            except e:
                raise Error("cannot read " + path + ": " + String(e))
            # Checked here as well as in task_attach: there it would come
            # after the comment exists.
            var slash = path.rfind("/")
            var name = String(path[byte = slash + 1 :]) if slash >= 0 else path
            if name in names:
                raise Error(
                    "two files in this batch have the same name " + name + "; attach them separately or rename one"
                )
            names[name] = True
            paths.append(path)
    var d = JsonDoc()
    var kw = d.object()
    d.set_str(kw, "parent", code)
    d.set_str(kw, "text", html)
    var reply_to = args.get("reply-to")
    if reply_to != "":
        var parent = comment_by_id(client, reply_to)
        var cls = "CmfDocument" if (args.pos(0) == "doc" or args.pos(0) == "docs") else "CmfTask"
        if parent.doc.text_at(parent.result, "parent_id") != id_of(client, cls, "code", code):
            raise Error(reply_to + " belongs to another task or document")
        d.set_str(kw, "tree_parent", reply_to)
    if preview_write(args.has("dry-run"), "CmfComment.create", d.dump(kw)):
        if len(paths) > 0:
            print("attachments follow after the server assigns a comment id: " + ", ".join(paths))
        return
    var r = client.call("CmfComment.create", d.dump(kw))
    var id = r.doc.text(r.result)
    var got = comment_by_id(client, id)
    print("commented on " + ui.bold(code) + "  " + id)
    # The comment exists either way: failing here would invite a duplicate.
    if not text_confirmed(html, got.doc.text_at(got.result, "text")):
        print(
            "note: " + id + " reads back with different text; check it",
            file=stderr,
        )
    if len(paths) > 0:
        var raw: List[String] = ["task", "attach", id]
        for path in paths:
            raw.append(path)
        var files = Args(raw)
        try:
            task_attach(client, files, ui)
        except e:
            raise Error("comment " + id + " is kept; " + String(e))


def comment_edit(client: Client, args: Args, ui: Out) raises:
    args.check_known(["file", "F", "md", "html", "verbose", "v"])
    var id = args.need(2, "comment id")
    var text = text_from(args, args.pos(3), "the comment")
    if text == "":
        raise Error("missing comment text")
    _ = comment_by_id(client, id)
    var html = body_html(args, text)
    var d = JsonDoc()
    var kw = d.object()
    d.set_str(kw, "text", html)
    _ = client.call("CmfComment.update", d.dump(kw), "[" + quote_str(id) + "]")
    var got = comment_by_id(client, id)
    if not text_confirmed(html, got.doc.text_at(got.result, "text")):
        raise Error(id + ": edit returned, but text was not confirmed")
    print("edited " + id + "; EvaTeam controls the edited marker")


def comments_kwargs(task_id: String, human: Bool, fields: List[String]) raises -> String:
    """CmfComment.list over one task, oldest first. log_level 0 is what people
    wrote; 1 is field and status changes, 2 is system records."""
    var d = JsonDoc()
    var kw = d.object()
    var flt = d.array()
    var tid = d.string(task_id)
    var by_task = d.triple("parent_id", "==", tid)
    d.push(flt, by_task)
    if human:
        var zero = d.number(0)
        var by_people = d.triple("log_level", "==", zero)
        d.push(flt, by_people)
    d.set(kw, "filter", flt)
    if len(fields) > 0:
        var fl = d.str_array(fields)
        d.set(kw, "fields", fl)
        var order = d.str_array([String("cmf_created_at")])
        d.set(kw, "order_by", order)
        var s = d.array()
        var lo = d.number(0)
        var hi = d.number(10000)
        d.push(s, lo)
        d.push(s, hi)
        d.set(kw, "slice", s)
    return d.dump(kw)


def task_comments(client: Client, args: Args, ui: Out) raises:
    args.check_known(
        [
            "human",
            "ids",
            "all",
            "limit",
            "n",
            "page",
            "verbose",
            "v",
            "json",
            "format",
            "full",
        ]
    )
    var code = args.need(2, "task or document code")
    var human = args.has("human")
    var cls = "CmfDocument" if (args.pos(0) == "doc" or args.pos(0) == "docs") else "CmfTask"
    var task_id = id_of(client, cls, "code", code)
    var fields: List[String] = [
        "id",
        "text",
        "cmf_created_at",
        "cmf_author.name",
        "log_level",
        "tree_parent_id",
    ]
    var count_kw = comments_kwargs(task_id, human, List[String]())
    var total_reply = client.call("CmfComment.count", count_kw)
    var total = Int(total_reply.doc.text(total_reply.result))
    var limit = args.int_or("limit", "n", 20)
    var page = args.int_or("page", "", 1)
    if limit < 1 or page < 1:
        raise Error("--limit and --page start at 1")
    if args.has("all") and (args.has("page") or args.has("limit", "n")):
        raise Error("--all cannot be combined with --page or --limit")
    var r: Reply
    if args.has("all"):
        var fd = JsonDoc()
        var root = fd.parse(count_kw)
        r = collect_rows(
            client,
            "CmfComment",
            fd.dump(fd.get(root, "filter")),
            ",".join(fields),
            10000,
            "cmf_created_at",
        )
    else:
        var d = JsonDoc()
        var kw = d.parse(comments_kwargs(task_id, human, fields))
        var order = d.str_array([String("-cmf_created_at"), String("-id")])
        d.set(kw, "order_by", order)
        var slice = d.array()
        var lo = d.number((page - 1) * limit)
        var hi = d.number(page * limit)
        d.push(slice, lo)
        d.push(slice, hi)
        d.set(kw, "slice", slice)
        r = client.call("CmfComment.list", d.dump(kw))
        r.doc.reverse_array(r.result)
    if want_json(args):
        print_json(r)
        return
    var n = r.doc.len(r.result)
    for i in range(n):
        var c = r.doc.at(r.result, i)
        var who = r.doc.text_at(c, "cmf_author.name")
        var head = ui.accent(r.doc.text_at(c, "cmf_created_at")) + ("  " + who if who != "" else "")
        if args.has("ids"):
            head += "  " + ui.dim(r.doc.text_at(c, "id"))
        var parent = r.doc.text_at(c, "tree_parent_id")
        if parent != "":
            head += "  reply to " + parent
        print(head)
        ui.untrusted(code + "/comments/" + String(i + 1), r.doc.text_at(c, "text"))
    var tally = String(n) + (" comment" if n == 1 else " comments")
    if human:
        var all = client.call("CmfComment.count", comments_kwargs(task_id, False, List[String]()))
        var hidden = Int(all.doc.text(all.result)) - total
        tally += " by people"
        if hidden > 0:
            tally += ", " + String(hidden) + " workflow and system entries hidden"
    print(ui.dim(tally))
    var summary = "shown " + String(n) + " of " + String(total)
    if not args.has("all") and page * limit < total:
        summary += " · earlier: --page " + String(page + 1)
    print(ui.dim(summary))


def task_comment_delete(client: Client, args: Args, ui: Out) raises:
    args.check_known(["verbose", "v"])
    var id = args.need(2, "comment id; eva task comments CODE --ids shows them")
    if id.find(":") < 0:
        id = "CmfComment:" + id
    if not id.startswith("CmfComment:"):
        raise Error(id + " is not a comment id (CmfComment:…)")
    # .delete takes the id positionally; as a kwarg the server refuses it.
    _ = client.call("CmfComment.delete", "", "[" + quote_str(id) + "]")
    print("deleted " + ui.bold(id) + "; EvaTeam keeps a 'comment deleted' entry with its text")
