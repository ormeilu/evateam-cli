"""The command tree. Each command builds kwargs as a JsonDoc, calls one or two
API methods and prints the reply."""

from std.python import Python

from eva.args import Args
from eva.client import Client, Reply, load_config
from eva.json import JsonDoc, NO_NODE, J_ARR, J_OBJ
from eva.render import Out, pad, clip, text_to_html

comptime TASK_FIELDS = (
    "*,status.name,status.code,responsible.name,responsible.login,"
    "cmf_author.name,cmf_author.login,parent.code,parent.name"
)

comptime LIST_FIELDS = (
    "code,name,cache_status_type,status.name,responsible.login,"
    "responsible.name,cmf_created_at"
)


def split_csv(raw: String) -> List[String]:
    var out = List[String]()
    for f in raw.split(","):
        var s = String(f.strip())
        if s != "":
            out.append(s)
    return out^


def fields_from(args: Args, default: String) -> List[String]:
    var raw = args.get("fields")
    return split_csv(raw if raw != "" else default)


# ---- shared helpers ----


def code_kwargs(code: String, fields: List[String]) raises -> String:
    var d = JsonDoc()
    var kw = d.object()
    var v = d.string(code)
    var f = d.triple("code", "==", v)
    d.set(kw, "filter", f)
    if len(fields) > 0:
        var fl = d.str_array(fields)
        d.set(kw, "fields", fl)
    return d.dump(kw)


def get_by_code(client: Client, cls: String, code: String, fields: List[String]) raises -> Reply:
    var r = client.call(cls + ".get", code_kwargs(code, fields))
    if r.doc.is_null(r.result) or r.doc.kind(r.result) != J_OBJ:
        raise Error(code + ": not found")
    return r^


def id_of(client: Client, cls: String, field: String, value: String) raises -> String:
    var d = JsonDoc()
    var kw = d.object()
    var v = d.string(value)
    var f = d.triple(field, "==", v)
    d.set(kw, "filter", f)
    var fl = d.str_array([String("id")])
    d.set(kw, "fields", fl)
    var r = client.call(cls + ".get", d.dump(kw))
    var id = r.doc.text_at(r.result, "id")
    if id == "":
        raise Error(cls + " with " + field + " " + value + ": not found")
    return id


def print_json(r: Reply):
    print(r.doc.dump_pretty(r.result))


def want_json(args: Args) -> Bool:
    return args.has("json") or args.get("format") == "json"


def person(doc: JsonDoc, n: Int, field: String) raises -> String:
    var login = doc.text_at(n, field + ".login")
    if login != "":
        return login
    var name = doc.text_at(n, field + ".name")
    return name if name != "" else "-"


def page_slice(mut d: JsonDoc, args: Args) raises -> Int:
    var limit = args.int_or("limit", "n", 25)
    var page = args.int_or("page", "", 1)
    if limit < 1 or page < 1:
        raise Error("--limit and --page start at 1")
    var s = d.array()
    var a = d.number((page - 1) * limit)
    var b = d.number(page * limit)
    d.push(s, a)
    d.push(s, b)
    return s


def footer(ui: Out, shown: Int, total: Int, args: Args) raises:
    var limit = args.int_or("limit", "n", 25)
    var page = args.int_or("page", "", 1)
    var first = (page - 1) * limit
    var line = "shown " + String(shown) + " of " + String(total)
    if first + shown < total:
        line += " — next: --page " + String(page + 1)
    print(ui.dim(line))


# ---- task ----


def task_get(client: Client, args: Args, ui: Out) raises:
    args.check_known(["fields", "json", "format", "full", "verbose", "v"])
    var code = args.need(2, "task code, e.g. eva task get DEV-12")
    var r = get_by_code(client, "CmfTask", code, fields_from(args, TASK_FIELDS))
    if want_json(args):
        print_json(r)
        return
    ref d = r.doc
    var t = r.result
    if args.get("fields") != "":
        for i in range(d.len(t)):
            print(d.key_at(t, i) + ": " + d.text(d.at(t, i)))
        return
    print(ui.bold(d.text_at(t, "code")) + "  " + d.text_at(t, "name"))
    var status = d.text_at(t, "status.name")
    if status == "":
        status = d.text_at(t, "cache_status_type")
    print("status: " + ui.status(status) + "   stage: " + d.text_at(t, "cache_status_type"))
    print("assignee: " + person(d, t, "responsible") + "   author: " + person(d, t, "cmf_author"))
    var parent = d.text_at(t, "parent.code")
    if parent != "":
        print("parent: " + parent + "  " + d.text_at(t, "parent.name"))
    print(ui.dim("created: " + d.text_at(t, "cmf_created_at") + "   updated: " + d.text_at(t, "cmf_modified_at")))
    var deadline = d.text_at(t, "deadline")
    if deadline != "":
        print("deadline: " + deadline)
    ui.untrusted(code + "/text", d.text_at(t, "text"))


def status_condition(mut d: JsonDoc, s: String) raises -> Int:
    var l = s.lower()
    if l == "open":
        var v = d.string("CLOSED")
        return d.triple("cache_status_type", "!=", v)
    if l == "closed" or l == "in_progress" or l == "in_review":
        var v = d.string(l.upper())
        return d.triple("cache_status_type", "==", v)
    var v = d.string(s)
    return d.triple("status.code", "==", v)


def task_filter(client: Client, mut d: JsonDoc, args: Args) raises -> Int:
    var conds = d.array()
    var f = d.boolean(False)
    var c = d.triple("system", "==", f)
    d.push(conds, c)
    var project = args.get("project", "p")
    if project != "":
        # project.code also catches tasks nested under an epic; parent_id
        # would not.
        var v = d.string(project)
        c = d.triple("project.code", "==", v)
        d.push(conds, c)
    var assignee = args.get("assignee", "a")
    if assignee != "":
        var v = d.string(assignee)
        c = d.triple("responsible.login", "==", v)
        d.push(conds, c)
    var status = args.get("status", "s")
    if status != "" and status != "all":
        c = status_condition(d, status)
        d.push(conds, c)
    var q = args.get("query", "q")
    if q != "":
        var v = d.string("%" + q + "%")
        c = d.triple("name", "LIKE", v)
        d.push(conds, c)
    var raw = args.get("filter")
    if raw != "":
        c = d.parse(raw)
        d.push(conds, c)
    return conds


def task_list(client: Client, args: Args, ui: Out) raises:
    args.check_known(
        ["project", "p", "assignee", "a", "status", "s", "query", "q", "filter",
         "limit", "n", "page", "fields", "order", "json", "format", "full", "verbose", "v"]
    )
    var d = JsonDoc()
    var kw = d.object()
    var flt = task_filter(client, d, args)
    d.set(kw, "filter", flt)
    var count_kw = d.dump(kw)
    var fl = d.str_array(fields_from(args, LIST_FIELDS))
    d.set(kw, "fields", fl)
    var order = args.get("order")
    var ob = d.str_array([order if order != "" else String("-cmf_created_at")])
    d.set(kw, "order_by", ob)
    var sl = page_slice(d, args)
    d.set(kw, "slice", sl)

    var r = client.call("CmfTask.list", d.dump(kw))
    if want_json(args):
        print_json(r)
        return
    ref rd = r.doc
    var n = rd.len(r.result)
    for i in range(n):
        var t = rd.at(r.result, i)
        var status = rd.text_at(t, "status.name")
        if status == "":
            status = rd.text_at(t, "cache_status_type")
        print(
            ui.accent(pad(rd.text_at(t, "code"), 12))
            + " "
            + ui.status(pad(clip(status, 18), 18))
            + " "
            + pad(clip(person(rd, t, "responsible"), 18), 18)
            + " "
            + clip(rd.text_at(t, "name"), 80)
        )
    var total = n
    try:
        var c = client.call("CmfTask.count", count_kw)
        total = Int(c.doc.text(c.result))
    except:
        pass
    footer(ui, n, total, args)


def task_create(client: Client, args: Args, ui: Out) raises:
    args.check_known(
        ["project", "p", "name", "title", "t", "description", "d", "assignee", "a",
         "sprint", "json", "format", "verbose", "v"]
    )
    var project = args.get("project", "p")
    var name = args.get("title", "t")
    if name == "":
        name = args.get("name")
    if project == "" or name == "":
        raise Error("usage: eva task create -p PROJECT -t TITLE [-d TEXT] [-a LOGIN] [--sprint SPR-1]")
    var d = JsonDoc()
    var kw = d.object()
    d.set_str(kw, "parent", project)
    d.set_str(kw, "name", name)
    var desc = args.get("description", "d")
    if desc != "":
        d.set_str(kw, "text", text_to_html(desc))
    var assignee = args.get("assignee", "a")
    if assignee != "":
        var ref_obj = d.object()
        d.set_str(ref_obj, "id", id_of(client, "CmfPerson", "login", assignee))
        d.set(kw, "responsible", ref_obj)
    var sprint = args.get("sprint")
    if sprint != "":
        var lists = d.str_array([sprint])
        d.set(kw, "lists", lists)
    var r = client.call("CmfTask.create", d.dump(kw))
    var id = r.doc.text(r.result)
    var code = id
    try:
        var g = JsonDoc()
        var gk = g.object()
        var v = g.string(id)
        var f = g.triple("id", "==", v)
        g.set(gk, "filter", f)
        var fl = g.str_array([String("code")])
        g.set(gk, "fields", fl)
        var t = client.call("CmfTask.get", g.dump(gk))
        var c = t.doc.text_at(t.result, "code")
        if c != "":
            code = c
    except:
        pass
    print("created " + ui.bold(code) + "  " + name)


def task_update(client: Client, args: Args, ui: Out) raises:
    args.check_known(
        ["name", "title", "t", "description", "d", "assignee", "a", "status", "s",
         "set", "json", "format", "verbose", "v"]
    )
    var code = args.need(2, "task code")
    var d = JsonDoc()
    var kw = d.object()
    var changed = List[String]()
    var name = args.get("title", "t")
    if name == "":
        name = args.get("name")
    if name != "":
        d.set_str(kw, "name", name)
        changed.append("name")
    var desc = args.get("description", "d")
    if desc != "":
        d.set_str(kw, "text", text_to_html(desc))
        changed.append("text")
    var status = args.get("status", "s")
    if status != "":
        d.set_str(kw, "status", status)
        changed.append("status")
    var assignee = args.get("assignee", "a")
    if assignee != "":
        var ref_obj = d.object()
        d.set_str(ref_obj, "id", id_of(client, "CmfPerson", "login", assignee))
        d.set(kw, "responsible", ref_obj)
        changed.append("responsible")
    var raw = args.get("set")
    if raw != "":
        # --set '{"deadline": "2026-12-01"}' merges raw fields.
        var extra = d.parse(raw)
        if d.kind(extra) != J_OBJ:
            raise Error("--set expects a JSON object")
        for i in range(d.len(extra)):
            d.set(kw, d.key_at(extra, i), d.at(extra, i))
            changed.append(d.key_at(extra, i))
    if len(changed) == 0:
        raise Error("nothing to change: pass -t, -d, -s, -a or --set")
    var id = id_of(client, "CmfTask", "code", code)
    var args_json = "[" + quote_str(id) + "]"
    _ = client.call("CmfTask.update", d.dump(kw), args_json)
    print("updated " + ui.bold(code) + ": " + ", ".join(changed))


def quote_str(s: String) -> String:
    var d = JsonDoc()
    return d.dump(d.string(s))


def task_comment(client: Client, args: Args, ui: Out) raises:
    args.check_known(["verbose", "v", "json", "format"])
    var code = args.need(2, "task code")
    var text = args.need(3, "comment text")
    var d = JsonDoc()
    var kw = d.object()
    d.set_str(kw, "parent", code)
    d.set_str(kw, "text", text_to_html(text))
    _ = client.call("CmfComment.create", d.dump(kw))
    print("commented on " + ui.bold(code))


def task_comments(client: Client, args: Args, ui: Out) raises:
    args.check_known(["verbose", "v", "json", "format", "full"])
    var code = args.need(2, "task code")
    var r = get_by_code(client, "CmfTask", code, [String("comments.*"), String("comments.cmf_author.name")])
    var list = r.doc.get(r.result, "comments")
    if want_json(args):
        print(r.doc.dump_pretty(list))
        return
    var n = r.doc.len(list)
    for i in range(n):
        var c = r.doc.at(list, i)
        var who = r.doc.text_at(c, "cmf_author.name")
        print(ui.accent(r.doc.text_at(c, "cmf_created_at")) + ("  " + who if who != "" else ""))
        ui.untrusted(code + "/comments/" + String(i + 1), r.doc.text_at(c, "text"))
    print(ui.dim(String(n) + " comments"))


def task_log(client: Client, args: Args, ui: Out) raises:
    args.check_known(["message", "m", "remaining", "verbose", "v", "json", "format"])
    var code = args.need(2, "task code")
    var minutes_raw = args.need(3, "minutes, e.g. 90 or 1h30m")
    var minutes = parse_minutes(minutes_raw)
    var id = id_of(client, "CmfTask", "code", code)
    var d = JsonDoc()
    var kw = d.object()
    var ts = d.number(minutes)
    d.set(kw, "time_spent", ts)
    var rem = args.get("remaining")
    if rem != "":
        var rv = d.number(parse_minutes(rem))
        d.set(kw, "remaining_estimate", rv)
    var msg = args.get("message", "m")
    if msg != "":
        d.set_str(kw, "text", msg)
    var dt = Python.import_module("datetime")
    d.set_str(kw, "date", String(dt.datetime.now()))
    _ = client.call("CmfTask.timetracker_change_time", d.dump(kw), "[" + quote_str(id) + "]")
    print("logged " + String(minutes) + " min on " + ui.bold(code))


def parse_minutes(s: String) raises -> Int:
    """`90`, `90m`, `2h`, `1h30m` → minutes."""
    var total = 0
    var num = 0
    var seen = False
    for b in s.lower().as_bytes():
        var c = Int(b)
        if c >= 0x30 and c <= 0x39:
            num = num * 10 + (c - 0x30)
            seen = True
        elif c == 0x68 and seen:  # h
            total += num * 60
            num = 0
            seen = False
        elif c == 0x6D and seen:  # m
            total += num
            num = 0
            seen = False
        else:
            raise Error("cannot read a duration from " + s)
    total += num
    if total <= 0:
        raise Error("duration must be positive: " + s)
    return total


def task_links(client: Client, args: Args, ui: Out) raises:
    args.check_known(["verbose", "v", "json", "format"])
    var code = args.need(2, "task code")
    var r = get_by_code(client, "CmfTask", code, [String("out_tasks.**"), String("in_tasks.**")])
    if want_json(args):
        print_json(r)
        return
    var n = 0
    var outs = r.doc.get(r.result, "out_tasks")
    for i in range(r.doc.len(outs)):
        var l = r.doc.at(outs, i)
        print("→ " + ui.accent(r.doc.text_at(l, "out_link.code")) + "  " + r.doc.text_at(l, "out_link.name"))
        n += 1
    var ins = r.doc.get(r.result, "in_tasks")
    for i in range(r.doc.len(ins)):
        var l = r.doc.at(ins, i)
        print("← " + ui.accent(r.doc.text_at(l, "in_link.code")) + "  " + r.doc.text_at(l, "in_link.name"))
        n += 1
    print(ui.dim(String(n) + " links (→ outgoing, ← incoming)"))


# ---- projects, people, documents ----


def simple_list(
    client: Client,
    args: Args,
    ui: Out,
    cls: String,
    var fields: List[String],
    filter_json: String,
    key: String,
    cols: List[String],
) raises:
    var d = JsonDoc()
    var kw = d.object()
    if filter_json != "":
        var f = d.parse(filter_json)
        d.set(kw, "filter", f)
    var count_kw = d.dump(kw)
    var fl = d.str_array(fields)
    d.set(kw, "fields", fl)
    var sl = page_slice(d, args)
    d.set(kw, "slice", sl)
    var r = client.call(cls + ".list", d.dump(kw))
    if want_json(args):
        print_json(r)
        return
    var n = r.doc.len(r.result)
    for i in range(n):
        var row = r.doc.at(r.result, i)
        var line = ui.accent(pad(r.doc.text_at(row, key), 14))
        for c in cols:
            line += "  " + clip(r.doc.text_at(row, c), 60)
        print(line)
    var total = n
    try:
        var c = client.call(cls + ".count", count_kw)
        total = Int(c.doc.text(c.result))
    except:
        pass
    footer(ui, n, total, args)


def like_filter(field: String, q: String, base: String) -> String:
    var d = JsonDoc()
    var conds = d.array()
    if base != "":
        try:
            var b = d.parse(base)
            d.push(conds, b)
        except:
            pass
    if q != "":
        var v = d.string("%" + q + "%")
        var c = d.triple(field, "LIKE", v)
        d.push(conds, c)
    if d.len(conds) == 0:
        return ""
    if d.len(conds) == 1:
        return d.dump(d.at(conds, 0))
    return d.dump(conds)


def project_list(client: Client, args: Args, ui: Out) raises:
    args.check_known(["query", "q", "limit", "n", "page", "json", "format", "verbose", "v"])
    var f = like_filter("name", args.get("query", "q"), "")
    simple_list(client, args, ui, "CmfProject", [String("code"), String("name")], f, "code", [String("name")])


def person_list(client: Client, args: Args, ui: Out) raises:
    args.check_known(["query", "q", "limit", "n", "page", "json", "format", "verbose", "v"])
    var f = like_filter("name", args.get("query", "q"), '["system", "==", false]')
    simple_list(
        client, args, ui, "CmfPerson",
        [String("login"), String("name"), String("email")],
        f, "login", [String("name"), String("email")],
    )


def doc_list(client: Client, args: Args, ui: Out) raises:
    args.check_known(["query", "q", "limit", "n", "page", "json", "format", "verbose", "v"])
    var f = like_filter("name", args.get("query", "q"), "")
    simple_list(client, args, ui, "CmfDocument", [String("code"), String("name")], f, "code", [String("name")])


def doc_get(client: Client, args: Args, ui: Out) raises:
    args.check_known(["json", "format", "full", "verbose", "v"])
    var code = args.need(2, "document code, e.g. DOC-000066")
    var r = get_by_code(client, "CmfDocument", code, [String("code"), String("name"), String("text"), String("cmf_owner.login")])
    if want_json(args):
        print_json(r)
        return
    print(ui.bold(r.doc.text_at(r.result, "code")) + "  " + r.doc.text_at(r.result, "name"))
    print(ui.dim("owner: " + r.doc.text_at(r.result, "cmf_owner.login")))
    ui.untrusted(code + "/text", r.doc.text_at(r.result, "text"))


# ---- escape hatch ----


def raw_call(client: Client, args: Args, ui: Out) raises:
    args.check_known(["kwargs", "k", "args", "flags", "verbose", "v", "json", "format"])
    var method = args.need(1, "method, e.g. eva call CmfTask.count --kwargs '{}'")
    var check = JsonDoc()
    var kwargs = args.get("kwargs", "k")
    var a = args.get("args")
    var flags = args.get("flags")
    # Validate locally so a typo fails before it reaches the server.
    if kwargs != "":
        _ = check.parse(kwargs)
    if a != "":
        _ = check.parse(a)
    if flags != "":
        _ = check.parse(flags)
    var r = client.call(method, kwargs, a, flags)
    print_json(r)
