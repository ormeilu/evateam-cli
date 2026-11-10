"""Shared local dates, times and durations."""
from std.ffi import external_call
from std.memory.alloc import unsafe_alloc

comptime DAY_NAMES = "Sun,Mon,Tue,Wed,Thu,Fri,Sat"


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


def minutes_of(text: String) raises -> Int:
    """A work-log time_spent in minutes; a null reads as 0."""
    if text == "":
        return 0
    try:
        return Int(text)
    except:
        return Int(Float64(text))


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


def local_now() -> String:
    return stamp(now_epoch())
