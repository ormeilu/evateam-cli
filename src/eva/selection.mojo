"""Complete bounded selections for bulk writes and aggregate reports.

Fail closed on caps, duplicate IDs or a changing selection, before a caller
can mistake a truncated page for the complete set.
"""
from eva.client import Client, Reply
from eva.json import JsonDoc, J_ARR
from eva.common import split_csv


def collect_rows(
    client: Client,
    cls: String,
    filter: String,
    fields: String,
    maximum: Int = 10000,
    order: String = "id",
) raises -> Reply:
    var count = client.call(cls + ".count", '{"filter":' + filter + "}")
    var expected = Int(count.doc.text(count.result))
    if expected < 0 or expected > maximum:
        raise Error(
            "selection has "
            + String(expected)
            + " rows; safety cap is "
            + String(maximum)
            + "; narrow the filter"
        )
    var d = JsonDoc()
    var result = d.array()
    var ids = Dict[String, Bool]()
    var offset = 0
    while offset < expected:
        var kw = d.object()
        var f = d.parse(filter)
        d.set(kw, "filter", f)
        var fl = d.str_array(split_csv("id," + fields))
        d.set(kw, "fields", fl)
        var sorting = d.str_array([order, String("id")])
        d.set(kw, "order_by", sorting)
        var slice = d.array()
        var lo = d.number(offset)
        var hi = d.number(min(offset + 200, expected))
        d.push(slice, lo)
        d.push(slice, hi)
        d.set(kw, "slice", slice)
        var page = client.call(cls + ".list", d.dump(kw))
        if (
            page.doc.kind(page.result) != J_ARR
            or page.doc.len(page.result) == 0
        ):
            raise Error(
                "selection changed or the server returned an incomplete page;"
                " no complete selection is available"
            )
        for i in range(page.doc.len(page.result)):
            var row = page.doc.at(page.result, i)
            var id = page.doc.text_at(row, "id")
            if id == "":
                raise Error("selection contains an unreadable id")
            if id in ids:
                raise Error(
                    "selection repeated "
                    + id
                    + "; no complete selection is available"
                )
            ids[id] = True
            var node = d.parse(page.doc.dump(row))
            d.push(result, node)
        offset += page.doc.len(page.result)
        if offset > expected:
            raise Error(
                "selection grew while reading; retry with a stable filter"
            )
    var final_count = client.call(cls + ".count", '{"filter":' + filter + "}")
    if Int(final_count.doc.text(final_count.result)) != expected:
        raise Error(
            "selection changed while reading; retry with a stable filter"
        )
    return Reply(d^, result)
