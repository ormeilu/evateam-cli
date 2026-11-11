"""Read-only feeds, and sprints and releases: their tasks and the lists themselves."""
from eva.args import Args
from eva.client import Client, Reply, MAYBE_APPLIED
from eva.common import (
    get_by_code,
    id_of,
    quote_str,
    split_csv,
    simple_list,
    like_filter,
    page_slice,
    footer,
    print_json,
    want_json,
    text_from,
    body_html,
)
from eva.json import JsonDoc
from eva.render import Out
from eva.task_options import person_id, valid_datetime
from eva.dates import fmt_minutes, minutes_of
from eva.validation import date_key, require_fields
from eva.writes import preview_write


def filter_eq(field: String, value: String) -> String:
    var d = JsonDoc()
    var v = d.string(value)
    return d.dump(d.triple(field, "==", v))


def page_rows(
    client: Client,
    args: Args,
    cls: String,
    filter: String,
    fields: String,
    order: String,
) raises -> Reply:
    var d = JsonDoc()
    var kw = d.object()
    var f = d.parse(filter)
    d.set(kw, "filter", f)
    var fl = d.str_array(split_csv(fields))
    d.set(kw, "fields", fl)
    var sl = page_slice(d, args)
    d.set(kw, "slice", sl)
    var ob = d.str_array([order, String("id")])
    d.set(kw, "order_by", ob)
    return client.call(cls + ".list", d.dump(kw))


def page_footer(client: Client, args: Args, ui: Out, cls: String, filter: String, shown: Int) raises:
    var c = client.call(cls + ".count", '{"filter":' + filter + "}")
    footer(ui, shown, Int(c.doc.text(c.result)), args)


def list_kind(group: String) -> String:
    return "list.agile_sprint:default" if group == "sprint" else "list.release:default"


def list_command(client: Client, args: Args, ui: Out) raises:
    var group = args.pos(0)
    var sub = args.pos(1)
    var field = "lists" if group == "sprint" else "fix_versions"
    if sub == "list" or sub == "":
        args.check_known(
            [
                "project",
                "p",
                "status",
                "s",
                "limit",
                "n",
                "page",
                "json",
                "format",
                "verbose",
                "v",
            ]
        )
        var d = JsonDoc()
        var filter = d.array()
        var v = d.string(list_kind(group))
        var c = d.triple("logic_type.code", "==", v)
        d.push(filter, c)
        if args.get("project", "p") != "":
            v = d.string(args.get("project", "p"))
            c = d.triple("project.code", "==", v)
            d.push(filter, c)
        var status = args.get("status", "s").lower()
        if status != "" and status != "all":
            if status != "open" and status != "closed":
                raise Error("--status expects open, closed or all")
            v = d.string("CLOSED")
            c = d.triple("cache_status_type", "==" if status == "closed" else "!=", v)
            d.push(filter, c)
        simple_list(
            client,
            args,
            ui,
            "CmfList",
            split_csv("code,name,project.code,cache_status_type,cache_members_count"),
            d.dump(filter),
            "code",
            split_csv("name,project.code,cache_status_type,cache_members_count"),
        )
        return
    if sub == "create":
        list_create(client, args, ui, group)
        return
    var code = args.need(2, group + " code")
    var r = get_by_code(
        client,
        "CmfList",
        code,
        split_csv("id,code,name,logic_type.code,cache_status_type,cache_members_count,plan_start_date,plan_end_date"),
    )
    if r.doc.text_at(r.result, "logic_type.code") != list_kind(group):
        raise Error(code + " is not a " + group)
    if sub == "get":
        args.check_known(["limit", "n", "page", "json", "format", "verbose", "v"])
        if want_json(args):
            print_json(r)
            return
        print(code + "  " + r.doc.text_at(r.result, "name") + "  " + r.doc.text_at(r.result, "cache_status_type"))
        print("dates: " + r.doc.text_at(r.result, "plan_start_date") + " → " + r.doc.text_at(r.result, "plan_end_date"))
        simple_list(
            client,
            args,
            ui,
            "CmfTask",
            split_csv("code,name,status.name"),
            filter_eq(field + ".code", code),
            "code",
            split_csv("status.name,name"),
        )
    elif sub == "add" or sub == "remove":
        list_membership(client, args, r, group, code, field, sub == "add")
    elif sub == "update" or sub == "rename":
        list_update(client, args, ui, r, group, code, sub == "rename")
    else:
        raise Error("unknown " + group + " command " + sub)


def list_membership(
    client: Client,
    args: Args,
    r: Reply,
    group: String,
    code: String,
    field: String,
    adding: Bool,
) raises:
    """`add` and `remove`, one task at a time through the field's own append
    and remove, so the task's other sprints or releases stay as they are."""
    args.check_known(["dry-run", "verbose", "v"])
    var sub = "add" if adding else "remove"
    if len(args.positionals) < 4:
        raise Error("usage: eva " + group + " " + sub + " CODE TASK [TASK...]")
    # Resolve all targets before the first write.
    var ids = List[String]()
    for i in range(3, len(args.positionals)):
        ids.append(id_of(client, "CmfTask", "code", args.positionals[i]))
    var lid = r.doc.text_at(r.result, "id")
    var method = "CmfTask." + field + "." + ("append" if adding else "remove")
    var failures = 0
    for i in range(len(ids)):
        var task_code = args.positionals[i + 3]
        try:
            var before = get_by_code(client, "CmfTask", task_code, split_csv(field + ".id"))
            var call_args = "[" + quote_str(ids[i]) + "," + quote_str(lid) + "]"
            if has_id(before, field, lid) == adding:
                print(task_code + (" already in " if adding else " not in ") + code)
            elif not preview_write(args.has("dry-run"), method, "", call_args):
                _ = client.call(method, "", call_args)
                var got = get_by_code(client, "CmfTask", task_code, split_csv(field + ".id"))
                if has_id(got, field, lid) != adding:
                    raise Error(("membership" if adding else "removal") + " was not confirmed by readback")
                print(task_code + (" in " if adding else " removed from ") + code)
        except e:
            failures += 1
            print("failed " + task_code + ": " + String(e))
    if failures > 0:
        raise Error(String(failures) + " tasks failed; successful changes were kept")


def list_by_id(client: Client, id: String, fields: String) raises -> Reply:
    var d = JsonDoc()
    var kw = d.object()
    var f = d.parse(filter_eq("id", id))
    d.set(kw, "filter", f)
    var fl = d.str_array(split_csv(fields))
    d.set(kw, "fields", fl)
    var r = client.call("CmfList.get", d.dump(kw))
    if r.doc.text_at(r.result, "id") == "":
        raise Error(id + ": not found")
    return r^


def check_dates(start: String, end: String) raises:
    """Start no later than end; a date without a time stands for the whole day."""
    var s = date_key(start)
    var e = date_key(end)
    if s == "" or e == "":
        return
    if s.byte_length() == 10 or e.byte_length() == 10:
        var s_day = String(s[byte=0:10])
        var e_day = String(e[byte=0:10])
        s = s_day^
        e = e_day^
    if s > e:
        raise Error("--start " + start + " is after --end " + end)


def list_fields(args: Args, mut d: JsonDoc, kw: Int, stored_start: String, stored_end: String) raises:
    """--start, --end and --text into `kw`; `none` clears a date."""
    var options: List[String] = ["start", "end"]
    var fields: List[String] = ["plan_start_date", "plan_end_date"]
    var dates: List[String] = [stored_start, stored_end]
    for i in range(len(options)):
        var value = args.get(options[i])
        if value == "":
            continue
        if value == "none" or value == "off":
            var n = d.null()
            d.set(kw, fields[i], n)
            dates[i] = ""
        else:
            valid_datetime(value)
            d.set_str(kw, fields[i], value)
            dates[i] = value
    check_dates(dates[0], dates[1])
    var inline = args.get("text")
    if inline == "":
        inline = args.get("description", "d")
    var text = text_from(args, inline, "the description")
    if text != "":
        d.set_str(kw, "text", body_html(args, text))


def list_create(client: Client, args: Args, ui: Out, group: String) raises:
    args.check_known(
        [
            "dry-run",
            "project",
            "p",
            "start",
            "end",
            "text",
            "description",
            "d",
            "file",
            "F",
            "md",
            "html",
            "verbose",
            "v",
        ]
    )
    var project = args.get("project", "p")
    if project == "" or len(args.positionals) != 3:
        raise Error(
            "usage: eva "
            + group
            + " create -p PROJECT NAME [--start DATE] [--end DATE] [--text TEXT]; quote a NAME that has spaces"
        )
    var name = args.positionals[2]
    if name.strip() == "":
        raise Error("the " + group + " name is empty")
    var d = JsonDoc()
    var kw = d.object()
    d.set_str(kw, "name", name)
    list_fields(args, d, kw, "", "")
    # What readback checks: the server fills in the project and type itself.
    var wanted = d.dump(kw)
    d.set_str(kw, "parent", id_of(client, "CmfProject", "code", project))
    d.set_str(kw, "logic_type", id_of(client, "CmfLogicType", "code", list_kind(group)))
    if preview_write(args.has("dry-run"), "CmfList.create", d.dump(kw)):
        return
    var id: String
    try:
        var r = client.call("CmfList.create", d.dump(kw))
        id = r.doc.text(r.result)
    except e:
        var msg = String(e)
        if msg.find(MAYBE_APPLIED) >= 0:
            msg += "; eva " + group + " list -p " + project + " shows whether it was"
        raise Error(msg)
    try:
        var code = created_list(client, id, wanted, group)
        print("created " + ui.bold(code) + "  " + name)
    except e:
        raise Error(
            id
            + " was created, but "
            + String(e)
            + "; check eva "
            + group
            + " list -p "
            + project
            + " before creating it again"
        )


def created_list(client: Client, id: String, wanted: String, group: String) raises -> String:
    """The code of a list just created, after checking it reads back as asked."""
    var w = JsonDoc()
    var kw = w.parse(wanted)
    var fields = String("id,code,logic_type.code")
    for i in range(w.len(kw)):
        fields += "," + w.key_at(kw, i)
    var got = list_by_id(client, id, fields)
    var code = got.doc.text_at(got.result, "code")
    if code == "":
        code = id
    if got.doc.text_at(got.result, "logic_type.code") != list_kind(group):
        raise Error("it reads back as " + got.doc.text_at(got.result, "logic_type.code") + ", not a " + group)
    require_fields(w, kw, got.doc, got.result, code)
    return code


def list_update(client: Client, args: Args, ui: Out, r: Reply, group: String, code: String, rename: Bool) raises:
    args.check_known(
        [
            "dry-run",
            "name",
            "start",
            "end",
            "text",
            "description",
            "d",
            "file",
            "F",
            "md",
            "html",
            "verbose",
            "v",
        ]
    )
    var name = args.get("name")
    if rename:
        if len(args.positionals) != 4 or args.has("name"):
            raise Error("usage: eva " + group + " rename CODE NAME; quote a NAME that has spaces")
        name = args.positionals[3]
    elif len(args.positionals) > 3:
        raise Error(
            "usage: eva "
            + group
            + " update CODE [--name NAME] [--start DATE] [--end DATE] [--text TEXT]; quote a NAME that has spaces"
        )
    if (rename or args.has("name")) and name.strip() == "":
        raise Error("the " + group + " name is empty")
    var d = JsonDoc()
    var kw = d.object()
    if name != "":
        d.set_str(kw, "name", name)
    list_fields(
        args,
        d,
        kw,
        r.doc.text_at(r.result, "plan_start_date"),
        r.doc.text_at(r.result, "plan_end_date"),
    )
    if d.len(kw) == 0:
        raise Error("nothing to change: pass --name, --start, --end or --text")
    var changed = List[String]()
    for i in range(d.len(kw)):
        changed.append(d.key_at(kw, i))
    var id = r.doc.text_at(r.result, "id")
    var call_args = "[" + quote_str(id) + "]"
    if preview_write(args.has("dry-run"), "CmfList.update", d.dump(kw), call_args):
        return
    _ = client.call("CmfList.update", d.dump(kw), call_args)
    print("updated " + ui.bold(code) + ": " + ", ".join(changed))
    var got = list_by_id(client, id, "id," + ",".join(changed))
    require_fields(d, kw, got.doc, got.result, code)


def has_id(r: Reply, field: String, id: String) raises -> Bool:
    var values = r.doc.get(r.result, field)
    for i in range(r.doc.len(values)):
        if r.doc.text_at(r.doc.at(values, i), "id") == id:
            return True
    return False


def task_history(client: Client, args: Args, ui: Out) raises:
    args.check_known(["limit", "n", "page", "json", "format", "verbose", "v"])
    var code = args.need(2, "task code")
    _ = id_of(client, "CmfTask", "code", code)
    var f = filter_eq("obj_code", code)
    var r = page_rows(
        client,
        args,
        "CmfStatusHistory",
        f,
        "id,from_status_name,to_status_name,cmf_created_at,cmf_author.login,resolution.name,transition.name",
        "-cmf_created_at",
    )
    if want_json(args):
        print_json(r)
        return
    for i in range(r.doc.len(r.result)):
        var row = r.doc.at(r.result, i)
        var from_name = r.doc.text_at(row, "from_status_name")
        print(
            r.doc.text_at(row, "cmf_created_at")
            + "  "
            + r.doc.text_at(row, "cmf_author.login")
            + "  "
            + (from_name if from_name != "" else String("(created)"))
            + " → "
            + r.doc.text_at(row, "to_status_name")
        )
    page_footer(client, args, ui, "CmfStatusHistory", f, r.doc.len(r.result))


def task_time(client: Client, args: Args, ui: Out) raises:
    args.check_known(["all", "limit", "n", "page", "json", "format", "full", "verbose", "v"])
    var code = args.need(2, "task code")
    var id = id_of(client, "CmfTask", "code", code)
    var d = JsonDoc()
    var f = d.array()
    var v = d.string(id)
    var c = d.triple("parent_id", "==", v)
    d.push(f, c)
    if not args.has("all"):
        v = d.string("fact")
        c = d.triple("history_type", "==", v)
        d.push(f, c)
    var filter = d.dump(f)
    var r = page_rows(
        client,
        args,
        "CmfTimeTrackerHistory",
        filter,
        "id,code,start_date,end_date,time_spent,history_type,cmf_author.login,text",
        "start_date",
    )
    if want_json(args):
        print_json(r)
        return
    var actual = 0
    var planned = 0
    for i in range(r.doc.len(r.result)):
        var row = r.doc.at(r.result, i)
        var kind = r.doc.text_at(row, "history_type")
        var minutes = minutes_of(r.doc.text_at(row, "time_spent"))
        if kind == "fact":
            actual += minutes
        elif kind == "plan" or kind == "plan_oper":
            planned += minutes
        print(
            kind
            + "  "
            + r.doc.text_at(row, "start_date")
            + " – "
            + r.doc.text_at(row, "end_date")
            + "  "
            + fmt_minutes(minutes)
            + "  "
            + r.doc.text_at(row, "cmf_author.login")
        )
        ui.untrusted(
            code + "/time/" + r.doc.text_at(row, "code"),
            escape_text(r.doc.text_at(row, "text")).replace("\n", "<br>"),
        )
    if args.has("all"):
        print(
            "visible page total: "
            + fmt_minutes(actual)
            + " actual, "
            + fmt_minutes(planned)
            + " planned; only entries this account may read"
        )
    else:
        print(
            "visible page total: "
            + fmt_minutes(actual)
            + " actual; --all adds planned entries; only entries this account may read"
        )
    page_footer(client, args, ui, "CmfTimeTrackerHistory", filter, r.doc.len(r.result))


def task_dev(client: Client, args: Args, ui: Out) raises:
    args.check_known(["json", "format", "full", "verbose", "v"])
    var code = args.need(2, "task code")
    var r = get_by_code(
        client,
        "CmfTask",
        code,
        split_csv("git_repos.**,git_branches.**,git_commits.**,git_merge_requests.**"),
    )
    if want_json(args):
        print_json(r)
        return
    for field in [
        String("git_repos"),
        String("git_branches"),
        String("git_commits"),
        String("git_merge_requests"),
    ]:
        var values = r.doc.get(r.result, field)
        print(field + ": " + String(r.doc.len(values)) + " visible")
        for i in range(r.doc.len(values)):
            var row = r.doc.at(values, i)
            ui.untrusted(
                code + "/" + field + "/" + String(i + 1),
                "<pre>" + escape_text(r.doc.dump_pretty(row)) + "</pre>",
            )


def escape_text(text: String) -> String:
    return text.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


def notify_list(client: Client, args: Args, ui: Out) raises:
    args.check_known(["all", "limit", "n", "page", "json", "format", "verbose", "v"])
    var id = person_id(client, "me")
    var d = JsonDoc()
    var f = d.array()
    var v = d.string(id)
    var c = d.triple("person_id", "==", v)
    d.push(f, c)
    if not args.has("all"):
        var no = d.boolean(False)
        c = d.triple("confirmed", "==", no)
        d.push(f, c)
    var filter = d.dump(f)
    var r = page_rows(
        client,
        args,
        "CmfNotify",
        filter,
        "id,code,name,obj_code,obj_status_name,cmf_created_at,confirmed,unread_cnt",
        "-cmf_created_at",
    )
    if want_json(args):
        print_json(r)
        return
    for i in range(r.doc.len(r.result)):
        var row = r.doc.at(r.result, i)
        print(
            r.doc.text_at(row, "cmf_created_at")
            + "  "
            + r.doc.text_at(row, "obj_code")
            + "  "
            + r.doc.text_at(row, "obj_status_name")
        )
        ui.untrusted(
            "notify/" + r.doc.text_at(row, "code"),
            escape_text(r.doc.text_at(row, "name")),
        )
    page_footer(client, args, ui, "CmfNotify", filter, r.doc.len(r.result))


def search(client: Client, args: Args, ui: Out) raises:
    args.check_known(
        [
            "type",
            "t",
            "project",
            "p",
            "limit",
            "n",
            "page",
            "json",
            "format",
            "full",
            "verbose",
            "v",
        ]
    )
    var query = args.need(1, "search text")
    if query.strip() == "":
        raise Error("search text is empty")
    var kind = args.get("type", "t")
    if kind == "":
        kind = "all"
    if kind != "all" and kind != "task" and kind != "doc":
        raise Error("--type expects task, doc or all")
    var combined = JsonDoc()
    var result = combined.object()
    for group in [String("task"), String("doc")]:
        if kind != "all" and kind != group:
            continue
        var d = JsonDoc()
        var conds = d.array()
        var either = d.array()
        var op = d.string("OR")
        d.push(either, op)
        var value = d.string("%" + query + "%")
        for field in [String("name"), String("text")]:
            var c = d.triple(field, "ILIKE", value)
            d.push(either, c)
        d.push(conds, either)
        if args.get("project", "p") != "":
            var v = d.string(args.get("project", "p"))
            var c = d.triple("project.code", "==", v)
            d.push(conds, c)
        var filter = d.dump(conds)
        var cls = "CmfTask" if group == "task" else "CmfDocument"
        var r = page_rows(client, args, cls, filter, "id,code,name,text", "code")
        if want_json(args):
            var values = combined.parse(r.doc.dump(r.result))
            combined.set(result, group, values)
            continue
        print(group + " matches (name or text; --limit is per type):")
        for i in range(r.doc.len(r.result)):
            var row = r.doc.at(r.result, i)
            var code = r.doc.text_at(row, "code")
            print(code + "  " + r.doc.text_at(row, "name"))
            ui.untrusted(code + "/search", r.doc.text_at(row, "text"))
        page_footer(client, args, ui, cls, filter, r.doc.len(r.result))
    if want_json(args):
        print(combined.dump_pretty(result))


def repo_list(client: Client, args: Args, ui: Out) raises:
    args.check_known(["query", "q", "limit", "n", "page", "json", "format", "verbose", "v"])
    simple_list(
        client,
        args,
        ui,
        "CmfGitRepo",
        split_csv("code,name,url"),
        like_filter("name", args.get("query", "q"), ""),
        "code",
        split_csv("name,url"),
    )


def project_list(client: Client, args: Args, ui: Out) raises:
    args.check_known(["query", "q", "limit", "n", "page", "json", "format", "verbose", "v"])
    var f = like_filter("name", args.get("query", "q"), "")
    simple_list(
        client,
        args,
        ui,
        "CmfProject",
        [String("code"), String("name")],
        f,
        "code",
        [String("name")],
    )


def person_list(client: Client, args: Args, ui: Out) raises:
    args.check_known(["query", "q", "limit", "n", "page", "json", "format", "verbose", "v"])
    var f = like_filter("name", args.get("query", "q"), '["system", "==", false]')
    simple_list(
        client,
        args,
        ui,
        "CmfPerson",
        [String("login"), String("name"), String("email")],
        f,
        "login",
        [String("name"), String("email")],
    )
