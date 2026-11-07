"""Time spent on tasks: log it, list the work log day by day against the
working-time calendar, and delete an entry.

EvaTeam keeps each entry as a CmfTimeTrackerHistory with a start, an end and
time_spent in minutes. The norm for a day comes from CmfCalendarDay: the
person's own calendar where it has the day, else the production calendar it
inherits from.
"""

from std.ffi import external_call, c_int
from std.memory.alloc import unsafe_alloc

from eva.args import Args
from eva.task_options import person_id
from eva.writes import preview_write
from eva.client import Client, Reply
from eva.common import id_of, print_json, quote_str, want_json
from eva.dates import (
    LocalTime,
    now_epoch,
    local_time,
    epoch_of,
    two,
    date_text,
    hm_text,
    stamp,
    parse_day,
    local_day,
    parse_hm,
    fmt_minutes,
    day_name,
    _iso_hm,
    parse_minutes,
)
from eva.json import JsonDoc, clean
from eva.render import Out, clip, pad

comptime DAY_START = "09:00"
comptime DAY_NAMES = "Sun,Mon,Tue,Wed,Thu,Fri,Sat"


# ---- local time through libc ----


# ---- people and calendars ----


struct DayNorm(Copyable, Movable):
    var date: String
    var kind: String  # work, weekend, holiday...; "" when the calendar has no day
    var minutes: Int

    def __init__(out self, date: String, kind: String, minutes: Int):
        self.date = date
        self.kind = kind
        self.minutes = minutes


def calendar_days(
    client: Client, person: String, first: String, last: String
) raises -> List[DayNorm]:
    """The days from first to last in this person's calendar; a day of their
    own calendar wins over the production calendar's."""
    var out = List[DayNorm]()
    var d = JsonDoc()
    var kw = d.object()
    var v = d.string(person)
    var f = d.triple("parent_id", "==", v)
    d.set(kw, "filter", f)
    var fl = d.str_array([String("id"), String("parent_calendar_id")])
    d.set(kw, "fields", fl)
    var cal = client.call("CmfCalendar.get", d.dump(kw))
    var own = cal.doc.text_at(cal.result, "id")
    var base = cal.doc.text_at(cal.result, "parent_calendar_id")
    if own == "" and base == "":
        return out^

    var q = JsonDoc()
    var qk = q.object()
    var flt = q.array()
    var cals = List[String]()
    cals.append(own)
    if base != "":
        cals.append(base)
    var ids = q.str_array(cals)
    var by_cal = q.triple("parent_id", "IN", ids)
    q.push(flt, by_cal)
    var lo = q.string(first)
    var from_ = q.triple("date", ">=", lo)
    q.push(flt, from_)
    var hi = q.string(last)
    var to = q.triple("date", "<=", hi)
    q.push(flt, to)
    q.set(qk, "filter", flt)
    var qf = q.str_array(
        [
            String("date"),
            String("day_type"),
            String("interval_total_minutes"),
            String("parent_id"),
        ]
    )
    q.set(qk, "fields", qf)
    var s = q.array()
    var a = q.number(0)
    var b = q.number(2000)
    q.push(s, a)
    q.push(s, b)
    q.set(qk, "slice", s)
    var r = client.call("CmfCalendarDay.list", q.dump(qk))
    for i in range(r.doc.len(r.result)):
        var x = r.doc.at(r.result, i)
        var date = r.doc.text_at(x, "date")
        var mins_text = r.doc.text_at(x, "interval_total_minutes")
        var mins = Int(mins_text) if mins_text != "" else 0
        var norm = DayNorm(date, r.doc.text_at(x, "day_type"), mins)
        var mine = r.doc.text_at(x, "parent_id") == own
        var at = -1
        for j in range(len(out)):
            if out[j].date == date:
                at = j
                break
        if at < 0:
            out.append(norm^)
        elif mine:
            out[at] = norm^
    return out^


# ---- commands ----


def log_kwargs(
    minutes: Int, start: String, text: String, remaining: String
) raises -> String:
    var d = JsonDoc()
    var kw = d.object()
    var ts = d.number(minutes)
    d.set(kw, "time_spent", ts)
    # The server requires remaining_estimate; null leaves the estimate alone.
    var rv = d.number(parse_minutes(remaining)) if remaining != "" else d.null()
    d.set(kw, "remaining_estimate", rv)
    if text != "":
        d.set_str(kw, "text", text)
    # `date` is where the entry starts; it ends time_spent later.
    d.set_str(kw, "date", start)
    return d.dump(kw)


def day_logs(
    client: Client, person: String, first: String, last: String
) raises -> Reply:
    """Work log entries by `person` starting from first to last (dates), oldest first.
    """
    var d = JsonDoc()
    var kw = d.object()
    var flt = d.array()
    var p = d.string(person)
    var by = d.triple("cmf_author_id", "==", p)
    d.push(flt, by)
    var lo = d.string(first + " 00:00:00")
    var from_ = d.triple("start_date", ">=", lo)
    d.push(flt, from_)
    var hi = d.string(last + " 23:59:59")
    var to = d.triple("start_date", "<=", hi)
    d.push(flt, to)
    d.set(kw, "filter", flt)
    var fl = d.str_array(
        [
            String("code"),
            String("start_date"),
            String("end_date"),
            String("time_spent"),
            String("text"),
            String("parent.code"),
            String("parent.name"),
        ]
    )
    d.set(kw, "fields", fl)
    var order = d.str_array([String("start_date")])
    d.set(kw, "order_by", order)
    var s = d.array()
    var a = d.number(0)
    var b = d.number(5000)
    d.push(s, a)
    d.push(s, b)
    d.set(kw, "slice", s)
    return client.call("CmfTimeTrackerHistory.list", d.dump(kw))


def start_for(client: Client, args: Args, minutes: Int) raises -> String:
    """Where a new entry starts: --at on --date (or today); after the last
    entry of --date, or at DAY_START; without either, so that it ends now."""
    var at = args.get("at")
    var day_arg = args.get("date")
    if at == "" and day_arg == "":
        return stamp(now_epoch() - minutes * 60)
    var day = parse_day(day_arg)
    if at != "":
        var hm = parse_hm(at)
        return date_text(day) + " " + two(hm[0]) + ":" + two(hm[1]) + ":00"
    var r = day_logs(
        client, person_id(client, ""), date_text(day), date_text(day)
    )
    var last = String(DAY_START)
    for i in range(r.doc.len(r.result)):
        var end = _iso_hm(r.doc.text_at(r.doc.at(r.result, i), "end_date"))
        if end > last:
            last = end
    return date_text(day) + " " + last + ":00"


def task_log(client: Client, args: Args, ui: Out) raises:
    args.check_known(
        [
            "dry-run",
            "message",
            "m",
            "remaining",
            "date",
            "at",
            "verbose",
            "v",
            "json",
            "format",
        ]
    )
    var code = args.need(2, "task code")
    var minutes = parse_minutes(
        args.need(3, "time spent, e.g. 90, 45m or 1h30m")
    )
    var id = id_of(client, "CmfTask", "code", code)
    var start = start_for(client, args, minutes)
    if preview_write(
        args.has("dry-run"),
        "CmfTask.timetracker_change_time",
        log_kwargs(
            minutes, start, args.get("message", "m"), args.get("remaining")
        ),
        "[" + quote_str(id) + "]",
    ):
        return
    _ = client.call(
        "CmfTask.timetracker_change_time",
        log_kwargs(
            minutes, start, args.get("message", "m"), args.get("remaining")
        ),
        "[" + quote_str(id) + "]",
    )
    print(
        "logged "
        + fmt_minutes(minutes)
        + " on "
        + ui.bold(code)
        + " from "
        + String(start[byte=0:16])
    )


def time_list(client: Client, args: Args, ui: Out) raises:
    args.check_known(
        [
            "from",
            "to",
            "week",
            "assignee",
            "a",
            "json",
            "format",
            "verbose",
            "v",
        ]
    )
    var today = local_day(now_epoch())
    var first: LocalTime
    var last: LocalTime
    if args.has("week") or (args.get("from") == "" and args.get("to") == ""):
        # Monday of this week through today.
        var back = (today.wday + 6) % 7
        first = local_time(
            epoch_of(today.year, today.month, today.day - back, 12, 0)
        )
        last = today.copy()
    else:
        first = (
            parse_day(args.get("from")) if args.get("from")
            != "" else today.copy()
        )
        last = (
            parse_day(args.get("to")) if args.get("to") != "" else today.copy()
        )
    var lo = date_text(first)
    var hi = date_text(last)
    if lo > hi:
        raise Error("--from " + lo + " is after --to " + hi)
    var who = person_id(client, args.get("assignee", "a"))
    var logs = day_logs(client, who, lo, hi)
    if want_json(args):
        print_json(logs)
        return
    var days = calendar_days(client, who, lo, hi)
    ref d = logs.doc
    var n = d.len(logs.result)
    var total = 0
    var norm_total = 0
    var at = first.copy()
    var guard = 0
    while date_text(at) <= hi and guard < 400:
        guard += 1
        var date = date_text(at)
        var spent = 0
        var lines = List[String]()
        for i in range(n):
            var e = d.at(logs.result, i)
            if not d.text_at(e, "start_date").startswith(date):
                continue
            var m_text = d.text_at(e, "time_spent")
            var m = Int(m_text) if m_text != "" else 0
            spent += m
            lines.append(
                "  "
                + _iso_hm(d.text_at(e, "start_date"))
                + "–"
                + _iso_hm(d.text_at(e, "end_date"))
                + "  "
                + pad(fmt_minutes(m), 6)
                + " "
                + ui.accent(pad(d.text_at(e, "parent.code"), 11))
                + " "
                + clip(clean(d.text_at(e, "text")), 60)
                + ui.dim("  " + d.text_at(e, "code"))
            )
        var kind = String("")
        var norm = 0
        for x in days:
            if x.date == date:
                kind = x.kind
                norm = x.minutes
        total += spent
        norm_total += norm
        var head = ui.bold(day_name(at.wday) + " " + date) + "  "
        if norm > 0:
            head += fmt_minutes(spent) + " of " + fmt_minutes(norm)
            if spent < norm:
                head += ui.dim("  " + fmt_minutes(norm - spent) + " left")
            elif spent > norm:
                head += ui.dim("  " + fmt_minutes(spent - norm) + " over")
        else:
            head += (kind if kind != "" else "no working hours") + (
                ", " + fmt_minutes(spent) + " logged" if spent > 0 else ""
            )
        if norm > 0 or spent > 0:
            print(head)
            for l in lines:
                print(l)
        else:
            print(
                ui.dim(
                    day_name(at.wday)
                    + " "
                    + date
                    + "  "
                    + (kind if kind != "" else "day off")
                )
            )
        at = local_time(epoch_of(at.year, at.month, at.day + 1, 12, 0))
    var tail = "total " + fmt_minutes(total) + " of " + fmt_minutes(norm_total)
    if norm_total > total:
        tail += "; " + fmt_minutes(norm_total - total) + " left to log"
    print(ui.dim(tail))


def time_delete(client: Client, args: Args, ui: Out) raises:
    args.check_known(["verbose", "v"])
    var ref_ = args.need(
        2, "work log entry, e.g. TTH-1193314 (eva time list shows them)"
    )
    var id = ref_
    if not ref_.startswith("CmfTimeTrackerHistory:"):
        if not ref_.upper().startswith("TTH-"):
            raise Error(ref_ + " is not a work log entry (TTH-…)")
        id = id_of(client, "CmfTimeTrackerHistory", "code", ref_.upper())
    _ = client.call(
        "CmfTimeTrackerHistory.delete", "", "[" + quote_str(id) + "]"
    )
    print(
        "deleted "
        + ui.bold(ref_.upper() if ref_.upper().startswith("TTH-") else ref_)
        + "; the task's time spent goes down by its minutes"
    )
