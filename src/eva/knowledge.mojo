"""Wiki navigation, project assignments, EvaTest and ServiceDesk reads.

Keep the distinctions the server exposes: opaque revision IDs, direct role
assignments rather than effective membership, and raw SLA duration units.
"""
from eva.args import Args
from eva.filters import validate_bql
from eva.client import Client
from eva.common import (
    get_by_code,
    id_of,
    split_csv,
    print_json,
    want_json,
    simple_list,
    like_filter,
)
from eva.resources import filter_eq, page_rows, page_footer, escape_text
from eva.json import JsonDoc
from eva.render import Out


def doc_children(client: Client, args: Args, ui: Out) raises:
    args.check_known(
        ["depth", "limit", "n", "page", "json", "format", "verbose", "v"]
    )
    var code = args.need(2, "document code")
    var depth = args.int_or("depth", "", 1)
    if depth < 1 or depth > 10:
        raise Error("--depth must be between 1 and 10")
    var id = id_of(client, "CmfDocument", "code", code)
    if want_json(args):
        var d = JsonDoc()
        var tree = child_nodes(client, args, id, depth, d, List[String]())
        print(d.dump_pretty(tree))
    else:
        print(
            "document-only children; mixed folder/object nodes are not included"
        )
        print_children(client, args, ui, id, depth, "", List[String]())


def child_nodes(
    client: Client,
    args: Args,
    id: String,
    depth: Int,
    mut d: JsonDoc,
    visited: List[String],
) raises -> Int:
    for seen in visited:
        if seen == id:
            raise Error("document tree contains a cycle at " + id)
    var next = visited.copy()
    next.append(id)
    var f = filter_eq("tree_parent_id", id)
    var rows = page_rows(client, args, "CmfDocument", f, "id,code,name", "code")
    var tree = d.object()
    var children = d.array()
    for i in range(rows.doc.len(rows.result)):
        var row = rows.doc.at(rows.result, i)
        var n = d.parse(rows.doc.dump(row))
        if depth > 1:
            var sub = child_nodes(
                client, args, rows.doc.text_at(row, "id"), depth - 1, d, next
            )
            d.set(n, "children_page", sub)
        d.push(children, n)
    d.set(tree, "nodes", children)
    var count = client.call("CmfDocument.count", '{"filter":' + f + "}")
    var total = d.parse(count.doc.dump(count.result))
    d.set(tree, "total_visible_documents", total)
    return tree


def print_children(
    client: Client,
    args: Args,
    ui: Out,
    id: String,
    depth: Int,
    indent: String,
    visited: List[String],
) raises:
    for seen in visited:
        if seen == id:
            raise Error("document tree contains a cycle at " + id)
    var next = visited.copy()
    next.append(id)
    var f = filter_eq("tree_parent_id", id)
    var rows = page_rows(client, args, "CmfDocument", f, "id,code,name", "code")
    for i in range(rows.doc.len(rows.result)):
        var row = rows.doc.at(rows.result, i)
        print(
            indent
            + rows.doc.text_at(row, "code")
            + "  "
            + rows.doc.text_at(row, "name")
        )
        if depth > 1:
            print_children(
                client,
                args,
                ui,
                rows.doc.text_at(row, "id"),
                depth - 1,
                indent + "  ",
                next,
            )
    print(indent + "children of " + id + ":")
    page_footer(client, args, ui, "CmfDocument", f, rows.doc.len(rows.result))


def doc_history(client: Client, args: Args, ui: Out) raises:
    args.check_known(["limit", "n", "page", "json", "format", "verbose", "v"])
    var id = id_of(client, "CmfDocument", "code", args.need(2, "document code"))
    var f = filter_eq("parent_id", id)
    var r = page_rows(
        client,
        args,
        "CmfDocumentHistory",
        f,
        "id,doc_version,approved_version,reason,cmf_created_at",
        "-doc_version",
    )
    if want_json(args):
        print_json(r)
        return
    for i in range(r.doc.len(r.result)):
        var row = r.doc.at(r.result, i)
        print(
            r.doc.text_at(row, "doc_version")
            + "  "
            + r.doc.text_at(row, "cmf_created_at")
            + "  "
            + r.doc.text_at(row, "id")
        )
        if r.doc.text_at(row, "reason") != "":
            ui.untrusted("revision/reason", r.doc.text_at(row, "reason"))
    print(
        "--version takes the exact opaque doc_version string, not an ordinal"
        " number"
    )
    page_footer(client, args, ui, "CmfDocumentHistory", f, r.doc.len(r.result))


def doc_version(client: Client, args: Args, ui: Out) raises:
    args.check_known(["version", "json", "format", "full", "verbose", "v"])
    var code = args.need(2, "document code")
    var id = id_of(client, "CmfDocument", "code", code)
    var version = args.get("version")
    var kw = (
        '{"filter":['
        + filter_eq("parent_id", id)
        + ","
        + filter_eq("doc_version", version)
        + '],"fields":["id","doc_version","text"],"slice":[0,2]}'
    )
    var r = client.call("CmfDocumentHistory.list", kw)
    if r.doc.len(r.result) != 1:
        raise Error(
            code
            + ": revision "
            + version
            + " not found or not unique; see doc history"
        )
    var row = r.doc.at(r.result, 0)
    if want_json(args):
        print(r.doc.dump_pretty(row))
        return
    print(code + "  version " + version)
    ui.untrusted(code + "/version/" + version, r.doc.text_at(row, "text"))


def project_get(client: Client, args: Args, ui: Out) raises:
    args.check_known(["limit", "n", "page", "json", "format", "verbose", "v"])
    var code = args.need(2, "project code")
    var project = get_by_code(
        client,
        "CmfProject",
        code,
        split_csv("id,code,name,cache_status_type,cmf_owner.login"),
    )
    var f = filter_eq("parent.code", code)
    var roles = page_rows(
        client,
        args,
        "CmfProjectRoleAssign",
        f,
        "id,project_role.name,members.id,members.class_name,members.login,members.name",
        "id",
    )
    if want_json(args):
        var d = JsonDoc()
        var result = d.object()
        var p = d.parse(project.doc.dump(project.result))
        var r = d.parse(roles.doc.dump(roles.result))
        d.set(result, "project", p)
        d.set(result, "direct_role_assignments", r)
        print(d.dump_pretty(result))
        return
    print(
        code
        + "  "
        + project.doc.text_at(project.result, "name")
        + "  "
        + project.doc.text_at(project.result, "cache_status_type")
    )
    print("owner: " + project.doc.text_at(project.result, "cmf_owner.login"))
    print(
        "direct role assignments; groups, defaults and inherited permissions"
        " are not expanded:"
    )
    for i in range(roles.doc.len(roles.result)):
        var row = roles.doc.at(roles.result, i)
        print("  " + roles.doc.text_at(row, "project_role.name"))
        var members = roles.doc.get(row, "members")
        for j in range(roles.doc.len(members)):
            var member = roles.doc.at(members, j)
            print(
                "    "
                + roles.doc.text_at(member, "class_name")
                + "  "
                + roles.doc.text_at(member, "login")
                + "  "
                + roles.doc.text_at(member, "name")
            )
    page_footer(
        client, args, ui, "CmfProjectRoleAssign", f, roles.doc.len(roles.result)
    )
    print("project lists (sprints, releases and other kinds):")
    simple_list(
        client,
        args,
        ui,
        "CmfList",
        split_csv("code,name,logic_type.code,cache_status_type"),
        filter_eq("project.code", code),
        "code",
        split_csv("name,logic_type.code,cache_status_type"),
    )


def test_command(client: Client, args: Args, ui: Out) raises:
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
            "full",
            "verbose",
            "v",
        ]
    )
    var cls = "CmfTestcase" if args.pos(0) == "testcase" else "CmfTestplan"
    var sub = args.pos(1)
    if sub == "list" or sub == "":
        var base = filter_eq(
            "project.code", args.get("project", "p")
        ) if args.get("project", "p") != "" else String("")
        simple_list(
            client,
            args,
            ui,
            cls,
            split_csv("code,name,cache_status_type"),
            like_filter("name", args.get("query", "q"), base),
            "code",
            split_csv("name,cache_status_type"),
        )
        return
    if sub != "get":
        raise Error("unknown " + args.pos(0) + " command " + sub)
    var code = args.need(2, "testcase or testplan code")
    var r = get_by_code(
        client,
        cls,
        code,
        split_csv(
            "id,code,name,text,cache_status_type,cmf_ver_number,cmf_ver_cur,deffects.code,type,environment.name,release.code"
        ),
    )
    var id = r.doc.text_at(r.result, "id")
    var is_case = cls == "CmfTestcase"
    var child_cls = "CmfTestcaseStep" if is_case else "CmfTestplanTestcase"
    var fields = (
        "id,step_number,step_section,text,expected_result,test_data" if is_case else "id,testcase_id,testcase.code,testcase.name,testplan_testcase_folder_id"
    )
    var f = filter_eq("parent_id", id)
    var children = page_rows(
        client, args, child_cls, f, fields, "step_number" if is_case else "id"
    )
    if want_json(args):
        var d = JsonDoc()
        var obj = d.parse(r.doc.dump(r.result))
        var c = d.parse(children.doc.dump(children.result))
        d.set(obj, "steps_page" if is_case else "testcases_page", c)
        print(d.dump_pretty(obj))
        return
    print(
        code
        + "  "
        + r.doc.text_at(r.result, "name")
        + "  "
        + r.doc.text_at(r.result, "cache_status_type")
    )
    if is_case:
        print("version: " + r.doc.text_at(r.result, "cmf_ver_number"))
    ui.untrusted(code + "/text", r.doc.text_at(r.result, "text"))
    for i in range(children.doc.len(children.result)):
        var row = children.doc.at(children.result, i)
        if is_case:
            print(
                children.doc.text_at(row, "step_number")
                + "  "
                + children.doc.text_at(row, "step_section")
            )
            ui.untrusted(code + "/step", children.doc.text_at(row, "text"))
            print("Expected result:")
            ui.untrusted(
                code + "/expected", children.doc.text_at(row, "expected_result")
            )
        else:
            print(
                children.doc.text_at(row, "testcase.code")
                + "  "
                + children.doc.text_at(row, "testcase.name")
            )
    page_footer(
        client, args, ui, child_cls, f, children.doc.len(children.result)
    )


def ticket_get(client: Client, args: Args, ui: Out) raises:
    args.check_known(
        ["limit", "n", "page", "json", "format", "full", "verbose", "v"]
    )
    if args.pos(1) != "get":
        raise Error("usage: eva ticket get CODE")
    var code = args.need(2, "ticket code")
    var r = get_by_code(
        client,
        "CmfTask",
        code,
        split_csv(
            "id,code,name,project_id,project.id,project.code,project.name,company.name"
        ),
    )
    var id = r.doc.text_at(r.result, "id")
    var f = filter_eq("parent_id", id)
    var sla = page_rows(
        client,
        args,
        "CmfSDeskSlaCycle",
        f,
        "id,code,sla_id,sla_goal_id,current,elapsed_time,remaining_time,breached,paused,start_time,breach_time",
        "id",
    )
    var d = JsonDoc()
    var result = d.object()
    var t = d.parse(r.doc.dump(r.result))
    var cycles = d.parse(sla.doc.dump(sla.result))
    d.set(result, "ticket", t)
    d.set(result, "sla_cycles", cycles)
    d.set_str(
        result, "sla_duration_units", "server-native; not converted to hours"
    )
    var queues = d.array()
    var queue_status = String(
        "visible project queue definitions on this page; matches are query"
        " membership, not a unique assignment"
    )
    try:
        var project = r.doc.text_at(r.result, "project_id")
        if project == "":
            project = r.doc.text_at(r.result, "project.id")
        if project == "" and r.doc.text_at(r.result, "project.code") != "":
            project = id_of(
                client,
                "CmfProject",
                "code",
                r.doc.text_at(r.result, "project.code"),
            )
        if project == "":
            raise Error("project id is not readable")
        var definitions = page_rows(
            client,
            args,
            "CmfTaskQueue",
            filter_eq("project_id", project),
            "id,code,name,bql_filter.bql",
            "id",
        )
        for i in range(definitions.doc.len(definitions.result)):
            var row = definitions.doc.at(definitions.result, i)
            var item = d.object()
            d.set_str(item, "code", definitions.doc.text_at(row, "code"))
            d.set_str(item, "name", definitions.doc.text_at(row, "name"))
            try:
                var bql = definitions.doc.text_at(row, "bql_filter.bql")
                if bql == "" or bql.byte_length() > 262144:
                    raise Error(
                        "missing/oversized computed JSON BQL; legacy"
                        " Python/UBQL is not executed"
                    )
                var query = d.parse(bql)
                validate_bql(d, query)
                var filter = d.array()
                var and_ = d.string("AND")
                d.push(filter, and_)
                d.push(filter, query)
                var value = d.string(id)
                var by_task = d.triple("id", "==", value)
                d.push(filter, by_task)
                var count = client.call(
                    "CmfTask.count", '{"filter":' + d.dump(filter) + "}"
                )
                var matches = d.boolean(Int(count.doc.text(count.result)) > 0)
                d.set(item, "matches", matches)
            except e:
                var unknown = d.null()
                d.set(item, "matches", unknown)
                d.set_str(item, "unavailable", String(e))
            d.push(queues, item)
    except e:
        queue_status = "unavailable: " + String(e)
    d.set(result, "queues_page", queues)
    d.set_str(result, "queue_membership", queue_status)
    if want_json(args):
        print(d.dump_pretty(result))
        return
    print(code + "  " + r.doc.text_at(r.result, "name"))
    print("project: " + r.doc.text_at(r.result, "project.code"))
    var company = r.doc.text_at(r.result, "company.name")
    print(
        "company/client: "
        + (company if company != "" else String("not exposed to this account"))
    )
    print("queue membership: " + queue_status)
    for i in range(d.len(queues)):
        var row = d.at(queues, i)
        var matched = d.text_at(row, "matches")
        print(
            "  "
            + d.text_at(row, "code")
            + "  "
            + d.text_at(row, "name")
            + "  "
            + (
                matched if matched
                != "" else String("unknown: ") + d.text_at(row, "unavailable")
            )
        )
    for i in range(sla.doc.len(sla.result)):
        var row = sla.doc.at(sla.result, i)
        ui.untrusted(
            code + "/sla",
            "<pre>" + escape_text(sla.doc.dump_pretty(row)) + "</pre>",
        )
    print(
        "SLA durations are server-native values; no hours or freshness"
        " guarantee is inferred"
    )
    page_footer(
        client, args, ui, "CmfSDeskSlaCycle", f, sla.doc.len(sla.result)
    )
