"""Multi-select custom fields of tasks.

Their values are objects of a generated model (CmfTaskCf<Name>Ch), and the API
returns them only when asked for by name: "*" and "**" leave them out. Which
fields there are comes from CmfTask.get_meta, a reply of almost a megabyte, so
the custom fields' names, types, value models and captions are cached for a
day per server.
"""

from std.ffi import external_call
from std.os import getenv, makedirs
from std.os.path import exists

from eva.args import Args
from eva.client import Client, Reply
from eva.json import JsonDoc, J_ARR, J_OBJ, clean
from eva.render import Out, pad

comptime CACHE_SECONDS = 86400


@fieldwise_init
struct MultiSelect(Copyable, Movable):
    var name: String
    var caption: String


@fieldwise_init
struct CustomField(Copyable, Movable):
    var name: String
    var widget: String  # CmfM2M, CmfChoice, CmfStr...
    var model: String  # the value model of a multi-select, else ""
    var caption: String


def kind_of(widget: String) -> String:
    """The widget as a word people use."""
    if widget == "CmfM2M":
        return "multi-select"
    if widget == "CmfChoice":
        return "choice"
    if widget == "CmfStr":
        return "text"
    if widget == "CmfMarkup":
        return "rich text"
    if widget == "CmfGenericRelation":
        return "link"
    if widget == "CmfNumeric" or widget == "CmfInt" or widget == "CmfFloat":
        return "number"
    if widget == "CmfDate":
        return "date"
    if widget == "CmfDateTime":
        return "date-time"
    if widget == "CmfBool":
        return "yes/no"
    return widget


def cache_file(url: String) -> String:
    var base = getenv("XDG_CACHE_HOME")
    if base == "":
        base = getenv("HOME") + "/.cache"
    var host = String()
    for cp in url.codepoints():
        var c = Int(cp)
        var ok = (c >= 0x30 and c <= 0x39) or (c >= 0x41 and c <= 0x5A) or (c >= 0x61 and c <= 0x7A)
        host += String(cp) if ok else "_"
    return base + "/eva-cli/task-fields-" + host


def _one_line(s: String) -> String:
    return String(clean(s).replace("\t", " ").replace("\n", " ").strip())


def parse_cache(text: String, now: Int) -> Optional[List[CustomField]]:
    """The cached fields, or None when the cache is missing, malformed or old."""
    var lines = text.split("\n")
    if len(lines) == 0 or not lines[0].startswith("# "):
        return None
    var stamp: Int
    try:
        stamp = Int(String(lines[0][byte=2:]).strip())
    except:
        return None
    if now - stamp > CACHE_SECONDS or stamp > now:
        return None
    var out = List[CustomField]()
    for i in range(1, len(lines)):
        var p = lines[i].split("\t")
        if len(p) == 4 and String(p[0]).startswith("cf_"):
            out.append(CustomField(String(p[0]), String(p[1]), String(p[2]), String(p[3])))
    return out^


def from_meta(doc: JsonDoc, meta: Int) raises -> List[CustomField]:
    var out = List[CustomField]()
    var fields = doc.get(meta, "fields")
    if fields < 0 or doc.kind(fields) != J_OBJ:
        return out^
    for i in range(doc.len(fields)):
        var name = doc.key_at(fields, i)
        if not name.startswith("cf_"):
            continue
        var f = doc.at(fields, i)
        var widget = _one_line(doc.text_at(f, "widget"))
        var model = _one_line(doc.text_at(f, "model")) if widget == "CmfM2M" else String("")
        var caption = _one_line(doc.text_at(f, "caption"))
        out.append(CustomField(name, widget, model, caption if caption != "" else name))
    return out^


def custom_fields(client: Client) -> List[CustomField]:
    """The task custom fields on this server; empty if they cannot be learned,
    so a task still prints without them."""
    var path = cache_file(client.cfg.url)
    var now = Int(external_call["time", Int](Int(0)))
    try:
        if exists(path):
            with open(path, "r") as f:
                var cached = parse_cache(f.read(), now)
                if cached:
                    return cached.value().copy()
    except:
        pass
    var out = List[CustomField]()
    try:
        var r = client.call("CmfTask.get_meta")
        out = from_meta(r.doc, r.result)
    except:
        return out^
    try:
        makedirs(path[byte = 0 : path.rfind("/")], exist_ok=True)
        var text = "# " + String(now) + "\n"
        for m in out:
            text += m.name + "\t" + m.widget + "\t" + m.model + "\t" + m.caption + "\n"
        with open(path, "w") as f:
            f.write(text)
    except:
        pass
    return out^


def multiselect_fields(client: Client) -> List[MultiSelect]:
    var out = List[MultiSelect]()
    for f in custom_fields(client):
        if f.widget == "CmfM2M":
            out.append(MultiSelect(f.name, f.caption))
    return out^


def find_field(client: Client, name: String) raises -> CustomField:
    var fields = custom_fields(client)
    var w = String(name.strip()).lower()
    for f in fields:
        if f.name.lower() == w:
            return f.copy()
    var hits = List[Int]()
    for i in range(len(fields)):
        if fields[i].caption.lower() == w:
            hits.append(i)
    if len(hits) == 1:
        return fields[hits[0]].copy()
    if len(hits) > 1:
        var names = List[String]()
        for i in hits:
            names.append(fields[i].name + " (" + kind_of(fields[i].widget) + ")")
        raise Error("several fields are called " + name + ": " + ", ".join(names) + "; name one")
    raise Error("no custom field " + name + "; eva field list shows them")


def multiselect_values(client: Client, model: String) raises -> Reply:
    return client.call(model + ".list", '{"fields":["id","name"],"slice":[0,1000]}')


def resolve_set(client: Client, mut d: JsonDoc, obj: Int) raises:
    """In --set, let a multi-select take value names: ["iOS"] becomes the ids
    of those values. Ids (Model:uuid) pass through."""
    var fields = List[CustomField]()
    var loaded = False
    for i in range(d.len(obj)):
        var key = d.key_at(obj, i)
        var v = d.at(obj, i)
        if not key.startswith("cf_") or d.kind(v) != J_ARR:
            continue
        var names = False
        for j in range(d.len(v)):
            var s = d.text(d.at(v, j))
            if s.find(":") < 0:
                names = True
        if not names:
            continue
        if not loaded:
            fields = custom_fields(client)
            loaded = True
        var model = String()
        for f in fields:
            if f.name == key and f.widget == "CmfM2M":
                model = f.model
        if model == "":
            continue
        var options = multiselect_values(client, model)
        var ids = d.array()
        for j in range(d.len(v)):
            var s = d.text(d.at(v, j))
            var id = s
            if s.find(":") < 0:
                id = ""
                var known = List[String]()
                for k in range(options.doc.len(options.result)):
                    var o = options.doc.at(options.result, k)
                    var oname = options.doc.text_at(o, "name")
                    known.append(oname)
                    if oname.lower() == String(s.strip()).lower():
                        id = options.doc.text_at(o, "id")
                if id == "":
                    raise Error("no value " + s + " in " + key + "; values: " + ", ".join(known))
            var node = d.string(id)
            d.push(ids, node)
        d.set(obj, key, ids)


def field_list(client: Client, args: Args, ui: Out) raises:
    args.check_known(["query", "q", "verbose", "v"])
    var q = args.get("query", "q").lower()
    var fields = custom_fields(client)
    if len(fields) == 0:
        raise Error("cannot read the task fields (CmfTask.get_meta)")
    var shown = 0
    for f in fields:
        if q != "" and f.name.lower().find(q) < 0 and f.caption.lower().find(q) < 0:
            continue
        print(ui.accent(pad(f.name, 24)) + " " + pad(kind_of(f.widget), 13) + " " + f.caption)
        shown += 1
    print(ui.dim(String(shown) + " custom fields; values of one: eva field get NAME"))


def field_get(client: Client, args: Args, ui: Out) raises:
    args.check_known(["verbose", "v"])
    var f = find_field(client, args.need(2, "field name or caption, e.g. eva field get cf_napravleniedev"))
    print(ui.bold(f.name) + "  " + f.caption + "  " + ui.dim(kind_of(f.widget)))
    if f.widget == "CmfM2M":
        var r = multiselect_values(client, f.model)
        for i in range(r.doc.len(r.result)):
            var o = r.doc.at(r.result, i)
            print("  " + pad(r.doc.text_at(o, "name"), 30) + " " + ui.dim(r.doc.text_at(o, "id")))
        print(ui.dim("set by name: eva task update CODE --set '{\"" + f.name + "\": [\"name\", ...]}'"))
    elif f.widget == "CmfChoice":
        var meta = client.call("CmfTask.get_meta")
        var choices = meta.doc.path(meta.result, "fields." + f.name + ".choices")
        for i in range(meta.doc.len(choices)):
            print("  " + pad(meta.doc.key_at(choices, i), 30) + " " + meta.doc.text(meta.doc.at(choices, i)))
        print(ui.dim("set by key: eva task update CODE --set '{\"" + f.name + "\": \"key\"}'"))


def value_names(doc: JsonDoc, n: Int) -> String:
    """A multi-select value as its names, `a, b`; anything else as text."""
    if n < 0 or doc.kind(n) != J_ARR:
        return doc.text(n)
    var names = List[String]()
    for i in range(doc.len(n)):
        var x = doc.at(n, i)
        try:
            var name = doc.text_at(x, "name") if doc.kind(x) == J_OBJ else doc.text(x)
            if name != "":
                names.append(name)
        except:
            pass
    return ", ".join(names)
