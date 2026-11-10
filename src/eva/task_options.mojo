"""Typed shortcuts for task fields, validated before any write."""
from std.math import isfinite
from eva.args import Args
from eva.client import Client
from eva.json import JsonDoc, J_NUM
from eva.fields import resolve_set
from eva.dates import parse_day, parse_hm


def current_login(client: Client, login: String) raises -> String:
    if login != "me":
        return login
    var r = client.call("CmfPerson.get_current_user", '{"fields":["id","login"]}')
    var value = r.doc.text_at(r.result, "login")
    if value == "":
        raise Error("current user has no readable login")
    return value


def person_id(client: Client, login: String) raises -> String:
    if login == "" or login == "me":
        var current = client.call("CmfPerson.get_current_user", '{"fields":["id"]}')
        var id = current.doc.text_at(current.result, "id")
        if id == "":
            raise Error("current user has no readable id")
        return id
    var name = login
    var d = JsonDoc()
    var kw = d.object()
    var v = d.string(name)
    var f = d.triple("login", "==", v)
    d.set(kw, "filter", f)
    var fields = d.str_array([String("id")])
    d.set(kw, "fields", fields)
    var r = client.call("CmfPerson.get", d.dump(kw))
    var id = r.doc.text_at(r.result, "id")
    if id == "":
        raise Error("person " + name + ": not found")
    return id


def priority_caption(value: String) -> String:
    var codes: List[String] = ["-2", "-1", "0", "1", "2", "3"]
    var names: List[String] = [
        "Минимальный",
        "Низкий",
        "Обычный",
        "Высокий",
        "Критичный",
        "Блокирующий",
    ]
    for i in range(len(codes)):
        if value == codes[i]:
            return names[i]
    return value


def priority_value(value: String) raises -> Int:
    var aliases: List[String] = [
        "lowest",
        "low",
        "normal",
        "high",
        "critical",
        "blocker",
    ]
    var want = value.lower()
    for i in range(len(aliases)):
        var code = String(i - 2)
        if want == code or want == aliases[i] or want == priority_caption(code).lower():
            return i - 2
    raise Error("unknown priority " + value + "; use -2..3, lowest, low, normal, high, critical or blocker")


def valid_datetime(value: String) raises:
    var parts = value.split(" ")
    if len(parts) > 2 or String(parts[0]).byte_length() != 10:
        raise Error("invalid date/time: " + value + "; use YYYY-MM-DD [HH:MM]")
    _ = parse_day(String(parts[0]))
    if len(parts) == 2:
        if String(parts[1]).byte_length() != 5:
            raise Error("invalid time: " + value + "; use HH:MM")
        _ = parse_hm(String(parts[1]))


def task_options(client: Client, args: Args, mut d: JsonDoc, kw: Int) raises:
    var value = args.get("priority")
    if value != "":
        var n = d.number(priority_value(value))
        d.set(kw, "priority", n)
    value = args.get("story-points")
    if value != "":
        var n = d.parse(value)
        if d.kind(n) != J_NUM or not isfinite(Float64(value)) or Float64(value) < 0:
            raise Error("--story-points requires a non-negative finite number")
        d.set(kw, "agile_story_points", n)
    var options: List[String] = ["plan-start", "plan-end", "alarm"]
    var fields: List[String] = [
        "plan_start_date",
        "plan_end_date",
        "alarm_date",
    ]
    for i in range(len(options)):
        value = args.get(options[i])
        if value == "":
            continue
        if value == "off" or value == "none":
            var n = d.null()
            d.set(kw, fields[i], n)
        else:
            valid_datetime(value)
            d.set_str(kw, fields[i], value)
    var start = d.text_at(kw, "plan_start_date")
    var end = d.text_at(kw, "plan_end_date")
    if start != "" and end != "":
        # A date without a time stands for the whole day.
        if start.byte_length() == 10 or end.byte_length() == 10:
            var start_day = String(start[byte=0:10])
            var end_day = String(end[byte=0:10])
            start = start_day^
            end = end_day^
        if start > end:
            raise Error("--plan-start is after --plan-end")
    value = args.get("waiting-for")
    if value != "":
        if value == "none":
            var n = d.null()
            d.set(kw, "waiting_for", n)
        else:
            d.set_str(kw, "waiting_for", person_id(client, value))
    for option in [String("co-assignee"), String("tag")]:
        if not args.has(option):
            continue
        var values = d.array()
        var clear = False
        for i in range(len(args.keys)):
            if args.keys[i] == option:
                value = args.values[i]
                if value == "none":
                    clear = True
                else:
                    var n = d.string(person_id(client, value) if option == "co-assignee" else value)
                    d.push(values, n)
        if clear and d.len(values) > 0:
            raise Error("--" + option + " none cannot be mixed with values")
        d.set(kw, "executors" if option == "co-assignee" else "tags", values)
    resolve_set(client, d, kw)
