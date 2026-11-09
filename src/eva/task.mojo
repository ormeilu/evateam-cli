"""Task cards, selection, creation and updates."""
from eva.args import Args
from eva.writes import preview_write
from eva.client import Client, Reply
from eva.json import JsonDoc, J_OBJ
from eva.render import Out, pad, clip
from eva.common import (
    split_csv,
    fields_from,
    get_by_code,
    id_of,
    text_from,
    body_html,
    print_json,
    want_json,
    person,
    page_slice,
    footer,
    quote_str,
)
from eva.workflow import find_resolution, move_task, refuse_noop_move
from eva.fields import MultiSelect, multiselect_fields, resolve_set, value_names
from eva.filters import task_filter_text
from eva.validation import require_fields
from eva.projection import project_json, column_text, tsv_cell
from eva.task_options import (
    task_options,
    current_login,
    priority_caption,
    person_id,
)
from eva.term import prompt_line, stdin_is_tty


comptime TASK_FIELDS = (
    "*,status.name,status.code,resolution.code,resolution.name,responsible.name,responsible.login,"
    "cmf_author.name,cmf_author.login,parent.code,parent.name,"
    "parent_task.code,parent_task.name,child_tasks.code,child_tasks.name,"
    "child_tasks.status.name,child_tasks.cache_status_type,child_tasks.responsible.login,"
    "attachments.code,attachments.file_name,priority,agile_story_points,plan_start_date,plan_end_date,alarm_date,"
    "op_gantt_task.sched_start_date,op_gantt_task.sched_finish_date,"
    "spectators.login,spectators.name,executors.login,executors.name,waiting_for.login,waiting_for.name,"
    "tags.name,components.name,fix_versions.code,fix_versions.name,lists.code,lists.name,"
    "checklists_items_count,checklists_items_done_count"
)

# Subtask rows shown through a pipe before `(+N more: --full)`.

comptime PIPE_SUBTASKS = 20

comptime LIST_FIELDS = (
    "code,name,cache_status_type,status.name,responsible.login,"
    "responsible.name,cmf_created_at"
)


def task_by_id(client: Client, id: String, fields: String) raises -> Reply:
    var d = JsonDoc()
    var kw = d.object()
    var v = d.string(id)
    var f = d.triple("id", "==", v)
    d.set(kw, "filter", f)
    var fl = d.str_array(split_csv(fields))
    d.set(kw, "fields", fl)
    return client.call("CmfTask.get", d.dump(kw))


def find_logic_type(client: Client, want: String) raises -> String:
    """A task type's id by name ("Подзадача", "Bug"), code ("task.sub:default")
    or short code ("sub"), any case."""
    var r = client.call(
        "CmfLogicType.list", '{"fields":["id","code","name"],"slice":[0,5000]}'
    )
    var w = String(want.strip()).lower()
    var names = List[String]()
    for i in range(r.doc.len(r.result)):
        var x = r.doc.at(r.result, i)
        var code = r.doc.text_at(x, "code").lower()
        if not code.startswith("task."):
            continue
        if (
            code == w
            or r.doc.text_at(x, "name").lower() == w
            or code == "task." + w + ":default"
        ):
            return r.doc.text_at(x, "id")
        names.append(r.doc.text_at(x, "name"))
    raise Error("no task type " + want + "; types: " + ", ".join(names))


# What the server may change on its own when a task is updated, with the
# fields that count as asking for it.

comptime WATCHED = "parent_task.code,epic.code,logic_type.name,responsible.login,status.name,waiting_for.login"


def watched_by(field: String) -> List[String]:
    var base = String(field.split(".")[0])
    return [base, base + "_id"]


def task_get(client: Client, args: Args, ui: Out) raises:
    args.check_known(["fields", "json", "format", "full", "verbose", "v"])
    var code = args.need(2, "task code, e.g. eva task get DEV-12")
    var fields = fields_from(args, TASK_FIELDS)
    # Multi-select custom fields come back only by name; ask for each.
    var multi = List[MultiSelect]()
    if args.get("fields") == "":
        multi = multiselect_fields(client)
        for m in multi:
            fields.append(m.name + ".name")
    var r = get_by_code(client, "CmfTask", code, fields)
    if want_json(args):
        if args.get("fields") != "":
            print(project_json(r.doc, r.result, fields))
        else:
            print_json(r)
        return
    ref d = r.doc
    var t = r.result
    if args.get("fields") != "":
        # Only what was asked for: the server adds ids, and a dotted path
        # comes back nested. A multi-select prints as its value names.
        for f in split_csv(args.get("fields")):
            print(
                f
                + ": "
                + (
                    value_names(d, d.path(t, f)) if f.find(".")
                    < 0 else column_text(d, t, f)
                )
            )
        return
    print(
        ui.bold(d.text_at(t, "code"))
        + "  "
        + String(d.text_at(t, "name").strip())
    )
    var status = d.text_at(t, "status.name")
    if status == "":
        status = d.text_at(t, "cache_status_type")
    var status_line = (
        "status: "
        + ui.status(status)
        + "   stage: "
        + d.text_at(t, "cache_status_type")
    )
    var resolution = d.text_at(t, "resolution.code")
    if resolution != "":
        status_line += (
            "   resolution: "
            + resolution
            + " ("
            + d.text_at(t, "resolution.name")
            + ")"
        )
    print(status_line)
    print(
        "assignee: "
        + person(d, t, "responsible")
        + "   author: "
        + person(d, t, "cmf_author")
    )
    var priority = d.text_at(t, "priority")
    if priority != "" or d.text_at(t, "agile_story_points") != "":
        print(
            "priority: "
            + priority_caption(priority)
            + " ("
            + priority
            + ")   story points: "
            + d.text_at(t, "agile_story_points")
        )
    for field in [
        String("spectators"),
        String("executors"),
        String("tags"),
        String("components"),
        String("lists"),
        String("fix_versions"),
    ]:
        var values = value_names(d, d.get(t, field))
        if field == "spectators" or field == "executors":
            var logins = column_text(d, t, field + ".login")
            if String(logins.strip()) != "":
                values = logins
        if values != "":
            var label = field
            if field == "spectators":
                label = "watchers"
            elif field == "executors":
                label = "co-assignees"
            elif field == "fix_versions":
                label = "release"
            print(label + ": " + values)
    if (
        d.text_at(t, "waiting_for.login") != ""
        or d.text_at(t, "waiting_for.name") != ""
    ):
        print("waiting for: " + person(d, t, "waiting_for"))
    if (
        d.text_at(t, "plan_start_date") != ""
        or d.text_at(t, "plan_end_date") != ""
    ):
        print(
            "planned: "
            + d.text_at(t, "plan_start_date")
            + " → "
            + d.text_at(t, "plan_end_date")
        )
    # The Gantt chart schedules its own copy of the task: writing the planned
    # dates does not move it, and its dates follow the working calendar.
    if (
        d.text_at(t, "op_gantt_task.sched_start_date") != ""
        or d.text_at(t, "op_gantt_task.sched_finish_date") != ""
    ):
        print(
            "gantt schedule: "
            + d.text_at(t, "op_gantt_task.sched_start_date")
            + " → "
            + d.text_at(t, "op_gantt_task.sched_finish_date")
            + "  (separate from planned dates)"
        )
    if d.text_at(t, "alarm_date") != "":
        print("alarm: " + d.text_at(t, "alarm_date"))
    if (
        d.text_at(t, "checklists_items_count") != ""
        and d.text_at(t, "checklists_items_count") != "0"
    ):
        print(
            "checklists: "
            + d.text_at(t, "checklists_items_done_count")
            + " of "
            + d.text_at(t, "checklists_items_count")
            + " items done; eva task checklist "
            + code
        )
    var project = d.text_at(t, "parent.code")
    if project != "":
        print("project: " + project + "  " + d.text_at(t, "parent.name"))
    var parent_task = d.text_at(t, "parent_task.code")
    if parent_task != "":
        print(
            "parent task: "
            + parent_task
            + "  "
            + String(d.text_at(t, "parent_task.name").strip())
        )
    print(
        ui.dim(
            "created: "
            + d.text_at(t, "cmf_created_at")
            + "   updated: "
            + d.text_at(t, "cmf_modified_at")
        )
    )
    var deadline = d.text_at(t, "deadline")
    if deadline != "":
        print("deadline: " + deadline)
    for m in multi:
        var values = value_names(d, d.get(t, m.name))
        if values != "":
            print(m.caption + ": " + values)
    var files = d.get(t, "attachments")
    var nfiles = d.len(files)
    if nfiles > 0:
        var names = List[String]()
        for i in range(min(nfiles, 5)):
            names.append(d.text_at(d.at(files, i), "file_name"))
        var more = ", +" + String(
            nfiles - 5
        ) + " more" if nfiles > 5 else String("")
        print(
            "attachments: "
            + String(nfiles)
            + " ("
            + ", ".join(names)
            + more
            + "): eva task attachments "
            + code
        )
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
        var v = d.string(current_login(client, assignee))
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
    for option in [
        String("author"),
        String("watching"),
        String("waiting-for"),
        String("tag"),
        String("component"),
    ]:
        var value = args.get(option)
        if value == "":
            continue
        var field = "components.name" if option == "component" else String(
            "tags.name"
        )
        if option == "author":
            field = "cmf_author.login"
        elif option == "watching":
            field = "spectators.login"
        elif option == "waiting-for":
            field = "waiting_for.login"
        var v = d.string(
            value if option == "tag"
            or option == "component" else current_login(client, value)
        )
        c = d.triple(field, "==", v)
        d.push(conds, c)
    if args.has("archived"):
        var v = d.boolean(True)
        c = d.triple("cmf_archived", "==", v)
        d.push(conds, c)
    var raw = args.get("filter")
    if raw != "":
        c = d.parse(task_filter_text(client, raw))
        d.push(conds, c)
    return conds


def task_list(client: Client, args: Args, ui: Out) raises:
    args.check_known(
        [
            "project",
            "p",
            "assignee",
            "a",
            "status",
            "s",
            "query",
            "q",
            "filter",
            "author",
            "watching",
            "waiting-for",
            "archived",
            "tag",
            "component",
            "limit",
            "n",
            "page",
            "fields",
            "cols",
            "order",
            "json",
            "format",
            "full",
            "verbose",
            "v",
        ]
    )
    var d = JsonDoc()
    var kw = d.object()
    var flt = task_filter(client, d, args)
    d.set(kw, "filter", flt)
    var count_kw = d.dump(kw)
    var cols = args.get("cols")
    var format = args.get("format")
    if (
        format != ""
        and format != "text"
        and format != "json"
        and format != "tsv"
    ):
        raise Error("--format expects text, json or tsv")
    if args.has("json") and format != "" and format != "json":
        raise Error("--json conflicts with --format " + format)
    if format == "tsv" and cols == "":
        cols = "code,status.name,responsible.login,name"
    var requested = split_csv(cols) if cols != "" else fields_from(
        args, LIST_FIELDS
    )
    var fl = d.str_array(requested)
    d.set(kw, "fields", fl)
    var order = args.get("order")
    var ob = d.str_array([order if order != "" else String("-cmf_created_at")])
    d.set(kw, "order_by", ob)
    var sl = page_slice(d, args)
    d.set(kw, "slice", sl)

    var r = client.call("CmfTask.list", d.dump(kw))
    if want_json(args):
        if cols != "" or args.get("fields") != "":
            print(project_json(r.doc, r.result, requested))
        else:
            print_json(r)
        return
    if cols != "":
        for i in range(r.doc.len(r.result)):
            var cells = List[String]()
            for col in requested:
                cells.append(
                    tsv_cell(column_text(r.doc, r.doc.at(r.result, i), col))
                )
            print("	".join(cells))
        return
    ref rd = r.doc
    var n = rd.len(r.result)
    var hidden = 0
    for i in range(n):
        var t = rd.at(r.result, i)
        if rd.text_at(t, "code") == "":
            # A task in a project this user cannot read: only its id and stage come back.
            hidden += 1
            continue
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
    var total = -1
    try:
        var c = client.call("CmfTask.count", count_kw)
        total = Int(c.doc.text(c.result))
    except:
        pass
    footer(ui, n, total, args)
    if hidden > 0:
        print(
            ui.dim(
                String(hidden) + " of them hidden: no access to their projects"
            )
        )


def task_create(client: Client, args: Args, ui: Out) raises:
    args.check_known(
        [
            "dry-run",
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
            "sprint",
            "parent",
            "type",
            "set",
            "json",
            "format",
            "verbose",
            "v",
            "priority",
            "story-points",
            "plan-start",
            "plan-end",
            "alarm",
            "co-assignee",
            "waiting-for",
            "tag",
        ]
    )
    var project = args.get("project", "p")
    var name = args.get("title", "t")
    if name == "":
        name = args.get("name")
    if project == "" or name == "":
        raise Error(
            "usage: eva task create -p PROJECT -t TITLE [-d TEXT | -F FILE]"
            " [--md|--html] [-a LOGIN] [--sprint SPR-1] [--parent CODE] [--type"
            " TYPE] [--set JSON]"
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
        d.set_str(ref_obj, "id", person_id(client, assignee))
        d.set(kw, "responsible", ref_obj)
    var sprint = args.get("sprint")
    if sprint != "":
        var lists = d.str_array([sprint])
        d.set(kw, "lists", lists)
    # Reference fields go by their own names with an id as the value: EvaTeam
    # refuses the *_id forms in a create.
    var parent = args.get("parent")
    var parent_id = String()
    if parent != "":
        var p = get_by_code(
            client, "CmfTask", parent, split_csv("id,epic_id,logic_type.code")
        )
        parent_id = p.doc.text_at(p.result, "id")
        # A subtask belongs to its parent's epic, or to the parent if that is the epic.
        var epic = parent_id if p.doc.text_at(
            p.result, "logic_type.code"
        ).startswith("task.epic") else p.doc.text_at(p.result, "epic_id")
        # The epic becomes the parent task even when a parent_task is sent
        # with it, so the parent task is set by an update after the create.
        if epic != "":
            d.set_str(kw, "epic", epic)
    var kind = args.get("type")
    if kind != "":
        d.set_str(kw, "logic_type", find_logic_type(client, kind))
    var raw = args.get("set")
    if raw != "":
        var extra = d.parse(raw)
        if d.kind(extra) != J_OBJ:
            raise Error("--set expects a JSON object")
        resolve_set(client, d, extra)
        for i in range(d.len(extra)):
            d.set(kw, d.key_at(extra, i), d.at(extra, i))
    task_options(client, args, d, kw)
    if preview_write(args.has("dry-run"), "CmfTask.create", d.dump(kw)):
        if parent_id != "":
            print(
                "parent-task update may follow creation/readback; requested"
                " parent_task: "
                + parent_id
            )
        return
    var r = client.call("CmfTask.create", d.dump(kw))
    var id = r.doc.text(r.result)
    var code = id
    var got_parent = String()
    try:
        var t = task_by_id(client, id, "code,parent_task_id")
        var c = t.doc.text_at(t.result, "code")
        if c != "":
            code = c
        got_parent = t.doc.text_at(t.result, "parent_task_id")
    except:
        pass
    print("created " + ui.bold(code) + "  " + name)
    if parent_id != "" and got_parent != parent_id:
        var u = JsonDoc()
        var uk = u.object()
        u.set_str(uk, "parent_task", parent_id)
        try:
            _ = client.call(
                "CmfTask.update", u.dump(uk), "[" + quote_str(id) + "]"
            )
        except e:
            raise Error(
                code
                + " is created, but setting "
                + parent
                + " as its parent task failed: "
                + String(e)
            )
        var t = task_by_id(client, id, "parent_task_id")
        if t.doc.text_at(t.result, "parent_task_id") != parent_id:
            print(
                "note: EvaTeam did not keep "
                + parent
                + " as the parent task; check eva task get "
                + code
            )


def task_delete(client: Client, args: Args, ui: Out) raises:
    args.check_known(["yes", "y", "verbose", "v"])
    var code = args.need(2, "task code")
    var t = get_by_code(
        client,
        "CmfTask",
        code,
        split_csv("id,code,name,cache_child_tasks_count"),
    )
    var id = t.doc.text_at(t.result, "id")
    var name = String(t.doc.text_at(t.result, "name").strip())
    var children = t.doc.text_at(t.result, "cache_child_tasks_count")
    var what = code + "  " + name
    if children != "" and children != "0":
        what += " (it has " + children + " subtasks)"
    if not args.has("yes", "y"):
        if not stdin_is_tty():
            raise Error(
                "deleting "
                + what
                + " needs confirmation: run it in a terminal, or pass --yes"
            )
        var answer = prompt_line("delete " + what + "? [y/N] ").lower()
        if (
            answer != "y"
            and answer != "yes"
            and answer != "д"
            and answer != "да"
        ):
            print("not deleted")
            return
    _ = client.call("CmfTask.delete", "", "[" + quote_str(id) + "]")
    print("deleted " + ui.bold(code) + "  " + name)


def build_update(
    client: Client, args: Args, mut d: JsonDoc, kw: Int
) raises -> List[String]:
    var name = args.get("title", "t")
    if name == "":
        name = args.get("name")
    if name != "":
        d.set_str(kw, "name", name)
    var desc = text_from(args, args.get("description", "d"), "the description")
    if desc != "":
        d.set_str(kw, "text", body_html(args, desc))
    # Status changes go through a workflow transition, after the other fields.
    var status = args.get("status", "s")
    var assignee = args.get("assignee", "a")
    if assignee != "":
        var ref_obj = d.object()
        d.set_str(ref_obj, "id", person_id(client, assignee))
        d.set(kw, "responsible", ref_obj)
    # With -s the resolution goes with the move: a transition into a closed
    # status would set its own default over one set here.
    var resolution = args.get("resolution", "r")
    if resolution != "" and status == "":
        d.set_str(kw, "resolution", find_resolution(client, resolution).id)
    var raw = args.get("set")
    if raw != "":
        # --set '{"deadline": "2026-12-01"}' merges raw fields.
        var extra = d.parse(raw)
        if d.kind(extra) != J_OBJ:
            raise Error("--set expects a JSON object")
        resolve_set(client, d, extra)
        for i in range(d.len(extra)):
            d.set(kw, d.key_at(extra, i), d.at(extra, i))
    task_options(client, args, d, kw)
    var changed = List[String]()
    for i in range(d.len(kw)):
        changed.append(d.key_at(kw, i))
    return changed^


def report_derived_changes(
    before: Reply, after: Reply, changed: List[String]
) raises:
    for w in split_csv(WATCHED):
        var asked = False
        for key in watched_by(w):
            for c in changed:
                if c == key:
                    asked = True
        var was = before.doc.text_at(before.result, w)
        var now = after.doc.text_at(after.result, w)
        if not asked and was != now:
            var label = String(w.split(".")[0]).replace("_", " ")
            print(
                "note: EvaTeam also changed "
                + label
                + ": "
                + (was if was != "" else "-")
                + " → "
                + (now if now != "" else "-")
            )


def task_update(client: Client, args: Args, ui: Out) raises:
    args.check_known(
        [
            "dry-run",
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
            "status",
            "s",
            "resolution",
            "r",
            "comment",
            "m",
            "set",
            "json",
            "format",
            "verbose",
            "v",
            "priority",
            "story-points",
            "plan-start",
            "plan-end",
            "alarm",
            "co-assignee",
            "waiting-for",
            "tag",
        ]
    )
    var code = args.need(2, "task code")
    var d = JsonDoc()
    var kw = d.object()
    var changed = build_update(client, args, d, kw)
    var status = args.get("status", "s")
    if len(changed) == 0 and status == "":
        raise Error(
            "nothing to change: pass -t, -d or -F, -s, -a, --resolution or"
            " --set"
        )
    var comment = args.get("comment", "m")
    if comment != "" and status == "":
        raise Error(
            "-m is the comment of a status change and needs -s; for a comment"
            " alone use eva task comment"
        )
    # Refuse before any field is written, not after.
    if status != "" and (comment != "" or args.get("resolution", "r") != ""):
        refuse_noop_move(client, code, status)
    if args.has("dry-run"):
        if len(changed) > 0:
            var id = id_of(client, "CmfTask", "code", code)
            _ = preview_write(
                True, "CmfTask.update", d.dump(kw), "[" + quote_str(id) + "]"
            )
        if status != "":
            move_task(
                client,
                code,
                status,
                args.get("comment", "m"),
                "",
                args.get("resolution", "r"),
                ui,
                False,
                True,
            )
        return
    if len(changed) > 0:
        var before = get_by_code(
            client, "CmfTask", code, split_csv("id," + WATCHED)
        )
        var id = before.doc.text_at(before.result, "id")
        var args_json = "[" + quote_str(id) + "]"
        _ = client.call("CmfTask.update", d.dump(kw), args_json)
        print("updated " + ui.bold(code) + ": " + ", ".join(changed))
        # The server derives some fields from others (an epic moves the parent
        # task to it); say so when one changed that was not asked for.
        var after = task_by_id(client, id, WATCHED + "," + ",".join(changed))
        require_fields(d, kw, after.doc, after.result, code)
        report_derived_changes(before, after, changed)
    if status != "":
        # --set already went into the update above.
        move_task(
            client,
            code,
            status,
            args.get("comment", "m"),
            "",
            args.get("resolution", "r"),
            ui,
        )


# ---- workflow transitions ----


def task_links(client: Client, args: Args, ui: Out) raises:
    args.check_known(["verbose", "v", "json", "format"])
    var code = args.need(2, "task code")
    var r = get_by_code(
        client,
        "CmfTask",
        code,
        [
            String("out_tasks.**"),
            String("in_tasks.**"),
            String("out_tasks.relation_type.code"),
            String("in_tasks.relation_type.code"),
        ],
    )
    if want_json(args):
        print_json(r)
        return
    # EvaTeam stores `eva task link A B` as out_link=A, in_link=B and lists it
    # in A's in_tasks and B's out_tasks. Each line names the other task.
    var n = 0
    var outgoing = r.doc.get(r.result, "in_tasks")
    for i in range(r.doc.len(outgoing)):
        var l = r.doc.at(outgoing, i)
        print(
            "→ "
            + ui.accent(r.doc.text_at(l, "in_link.code"))
            + "  "
            + r.doc.text_at(l, "in_link.name")
            + "  "
            + r.doc.text_at(l, "relation_type.code")
        )
        n += 1
    var incoming = r.doc.get(r.result, "out_tasks")
    for i in range(r.doc.len(incoming)):
        var l = r.doc.at(incoming, i)
        print(
            "← "
            + ui.accent(r.doc.text_at(l, "out_link.code"))
            + "  "
            + r.doc.text_at(l, "out_link.name")
            + "  "
            + r.doc.text_at(l, "relation_type.code")
        )
        n += 1
    print(ui.dim(String(n) + " links (→ outgoing, ← incoming)"))


# ---- projects, people, documents ----
