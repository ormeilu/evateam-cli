"""Shared lookups, input and paginated output; no command dependencies."""
from eva.args import Args
from eva.client import Client, Reply
from eva.json import JsonDoc, NO_NODE, J_ARR, J_OBJ
from eva.render import Out, pad, clip, text_to_html, markdown_to_html
from eva.term import read_all


def split_csv(raw: String) -> List[String]:
    var out = List[String]()
    for f in raw.split(","):
        var s = String(f.strip())
        if s != "":
            out.append(s)
    return out^


def fields_from(args: Args, default: String) -> List[String]:
    var raw = args.get("fields")
    return split_csv(raw if raw != "" else default)


# ---- shared helpers ----


def code_kwargs(code: String, fields: List[String]) raises -> String:
    var d = JsonDoc()
    var kw = d.object()
    var v = d.string(code)
    var f = d.triple("code", "==", v)
    d.set(kw, "filter", f)
    if len(fields) > 0:
        var fl = d.str_array(fields)
        d.set(kw, "fields", fl)
    return d.dump(kw)


def get_by_code(
    client: Client, cls: String, code: String, fields: List[String]
) raises -> Reply:
    var r = client.call(cls + ".get", code_kwargs(code, fields))
    if r.doc.is_null(r.result) or r.doc.kind(r.result) != J_OBJ:
        raise Error(code + ": not found")
    return r^


def id_of(
    client: Client, cls: String, field: String, value: String
) raises -> String:
    var d = JsonDoc()
    var kw = d.object()
    var v = d.string(value)
    var f = d.triple(field, "==", v)
    d.set(kw, "filter", f)
    var fl = d.str_array([String("id")])
    d.set(kw, "fields", fl)
    var r = client.call(cls + ".get", d.dump(kw))
    var id = r.doc.text_at(r.result, "id")
    if id == "":
        raise Error(cls + " with " + field + " " + value + ": not found")
    return id


def text_from(args: Args, inline: String, what: String) raises -> String:
    """`inline`, or the text of the file -F names (`-` reads stdin)."""
    var path = args.get("file", "F")
    if path == "":
        return inline
    if inline != "":
        raise Error("give " + what + " as an argument or with -F, not both")
    var text: String
    if path == "-":
        text = read_all()
    else:
        try:
            with open(path, "r") as f:
                text = f.read()
        except e:
            raise Error("cannot read " + path + ": " + String(e))
    if text.strip() == "":
        raise Error(
            what + " in " + ("stdin" if path == "-" else path) + " is empty"
        )
    return String(text.rstrip())


def body_html(args: Args, text: String) raises -> String:
    """Text as EvaTeam stores it: plain by default, --md converted, --html as is.
    """
    var md = args.has("md")
    var html = args.has("html")
    if md and html:
        raise Error("--md and --html exclude each other")
    if html:
        return text
    if md:
        return markdown_to_html(text)
    return text_to_html(text)


def print_json(r: Reply):
    print(r.doc.dump_pretty(r.result))


def want_json(args: Args) -> Bool:
    return args.has("json") or args.get("format") == "json"


def person(doc: JsonDoc, n: Int, field: String) raises -> String:
    var login = doc.text_at(n, field + ".login")
    if login != "":
        return login
    var name = doc.text_at(n, field + ".name")
    return name if name != "" else "-"


def page_slice(mut d: JsonDoc, args: Args) raises -> Int:
    var limit = args.int_or("limit", "n", 25)
    var page = args.int_or("page", "", 1)
    if limit < 1 or page < 1:
        raise Error("--limit and --page start at 1")
    var s = d.array()
    var a = d.number((page - 1) * limit)
    var b = d.number(page * limit)
    d.push(s, a)
    d.push(s, b)
    return s


def footer(ui: Out, shown: Int, total: Int, args: Args) raises:
    var limit = args.int_or("limit", "n", 25)
    var page = args.int_or("page", "", 1)
    var first = (page - 1) * limit
    var line = (
        "shown "
        + String(shown)
        + (" of " + String(total) if total >= 0 else " (total unavailable)")
    )
    if first + shown < total or (total < 0 and shown == limit):
        line += " — next: --page " + String(page + 1)
    print(ui.dim(line))


# ---- task ----


def quote_str(s: String) -> String:
    var d = JsonDoc()
    return d.dump(d.string(s))


def simple_list(
    client: Client,
    args: Args,
    ui: Out,
    cls: String,
    var fields: List[String],
    filter_json: String,
    key: String,
    cols: List[String],
) raises:
    var d = JsonDoc()
    var kw = d.object()
    if filter_json != "":
        var f = d.parse(filter_json)
        d.set(kw, "filter", f)
    var count_kw = d.dump(kw)
    var fl = d.str_array(fields)
    d.set(kw, "fields", fl)
    var sl = page_slice(d, args)
    d.set(kw, "slice", sl)
    var r = client.call(cls + ".list", d.dump(kw))
    if want_json(args):
        print_json(r)
        return
    var n = r.doc.len(r.result)
    for i in range(n):
        var row = r.doc.at(r.result, i)
        var line = ui.accent(pad(r.doc.text_at(row, key), 14))
        for c in cols:
            line += "  " + clip(r.doc.text_at(row, c), 60)
        print(line)
    var total = -1
    try:
        var c = client.call(cls + ".count", count_kw)
        total = Int(c.doc.text(c.result))
    except:
        pass
    footer(ui, n, total, args)


def like_filter(field: String, q: String, base: String) -> String:
    var d = JsonDoc()
    var conds = d.array()
    if base != "":
        try:
            var b = d.parse(base)
            d.push(conds, b)
        except:
            pass
    if q != "":
        var v = d.string("%" + q + "%")
        var c = d.triple(field, "ILIKE", v)
        d.push(conds, c)
    if d.len(conds) == 0:
        return ""
    if d.len(conds) == 1:
        return d.dump(d.at(conds, 0))
    return d.dump(conds)
