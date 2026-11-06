"""Multi-select custom fields of tasks.

Their values are objects of a generated model (CmfTaskCf<Name>Ch), and the API
returns them only when asked for by name: "*" and "**" leave them out. Which
fields there are comes from CmfTask.get_meta, a reply of almost a megabyte, so
the names and captions are cached for a day per server.
"""

from std.ffi import external_call
from std.os import getenv, makedirs
from std.os.path import exists

from eva.client import Client
from eva.json import JsonDoc, J_ARR, J_OBJ, clean

comptime CACHE_SECONDS = 86400


@fieldwise_init
struct MultiSelect(Copyable, Movable):
    var name: String
    var caption: String


def cache_file(url: String) -> String:
    var base = getenv("XDG_CACHE_HOME")
    if base == "":
        base = getenv("HOME") + "/.cache"
    var host = String()
    for cp in url.codepoints():
        var c = Int(cp)
        var ok = (c >= 0x30 and c <= 0x39) or (c >= 0x41 and c <= 0x5A) or (c >= 0x61 and c <= 0x7A)
        host += String(cp) if ok else "_"
    return base + "/eva-cli/task-multiselects-" + host


def _one_line(s: String) -> String:
    return String(clean(s).replace("\t", " ").replace("\n", " ").strip())


def parse_cache(text: String, now: Int) -> Optional[List[MultiSelect]]:
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
    var out = List[MultiSelect]()
    for i in range(1, len(lines)):
        var parts = lines[i].split("\t")
        if len(parts) == 2 and String(parts[0]).startswith("cf_"):
            out.append(MultiSelect(String(parts[0]), String(parts[1])))
    return out^


def from_meta(doc: JsonDoc, meta: Int) raises -> List[MultiSelect]:
    var out = List[MultiSelect]()
    var fields = doc.get(meta, "fields")
    if fields < 0 or doc.kind(fields) != J_OBJ:
        return out^
    for i in range(doc.len(fields)):
        var name = doc.key_at(fields, i)
        if not name.startswith("cf_"):
            continue
        var f = doc.at(fields, i)
        if doc.text_at(f, "widget") != "CmfM2M":
            continue
        var caption = _one_line(doc.text_at(f, "caption"))
        out.append(MultiSelect(name, caption if caption != "" else name))
    return out^


def multiselect_fields(client: Client) -> List[MultiSelect]:
    """The task multi-select fields on this server; empty if they cannot be
    learned, so a task still prints without them."""
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
    var out = List[MultiSelect]()
    try:
        var r = client.call("CmfTask.get_meta")
        out = from_meta(r.doc, r.result)
    except:
        return out^
    try:
        makedirs(path[byte = 0 : path.rfind("/")], exist_ok=True)
        var text = "# " + String(now) + "\n"
        for m in out:
            text += m.name + "\t" + m.caption + "\n"
        with open(path, "w") as f:
            f.write(text)
    except:
        pass
    return out^


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
