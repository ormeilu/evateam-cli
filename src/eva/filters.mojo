"""Saved filters are data: JSON BQL is parsed, never evaluated as code."""
from eva.args import Args
from eva.client import Client
from eva.common import simple_list, split_csv, quote_str
from eva.json import JsonDoc, J_ARR, J_STR
from eva.render import Out


def validate_bql(d: JsonDoc, node: Int, depth: Int = 0) raises:
    if depth > 32 or d.kind(node) != J_ARR:
        raise Error("BQL must be an array with nesting at most 32")
    var n = d.len(node)
    if n == 0:
        return
    var first = d.at(node, 0)
    if d.kind(first) == J_ARR:
        for i in range(n):
            validate_bql(d, d.at(node, i), depth + 1)
        return
    var op = d.text(first)
    if op == "AND" or op == "OR" or op == "NOT":
        if n < 2 or (op == "NOT" and n != 2):
            raise Error("invalid BQL boolean expression")
        for i in range(1, n):
            validate_bql(d, d.at(node, i), depth + 1)
    elif (
        n != 3
        or d.kind(first) != J_STR
        or d.kind(d.at(node, 1)) != J_STR
        or op == ""
    ):
        raise Error("invalid BQL predicate; expected [field,operator,value]")


def task_filter_text(client: Client, raw: String) raises -> String:
    if raw.byte_length() > 262144:
        raise Error("filter exceeds the 256 KiB safety limit")
    var text = String(raw.strip())
    if text.startswith("[") or text.startswith("{"):
        var d = JsonDoc()
        var node = d.parse(text)
        validate_bql(d, node)
        return d.dump(node)
    var field = "code" if text.startswith("RFBF-") else "name"
    var kw = (
        '{"filter":["AND",["cmf_owner","==","__G_CURRENT_USER"],['
        + quote_str(field)
        + ',"==",'
        + quote_str(text)
        + ']],"fields":["id","code","bql","cmf_model_name"],"slice":[0,2]}'
    )
    var r = client.call("CmfBqlFilter.list", kw)
    if r.doc.len(r.result) == 0:
        raise Error("own saved filter " + text + ": not found or not readable")
    if r.doc.len(r.result) != 1:
        raise Error("ambiguous saved filter " + text + "; use its code")
    var row = r.doc.at(r.result, 0)
    var model = r.doc.text_at(row, "cmf_model_name")
    if model != "" and model != "CmfTask":
        raise Error(text + " is for " + model + ", not CmfTask")
    # Legacy filters with no declared model are allowed only with stored JSON
    # BQL. Missing/UBQL-only bodies must never turn into an unrestricted [].
    var bql = r.doc.text_at(row, "bql")
    if bql == "" or bql.byte_length() > 262144:
        raise Error(
            text
            + ": missing or oversized computed BQL; UBQL compilation is not"
            " supported"
        )
    var d = JsonDoc()
    var node = d.parse(bql)
    validate_bql(d, node)
    return d.dump(node)


def filter_list(client: Client, args: Args, ui: Out) raises:
    args.check_known(
        [
            "project",
            "p",
            "query",
            "q",
            "limit",
            "n",
            "page",
            "json",
            "format",
            "verbose",
            "v",
        ]
    )
    var d = JsonDoc()
    var f = d.array()
    var v = d.string("__G_CURRENT_USER")
    var c = d.triple("cmf_owner", "==", v)
    d.push(f, c)
    if args.get("project", "p") != "":
        v = d.string(args.get("project", "p"))
        c = d.triple("project.code", "==", v)
        d.push(f, c)
    if args.get("query", "q") != "":
        v = d.string("%" + args.get("query", "q") + "%")
        c = d.triple("name", "ILIKE", v)
        d.push(f, c)
    simple_list(
        client,
        args,
        ui,
        "CmfBqlFilter",
        split_csv("code,name,cmf_model_name,project.code"),
        d.dump(f),
        "code",
        split_csv("name,cmf_model_name,project.code"),
    )
