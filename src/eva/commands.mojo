"""The raw JSON-RPC escape hatch."""
from eva.args import Args
from eva.diagnostics import print_raw_reply
from eva.client import Client, Reply
from eva.json import JsonDoc, NO_NODE, J_ARR, J_OBJ
from eva.render import Out, pad, clip, text_to_html, markdown_to_html
from eva.common import (
    split_csv,
    fields_from,
    code_kwargs,
    get_by_code,
    id_of,
    text_from,
    body_html,
    print_json,
    want_json,
    person,
    page_slice,
    footer,
    quote_str,
    simple_list,
    like_filter,
)


def raw_call(client: Client, args: Args, ui: Out) raises:
    args.check_known(
        [
            "kwargs",
            "k",
            "args",
            "flags",
            "full",
            "verbose",
            "v",
            "json",
            "format",
        ]
    )
    var method = args.need(
        1, "method, e.g. eva call CmfTask.count --kwargs '{}'"
    )
    var check = JsonDoc()
    var kwargs = args.get("kwargs", "k")
    var a = args.get("args")
    var flags = args.get("flags")
    # Validate locally so a typo fails before it reaches the server.
    if kwargs != "":
        _ = check.parse(kwargs)
    if a != "":
        _ = check.parse(a)
    if flags != "":
        _ = check.parse(flags)
    var r = client.call(method, kwargs, a, flags)
    print_raw_reply(r, args, ui)
