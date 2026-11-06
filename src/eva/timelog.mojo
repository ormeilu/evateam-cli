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
from eva.client import Client, Reply
from eva.commands import id_of, parse_minutes, print_json, quote_str, want_json
from eva.json import JsonDoc, clean
from eva.render import Out, clip, pad

comptime DAY_START = "09:00"
comptime DAY_NAMES = "Sun,Mon,Tue,Wed,Thu,Fri,Sat"


# ---- local time through libc ----


struct LocalTime(Copyable, Movable):
    var year: Int
    var month: Int
    var day: Int
    var hour: Int
    var minute: Int
    var wday: Int  # 0 is Sunday

    def __init__(out self):
        self.year = 0
        self.month = 0
        self.day = 0
        self.hour = 0
        self.minute = 0
        self.wday = 0


def now_epoch() -> Int:
    return Int(external_call["time", Int](Int(0)))


def local_time(epoch: Int) -> LocalTime:
    var t = unsafe_alloc[Int](1)
    t[unsafe_offset=0] = epoch
    # struct tm starts with nine ints on every platform eva builds for.
    var tm = unsafe_alloc[Int32](32)
    _ = external_call["localtime_r", Int](t, tm)
    var out = LocalTime()
    out.minute = Int(tm[unsafe_offset=1])
    out.hour = Int(tm[unsafe_offset=2])
    out.day = Int(tm[unsafe_offset=3])
    out.month = Int(tm[unsafe_offset=4]) + 1
    out.year = Int(tm[unsafe_offset=5]) + 1900
    out.wday = Int(tm[unsafe_offset=6])
    t.unsafe_free()
    tm.unsafe_free()
    return out^


def epoch_of(year: Int, month: Int, day: Int, hour: Int, minute: Int) -> Int:
    """Local wall time to seconds since the epoch; mktime normalises overflow
    (day 32 is the next month's first)."""
    var tm = unsafe_alloc[Int32](32)
    for i in range(32):
        tm[unsafe_offset=i] = 0
    tm[unsafe_offset=1] = Int32(minute)
    tm[unsafe_offset=2] = Int32(hour)
    tm[unsafe_offset=3] = Int32(day)
    tm[unsafe_offset=4] = Int32(month - 1)
    tm[unsafe_offset=5] = Int32(year - 1900)
    tm[unsafe_offset=8] = -1  # let mktime decide daylight saving
    var e = Int(external_call["mktime", Int](tm))
    tm.unsafe_free()
    return e


def two(n: Int) -> String:
    return ("0" if n < 10 else "") + String(n)


def date_text(t: LocalTime) -> String:
    return String(t.year) + "-" + two(t.month) + "-" + two(t.day)


def hm_text(t: LocalTime) -> String:
    return two(t.hour) + ":" + two(t.minute)


def stamp(epoch: Int) -> String:
    """`YYYY-MM-DD HH:MM:SS`, the form timetracker_change_time takes."""
    var t = local_time(epoch)
    return date_text(t) + " " + hm_text(t) + ":00"


def _digits(s: String) raises -> Int:
    if s.byte_length() == 0:
        raise Error("expected digits")
    var n = 0
    for b in s.as_bytes():
        var c = Int(b)
        if c < 0x30 or c > 0x39:
            raise Error("expected digits in " + s)
        n = n * 10 + (c - 0x30)
    return n


def parse_day(s: String) raises -> LocalTime:
    """today, yesterday, or YYYY-MM-DD; the time of day is noon."""
    var w = String(s.strip()).lower()
    var now = now_epoch()
    if w == "" or w == "today":
        return local_day(now)
    if w == "yesterday":
        var t = local_time(now)
        return local_time(epoch_of(t.year, t.month, t.day - 1, 12, 0))
    var parts = w.split("-")
    if len(parts) != 3 or w.byte_length() != 10:
        raise Error("expected a date like 2026-11-05, today or yesterday, got " + s)
    var y: Int
    var m: Int
    var d: Int
    try:
        y = _digits(String(parts[0]))
        m = _digits(String(parts[1]))
        d = _digits(String(parts[2]))
    except:
        raise Error("expected a date like 2026-11-05, got " + s)
    var t = local_time(epoch_of(y, m, d, 12, 0))
    if t.year != y or t.month != m or t.day != d:
        raise Error("no such date: " + s)
    return t^


def local_day(epoch: Int) -> LocalTime:
    var t = local_time(epoch)
    return local_time(epoch_of(t.year, t.month, t.day, 12, 0))


def parse_hm(s: String) raises -> Tuple[Int, Int]:
    var parts = s.strip().split(":")
    if len(parts) != 2:
        raise Error("expected a time like 09:30, got " + s)
    var h: Int
    var m: Int
    try:
        h = _digits(String(parts[0]))
        m = _digits(String(parts[1]))
    except:
        raise Error("expected a time like 09:30, got " + s)
    if h > 23 or m > 59:
        raise Error("no such time: " + s)
    return (h, m)


def fmt_minutes(n: Int) -> String:
    """90 → 1h30, 45 → 45m, 0 → 0h00."""
    var sign = "-" if n < 0 else ""
    var a = -n if n < 0 else n
    if a < 60 and a > 0:
        return sign + String(a) + "m"
    return sign + String(a // 60) + "h" + two(a % 60)


def day_name(wday: Int) -> String:
    return String(DAY_NAMES.split(",")[wday % 7])


def _iso_hm(iso: String) -> String:
    """`2026-11-05T16:05:00+03:00` → `16:05`."""
    if iso.byte_length() < 16:
        return ""
    return String(iso[byte=11:16])


# ---- people and calendars ----


def person_id(client: Client, login: String) raises -> String:
    if login != "":
        return id_of(client, "CmfPerson", "login", login)
    var r = client.call("CmfPerson.get_current_user", '{"fields":["id"]}')
    var id = r.doc.text_at(r.result, "id")
    if id == "":
        raise Error("cannot tell who is signed in")
    return id


struct DayNorm(Copyable, Movable):
    var date: String
    var kind: String  # work, weekend, holiday...; "" when the calendar has no day
    var minutes: Int

    def __init__(out self, date: String, kind: String, minutes: Int):
        self.date = date
        self.kind = kind
        self.minutes = minutes


def calendar_days(client: Client, person: String, first: String, last: String) raises -> List[DayNorm]:
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
    var qf = q.str_array([String("date"), String("day_type"), String("interval_total_minutes"), String("parent_id")])
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


def log_kwargs(minutes: Int, start: String, text: String, remaining: String) raises -> String:
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


def day_logs(client: Client, person: String, first: String, last: String) raises -> Reply:
    """Work log entries by `person` starting from first to last (dates), oldest first."""
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
        [String("code"), String("start_date"), String("end_date"), String("time_spent"), String("text"),
         String("parent.code"), String("parent.name")]
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
    var r = day_logs(client, person_id(client, ""), date_text(day), date_text(day))
    var last = String(DAY_START)
    for i in range(r.doc.len(r.result)):
        var end = _iso_hm(r.doc.text_at(r.doc.at(r.result, i), "end_date"))
        if end > last:
            last = end
    return date_text(day) + " " + last + ":00"


def task_log(client: Client, args: Args, ui: Out) raises:
    args.check_known(["message", "m", "remaining", "date", "at", "verbose", "v", "json", "format"])
    var code = args.need(2, "task code")
    var minutes = parse_minutes(args.need(3, "time spent, e.g. 90, 45m or 1h30m"))
    var id = id_of(client, "CmfTask", "code", code)
    var start = start_for(client, args, minutes)
    _ = client.call(
        "CmfTask.timetracker_change_time",
        log_kwargs(minutes, start, args.get("message", "m"), args.get("remaining")),
        "[" + quote_str(id) + "]",
    )
    print("logged " + fmt_minutes(minutes) + " on " + ui.bold(code) + " from " + String(start[byte=0:16]))


def time_list(client: Client, args: Args, ui: Out) raises:
    args.check_known(["from", "to", "week", "assignee", "a", "json", "format", "verbose", "v"])
    var today = local_day(now_epoch())
    var first: LocalTime
    var last: LocalTime
    if args.has("week") or (args.get("from") == "" and args.get("to") == ""):
        # Monday of this week through today.
        var back = (today.wday + 6) % 7
        first = local_time(epoch_of(today.year, today.month, today.day - back, 12, 0))
        last = today.copy()
    else:
        first = parse_day(args.get("from")) if args.get("from") != "" else today.copy()
        last = parse_day(args.get("to")) if args.get("to") != "" else today.copy()
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
                "  " + _iso_hm(d.text_at(e, "start_date")) + "–" + _iso_hm(d.text_at(e, "end_date")) + "  "
                + pad(fmt_minutes(m), 6) + " " + ui.accent(pad(d.text_at(e, "parent.code"), 11)) + " "
                + clip(clean(d.text_at(e, "text")), 60) + ui.dim("  " + d.text_at(e, "code"))
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
            head += (kind if kind != "" else "no working hours") + (", " + fmt_minutes(spent) + " logged" if spent > 0 else "")
        if norm > 0 or spent > 0:
            print(head)
            for l in lines:
                print(l)
        else:
            print(ui.dim(day_name(at.wday) + " " + date + "  " + (kind if kind != "" else "day off")))
        at = local_time(epoch_of(at.year, at.month, at.day + 1, 12, 0))
    var tail = "total " + fmt_minutes(total) + " of " + fmt_minutes(norm_total)
    if norm_total > total:
        tail += "; " + fmt_minutes(norm_total - total) + " left to log"
    print(ui.dim(tail))


def time_delete(client: Client, args: Args, ui: Out) raises:
    args.check_known(["verbose", "v"])
    var ref_ = args.need(2, "work log entry, e.g. TTH-1193314 (eva time list shows them)")
    var id = ref_
    if not ref_.startswith("CmfTimeTrackerHistory:"):
        if not ref_.upper().startswith("TTH-"):
            raise Error(ref_ + " is not a work log entry (TTH-…)")
        id = id_of(client, "CmfTimeTrackerHistory", "code", ref_.upper())
    _ = client.call("CmfTimeTrackerHistory.delete", "", "[" + quote_str(id) + "]")
    print("deleted " + ui.bold(ref_.upper() if ref_.upper().startswith("TTH-") else ref_) + "; the task's time spent goes down by its minutes")
