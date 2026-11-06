"""Dates, times and durations for the work log."""

from std.testing import assert_equal, assert_true, assert_raises, TestSuite

from eva.args import Args
from eva.timelog import (
    _iso_hm,
    date_text,
    day_name,
    epoch_of,
    fmt_minutes,
    local_time,
    log_kwargs,
    parse_day,
    parse_hm,
    stamp,
)


def test_fmt_minutes() raises:
    assert_equal(fmt_minutes(0), "0h00")
    assert_equal(fmt_minutes(1), "1m")
    assert_equal(fmt_minutes(45), "45m")
    assert_equal(fmt_minutes(60), "1h00")
    assert_equal(fmt_minutes(90), "1h30")
    assert_equal(fmt_minutes(2400), "40h00")
    assert_equal(fmt_minutes(-30), "-30m")


def test_parse_day() raises:
    var t = parse_day("2026-11-05")
    assert_equal(date_text(t), "2026-11-05")
    assert_equal(day_name(t.wday), "Thu")
    assert_equal(date_text(parse_day("2028-02-29")), "2028-02-29")
    with assert_raises(contains="no such date"):
        _ = parse_day("2026-02-30")
    with assert_raises(contains="expected a date"):
        _ = parse_day("05.11.2026")
    with assert_raises(contains="expected a date"):
        _ = parse_day("2026-1-5")


def test_today_and_yesterday_are_consecutive() raises:
    var today = parse_day("today")
    var yesterday = parse_day("Yesterday")
    var next = local_time(epoch_of(yesterday.year, yesterday.month, yesterday.day + 1, 12, 0))
    assert_equal(date_text(next), date_text(today))


def test_month_and_year_roll_over() raises:
    assert_equal(date_text(local_time(epoch_of(2026, 12, 32, 12, 0))), "2027-01-01")
    assert_equal(date_text(local_time(epoch_of(2026, 3, 0, 12, 0))), "2026-02-28")


def test_parse_hm() raises:
    var hm = parse_hm("09:05")
    assert_equal(hm[0], 9)
    assert_equal(hm[1], 5)
    with assert_raises(contains="no such time"):
        _ = parse_hm("24:00")
    with assert_raises(contains="expected a time"):
        _ = parse_hm("9h")


def test_stamp_round_trip() raises:
    assert_equal(stamp(epoch_of(2026, 11, 5, 14, 15)), "2026-11-05 14:15:00")
    # Ninety minutes back across midnight lands on the previous day.
    assert_equal(stamp(epoch_of(2026, 11, 5, 0, 30) - 90 * 60), "2026-11-04 23:00:00")


def test_iso_hm() raises:
    assert_equal(_iso_hm("2026-11-05T16:05:00+03:00"), "16:05")
    assert_equal(_iso_hm(""), "")


def test_log_kwargs() raises:
    assert_equal(
        log_kwargs(90, "2026-11-05 09:00:00", "отчёт", ""),
        '{"time_spent":90,"remaining_estimate":null,"text":"отчёт","date":"2026-11-05 09:00:00"}',
    )
    assert_true(log_kwargs(30, "2026-11-05 09:00:00", "", "2h").find('"remaining_estimate":120') >= 0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
