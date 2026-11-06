"""The command tree. Each command builds kwargs as a JsonDoc, calls one or two
API methods and prints the reply."""

from std.ffi import external_call, c_int
from std.memory.alloc import unsafe_alloc

from eva.args import Args
from eva.client import Client, Reply, load_config
from eva.json import JsonDoc, NO_NODE, J_ARR, J_OBJ
from eva.render import Out, pad, clip, text_to_html, markdown_to_html
from eva.term import read_all

comptime TASK_FIELDS = (
    "*,status.name,status.code,responsible.name,responsible.login,"
    "cmf_author.name,cmf_author.login,parent.code,parent.name,"
    "parent_task.code,parent_task.name,child_tasks.code,child_tasks.name,"
    "child_tasks.status.name,child_tasks.cache_status_type,child_tasks.responsible.login"
)

# Subtask rows shown through a pipe before `(+N more: --full)`.
comptime PIPE_SUBTASKS = 20

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


def text_from(args: Args, inline: String, what: String) raises -> String:
    """`inline`, or the text of the file -F names (`-` reads stdin)."""
    var path = args.get("file", "F")
    if path == "":
        return inline
    if inline != "":
        raise Error("give " + what + " as an argument or with -F, not both")
    var text: String
    if path == "-":
        text = read_all()
    else:
        try:
            with open(path, "r") as f:
                text = f.read()
        except e:
            raise Error("cannot read " + path + ": " + String(e))
    if text.strip() == "":
        raise Error(what + " in " + ("stdin" if path == "-" else path) + " is empty")
    return String(text.rstrip())


def body_html(args: Args, text: String) raises -> String:
    """Text as EvaTeam stores it: plain by default, --md converted, --html as is."""
    var md = args.has("md")
    var html = args.has("html")
    if md and html:
        raise Error("--md and --html exclude each other")
    if html:
        return text
    if md:
        return markdown_to_html(text)
    return text_to_html(text)


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
        # Only what was asked for: the server adds ids, and a dotted path
        # comes back nested.
        for f in split_csv(args.get("fields")):
            print(f + ": " + d.text_at(t, f))
        return
    print(ui.bold(d.text_at(t, "code")) + "  " + String(d.text_at(t, "name").strip()))
    var status = d.text_at(t, "status.name")
    if status == "":
        status = d.text_at(t, "cache_status_type")
    print("status: " + ui.status(status) + "   stage: " + d.text_at(t, "cache_status_type"))
    print("assignee: " + person(d, t, "responsible") + "   author: " + person(d, t, "cmf_author"))
    var project = d.text_at(t, "parent.code")
    if project != "":
        print("project: " + project + "  " + d.text_at(t, "parent.name"))
    var parent_task = d.text_at(t, "parent_task.code")
    if parent_task != "":
        print("parent task: " + parent_task + "  " + String(d.text_at(t, "parent_task.name").strip()))
    print(ui.dim("created: " + d.text_at(t, "cmf_created_at") + "   updated: " + d.text_at(t, "cmf_modified_at")))
    var deadline = d.text_at(t, "deadline")
    if deadline != "":
        print("deadline: " + deadline)
    print_subtasks(d, d.get(t, "child_tasks"), ui)
    ui.untrusted(code + "/text", d.text_at(t, "text"))


def print_subtasks(d: JsonDoc, list: Int, ui: Out) raises:
    """Open subtasks first, then closed, with a count of each stage."""
    var n = d.len(list)
    if n == 0:
        return
    var open_rows = List[Int]()
    var closed_rows = List[Int]()
    var n_open = 0
    var n_progress = 0
    var n_review = 0
    for i in range(n):
        var c = d.at(list, i)
        var stage = d.text_at(c, "cache_status_type")
        if stage == "CLOSED":
            closed_rows.append(c)
        else:
            open_rows.append(c)
            if stage == "IN_PROGRESS":
                n_progress += 1
            elif stage == "IN_REVIEW":
                n_review += 1
            else:
                n_open += 1
    var tally = String(n_open) + " open, " + String(n_progress) + " in progress"
    if n_review > 0:
        tally += ", " + String(n_review) + " in review"
    tally += ", " + String(len(closed_rows)) + " closed"
    print("subtasks: " + String(n) + " (" + tally + ")")
    var rows = open_rows^
    for c in closed_rows:
        rows.append(c)
    var limit = n if ui.tty or ui.full else min(n, PIPE_SUBTASKS)
    for i in range(limit):
        var c = rows[i]
        var status = d.text_at(c, "status.name")
        if status == "":
            status = d.text_at(c, "cache_status_type")
        var who = d.text_at(c, "responsible.login")
        print(
            "  "
            + ui.accent(pad(d.text_at(c, "code"), 12))
            + " "
            + ui.status(pad(clip(status, 18), 18))
            + " "
            + pad(clip(who if who != "" else "-", 18), 18)
            + " "
            + clip(d.text_at(c, "name"), 70)
        )
    if limit < n:
        print(ui.dim("  (+" + String(n - limit) + " more subtasks: --full)"))


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
        c = d.triple("name", "ILIKE", v)
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
        ["project", "p", "name", "title", "t", "description", "d", "file", "F", "md", "html",
         "assignee", "a", "sprint", "json", "format", "verbose", "v"]
    )
    var project = args.get("project", "p")
    var name = args.get("title", "t")
    if name == "":
        name = args.get("name")
    if project == "" or name == "":
        raise Error(
            "usage: eva task create -p PROJECT -t TITLE [-d TEXT | -F FILE] [--md|--html] [-a LOGIN]"
            " [--sprint SPR-1]"
        )
    var d = JsonDoc()
    var kw = d.object()
    d.set_str(kw, "parent", project)
    d.set_str(kw, "name", name)
    var desc = text_from(args, args.get("description", "d"), "the description")
    if desc != "":
        d.set_str(kw, "text", body_html(args, desc))
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
        ["name", "title", "t", "description", "d", "file", "F", "md", "html", "assignee", "a",
         "status", "s", "comment", "m", "set", "json", "format", "verbose", "v"]
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
    var desc = text_from(args, args.get("description", "d"), "the description")
    if desc != "":
        d.set_str(kw, "text", body_html(args, desc))
        changed.append("text")
    # Status changes go through a workflow transition, after the other fields.
    var status = args.get("status", "s")
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
    if len(changed) == 0 and status == "":
        raise Error("nothing to change: pass -t, -d or -F, -s, -a or --set")
    if len(changed) > 0:
        var id = id_of(client, "CmfTask", "code", code)
        var args_json = "[" + quote_str(id) + "]"
        _ = client.call("CmfTask.update", d.dump(kw), args_json)
        print("updated " + ui.bold(code) + ": " + ", ".join(changed))
    if status != "":
        # --set already went into the update above.
        move_task(client, code, status, args.get("comment", "m"), "", ui)


# ---- workflow transitions ----


struct Transitions(Movable):
    """The transitions a task can take from its current status."""

    var task_id: String
    var current: String
    var trans_ids: List[String]
    var trans_names: List[String]
    var to_ids: List[String]
    var to_codes: List[String]
    var to_names: List[String]

    def __init__(out self):
        self.task_id = ""
        self.current = ""
        self.trans_ids = List[String]()
        self.trans_names = List[String]()
        self.to_ids = List[String]()
        self.to_codes = List[String]()
        self.to_names = List[String]()


def transitions_for(client: Client, code: String) raises -> Transitions:
    var t = get_by_code(
        client, "CmfTask", code, split_csv("id,status_id,status.name,workflow_id")
    )
    var out = Transitions()
    out.task_id = t.doc.text_at(t.result, "id")
    out.current = t.doc.text_at(t.result, "status.name")
    var status_id = t.doc.text_at(t.result, "status_id")
    var wf = t.doc.text_at(t.result, "workflow_id")
    if wf == "":
        raise Error(code + ": the task has no workflow")

    var d = JsonDoc()
    var kw = d.object()
    var v = d.string(wf)
    var f = d.triple("workflow_id", "==", v)
    d.set(kw, "filter", f)
    var fl = d.str_array(
        split_csv("name,status_to_id,status_to.code,status_to.name,status_from.id")
    )
    d.set(kw, "fields", fl)
    var r = client.call("CmfTrans.list", d.dump(kw))
    for i in range(r.doc.len(r.result)):
        var tr = r.doc.at(r.result, i)
        var to_id = r.doc.text_at(tr, "status_to_id")
        if to_id == status_id:
            continue
        # An empty status_from is a system transition (creation, reset); skip it.
        var from_list = r.doc.get(tr, "status_from")
        var allowed = False
        for j in range(r.doc.len(from_list)):
            if r.doc.text_at(r.doc.at(from_list, j), "id") == status_id:
                allowed = True
                break
        if not allowed:
            continue
        out.trans_ids.append(r.doc.text_at(tr, "id"))
        out.trans_names.append(r.doc.text_at(tr, "name"))
        out.to_ids.append(to_id)
        out.to_codes.append(r.doc.text_at(tr, "status_to.code"))
        out.to_names.append(r.doc.text_at(tr, "status_to.name"))
    return out^


def move_task(
    client: Client, code: String, target: String, comment: String, fields: String, ui: Out
) raises:
    var tr = transitions_for(client, code)
    var want = target.lower()
    var pick = -1
    for i in range(len(tr.trans_ids)):
        if tr.to_codes[i].lower() == want or tr.to_names[i].lower() == want:
            pick = i
            break
    if pick < 0:
        var options = List[String]()
        for i in range(len(tr.to_codes)):
            options.append(tr.to_codes[i] + " (" + tr.to_names[i] + ")")
        raise Error(
            code + " is in " + tr.current + " and cannot move to " + target
            + "; it can move to: " + (", ".join(options) if len(options) > 0 else "nothing")
        )
    var d = JsonDoc()
    var kw = d.object()
    d.set_str(kw, "comment_append", text_to_html(comment) if comment != "" else "")
    var changed = d.object()
    if fields != "":
        # Fields the transition requires, e.g. --set '{"cf_vid_uslugi": "razvitie"}'.
        changed = d.parse(fields)
        if d.kind(changed) != J_OBJ:
            raise Error("--set expects a JSON object")
    d.set_str(changed, "status", tr.to_ids[pick])
    d.set(kw, "changed_fields", changed)
    var args_json = "[" + quote_str(tr.task_id) + "," + quote_str(tr.trans_ids[pick]) + "]"
    _ = client.call("CmfTask.task_transition_run", d.dump(kw), args_json)
    print("moved " + ui.bold(code) + ": " + tr.current + " → " + ui.status(tr.to_names[pick]))


def task_statuses(client: Client, args: Args, ui: Out) raises:
    args.check_known(["verbose", "v"])
    var code = args.need(2, "task code")
    var tr = transitions_for(client, code)
    print(ui.bold(code) + " is in " + ui.status(tr.current) + "; it can move to:")
    for i in range(len(tr.to_codes)):
        print("  " + ui.accent(pad(tr.to_codes[i], 26)) + " " + tr.to_names[i])
    if len(tr.to_codes) == 0:
        print(ui.dim("  nothing"))


def quote_str(s: String) -> String:
    var d = JsonDoc()
    return d.dump(d.string(s))


def task_comment(client: Client, args: Args, ui: Out) raises:
    args.check_known(["file", "F", "md", "html", "verbose", "v", "json", "format"])
    var code = args.need(2, "task code")
    var text = text_from(args, args.pos(3), "the comment")
    if text == "":
        raise Error("missing comment text: eva task comment CODE TEXT, or -F FILE (- for stdin)")
    var d = JsonDoc()
    var kw = d.object()
    d.set_str(kw, "parent", code)
    d.set_str(kw, "text", body_html(args, text))
    _ = client.call("CmfComment.create", d.dump(kw))
    print("commented on " + ui.bold(code))


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
    args.check_known(["human", "ids", "verbose", "v", "json", "format", "full"])
    var code = args.need(2, "task code")
    var human = args.has("human")
    # Listed from CmfComment itself: the task's `comments` relation can miss
    # comments posted from the web UI.
    var task_id = id_of(client, "CmfTask", "code", code)
    var fields: List[String] = ["id", "text", "cmf_created_at", "cmf_author.name", "log_level"]
    var r = client.call("CmfComment.list", comments_kwargs(task_id, human, fields))
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
        print(head)
        ui.untrusted(code + "/comments/" + String(i + 1), r.doc.text_at(c, "text"))
    var tally = String(n) + (" comment" if n == 1 else " comments")
    if human:
        var all = client.call("CmfComment.count", comments_kwargs(task_id, False, List[String]()))
        var hidden = Int(all.doc.text(all.result)) - n
        tally += " by people"
        if hidden > 0:
            tally += ", " + String(hidden) + " workflow and system entries hidden"
    print(ui.dim(tally))


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
    # The server requires remaining_estimate; null leaves the estimate alone.
    var rem = args.get("remaining")
    var rv = d.number(parse_minutes(rem)) if rem != "" else d.null()
    d.set(kw, "remaining_estimate", rv)
    var msg = args.get("message", "m")
    if msg != "":
        d.set_str(kw, "text", msg)
    d.set_str(kw, "date", local_now())
    _ = client.call("CmfTask.timetracker_change_time", d.dump(kw), "[" + quote_str(id) + "]")
    print("logged " + String(minutes) + " min on " + ui.bold(code))


def local_now() -> String:
    """Local time as YYYY-MM-DD HH:MM:SS, via libc."""
    var t = unsafe_alloc[Int](1)
    t[unsafe_offset=0] = Int(external_call["time", Int](Int(0)))
    # struct tm is 36-56 bytes depending on the platform; 128 leaves room.
    var tm = unsafe_alloc[UInt8](128)
    _ = external_call["localtime_r", Int](t, tm)
    var buf = unsafe_alloc[UInt8](64)
    var fmt = "%Y-%m-%d %H:%M:%S"
    var n = Int(external_call["strftime", Int](buf, Int(64), fmt.unsafe_ptr(), tm))
    var bytes = List[UInt8]()
    for i in range(n):
        bytes.append(buf[unsafe_offset=i])
    t.unsafe_free()
    tm.unsafe_free()
    buf.unsafe_free()
    return String(from_utf8_lossy=Span(bytes))


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
        var c = d.triple(field, "ILIKE", v)
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
    print(ui.bold(r.doc.text_at(r.result, "code")) + "  " + String(r.doc.text_at(r.result, "name").strip()))
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


def task_move(client: Client, args: Args, ui: Out) raises:
    args.check_known(["comment", "m", "set", "verbose", "v"])
    var code = args.need(2, "task code")
    var target = args.need(3, "status code or name; see eva task statuses " + code)
    move_task(client, code, target, args.get("comment", "m"), args.get("set"), ui)
