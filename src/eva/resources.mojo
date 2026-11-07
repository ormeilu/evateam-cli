"""Read-only feeds and task list membership (sprints and releases)."""
from eva.args import Args
from eva.client import Client, Reply
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
)
from eva.json import JsonDoc, J_OBJ
from eva.render import Out
from eva.task_options import person_id
from eva.dates import fmt_minutes


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


def page_footer(
    client: Client, args: Args, ui: Out, cls: String, filter: String, shown: Int
) raises:
    var c = client.call(cls + ".count", '{"filter":' + filter + "}")
    footer(ui, shown, Int(c.doc.text(c.result)), args)


def list_kind(group: String) -> String:
    return (
        "list.agile_sprint:default" if group
        == "sprint" else "list.release:default"
    )


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
            c = d.triple(
                "cache_status_type", "==" if status == "closed" else "!=", v
            )
            d.push(filter, c)
        simple_list(
            client,
            args,
            ui,
            "CmfList",
            split_csv(
                "code,name,project.code,cache_status_type,cache_members_count"
            ),
            d.dump(filter),
            "code",
            split_csv(
                "name,project.code,cache_status_type,cache_members_count"
            ),
        )
        return
    var code = args.need(2, group + " code")
    var r = get_by_code(
        client,
        "CmfList",
        code,
        split_csv(
            "id,code,name,logic_type.code,cache_status_type,cache_members_count,plan_start_date,plan_end_date"
        ),
    )
    if r.doc.text_at(r.result, "logic_type.code") != list_kind(group):
        raise Error(code + " is not a " + group)
    if sub == "get":
        args.check_known(
            ["limit", "n", "page", "json", "format", "verbose", "v"]
        )
        if want_json(args):
            print_json(r)
            return
        print(
            code
            + "  "
            + r.doc.text_at(r.result, "name")
            + "  "
            + r.doc.text_at(r.result, "cache_status_type")
        )
        print(
            "dates: "
            + r.doc.text_at(r.result, "plan_start_date")
            + " → "
            + r.doc.text_at(r.result, "plan_end_date")
        )
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
    elif sub == "add":
        args.check_known(["verbose", "v"])
        if len(args.positionals) < 4:
            raise Error("usage: eva " + group + " add CODE TASK [TASK...]")
        # Resolve all targets before the first write.
        var ids = List[String]()
        for i in range(3, len(args.positionals)):
            ids.append(id_of(client, "CmfTask", "code", args.positionals[i]))
        var failures = 0
        for i in range(len(ids)):
            var task_code = args.positionals[i + 3]
            try:
                var before = get_by_code(
                    client, "CmfTask", task_code, split_csv(field + ".id")
                )
                var lid = r.doc.text_at(r.result, "id")
                if not has_id(before, field, lid):
                    _ = client.call(
                        "CmfTask." + field + ".append",
                        "",
                        "[" + quote_str(ids[i]) + "," + quote_str(lid) + "]",
                    )
                    var got = get_by_code(
                        client, "CmfTask", task_code, split_csv(field + ".id")
                    )
                    if not has_id(got, field, lid):
                        raise Error("membership was not confirmed by readback")
                print(task_code + " in " + code)
            except e:
                failures += 1
                print("failed " + task_code + ": " + String(e))
        if failures > 0:
            raise Error(
                String(failures) + " tasks failed; successful changes were kept"
            )
    else:
        raise Error("unknown " + group + " command " + sub)


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
    args.check_known(
        ["all", "limit", "n", "page", "json", "format", "full", "verbose", "v"]
    )
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
        var minutes = Int(r.doc.text_at(row, "time_spent"))
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
    print(
        "visible page total: "
        + fmt_minutes(actual)
        + " actual, "
        + fmt_minutes(planned)
        + " planned; only entries this account may read"
    )
    page_footer(
        client, args, ui, "CmfTimeTrackerHistory", filter, r.doc.len(r.result)
    )


def task_dev(client: Client, args: Args, ui: Out) raises:
    args.check_known(["json", "format", "full", "verbose", "v"])
    var code = args.need(2, "task code")
    var r = get_by_code(
        client,
        "CmfTask",
        code,
        split_csv(
            "git_repos.**,git_branches.**,git_commits.**,git_merge_requests.**"
        ),
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
    args.check_known(
        ["all", "limit", "n", "page", "json", "format", "verbose", "v"]
    )
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
        var r = page_rows(
            client, args, cls, filter, "id,code,name,text", "code"
        )
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
    args.check_known(
        ["query", "q", "limit", "n", "page", "json", "format", "verbose", "v"]
    )
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
    args.check_known(
        ["query", "q", "limit", "n", "page", "json", "format", "verbose", "v"]
    )
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
    args.check_known(
        ["query", "q", "limit", "n", "page", "json", "format", "verbose", "v"]
    )
    var f = like_filter(
        "name", args.get("query", "q"), '["system", "==", false]'
    )
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
