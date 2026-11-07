"""Visible work-log totals, grouped locally by project and start-date day."""
from eva.args import Args
from eva.client import Client
from eva.dates import parse_day, date_text, fmt_minutes, minutes_of
from eva.task_options import person_id
from eva.selection import collect_rows
from eva.json import JsonDoc
from eva.render import Out


@fieldwise_init
struct TimeGroup(Copyable, Movable):
    var project: String
    var date: String
    var actual: Int
    var planned: Int
    var other: Int


def time_report(client: Client, args: Args, ui: Out) raises:
    args.check_known(
        [
            "from",
            "to",
            "project",
            "p",
            "assignee",
            "a",
            "json",
            "format",
            "verbose",
            "v",
        ]
    )
    if args.get("from") == "" or args.get("to") == "":
        raise Error("time report requires --from DATE and --to DATE")
    var first = date_text(parse_day(args.get("from")))
    var last = date_text(parse_day(args.get("to")))
    if first > last:
        raise Error("--from is after --to")
    var d = JsonDoc()
    var filter = d.array()
    var v = d.string(first + " 00:00:00")
    var c = d.triple("start_date", ">=", v)
    d.push(filter, c)
    v = d.string(last + " 23:59:59")
    c = d.triple("start_date", "<=", v)
    d.push(filter, c)
    var login = args.get("assignee", "a")
    v = d.string(person_id(client, login if login != "" else String("me")))
    c = d.triple("cmf_author_id", "==", v)
    d.push(filter, c)
    if args.get("project", "p") != "":
        v = d.string(args.get("project", "p"))
        c = d.triple("project.code", "==", v)
        d.push(filter, c)
    var rows = collect_rows(
        client,
        "CmfTimeTrackerHistory",
        d.dump(filter),
        "project.code,start_date,time_spent,history_type",
        10000,
        "start_date",
    )
    var groups = List[TimeGroup]()
    var indices = Dict[String, Int]()
    var actual = 0
    var planned = 0
    var other = 0
    for i in range(rows.doc.len(rows.result)):
        var row = rows.doc.at(rows.result, i)
        var start_date = rows.doc.text_at(row, "start_date")
        if start_date.byte_length() < 10:
            raise Error("work-log row has no readable start date")
        var date = String(start_date[byte=0:10])
        var project = rows.doc.text_at(row, "project.code")
        if project == "":
            project = "(hidden project)"
        var key = project + "\t" + date
        if key not in indices:
            indices[key] = len(groups)
            groups.append(TimeGroup(project, date, 0, 0, 0))
        var index = indices[key]
        var minutes = minutes_of(rows.doc.text_at(row, "time_spent"))
        var kind = rows.doc.text_at(row, "history_type")
        if kind == "fact":
            groups[index].actual += minutes
            actual += minutes
        elif kind == "plan" or kind == "plan_oper":
            groups[index].planned += minutes
            planned += minutes
        else:
            groups[index].other += minutes
            other += minutes
    var result = d.object()
    var items = d.array()
    for group in groups:
        var row = d.object()
        d.set_str(row, "project", group.project)
        d.set_str(row, "date", group.date)
        var a = d.number(group.actual)
        var p = d.number(group.planned)
        var o = d.number(group.other)
        d.set(row, "actual_minutes", a)
        d.set(row, "planned_minutes", p)
        d.set(row, "other_minutes", o)
        d.push(items, row)
    d.set(result, "groups", items)
    var a = d.number(actual)
    var p = d.number(planned)
    var o = d.number(other)
    d.set(result, "actual_minutes", a)
    d.set(result, "planned_minutes", p)
    d.set(result, "other_minutes", o)
    d.set_str(
        result,
        "scope",
        (
            "visible rows for the selected person, grouped by entry start-date;"
            " permissions may hide other rows"
        ),
    )
    if args.has("json") or args.get("format") == "json":
        print(d.dump_pretty(result))
        return
    for group in groups:
        print(
            group.project
            + "  "
            + group.date
            + "  "
            + fmt_minutes(group.actual)
            + " actual  "
            + fmt_minutes(group.planned)
            + " planned  "
            + fmt_minutes(group.other)
            + " other/draft"
        )
    print(
        "visible total: "
        + fmt_minutes(actual)
        + " actual, "
        + fmt_minutes(planned)
        + " planned, "
        + fmt_minutes(other)
        + " other/draft"
    )
    print(
        "only rows this account may read; entries are assigned to their"
        " start-date, not split across midnight"
    )
