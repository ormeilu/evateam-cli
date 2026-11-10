"""Multi-select custom fields of tasks.

Their values are objects of a generated model (CmfTaskCf<Name>Ch), and the API
returns them only when asked for by name: "*" and "**" leave them out. Which
fields there are comes from CmfTask.get_meta, a reply of almost a megabyte, so
the custom fields' names, types, value models and captions are cached for a
day per server.
"""


from eva.args import Args
from eva.client import Client, Reply
from eva.diagnostics import schema_metadata
from eva.json import JsonDoc, J_ARR, J_OBJ, clean
from eva.render import Out, pad


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


def _one_line(s: String) -> String:
    return String(clean(s).replace("\t", " ").replace("\n", " ").strip())


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
    """Use the same private, principal-scoped metadata cache as schema."""
    try:
        var text = schema_metadata(client, "CmfTask")
        var d = JsonDoc()
        var root = d.object()
        var fields = d.parse(text)
        d.set(root, "fields", fields)
        return from_meta(d, root)
    except:
        return List[CustomField]()


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
    var r = client.call(model + ".list", '{"fields":["id","name"],"slice":[0,1000]}')
    if r.doc.len(r.result) >= 1000:
        raise Error(model + ": value lookup reached its 1000-row cap; use exact IDs or a paginated raw query")
    return r^


def resolve_set(client: Client, mut d: JsonDoc, obj: Int) raises:
    """In --set, let a multi-select take value names: ["iOS"] becomes the ids
    of those values. Ids (Model:uuid) pass through."""
    var fields = List[CustomField]()
    var loaded = False
    for i in range(d.len(obj)):
        var key = d.key_at(obj, i)
        var v = d.at(obj, i)
        if (not key.startswith("cf_") and key != "tags" and key != "components") or d.kind(v) != J_ARR:
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
        if key == "tags":
            model = "CmfTag"
        elif key == "components":
            model = "CmfComponent"
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
                        if id != "":
                            raise Error("ambiguous value " + s + " in " + key + "; use its id")
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
    var f = find_field(
        client,
        args.need(2, "field name or caption, e.g. eva field get cf_direction"),
    )
    print(ui.bold(f.name) + "  " + f.caption + "  " + ui.dim(kind_of(f.widget)))
    if f.widget == "CmfM2M":
        var r = multiselect_values(client, f.model)
        for i in range(r.doc.len(r.result)):
            var o = r.doc.at(r.result, i)
            print("  " + pad(r.doc.text_at(o, "name"), 30) + " " + ui.dim(r.doc.text_at(o, "id")))
        print(ui.dim("set by name: eva task update CODE --set '{\"" + f.name + '": ["name", ...]}\''))
    elif f.widget == "CmfChoice":
        var meta = JsonDoc()
        var root = meta.parse(schema_metadata(client, "CmfTask"))
        var choices = meta.path(root, f.name + ".choices")
        for i in range(meta.len(choices)):
            print("  " + pad(meta.key_at(choices, i), 30) + " " + meta.text(meta.at(choices, i)))
        print(ui.dim("set by key: eva task update CODE --set '{\"" + f.name + '": "key"}\''))


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
